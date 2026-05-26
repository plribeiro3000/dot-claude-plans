# SPIKE: Prompt Engineering Advanced — Frameworks & Best Practices

## Question

What should the second presentation cover? After the team went through "Prompting Engineering for Dummies" (mindset shift, communication-first, APE framework, common mistakes), what's the next step to make them proficient with AI?

## Status

**In Progress** — Initial research only. Needs deeper investigation before planning.

## Context

This is the sequel to **Presentation 1: Prompting Engineering for Dummies** (`~/.claude/plans/active/content/prompting-engineering-for-dummies/`).

Presentation 1 covers:
- Communication as the real problem (not AI)
- "People compensate for you, AI doesn't" insight
- APE framework (Action, Purpose, Expectation) as starter
- 5 common mistakes with before/after examples
- Wake-up call to evolve and learn continuously

Presentation 2 needs to build on that foundation — not repeat it.

## Initial Research Directions

### 1. Advanced Frameworks

Frameworks identified in Presentation 1's research that were intentionally deferred:

| Framework | Elements | Why for Presentation 2 |
|-----------|----------|----------------------|
| **RACE** | Role, Action, Context, Expectations | Natural next step from APE — adds Role and Context as explicit elements |
| **CO-STAR** | Context, Objective, Style, Tone, Audience, Response | Most complete framework, won Singapore GPT-4 competition — the "graduate" level |
| **CRISP** | Clarity, Relevance, Intent, Specificity, Precision | Meta-framework for EVALUATING prompts — useful for self-improvement |

**Open question**: Should we teach RACE and CO-STAR as progression, or pick one and go deep? The research from Presentation 1 says "one framework per presentation" — but this audience will already have APE.

### 2. Techniques Beyond Frameworks

| Technique | What it is | Relevance |
|-----------|-----------|-----------|
| **Few-shot prompting** | Give 2-3 examples before the request | Dramatic improvement (0% → 90% accuracy in one study) |
| **Iteration / refinement** | Build on previous responses | Already introduced in Catch 5, but needs deeper treatment |
| **Output priming** | Start the response for the AI | Powerful for format control |
| **Meta-prompting** | Ask AI to help design better prompts | "Use AI to get better at using AI" |
| **Prompt chaining** | Break complex tasks into sequential prompts | Extension of Catch 4 (one thing at a time) |

### 3. Practical Application by Area

The team is mixed (operations, commercial, engineering). Presentation 2 could have area-specific sections:

- **Operations**: Process documentation, SOPs, reporting automation, delivery tracking
- **Commercial**: Proposals, client emails, follow-ups, competitive analysis
- **Engineering**: Code review, debugging, architecture decisions, documentation

**Open question**: Is this the right approach or does it fragment the audience? Maybe better to keep universal and let them apply to their own context.

### 4. The Learning Loop (deep dive)

Presentation 1 introduces the concept: "when it goes wrong, investigate why." Presentation 2 could go deeper:

- How to ask AI "why did you go that direction?"
- How to identify if the error is YOUR communication vs. AI limitation
- How to adapt your process for AI limitations
- How to build a personal prompt library that evolves
- How to measure if you're getting better

### 5. Tools & Productivity

- Speech-to-text for faster context delivery
- Prompt templates / snippets
- ChatGPT custom instructions / Claude Projects
- When to use which AI tool

## Open Questions (need investigation)

1. What's the ideal gap between Presentation 1 and 2? (days, weeks?)
2. Should Presentation 2 include hands-on exercises? (Blackstone+Cullen data says practical application is critical)
3. How to measure if Presentation 1 had impact before running Presentation 2?
4. Should area-specific content be in Presentation 2 or in separate mini-sessions?

## Next Steps

- [ ] Deeper research on each direction above
- [ ] Decide structure and scope
- [ ] Create PLAN.md with narrative arc
- [ ] Create Gamma prompt
