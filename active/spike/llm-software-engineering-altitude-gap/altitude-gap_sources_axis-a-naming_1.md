# Auxiliary source file — Axis A (naming / domain modeling)

Raw fetched excerpts backing the Axis A findings in SPIKE.md. One section per source.
Fetched 2026-09-02.

---

## Source: threedots.tech — "Domain-Driven Design matters more when AI writes your code"

URL: https://threedots.tech/post/ddd-and-ai-coding/

Fetched quotes (via WebFetch extraction against the live page):

> "Agents have access to your whole repository, and they'll look for the names you give them. They may naively try to unify similar entities, so make it clear they are separate for a reason."
(Section: "Ubiquitous Language")

> "Add user to CRM and support after it's created" (labeled by the article as the vague/bad version)
> "Once the user signs up on the website, asynchronously create: 1) a customer entry in the CRM, 2) a profile in the support system" (labeled by the article as the precise/good version)
(Section: "Ubiquitous Language")

> "You want the details about your domain language in your agents' context. It's yet another reason to keep the documentation up to date."
(Section: "Ubiquitous Language")

> "You design and discuss the solution as a team before sitting down to code."
(Section: "Design before writing generating code")

Note: threedots.tech is the blog of Three Dots Labs (Robert Laszczak), a practitioner blog focused on DDD/Go — treat as informed practitioner opinion, not a peer-reviewed study.

---

## Source: arXiv 2605.19901 — "Can LLMs Produce Better Object-Oriented Designs than Human-Involved Development?" (Zhang, Wen, Tempero)

URL: https://arxiv.org/pdf/2605.19901 / https://arxiv.org/html/2605.19901

Fetched quotes:

RQ1: "What differences exist in OOD quality among PreAI, PostAI, and PureAI projects?" (Introduction)
RQ2: "What effect does the level of design guidance in prompts have on the OOD quality of PureAI projects?" (Introduction)

Methodology: "We conducted a comparative case study on a postgraduate Java assignment. Two offerings of the same assignment were selected as the PreAI and PostAI datasets. PureAI projects were generated using three contemporary LLMs." (Abstract)

> "PureAI projects often appear simpler in terms of total size, complexity, and coupling. However, this is consistent with oversimplification, as it is associated with missing abstractions and weaker responsibility separation." (Abstract)

> "burden is concentrated in fewer classes, average and max-percentage values increase, and cohesion often decreases because one class is more likely to represent multiple domain concepts." (Discussion)

On naming (Section 6, Threats to Validity):
> "Very poor naming may still lead to missed matches; however, this is not entirely undesirable, because one purpose of explicit concept representation is to support comprehension, and poor naming itself undermines that goal."

Conclusion:
> "LLMs can support implementation effectively, but appropriate human guidance remains important for object-oriented decomposition and responsibility assignment." (Conclusions)

This is the strongest empirical (peer-reviewed-track arXiv) source found that speaks to BOTH axes at once: naming quality is treated as a proxy for whether a class properly represents a single domain concept, and the paper directly measures responsibility-separation quality (Axis B) degrading in AI-only projects.

---

## Source: arXiv 2511.12884 — "Agent READMEs: An Empirical Study of Context Files for Agentic Coding"

URL: https://arxiv.org/html/2511.12884

> "These are specialized files (e.g., AGENTS.md) that work like a README for agents and define how the agent should behave within a given software project."

16 instruction categories identified; most prevalent:
> "Testing (75.9%), containing procedures related to automated tests"
> "Implementation Details (70.8%) with development guidance (e.g., code style)"
> "Architecture (68.1%) describing high-level system design"

> "Instructions are heavily skewed toward functional operations (e.g., Build and Run, Implementation Details), while critical non-functional requirements like Security and Performance are rare."
> "Security (14.8%) and Performance (14.5%) are rarely specified."

Example naming instruction found in a real Agent README (illustrative, not a general claim):
> "Names: modules/functions 'snake_case', classes 'CapWords', constants 'UPPER_SNAKE_CASE'."

> "agents actively parse and stick to the project-specific rules provided by developers."

Note: this example is a STYLE/casing convention, not a domain-vocabulary rule — the paper does not report a category specifically for "domain terminology" or "ubiquitous language" among its 16 instruction categories. This is itself informative: domain-naming guidance is not a category the study's corpus of real-world Agent READMEs commonly contains.

---

## Source: dev.to — "Why Naming is Hard in Programming and Why LLMs Struggle to Write Real Code" (mateuscechetto)

URL: https://dev.to/mateuscechetto/why-naming-is-hard-in-programming-and-why-llms-struggle-write-real-code-3bee

> "they rely on natural language to interpret intent, and that is inherently fuzzy"

Bad/good example given:
> "handleUserData() { // actually just filters inactive users }" (bad)
> "filterInactiveUsers()" (recommended)

Assessment: this article discusses naming difficulty in general and argues LLMs cannot replace programmers due to natural-language ambiguity; it does NOT specifically analyze whether LLMs default to implementation-space vs domain-space naming, and offers no fix for LLM naming behavior. Included for completeness; weighted low in the synthesis.
