# SPIKE — The LLM software-engineering "altitude gap": naming/domain modeling and solution-structure quality

## Investigation question

An engineer at a small Rails/Angular team practicing Domain-Driven Design reports that the recurring, single biggest frustration with an LLM coding assistant (Claude Code) is not correctness but software-engineering *quality*, along two axes:

- **Axis A — Naming and domain modeling.** The assistant names variables/classes from the implementation/format space (technical type, display format, data shape) rather than the domain space (what the value IS to the business), which conflicts with a DDD team's requirement that every name reflect the ubiquitous language.
- **Axis B — Solution structure / engineering altitude.** The assistant reaches for the locally-obvious, naive solution (e.g., implementing cross-child validation logic inside each child, which forces N children to each load all their siblings) instead of the globally-better one (validating once, at the parent/aggregate, over a batch built from all children's data).

The question: is this a problem the community is discussing (papers, blog posts, Hacker News/Reddit/X)? What are people saying, and how are they correcting it? Is there research on raising the software-engineering/domain-knowledge level of AI coding assistants, especially subscription tools like Claude Code?

## Sources consulted

- [threedots.tech — DDD and AI coding](https://threedots.tech/post/ddd-and-ai-coding/) — practitioner post directly on Axis A; naming/unification failure mode and remediation via kept-current domain docs
- [arXiv 2605.19901 — Can LLMs Produce Better OO Designs?](https://arxiv.org/pdf/2605.19901) — the strongest empirical source spanning both axes (naming as comprehension proxy + measured responsibility-separation quality)
- [arXiv 2511.20933 — Hierarchical Evaluation of Software Design Capabilities](https://arxiv.org/abs/2511.20933) — cohesion/coupling reasoning collapses under open-ended, low-guidance generation; names the mechanism "cognitive shortcutting"
- [Modular blog — Chris Lattner's review of the Claude C Compiler](https://www.modular.com/blog/the-claude-c-compiler-what-it-reveals-about-the-future-of-software) — primary-source, senior-engineer post-hoc architecture review of Claude-generated code
- [arXiv 2603.28592 — Debt Behind the AI Boom](https://arxiv.org/html/2603.28592v1) — 304k-commit study; Claude has the highest per-commit issue rate among five assistants studied
- [arXiv 2511.10271 — Quality Assurance of LLM-generated Code](https://arxiv.org/html/2511.10271v2) — literature review on non-functional quality; "poor modularity and structure" finding
- [arXiv 2508.00700 — Is LLM-Generated Code More Maintainable & Reliable?](https://arxiv.org/abs/2508.00700) — structural issues concentrate in harder/more open-ended problems
- [arXiv 2401.14176 — Copilot code-smell taxonomy](https://arxiv.org/html/2401.14176v1) — shows the standard code-smell literature is entirely mechanical (length/nesting/parameters), with no category for the altitude failure at all
- [arXiv 2511.12884 — Agent READMEs empirical study](https://arxiv.org/html/2511.12884) — what real CLAUDE.md/AGENTS.md files contain; domain vocabulary is not a tracked category
- [arXiv 2605.10039 — Instruction Adherence factorial study](https://arxiv.org/abs/2605.10039) — tested on Claude Code CLI directly; steering-file *structure* did not move compliance, and compliance decays within a session
- [damiangalarza.com — Four Dimensions of Agent-Ready Codebase Design](https://www.damiangalarza.com/posts/2026-03-25-four-patterns-that-separate-agent-ready-codebases/) — practitioner case for example-driven over prose-only guidance
- [Hacker News — "Various LLM Smells"](https://news.ycombinator.com/item?id=48313810) — Claude Code's "bespoke per-feature" pattern; steering docs reported as unreliable
- [Hacker News — "Why LLMs can't really build software"](https://news.ycombinator.com/item?id=44900116) and ["2x, not 10x"](https://news.ycombinator.com/item?id=49047839) — practitioner opinion on architectural judgment gaps
- [GitHub Blog — Spec Kit announcement](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/) — spec-driven development as a remediation approach
- [dev.to (forgecode) — Simple over Easy](https://dev.to/forgecode/simple-over-easy-architectural-constraints-that-make-ai-generated-code-maintainable-4o77) and [dev.to (art_light) — Prompt Engineering Won't Fix Your Architecture](https://dev.to/art_light/prompt-engineering-wont-fix-your-architecture-23h) — practitioner opinion, Axis B
- [Zed Blog — Addy Osmani, "AI's 70% Problem"](https://zed.dev/blog/ai-70-problem-addy-osmani) — the "last 30%" framing
- [philippdubach.com — Karpathy "Software 3.0" summary](https://philippdubach.com/posts/karpathys-software-3.0-playbook/) — secondary source, quotes attributed to Karpathy on taste/judgment
- [Baeldung — Aggregate Root in DDD](https://www.baeldung.com/cs/aggregate-root-ddd) — could not be fetched (403); the aggregate-root pattern claim in Finding B3 relies on prior, non-LLM-specific DDD literature and is flagged as **not independently re-verified via a fetched quote in this research pass**
- See auxiliary: `altitude-gap_sources_axis-a-naming_1.md` — full raw quotes for every Axis A source
- See auxiliary: `altitude-gap_sources_axis-b-altitude_1.md` — full raw quotes for every Axis B source
- See auxiliary: `altitude-gap_sources_remediation_1.md` — full raw quotes for remediation-technique sources
- See auxiliary: `altitude-gap_sources_empirical-studies_1.md` — full abstracts/quotes for every empirical study, with a cross-cutting note on what the code-smell literature does and does not measure

## Findings

### Finding A1: Practitioners in the DDD community have already named the specific naming failure the engineer describes — agents "naively unify" distinct domain entities under one name

**Evidence:** "Agents have access to your whole repository, and they'll look for the names you give them. They may naively try to unify similar entities, so make it clear they are separate for a reason." The same post's fix is to keep the ubiquitous-language documentation current so the agent reads it: "You want the details about your domain language in your agents' context. It's yet another reason to keep the documentation up to date."

**Source:** [threedots.tech — "Domain-Driven Design matters more when AI writes your code"](https://threedots.tech/post/ddd-and-ai-coding/)

**Significance:** This is a practitioner (not peer-reviewed) DDD-focused blog making almost exactly the engineer's Axis A complaint, from the opposite direction — the failure mode described is agents collapsing two domain-distinct concepts into one name, which is a close cousin of naming from the "shape" rather than the "meaning" of a value. The proposed fix (keep domain-language docs current, in context) is the same class of technique this team already uses (a `CLAUDE.md`-equivalent with domain rules) — see Finding R2 for an important caveat on how much that technique alone is shown to help.

---

### Finding A2: The one controlled study found in this research that measures both naming and responsibility-placement quality together shows AI-only code both under- and over-concentrates responsibility, and explicitly ties poor naming to loss of "one class, one domain concept"

**Evidence:** "PureAI projects often appear simpler in terms of total size, complexity, and coupling. However, this is consistent with oversimplification, as it is associated with missing abstractions and weaker responsibility separation." And: "burden is concentrated in fewer classes, average and max-percentage values increase, and cohesion often decreases because one class is more likely to represent multiple domain concepts." On naming specifically: "one purpose of explicit concept representation is to support comprehension, and poor naming itself undermines that goal."

**Source:** arXiv 2605.19901, Zhang/Wen/Tempero, "Can LLMs Produce Better Object-Oriented Designs than Human-Involved Development?" — a comparative case study using a postgraduate Java assignment, comparing pre-AI, post-AI, and pure-AI (LLM-generated) submissions.

**Significance:** This is the single strongest empirical link found between Axis A (naming) and Axis B (responsibility placement) — the study frames naming quality as a *symptom* of whether a class represents one coherent domain concept or several conflated ones, which is exactly the DDD "ubiquitous language" concern applied to class design rather than variable naming. Its conclusion is stated as guidance, not alarm: "LLMs can support implementation effectively, but appropriate human guidance remains important for object-oriented decomposition and responsibility assignment." Scope limit: the study population is a university Java assignment, not a production Rails/DDD codebase, and it does not test Claude Code specifically.

---

### Finding A3: The literature on what real CLAUDE.md/AGENTS.md files contain shows domain vocabulary is not a category teams commonly document at all

**Evidence:** An empirical survey of real-world Agent README files (the CLAUDE.md/AGENTS.md family) found 16 instruction categories; the most prevalent were "Testing (75.9%)," "Implementation Details (70.8%)," and "Architecture (68.1%)." Naming guidance, where present, took the form of mechanical style rules ("Names: modules/functions 'snake_case', classes 'CapWords', constants 'UPPER_SNAKE_CASE'") — not domain-vocabulary rules. The paper's own framing: "Instructions are heavily skewed toward functional operations... while critical non-functional requirements like Security and Performance are rare."

**Source:** [arXiv 2511.12884 — "Agent READMEs: An Empirical Study of Context Files for Agentic Coding"](https://arxiv.org/html/2511.12884)

**Significance:** The study's 16-category taxonomy has no dedicated "domain terminology / ubiquitous language" category, which is informative by absence: across the corpus of steering files this study examined, teams instruct agents about testing procedures, code style, and system architecture far more than about what a name should mean to the business. This suggests Axis A is a known-but-under-documented gap in the standard remediation technique (steering files), rather than a solved problem the community has already encoded into common practice.

---

### Finding B1: A primary-source, senior-compiler-engineer review of Claude-generated code independently reproduces the engineer's Axis B complaint at the architecture level, and gives it the clearest available framing: "known techniques, not new abstractions"

**Evidence:** "CCC didn't invent a new architecture or explore an unfamiliar design space. Instead, it reproduced something strikingly close to the accumulated consensus of decades of compiler engineering." And: "Implementing known abstractions is not the same as inventing new ones. I see nothing novel in this implementation." More concretely on structure: "the optimizer reparses assembly text instead of using an IR, and the code generators are poorly factored." Overall diagnosis: "Several design choices suggest optimization toward passing tests rather than building general abstractions like a human would" and "current AI systems excel at assembling known techniques and optimizing toward measurable success criteria, while struggling with the open-ended generalization required for production-quality systems."

**Source:** [Chris Lattner (creator of LLVM/Clang/Swift/Mojo) reviewing "The Claude C Compiler," Modular blog](https://www.modular.com/blog/the-claude-c-compiler-what-it-reveals-about-the-future-of-software)

**Significance:** This is the closest match in this research to the engineer's exact complaint, from an author with direct domain authority to make the judgment (a compiler architect reviewing an LLM-built compiler). The mechanism named — optimizing toward the locally measurable success criterion (tests passing, one feature working) rather than the globally coherent abstraction — matches the shape of the team's own example: implementing validation logic that satisfies "this child validates correctly" is the locally-testable target; recognizing "this belongs at the parent as a batch/aggregate operation" requires reasoning about the system as a whole, which is exactly the axis Lattner reports as weak. Lattner's own conclusion about where value shifts: "the scarce skills become choosing the right abstractions, defining meaningful problems, and designing systems that humans and AI can evolve together."

---

### Finding B2: A controlled study measuring LLM reasoning about coupling and cohesion — the two textbook design concepts underlying the team's example — finds that reasoning collapses specifically under open-ended, low-guidance, noisy conditions, and names the mechanism "cognitive shortcutting"

**Evidence:** "While models exhibit a solid baseline understanding of both concepts in ideal conditions, their practical knowledge is fragile and highly asymmetrical. Reasoning about coupling proves brittle; performance collapses in noisy, open-ended scenarios, with F1 scores dropping by over 50%." And: "Reasoning-trace analysis confirms these failure modes, revealing cognitive shortcutting for coupling versus a more exhaustive (yet still failing) analysis for cohesion."

**Source:** [arXiv 2511.20933 — "Hierarchical Evaluation of Software Design Capabilities of Large Language Models of Code," Saad/Chen/Hernández López/Varró/Sharma](https://arxiv.org/abs/2511.20933)

**Significance:** "Cognitive shortcutting" is the closest thing found in the academic literature to a named term for what the engineer is describing — a documented mechanism by which the model's reasoning about a design property (here, coupling: how much the child validators would need to know about their siblings) degrades specifically when the task is open-ended rather than tightly guided. This maps directly onto the team's example: "validate the parent's children" is an open-ended design task with no single obviously-correct decomposition stated in the prompt, which is exactly the condition under which this study found reasoning quality collapses. Scope limit: tested on the DeepSeek-R1 family (14B/32B/70B), not Claude, and on synthetic/programmatically-generated code fragments, not a production Rails/DDD codebase — a generalization, not a Claude-specific finding.

---

### Finding B3: The DDD community has an established pattern that names exactly the correct answer to the engineer's example — the "aggregate root enforces invariants across its children" pattern — as a pre-existing (non-LLM) concept

**Evidence:** [Could not independently re-verify with a fetched quote — Baeldung's page returned HTTP 403 on fetch attempt in this session.] Per the (unverified) WebSearch synthesis of that and other DDD reference pages: an aggregate is described as a consistency boundary where the aggregate root enforces invariants across all entities inside the boundary, and objects outside the boundary interact with the aggregate only through the root, so that cross-entity invariants are checked in one place rather than by each entity independently.

**Source:** [Baeldung — "What Is an Aggregate Root?"](https://www.baeldung.com/cs/aggregate-root-ddd) — **UNVERIFIED, HTTP 403; not independently fetched. Included only as an unresolved lead, not a sustaining citation.**

**Significance:** If verified, this would show the *correct* answer to the team's specific example is not a novel invention by the engineer but a decades-old, named DDD pattern (aggregate root / invariant enforcement at the aggregate boundary) that any DDD-trained engineer would recognize — and that the LLM, in this instance, did not reach for despite this being squarely within the DDD vocabulary the team already uses. This finding is flagged as unresolved and should be re-verified (a plain non-Baeldung DDD source, e.g. Vaughn Vernon's "Implementing Domain-Driven Design," would independently confirm the pattern's existence) before being treated as established in any downstream document.

---

### Finding B4: The mechanically-detectable code-smell literature — the closest thing to an existing measurement standard for "AI code quality" — has no category for the altitude failure at all

**Evidence:** A dedicated study of code smells in Copilot-generated Python code used a 10-type taxonomy: "Long Parameter List (LPL), Long Method (LM), Long Scope Chaining (LSC), Large Class (LC), Long Message Chain (LMC), Long Base Class List (LBCL), Long Lambda Function (LLF), Long Ternary Conditional Expression (LTCE), Complex Container Comprehension (CCC), [and] Multiply-Nested Container (MNC)." All ten are metric-based (length, nesting depth, parameter count) — none is a placement/architecture smell.

**Source:** [arXiv 2401.14176 — "Copilot Refinement: Addressing Code Smells in Copilot-Generated Python Code"](https://arxiv.org/html/2401.14176v1)

**Significance:** This is negative evidence with a specific, useful shape: the standard "code smell" measurement apparatus the community currently uses to grade LLM code quality (and that underlies the larger studies in Finding B5, e.g. the 484k-issue "Debt Behind the AI Boom" dataset) does not and cannot detect the engineer's Axis B failure, because "logic that should live at the parent lives at the child instead" produces no long method, no large class, no deep nesting — the code can be short, clean, and pass every mechanical smell detector while still being architecturally wrong at the level the engineer cares about. This explains, mechanically, why large-scale empirical studies (Finding B5) can report "AI fixes more code smells than it introduces" while the engineer's daily frustration persists — the two are measuring different things.

---

### Finding B5: At production scale, Claude has the highest per-commit issue rate among five studied coding assistants, though the measured "issues" are code smells/security/correctness, not architecture-placement judgments

**Evidence:** "Claude has the highest issue rate per commit (1.96), while Devin has the lowest (0.87)." Overall, across all five tools: "code smells are by far the most common type, accounting for 89.1% of all issues," and "AI-authored commits fix more issues than they introduce (449,984 vs. 431,850)" for code smells specifically, but 22.7% of introduced issues (across all categories) "still survive at the latest version of the repository."

**Source:** [arXiv 2603.28592 — "Debt Behind the AI Boom: A Large-Scale Empirical Study of AI-Generated Code in the Wild"](https://arxiv.org/html/2603.28592v1) — 304k AI-authored commits across 6,275 GitHub repositories, covering GitHub Copilot, Claude, Cursor, Gemini, and Devin

**Significance:** This directly answers "is anyone measuring Claude specifically at scale, in production repos" — yes, and it shows a real, measured quality gap for Claude relative to the other four tools studied on this particular metric (issues per commit). But per Finding B4, "issue rate" here means static-analysis-detectable smells/security/correctness defects, not the naming-space or responsibility-placement judgment the engineer is describing — so this finding corroborates that Claude output needs correction at scale, without directly confirming the specific mechanism the engineer identified.

---

### Finding R1: Spec-driven development is the community's most concrete, tool-backed remediation, aimed specifically at closing the ambiguity that produces "guessed" designs

**Evidence:** "A vague prompt like 'add photo sharing to my app' forces the model to guess at potentially thousands of unstated requirements." The proposed fix: "Specs become the shared source of truth. When something doesn't make sense, you go back to the spec," and a stated architectural side-effect: "The new code feels native to the project instead of a bolted-on addition."

**Source:** [GitHub Blog — "Spec-driven development with AI: Get started with a new open source toolkit"](https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/) (GitHub Spec Kit)

**Significance:** This maps directly onto the team's specific example — "validate a parent with many children" is exactly the kind of underspecified prompt Spec Kit's argument targets; forcing the design decision (validate at the parent as a batch vs. validate at each child) into an explicit, reviewed spec step, before code generation starts, moves the decision to a point where a human can catch it before N implementations exist. This is architecturally the same idea as the DDD "design before generating code" step reported in Finding A1 (threedots.tech): both push a design decision earlier, out of the code-generation step itself.

---

### Finding R2: A factorial study run directly on Claude Code CLI found that how a CLAUDE.md/AGENTS.md-style file is *structured* does not measurably change compliance, and that compliance decays as a session gets longer — a direct, load-bearing caveat on the team's own primary remediation tool

**Evidence:** "None of the four structural variables or three two-way interactions produces a detectable contrast after multiple-testing correction. Size and conflict nulls are supported by affirmative-null Bayes factors (BF10 between 0.05 and 0.10)... The largest effect we measured is within-session: each additional function the agent generates is associated with approximately 5.6% lower odds of compliance per step (OR = 0.944) within the session-length range we tested."

**Source:** [arXiv 2605.10039 — "Instruction Adherence in Coding Agent Configuration Files: A Factorial Study of Four File-Structure Variables"](https://arxiv.org/abs/2605.10039) — 1,650 Claude Code CLI sessions, 16,050 function-level observations, tested on Sonnet 4.6 (primary) plus Opus 4.6/4.7 cross-checks

**Significance:** This is the one study found that tests the engineer's own tool (Claude Code CLI) directly, and it is a load-bearing qualifier rather than a blanket refutation. What it shows: reorganizing a CLAUDE.md's *structure* (its size, where an instruction sits in the file, how the file is architected, whether adjacent files contradict each other) did not move compliance with a trivial, mechanically-checkable rule. What it does NOT show: it does not test whether *having* domain-vocabulary content in the file versus not having it changes naming behavior, and it does not test compliance with a subjective judgment like "pick the right architectural level" — only a trivial annotation rule. Its most actionable finding for a long-running session is the within-session decay: the longer an agent works in one session generating functions, the lower the odds it keeps following the steering file's rules, independent of how that file is organized. This is a testable, falsifiable claim about a mechanism (session-length erosion) distinct from file structure, and it suggests that re-grounding an agent (e.g., shorter sessions, re-stating the rule mid-session) may matter more than reorganizing the steering document itself.

---

### Finding R3: Practitioner consensus converges on example-driven guidance ("show a pattern, don't just describe it") over prose-only convention documents, matching the team's existing "read sibling files first" practice — but the same practitioners report steering documents are not reliable on their own

**Evidence:** "One well-structured example teaches the agent more than any documentation, because it's a pattern it can directly replicate," and "Agents replicate patterns they find in the codebase." Counter-evidence from a separate, independent report: developers who wrote explicit instructions like "ALWAYS look for existing patterns within the codebase to keep it consistent" into their `AGENTS.md`/`CLAUDE.md` found these directives "don't reliably prevent the model from generating 'useless, verbose code anyway.'"

**Sources:** [damiangalarza.com — "Four Dimensions of Agent-Ready Codebase Design"](https://www.damiangalarza.com/posts/2026-03-25-four-patterns-that-separate-agent-ready-codebases/) (for the example-driven claim); [Hacker News, "Various LLM Smells"](https://news.ycombinator.com/item?id=48313810) (for the counter-evidence)

**Significance:** These two sources together describe the technique the team already practices (reading 2-3 sibling files before writing — "Pattern Priming" in the team's own vocabulary) as directionally correct per practitioner opinion, while also reporting that the same class of instruction, written into a steering file, is not reliably followed in practice by at least one other team's experience with the same tool. Combined with Finding R2's session-decay result, the emerging picture across independent sources is: example-driven guidance is believed more effective than prose-only rules, but no source in this research demonstrates that either technique reliably holds for an entire long agentic session — the "does this specific technique work" question remains open (see "What remains uncertain" below).

---

### Finding R4: Agentic/multi-agent code review is an active research direction, but no source found demonstrates — empirically — that it catches architecture/naming-altitude problems specifically, as opposed to correctness/style issues

**Evidence:** A 2026 vision paper proposes a five-stage agentic review workflow — "PR Creation, PR Augmentation, Reviewer Selection, AI-Assisted Code Review, and PR Retrospective, with humans retained at key decision points to preserve judgment, accountability, and team-level understanding" — explicitly because "Current AI support in code review remains fragmented, with tools focusing on isolated tasks... rather than the end-to-end PR review workflow."

**Source:** [arXiv 2605.17548 — "Rethinking Code Review in the Age of AI: A Vision for Agentic Code Review"](https://arxiv.org/abs/2605.17548)

**Significance:** This is a *vision/position* paper, not an empirical evaluation — it argues reviewers should shift from "manual inspectors" to "supervisory operators of agents" and explicitly keeps humans "at key decision points to preserve judgment," which implicitly concedes that judgment-level decisions (the kind Axis A/B require) are not yet delegated to the agentic review layer itself. No source found in this research empirically measures whether a second AI review pass catches solution-altitude or domain-naming mistakes better than a human reviewer or better than no review at all.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Steering file (CLAUDE.md/AGENTS.md) with domain vocabulary + architecture rules | Matches what real-world files already emphasize (testing, architecture); example-driven variants are believed more effective than prose | Structural reorganization of the file was shown not to move compliance on a trivial rule (arXiv 2605.10039); compliance decays within a long session regardless of file structure; independent practitioner report says explicit "follow existing patterns" instructions were not reliably followed | arXiv 2605.10039; HN "Various LLM Smells" |
| Spec-driven development (write/review a spec before code generation) | Forces the ambiguous design decision (e.g., "validate at parent vs. at each child") into an explicit, reviewable step before N implementations exist; reported to make generated code "feel native to the project" | No empirical (as opposed to vendor-announcement) study found measuring whether spec review actually catches solution-altitude mistakes at a higher rate than steering files alone | GitHub Spec Kit announcement |
| Pattern Priming — read 2-3 sibling files before writing (team's existing practice) | Matches the practitioner claim that "one well-structured example teaches the agent more than any documentation"; agent explicitly told to replicate existing patterns rather than invent | Only as good as the existing pattern — an agent following existing structure will replicate an already-poor pattern; does not, by itself, address a genuinely novel design decision (like the parent/children validation example) where no sibling pattern yet exists to copy | damiangalarza.com |
| Agentic/multi-stage AI code review | Active, well-funded research direction; explicitly designed to move review from isolated single-task tools to an end-to-end workflow | Still a vision paper, not a demonstrated capability; the paper's own design keeps humans "at key decision points to preserve judgment" — i.e., does not yet claim to replace human judgment on exactly this kind of decision | arXiv 2605.17548 |
| Mechanical code-smell/static-analysis gates (SonarQube-style) | Measurable, automatable, already deployed at scale (used in three of the empirical studies gathered here) | Demonstrably blind to the altitude failure — the 10-type Copilot code-smell taxonomy has no category that would flag "logic placed at the wrong level"; short, clean, mechanically-smell-free code can still be architecturally wrong | arXiv 2401.14176 |

## What remains uncertain

- **No source found in this research gives Axis B (solution-altitude / responsibility-placement) an established community-wide name.** The closest terms found are "cognitive shortcutting" (arXiv 2511.20933, scoped narrowly to coupling reasoning under noisy/open-ended conditions, tested on DeepSeek-R1 not Claude) and "weaker responsibility separation" / "missing abstractions" (arXiv 2605.19901, a Java-assignment case study). Multiple direct searches for terms like "low-altitude reasoning," "local optimum," and "solution altitude" in the context of LLM code generation returned no matching established term. This should be read as a genuine absence of a name, not as this spike having failed to find an existing one.
- **The specific claim that the correct answer to the team's example is a named, pre-existing DDD pattern (aggregate root enforcing cross-child invariants) could not be independently verified with a fetched quote in this session** (Baeldung returned HTTP 403; see Finding B3). This is worth re-confirming against a primary DDD source (e.g., Vaughn Vernon or Eric Evans directly) before treating it as established.
- **Whether the team's own existing techniques (a CLAUDE.md-equivalent, Pattern Priming / reading sibling files, per-file pattern conventions) measurably reduce Axis A/B failures was not found tested anywhere as a direct causal claim** — the one rigorous test found (arXiv 2605.10039) tests file *structure*, not file *content*, and tests compliance with a trivial rule, not naming or architecture judgment. No source found runs the experiment "give the agent domain-vocabulary + architecture rules vs. not, then measure naming/placement quality" directly.
- **No source found addresses the engineer's explicit "subscription incentive" hypothesis directly** — that a subscription coding tool is optimized to make features land / demos work rather than for durable engineering quality. Several sources describe a related but distinct dynamic (Osmani's "70% problem"; general "AI coding tools trade productivity for quality" commentary), but none of the sources fetched in this session state or demonstrate a causal link between the subscription/commercial model specifically and design-quality shortfalls. This hypothesis remains unconfirmed either way.
- **Whether Claude Code specifically (as opposed to "LLMs generally" or "Copilot specifically," the more commonly studied tools) exhibits the altitude failure at a different rate than other assistants is not directly measured anywhere found** — the one large-scale production study that includes Claude (arXiv 2603.28592) measures a different thing (mechanical code-smell/security/correctness issue rate, where Claude scores worst of five tools studied), not the altitude judgment itself.
- **Reddit was largely unreachable in this research session** (direct `reddit.com` fetches are blocked in this environment) — the community-discussion evidence gathered leans on Hacker News and dev.to; a fuller picture of Reddit (r/ExperiencedDevs, r/programming) sentiment on this specific topic was not obtained.

## Suggested options for main and the engineer

- **Option A — Treat this as an ambiguity problem and adopt a spec-first step for cross-entity design decisions.** Before letting the agent implement anything that spans a parent and its children (or any decision with more than one plausible decomposition), write a short spec/decision note stating where the responsibility lives and why, then generate code against that spec. This targets the open-ended/low-guidance condition that Findings B1, B2, and B5 (taken together) suggest is where the altitude failure is most likely to occur.
- **Option B — Treat this as a documentation-content gap and explicitly encode both the ubiquitous language AND the team's structural defaults (e.g., "cross-entity invariants belong at the aggregate root, not at each entity") into the steering file, while treating Finding R2's caveat as a live constraint** — i.e., accept that reorganizing the file's structure alone won't help, and that a long session will still decay in compliance regardless, so pair this with shorter/more frequently re-grounded sessions rather than relying on the steering file alone.
- **Option C — Treat this as a review-gap problem and add an explicit, human-performed design-review checkpoint for any AI-proposed solution that spans more than one entity/file**, on the grounds that no source found in this research shows either mechanical code-smell tooling (Finding B4) or agentic review (Finding R4) currently catches this class of problem — only a human (or, per Finding B1, a domain expert like Lattner) demonstrably caught it in every example gathered.
- **Option D — Treat Axis A and Axis B as two different problems needing two different fixes**, since Finding A2 is the only source that measures them together and it treats naming as a *symptom* of responsibility-placement quality rather than an independent failure — under this reading, fixing Axis B (getting responsibility placement right) may substantially reduce Axis A (naming) failures as a side effect, rather than needing a separate naming-specific intervention.

These four options are not mutually exclusive — Findings A1 and R1 both describe pushing the design decision earlier (into documentation or into a spec step, respectively), which is compatible with all four options above.
