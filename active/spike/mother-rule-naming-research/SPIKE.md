# SPIKE — Mother Rule Naming Research

## Investigation question

What names does the broader AI-coding-agent community use for the compound practice currently called "Mother Rule" internally — the mandatory pre-generation step where an LLM agent reads 2-3 sibling files, identifies the established pattern, checks against named anti-patterns, presents findings to the engineer, and waits for confirmation before writing any code? Does the community have a canonical name for this composite, or does it only name individual sub-components?

## Sources consulted

| URL | Status | Contribution |
|-----|--------|-------------|
| https://code.claude.com/docs/en/best-practices | FETCHED | Official Anthropic docs — verbatim workflow steps and "Reference existing patterns" strategy |
| https://martinfowler.com/articles/reduce-friction-ai/knowledge-priming.html | FETCHED | Named concept "Knowledge Priming" with exact definition quote |
| https://agentic-coding.github.io/ | FETCHED | Named practices "Practice 8" (Few-Shot Prompting) and "Practice 9" (Exploration Before Implementation) |
| https://dev.to/_vjk/i-made-claude-code-think-before-it-codes-heres-the-prompt-bf | FETCHED | "Process prompt" concept and "Phase 2: Explore before you assume" |
| https://virtuslab.com/blog/ai/how-to-write-rules-for-ai | FETCHED | Rule for reading files before generating output; meta-prompt extraction |
| https://blog.logrocket.com/context-engineering-for-ides-agents-md-agent-skills/ | FETCHED | "Context engineering" definition and "spatial awareness" term |
| https://addyosmani.com/blog/ai-coding-workflow/ | FETCHED | "Context packing", "prime the model with the pattern to follow" |
| https://tweag.github.io/agentic-coding-handbook/PROMPT_ZERO_ONE_N_SHOT_PROMPTS/ | FETCHED | "Multi-Shot Prompting" defined verbatim |
| https://blog.jetbrains.com/idea/2025/05/coding-guidelines-for-your-ai-agents/ | FETCHED | `.junie/guidelines.md` pattern; no named pre-generation practice found |
| https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html | FETCHED | "AI-friendly codebase design"; no named pre-generation practice found |

## Findings

### Finding 1: "Explore First" — Anthropic's official workflow step

**Evidence:**

From the Anthropic Claude Code official documentation, under heading "Explore first, then plan, then code":

> "Separate research and planning from implementation to avoid solving the wrong problem."

Step 1 of the recommended four-phase workflow is named "Explore":

> "Enter plan mode. Claude reads files and answers questions without making changes."

And under "Provide specific context in your prompts", the strategy row is labeled **"Reference existing patterns."** with this after-example:

> "look at how existing widgets are implemented on the home page to understand the patterns. HotDogWidget.php is a good example. follow the pattern to implement a new calendar widget..."

**Source:** https://code.claude.com/docs/en/best-practices

**Significance:** Anthropic's own documentation names the pre-generation read phase "Explore" and the pattern-alignment strategy "Reference existing patterns." Neither is presented as a mandatory gate with engineer confirmation — they are workflow recommendations, not enforced rules.

**Verification:**
- URL fetched: https://code.claude.com/docs/en/best-practices
- Verbatim quote checked: yes
- Quote substring confirmed at: section heading "Explore first, then plan, then code" → Step 1 block titled "Explore"; and table row "Reference existing patterns." in section "Provide specific context in your prompts"

---

### Finding 2: "Knowledge Priming" — Martin Fowler's site

**Evidence:**

From the article at martinfowler.com, exact definition:

> "Knowledge Priming is the practice of sharing curated documentation, architectural patterns, and version information with AI _before_ asking it to generate code."

And later:

> "Technically, this is manual RAG (Retrieval-Augmented Generation)—filling the context window with high-value project-specific tokens that override lower-priority training data."

**Source:** https://martinfowler.com/articles/reduce-friction-ai/knowledge-priming.html

**Significance:** "Knowledge Priming" is a named concept for the human-to-AI knowledge transfer that happens before generation. It covers the "share context" direction (human prepares context, AI consumes it), not the "agent reads sibling files itself" direction. It is a partial overlap: it names the purpose (override training data with project-specific context) but not the agent's active inspection step.

**Verification:**
- URL fetched: https://martinfowler.com/articles/reduce-friction-ai/knowledge-priming.html
- Verbatim quote checked: yes
- Quote substring confirmed at: opening definition paragraph ("Knowledge Priming is the practice of...") and subsequent paragraph starting "Technically, this is manual RAG"

---

### Finding 3: "Practice 9 — Prioritizing Exploration Before Implementation/Planning"

**Evidence:**

From agentic-coding.github.io, verbatim:

> "When tackling complex problems or unfamiliar codebases, instruct the AI to first explore relevant background information by reading specified files, documentation, or URLs before asking it to implement code or create a plan. During this exploration phase, explicitly prevent the AI from prematurely generating code or suggesting solutions."

**Source:** https://agentic-coding.github.io/

**Significance:** This source names the practice "Prioritizing Exploration Before Implementation/Planning" and frames it as a numbered practice. It describes the agent reading files before coding as a distinct, nameable step. It does not cover the sibling-file pattern-check or the engineer confirmation gate that are part of the Mother Rule compound.

**Verification:**
- URL fetched: https://agentic-coding.github.io/
- Verbatim quote checked: yes
- Quote substring confirmed at: section labeled "Practice 9: Prioritizing Exploration Before Implementation/Planning"

---

### Finding 4: "Practice 8 — Ensuring Consistency with Code Examples (Few-Shot Prompting)"

**Evidence:**

From agentic-coding.github.io, verbatim:

> "AI often generates more accurate and consistent results when provided with specific examples (few-shot prompting). When adding or modifying features, rather than simply instructing the AI to follow a pattern, it's more effective to include relevant existing code snippets or examples of similar functionality within the prompt."

**Source:** https://agentic-coding.github.io/

**Significance:** This source names the pattern-alignment mechanism "Few-Shot Prompting" (applied to code). This covers the "show examples before generating" part of the Mother Rule but frames it as prompt-design, not an agent-side read-then-confirm gate.

**Verification:**
- URL fetched: https://agentic-coding.github.io/
- Verbatim quote checked: yes
- Quote substring confirmed at: section labeled "Practice 8: Ensuring Consistency with Code Examples (Few-Shot Prompting)"

---

### Finding 5: "Process prompt" — encoding senior engineering habits

**Evidence:**

From the DEV Community article by v.j.k.:

> "It's a **process prompt**: a way to encode senior engineering habits into Claude's workflow so those habits happen consistently, on every task, even at 2am when you're tired and just want the feature to ship."

The article describes an 8-phase methodology called `/wizard`. Phase 2 is described as:

> "With a plan in place, Claude explores the actual codebase. It greps for every model, method, relationship, and constant it intends to use and verifies they exist before referencing them in code. Without this phase, Claude might confidently call `user.clientProfile.accounts`, a relationship chain it hallucinated with complete conviction. Phase 2 exists specifically to prevent that."

**Source:** https://dev.to/_vjk/i-made-claude-code-think-before-it-codes-heres-the-prompt-bf

**Significance:** The term "process prompt" names the general concept of encoding a repeatable workflow into an AI agent's operating instructions. The `/wizard` framework implements an "explore before write" phase (Phase 2) that shares the intent of the Mother Rule but is discovery-oriented (verify things exist), not pattern-alignment-oriented (identify the established style).

**Verification:**
- URL fetched: https://dev.to/_vjk/i-made-claude-code-think-before-it-codes-heres-the-prompt-bf
- Verbatim quote checked: yes
- Quote substring confirmed at: paragraph describing the `/wizard` concept ("It's a **process prompt**") and subsequent paragraph describing Phase 2

---

### Finding 6: "Context packing" and "prime the model with the pattern to follow"

**Evidence:**

From Addy Osmani's blog, exact quotes:

> "Expert LLM users emphasize this 'context packing' step. For example, doing a **'brain dump'** of everything the model should know before coding, including: high-level goals and invariants, examples of good solutions, and warnings about approaches to avoid."

And:

> "prime the model with the pattern to follow"

Full context of the second quote:

> "Another powerful technique is providing **in-line examples** of the output format or approach you want. If I want the AI to write a function in a very specific way, I might first show it a similar function already in the codebase: 'Here's how we implemented X, use a similar approach for Y.' [...] Essentially, _prime_ the model with the pattern to follow."

**Source:** https://addyosmani.com/blog/ai-coding-workflow/

**Significance:** "Context packing" names the preparation phase before generation. "Prime the model with the pattern" is a description of showing the agent existing code before generating new code. Neither is a formal coined term — they are descriptive phrases used in a practitioner blog. The verb "prime" (from "priming") is used informally, not as a named practice.

**Verification:**
- URL fetched: https://addyosmani.com/blog/ai-coding-workflow/
- Verbatim quote checked: yes
- Quote substring confirmed at: section on expert workflow preparation ("Expert LLM users emphasize this 'context packing' step") and section on in-line examples ("prime the model with the pattern to follow")

---

### Finding 7: Reading files before output — VirtusLab rule formulation

**Evidence:**

From VirtusLab's article, under section "Rules can tell the AI how to use tools":

> "You can also tell it to always read certain files before generating output, or to confirm assumptions before making changes. I place these rules either in the `general rule` set when they apply broadly, or in specific rule files when they target a particular area."

And separately, under "How I use my meta-prompt":

> "If I give the model 2–3 unit test files, it will detect naming patterns, mocking patterns, `Given-When-Then` structure, and turn those into rules."

**Source:** https://virtuslab.com/blog/ai/how-to-write-rules-for-ai

**Significance:** The article treats "read certain files before generating output" as a rule type that can be placed in a rules file, not as a named practice. The meta-prompt technique of giving 2-3 examples to extract patterns is structurally similar to the Mother Rule's "read 2-3 sibling files" step, but is used for generating rules, not for in-session pre-generation inspection.

**Verification:**
- URL fetched: https://virtuslab.com/blog/ai/how-to-write-rules-for-ai
- Verbatim quote checked: yes
- Quote substring confirmed at: section "Rules can tell the AI how to use tools" and section "How I use my meta-prompt"

---

### Finding 8: "Multi-Shot Prompting" — Tweag Agentic Coding Handbook

**Evidence:**

From the handbook, verbatim:

> "Give the AI multiple examples before asking it to continue the pattern."

The practice is labeled **"Multi-Shot Prompting"** (under the broader category "N-Shot Prompting").

> "Enables the AI to model based on pattern, not just one instance."

**Source:** https://tweag.github.io/agentic-coding-handbook/PROMPT_ZERO_ONE_N_SHOT_PROMPTS/

**Significance:** "Multi-Shot Prompting" is the established prompt-engineering term for showing the AI multiple examples before requesting generation. This covers the "sibling files as examples" mechanic from the Mother Rule but is a general prompting technique, not a code-generation gate with anti-pattern checking or engineer confirmation.

**Verification:**
- URL fetched: https://tweag.github.io/agentic-coding-handbook/PROMPT_ZERO_ONE_N_SHOT_PROMPTS/
- Verbatim quote checked: yes
- Quote substring confirmed at: section defining "Multi-Shot Prompting" under the N-Shot Prompts page

---

## What the community does NOT name

The research found no community-canonical name for the **compound practice** as defined by the Mother Rule:

1. Read 2-3 sibling files actively (agent-side action)
2. Identify the established pattern (agent-side synthesis)
3. Check against a named anti-pattern catalog (project-specific gate)
4. Surface findings to the engineer and wait for confirmation (human-in-the-loop gate before any write)

Each sub-component has partial coverage in community vocabulary:

| Sub-component | What the community calls it | Gap |
|---|---|---|
| Read existing files before generating | "Explore" (Anthropic), "Practice 9" (agentic-coding.github.io), "Phase 2" (v.j.k./DEV) | Not framed as mandatory gate; no anti-pattern check |
| Show examples before generating | "Few-Shot / Multi-Shot Prompting", "prime the model" (Osmani) | Prompt technique, not agent-side read step |
| Prepare context before generating | "Knowledge Priming" (Fowler), "context packing" (Osmani) | Human-prepares-then-AI-consumes direction only |
| Encoding repeatable habits into agent | "Process prompt" (v.j.k./DEV) | General concept; does not specify sibling-file read or confirmation gate |
| Full compound with confirmation gate | **No community name found** | — |

## Candidates

The table below lists names whose derivation traces entirely to verified Findings. Candidates are descriptive, not a selection — the engineer and main decide.

| Name candidate | Findings that sustain it | Derivation from literal source text | Pro | Con |
|---|---|---|---|---|
| **Pre-Generation Exploration** | Finding 1, Finding 3 | Anthropic calls Step 1 "Explore"; agentic-coding.github.io calls it "Exploration Before Implementation" | Matches established vocabulary from two independent sources; communicates the "before write" intent | Does not convey pattern-check, anti-pattern catalog, or confirmation gate — the distinctive parts |
| **Pattern Priming** | Finding 6, Finding 8 | Osmani uses "prime the model with the pattern"; Tweag uses "Multi-Shot Prompting" for showing patterns before generation | "Priming" has community currency; "pattern" names the subject | "Priming" in Osmani is a verb phrase, not a coined term; does not name the confirmation gate |
| **Codebase Exploration Gate** | Finding 1, Finding 3, Finding 5 | Combines Anthropic's "Explore" step with the gate concept implicit in "explicitly prevent the AI from prematurely generating code" (Practice 9) | "Gate" communicates that generation is blocked until the step completes | Composite invented here; no single source uses "gate" in this context |
| **Knowledge Priming** | Finding 2 | Martin Fowler article uses this exact phrase with a clear definition | Established, named, carries the "before generation, override training data" intent | Defined as the human's act of preparing context for the AI — not the agent's act of reading siblings; covers the wrong direction |
| **Convention Inspection** | No single Finding sustains it | Not found verbatim in any fetched source | — | **NOT A VALID CANDIDATE** — no verified source uses this exact phrase |

## Open questions

1. **Is the confirmation gate the distinguishing feature?** Most community practices describe an "explore" step but do not require the agent to surface findings to the engineer and wait for approval before writing. If the confirmation gate is the core differentiator, the name should signal it — none of the community names do.

2. **Is "Exploration" the right frame?** The community uses "explore" to mean "read files to understand the codebase." The Mother Rule uses sibling-file reading to identify a *pattern* and check against *anti-patterns* — closer to code review than exploration. These are different cognitive operations.

3. **Should the name signal the anti-pattern catalog?** The Mother Rule enforces a named list of forbidden shapes (Iceberg Class, Parameter-Passing Pipeline, etc.). None of the community practices include a project-specific anti-pattern catalog as part of the pre-generation step. A name that signals this would be unique to the 4Shark context.

4. **Scope question for the engineer**: Should the renamed rule still cover all five steps (read, identify, check, surface, wait) or should individual steps be named separately and composed? The community treats these as separable practices.

5. **"Mother Rule" hierarchy problem**: The engineer noted the name suggests "main/root rule" but the rule is specific to code generation. If a new name is chosen, should it be positionally humble (a workflow step, e.g., "pre-write pattern check") or descriptively comprehensive (naming all five sub-steps)?
