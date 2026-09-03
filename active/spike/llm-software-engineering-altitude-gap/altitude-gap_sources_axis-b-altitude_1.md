# Auxiliary source file — Axis B (solution altitude / responsibility placement)

Raw fetched excerpts backing the Axis B findings in SPIKE.md. One section per source.
Fetched 2026-09-02.

---

## Source: Modular blog — Chris Lattner, "The Claude C Compiler: What It Reveals About the Future of Software" (Feb 22, 2026)

URL: https://www.modular.com/blog/the-claude-c-compiler-what-it-reveals-about-the-future-of-software

Fetched quotes:

> "The code generator is 'toy' and the optimizer reparses assembly text instead of using an IR, and the code generators are poorly factored."

> "The parser appears to have poor error recovery / usability and have some incorrect corner cases."

> "CCC doesn't parse system headers (which are much more gnarly to deal with than application code) so it hard codes in things it needs for its tests."

> "These flaws are informative rather than surprising, suggesting that current AI systems excel at assembling known techniques and optimizing toward measurable success criteria, while struggling with the open-ended generalization required for production-quality systems."

> "CCC didn't invent a new architecture or explore an unfamiliar design space. Instead, it reproduced something strikingly close to the accumulated consensus of decades of compiler engineering."

> "Implementing known abstractions is not the same as inventing new ones. I see nothing novel in this implementation."

> "AI coding is therefore best understood as another step forward in automation. It dramatically lowers the cost of implementation, translation, and refinement."

> "As implementation becomes cheaper, the role of engineers shifts upward. The scarce skills become choosing the right abstractions, defining meaningful problems, and designing systems that humans and AI can evolve together."

Also quoted secondhand via Simon Willison's newsletter (https://simonw.substack.com/p/agentic-engineering-patterns), which reproduces the same passage and attributes it explicitly:
> "Several design choices suggest optimization toward passing tests rather than building general abstractions like a human would." — attributed by Willison to Lattner's post; Willison's framing: "Chris Lattner (Swift, LLVM, Clang, Mojo) knows more about C compilers than most. He just published this review of the code."

Author credentials: Chris Lattner created LLVM, Clang, Swift, and Mojo — a primary source with direct, deep expertise in compiler architecture, reviewing an LLM-built compiler specifically for its architectural choices. This is the single strongest "senior engineer post-hoc reviews AI-produced architecture" source found in this research.

---

## Source: arXiv 2511.20933 — "Hierarchical Evaluation of Software Design Capabilities of Large Language Models of Code" (Saad, Chen, Hernández López, Varró, Sharma)

URL: https://arxiv.org/abs/2511.20933

Full abstract (verbatim):
> "Large language models (LLMs) are being increasingly adopted in the software engineering domain, yet the robustness of their grasp on core software design concepts remains unclear. We conduct an empirical study to systematically evaluate their understanding of cohesion (intra-module) and coupling (inter-module). We programmatically generate poorly designed code fragments and test the DeepSeek-R1 model family (14B, 32B, 70B) under varying levels of guidance, from simple Verification to Guided and Open-ended Generation, while varying contextual noise by injecting distractor elements. While models exhibit a solid baseline understanding of both concepts in ideal conditions, their practical knowledge is fragile and highly asymmetrical. Reasoning about coupling proves brittle; performance collapses in noisy, open-ended scenarios, with F1 scores dropping by over 50%. In contrast, the models' analysis of cohesion is remarkably robust to internal noise in guided tasks, showing little performance degradation. However, this resilience also fails when all guidance is removed. Reasoning-trace analysis confirms these failure modes, revealing cognitive shortcutting for coupling versus a more exhaustive (yet still failing) analysis for cohesion. To summarize, while LLMs can provide reliable assistance for recognizing design flaws, their ability to reason autonomously in noisy, realistic contexts is limited, highlighting the critical need for more scalable and robust program understanding capabilities."

Hierarchy tested: three levels of guidance — "Verification" (most constrained) → "Guided Generation" → "Open-ended Generation" (least constrained / no external structure).

Key mechanism named by the authors: "cognitive shortcutting" (for coupling reasoning) — this is the closest thing found in the literature to a named mechanism for what the engineer describes as picking the locally-obvious solution. It is scoped to coupling/cohesion judgment specifically, tested on the DeepSeek-R1 family (not Claude), under programmatically-injected noisy/open-ended conditions — not a general architecture-choice benchmark and not tested on the model family the engineer uses.

---

## Source: arXiv 2511.10271 — "Quality Assurance of LLM-generated Code: Addressing Non-Functional Quality Characteristics" (survey/SLR)

URL: https://arxiv.org/html/2511.10271v2

> "According to the ISO/IEC 25010 quality model, software quality encompasses not only functional correctness but also NFQCs such as performance efficiency, maintainability, and security." (Section 1, Introduction)

> "security emerges as the most frequently examined attribute, accounting for 33.6% of the studies. Performance efficiency (23.3%) and maintainability (17.2%) also receive substantial attention." (Section 3.2)

> "LLMs can produce readable and partially maintainable code, but maintainability is not ensured by default." (Section 3.2, Maintainability)

> "LLMs often generate code with poor modularity and structure, making it difficult for developers to understand and modify." (Section 3.2, Maintainability)

> "Kang et al. questioned the traditional assumption that modularity improves code quality for LLM-generated code, finding that modular code does not consistently enhance performance." (Section 3.2)

> "Our findings expose a misalignment between academic focus, industry priorities, and observed model behavior, highlighting the need to integrate quality assurance mechanisms into LLM code generation pipelines to ensure that future generated code not only passes tests but truly passes with quality." (Abstract)

> "Practitioners emphasized that maintainability and readability are important aspects given their direct impact on long-term projects and complex systems." (Section 4.3)

---

## Source: dev.to (forgecode) — "Simple over Easy: Architectural Constraints That Make AI-Generated Code Maintainable"

URL: https://dev.to/forgecode/simple-over-easy-architectural-constraints-that-make-ai-generated-code-maintainable-4o77

> "AI agents are optimization machines that tend to choose the path of least resistance during generation, not the path of least resistance during review."

> "The root cause: We don't constrain our AI with architecture. We give it infinite ways to solve every problem, then wonder why it chose the most complex path."

> "For every problem your AI might encounter, there should be exactly one obvious way to solve it."

> "Coordination between services happens only through event queues. When services can't call each other directly, AI can't create temporal coupling."

Draws on Rich Hickey's distinction between "simple" (non-interleaved) and "easy" (familiar) and his term "complecting" (interweaving/braiding concepts) — practitioner blog, not a study.

---

## Source: dev.to (art_light) — "Prompt Engineering Won't Fix Your Architecture"

URL: https://dev.to/art_light/prompt-engineering-wont-fix-your-architecture-23h

> "Prompt engineering is not a silver bullet. It's a very expensive bandaid applied to architectural wounds that were already infected."

> "Prompt engineering won't fix your architecture. But it will expose it."

> "You have a messy backend / Inconsistent APIs / No real domain boundaries / Business logic scattered across controllers, cron jobs, and Slack messages" (listed architectural symptoms the author says get exposed, not caused, by AI coding)

> "If your AI system needs: a 2,000-token prompt to explain business rules / constant retries to 'get it right' / human review for every important decision — You don't have an AI problem. You have an architecture problem that now speaks English."

---

## Source: Hacker News — "Various LLM Smells" (item 48313810)

URL: https://news.ycombinator.com/item?id=48313810

Reported pattern (from a commenter on Claude Code specifically):
> Claude Code "really wants to implement every feature in as bespoke way as possible." Result: "every web modal is implemented differently. Every button is different. Business logic is disconnected." "every feature is developed in a vacuum."

On mitigation attempts:
> Developers documented patterns in `AGENTS.md`/`CLAUDE.md` with instructions like "ALWAYS look for existing patterns within the codebase to keep it consistent," but these directives "don't reliably prevent the model from generating 'useless, verbose code anyway.'"

Also reported: a redundant reimplementation incident — Claude Opus rebuilt an already-completed feature because it lost track of prior work, "argued that they were completely different features" before acknowledging the redundancy; and a general note that "once knowledge leaves the model's context window, previously established patterns and decisions are forgotten, forcing developers to repeatedly reinforce architectural guidelines."

---

## Source: Hacker News — "Why LLMs can't really build software" (item 44900116)

URL: https://news.ycombinator.com/item?id=44900116

> "Software engineers are able to step back, think about the whole thing, and determine the root cause of a problem." (paraphrased consensus of the thread, attributed to a commenter)

> "The most clever lines of code are the ones you don't write." (a commenter)

> "Good programmers...question the business logic itself and suggest non-technical, operational solutions to user issues before we take a hammer to the code." (a commenter)

Skilled developers recognize when data structures are "inside out" and need fundamental redesign; LLMs are described in the thread as lacking this "geometric intuition about problem shape" (paraphrase of thread consensus, not a single verbatim quote from one identified commenter — treat as aggregated forum opinion, not a citable individual claim).

---

## Source: Hacker News — "2x, not 10x: coding with LLMs in 2026" (item 49047839)

URL: https://news.ycombinator.com/item?id=49047839

> "it produces some extremely crappy code that would've NEVER passed a code review 1 year ago" — commenter, describing needing to fix Claude implementations that lack "underlying coherent vision"

> "to review Claude's code *properly* takes 2-3x the amount of time it would have taken me to write it all by hand" — commenter, on hidden review costs

Developers reported LLMs struggle with "getting the big picture and reusing code that is already implemented," instead favoring "rewriting everything from scratch."
