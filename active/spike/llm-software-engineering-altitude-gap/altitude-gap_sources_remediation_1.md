# Auxiliary source file — remediation techniques (steering docs, spec-driven dev, pattern priming, review loops)

Raw fetched excerpts backing the remediation-techniques findings in SPIKE.md. Fetched 2026-09-02.

---

## Source: GitHub Blog — "Spec-driven development with AI: Get started with a new open source toolkit" (Spec Kit)

URL: https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/

> "Sometimes the code doesn't compile. Sometimes it solves part of the problem but misses the actual intent." (stated problem)

> "Specs become the shared source of truth. When something doesn't make sense, you go back to the spec"

> "The new code feels native to the project instead of a bolted-on addition."

> "They excel at pattern recognition but still need unambiguous instructions."

> "A vague prompt like 'add photo sharing to my app' forces the model to guess at potentially thousands of unstated requirements."

Spec Kit is MIT-licensed, from GitHub; per WebSearch result metadata it had "111k stars and 9.8k forks as of June 2026" (this specific figure was reported by the search tool's synthesis, not independently re-verified against a live GitHub stars count — treat the exact number as approximate/unverified, the existence and MIT license of the project is corroborated by the github.blog post itself).

---

## Source: arXiv 2605.10039 — "Instruction Adherence in Coding Agent Configuration Files: A Factorial Study of Four File-Structure Variables"

URL: https://arxiv.org/abs/2605.10039

Full abstract (verbatim):
> "Frontier coding agents read configuration files (CLAUDE.md, AGENTS.md, Cursor Rules) at session start and are expected to follow the conventions inside them. Practitioners assume that structural choices (file size, instruction position, file architecture, contradictions in adjacent files) measurably affect adherence. We report a systematic factorial study of these choices using four manipulated variables, measuring compliance with a trivial target annotation across 1,650 Claude Code CLI sessions (16,050 function-level observations) on two TypeScript codebases, three frontier models (primarily Sonnet 4.6, with Opus 4.6 as a CLI-matched cross-model check and Opus 4.7 reported descriptively under a CLI-version confound), and five coding tasks. We use mixed-effects models with a Bayesian companion. None of the four structural variables or three two-way interactions produces a detectable contrast after multiple-testing correction. Size and conflict nulls are supported by affirmative-null Bayes factors (BF10 between 0.05 and 0.10); position and architecture nulls are failures to reject without Bayes-factor support. The largest effect we measured is within-session: each additional function the agent generates is associated with approximately 5.6% lower odds of compliance per step (OR = 0.944) within the session-length range we tested, though the relationship is non-monotonic rather than a constant per-step effect. This reproduces on a second TypeScript codebase and on Opus 4.6 at matched configuration; it was identified during analysis rather than pre-specified. Within the conditions tested, file-structure variables did not produce detectable contrasts; compliance varies systematically between coding tasks and across each session's sequence of generated functions."

Key facts this study established, precisely scoped:
- The four variables tested: file size, instruction position, file architecture, contradictions in adjacent files.
- Model tested: Claude Code CLI (Sonnet 4.6 primary, Opus 4.6/4.7 cross-checks) — i.e., the exact tool family the engineer uses.
- The task tested for compliance: "a trivial target annotation" — a narrow, mechanically-checkable compliance target, NOT domain naming or architecture quality.
- Finding: none of the four STRUCTURAL variables of a CLAUDE.md/AGENTS.md-style file measurably changed compliance.
- Finding: compliance degrades as the session progresses (~5.6% lower odds of compliance per additional function generated in the session), a within-session effect independent of file structure.

Scope limits to note explicitly: this study is about the FILE'S STRUCTURE (how it is organized), not its CONTENT (whether domain vocabulary or architectural rules are present in it at all — a variable the study did not manipulate). It also measured compliance with a single trivial annotation rule, not naming quality or solution-altitude choices. It should not be read as "steering docs don't work" — it is read as "how you structure/organize a steering doc's content, specifically, was not shown to matter, and compliance erodes over a long session regardless of structure."

---

## Source: damiangalarza.com — "Four Dimensions of Agent-Ready Codebase Design"

URL: https://www.damiangalarza.com/posts/2026-03-25-four-patterns-that-separate-agent-ready-codebases/

> "The model is rarely the bottleneck. The codebase is."

> "Point it at a codebase with weak coverage, no architecture docs, and no linting, and you get drift."

> "If your codebase has clear boundaries (controllers handle HTTP, services handle business logic, models handle persistence), the agent follows those boundaries."

> "Domain namespacing is especially powerful for agents because it constrains the search space."

> "One well-structured example teaches the agent more than any documentation, because it's a pattern it can directly replicate."

> "Agents replicate patterns they find in the codebase."

> "An agent asked to add a new feature looks at the existing controller, sees that's where logic goes, and adds more logic to the controller." (cited as a failure mode when the existing pattern itself is already poor — the agent replicates existing structure, good or bad)

> "Without an agent-facing entry point (a `CLAUDE.md`, `AGENTS.md`, or equivalent), an agent has to reverse-engineer your conventions from the code itself."

> "The entry file gives agents quick commands and a documentation map."

> "`AGENTS.md` is an emerging standard supported by Codex, Cursor, Gemini CLI, GitHub Copilot, Windsurf, Devin."

This is a practitioner blog post (not a study) but its central claim — "one well-structured example teaches the agent more than any documentation, because it's a pattern it can directly replicate" and "agents replicate patterns they find in the codebase" — is the clearest practitioner-level statement found supporting example-driven/pattern-priming-style guidance over prose-only convention documents.

---

## Source: Hacker News — "Various LLM Smells" (item 48313810), remediation-relevant excerpt

URL: https://news.ycombinator.com/item?id=48313810

(See axis-b auxiliary file for the full excerpt.) Relevant remediation counter-evidence:
> Developers who documented patterns in `AGENTS.md`/`CLAUDE.md` with instructions like "ALWAYS look for existing patterns within the codebase to keep it consistent" found these directives "don't reliably prevent the model from generating 'useless, verbose code anyway.'"

---

## Source: arXiv 2605.17548 — "Rethinking Code Review in the Age of AI: A Vision for Agentic Code Review"

URL: https://arxiv.org/abs/2605.17548

Full abstract (verbatim):
> "Code review has evolved for decades, from informal peer checking to today's pull request (PR) workflows, yet it remains a largely manual and cognitively demanding process. The rise of Artificial Intelligence (AI) coding assistants has intensified this challenge: while these tools increase code production velocity, they also expand the volume of code requiring review, turning code review into a growing bottleneck. Current AI support in code review remains fragmented, with tools focusing on isolated tasks such as reviewer recommendation, PR description generation, or comment suggestion rather than the end-to-end PR review workflow. We address this gap by treating review effectiveness as an outcome of the full code review lifecycle rather than a single stage, proposing a framework that carries context across stage boundaries. We propose a future vision for code review in which reviewers transition from manual inspectors into supervisory operators of agents. In this vision, staged, AI-powered workflows aim to align the pace of code generation with shared understanding and accountable engineering. In this paper, we review the historical evolution of code review practices, identify challenges in traditional code review systems, and examine the shift driven by large language models (LLMs) and agentic AI systems. We then present a vision for an AI-powered code review workflow combining specialized agents with human-controlled quality gates. Our framework spans five stages: PR Creation, PR Augmentation, Reviewer Selection, AI-Assisted Code Review, and PR Retrospective, with humans retained at key decision points to preserve judgment, accountability, and team-level understanding. Finally, we identify key adoption challenges and outline research directions for evaluation, governance, and responsible human-AI collaboration."

This paper is a position/vision paper (not an empirical evaluation of whether agentic review catches design-altitude problems) — proposes a 5-stage framework (PR Creation, PR Augmentation, Reviewer Selection, AI-Assisted Code Review, PR Retrospective) with "humans retained at key decision points to preserve judgment, accountability, and team-level understanding." It does not present evidence that agentic review specifically catches solution-altitude or naming problems better than human review; it argues reviewers should become "supervisory operators of agents" rather than manual inspectors.

---

## Source: Zed Blog — Addy Osmani, "AI's 70% Problem"

URL: https://zed.dev/blog/ai-70-problem-addy-osmani

> "AI can rapidly produce maybe 70% of the code for an app, for a feature."

> "AI coding tools can get you most of the way to a solution, but not all the way."

> "The remaining 30%—things like edge cases where you might have to put in additional debugging, integration with production systems, making sure that your security, your API keys, all of that stuff is in a healthy place—that can be just as time consuming as it ever was."

Note: this article does NOT discuss naming, domain modeling, or subscription/product-incentive framing explicitly — those associations reported elsewhere (Indie Hackers summary, Pragmatic Engineer coverage) around "house of cards code" and juniors-vs-seniors were not independently re-verified against a primary Osmani source in this research pass, and are therefore NOT used as cited claims in SPIKE.md.

---

## Source: philippdubach.com — summary of Andrej Karpathy's "Software 3.0" framing (secondary source)

URL: https://philippdubach.com/posts/karpathys-software-3.0-playbook/

Quotes reported by this secondary source as direct Karpathy quotes:
> "You're in charge of the taste, the engineering, the design, and that it makes sense, and that you're asking for the right things."

> "When you actually look at the code, sometimes I get a little bit of a heart attack, because it's not super amazing code... It's very bloaty, and there's a lot of copy-paste, and there's awkward abstractions that are brittle."

> "You're doing some of the design and development, and the engineers are doing the fill in the blanks."

Attribution caveat: these are quotes AS REPRODUCED by philippdubach.com, not independently cross-checked against Karpathy's original talk/post in this research pass. Cited here as "reported by [secondary source], attributed to Karpathy" rather than as directly-verified Karpathy primary-source quotes.

---

## Source: Hacker News — "Ask HN: Why do people say LLMs create bad code 'quality'?" (item 46071429)

URL: https://news.ycombinator.com/item?id=46071429

This URL returned HTTP 429 (rate-limited) on fetch attempts during this research session and could not be independently verified. UNVERIFIED — not used to sustain any finding in SPIKE.md.

## Source: oreilly.com/radar/agentic-code-review/

URL: https://www.oreilly.com/radar/agentic-code-review/

This URL returned HTTP 403 Forbidden and could not be fetched. UNVERIFIED — not used to sustain any finding in SPIKE.md.
