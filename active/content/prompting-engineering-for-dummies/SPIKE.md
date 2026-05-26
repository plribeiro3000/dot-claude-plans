# SPIKE: Prompt Engineering Presentations — Market Research

## Question

What exists in the market for beginner-oriented prompt engineering presentations? How are they structured, what frameworks do they teach, what techniques do they use, and where are the gaps?

## Status

**Completed** — Research informed the PLAN.md for the first presentation.

## Research Files

- `/tmp/prompt_engineering_presentations_research_20260328.md` — Comprehensive research: presentations, frameworks, analogies, anti-patterns, aha moments, storytelling techniques, structure patterns, exercises, official guides
- `/tmp/prompt_engineering_comparison_analysis_20260328.md` — Comparative analysis: our presentation vs. the market across 9 dimensions

## Key Findings

### Market Landscape

The market has three buckets:
- **Bucket A — Technical** (dominant): DAIR.AI, Anthropic tutorial, AWS Quest, OpenAI guide
- **Bucket B — "Accessible Beginner"** (growing): University of Victoria, Coursera/Udemy, IBM guide
- **Bucket C — Truly Non-Technical** (rare): Blackstone+Cullen, Ziya GmbH, AI for Education

68% of businesses train non-technical staff on PE, but with content designed for technical audiences and then "simplified" — not designed from scratch for non-technical people (Blackstone+Cullen).

### Frameworks Catalogued

| Tier | Frameworks | Best For |
|------|-----------|----------|
| Beginner | APE, RTF, TAG | Entry point, simple tasks |
| Intermediate | CO-STAR, RACE, CLEAR, ROSES | Professional use, business tasks |
| Advanced | CRISP, OSCAR, PECRA | Complex projects, QA |
| Creative | AIDA, PAS, SCAMPER | Marketing, brainstorming |

**APE** (Action, Purpose, Expectation) chosen for presentation 1 as the validated beginner entry point. **RACE** and **CO-STAR** reserved for presentation 2.

### Anti-patterns ("Big 7")

1. Being too vague (100% of sources)
2. Overloading with multiple tasks (~80%)
3. Not iterating / one-shot mentality (~75%)
4. Not providing context (~90%)
5. Wall-of-text / no structure (~70%)
6. Using negative language (~60%)
7. Ignoring model limitations (~50%)

### Gaps We Exploit (Unique Positioning)

| Gap | Market Status | Our Approach |
|-----|--------------|--------------|
| Communication-first framing | Exists in articles, NOT in presentations | Central thesis |
| "People compensate, AI doesn't" insight | Written about (Frazier, Mallick), never presented | Core reveal |
| "AI as mirror" metaphor | Fragments in 7+ articles, never crystallized | Act 5 metaphor |
| Wake-up call tone | 0% of presentations use it; 100% is gentle | Act 8 tone |
| Emotional storytelling as main vehicle | Used as 30-60s hooks only | Entire presentation |
| 4-beat repeating mechanic | Only 2-beat before/after exists | All catches |
| Non-technical by design | Most is "simplified technical" | Built from scratch |

### Sources

Full source list in the research files. Key references:
- [PR Daily — Prompt engineering is just good communication](https://www.prdaily.com/prompt-engineering-is-just-good-communication/)
- [EverWorker — It's Not Prompt Engineering. It's Just Communication](https://everworker.ai/blog/its-not-prompt-engineering-its-just-communication)
- [Laurel Frazier — Human Communication, Engineered](https://medium.com/@laurel.frazier/human-communication-engineered-a26937b735dc)
- [Austin Mallick — AI proves we suck at communicating](https://medium.com/@austin.mallick/ai-proves-we-suck-at-communicating-21901032738d)
- [Blackstone+Cullen — Training for Non-Technical Teams](https://www.blackstoneandcullen.com/blog/ai-training/business-prompt-engineering-training-for-non-technical-teams/)
- [Anthropic — Prompting Best Practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices)

## Impact

Research directly shaped:
- Choice of APE as starter framework
- Selection of 5 anti-patterns for catches
- Communication-first framing (Act 5)
- "People compensate, AI doesn't" insight (slides 18-19)
- 4-beat catch mechanic (no existing precedent found)
- Wake-up call tone instead of confrontation (Act 8)

## Next Steps

Research feeds into **Presentation 2** (advanced frameworks, practical techniques) — see `~/.claude/plans/active/content/prompting-engineering-advanced/SPIKE.md`.
