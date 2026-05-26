# Auxiliary: Tool survey — how each AI code review tool surfaces findings

## Sources used in this document

- https://dev.to/heraldofsolace/the-best-ai-code-review-tools-of-2026-2mb3 (fetched May 2026)
- https://www.morphllm.com/github-ai-code-review (fetched May 2026)
- https://www.greptile.com/what-is-ai-code-review (fetched May 2026)
- https://github.com/sourcery-ai/sourcery (README, fetched May 2026)
- https://blog.cloudflare.com/ai-code-review/ (fetched May 2026)

---

## Tool-by-tool surface catalog

| Tool | Surface used | Suggested changes | Triage of others' comments | License/cost |
|------|-------------|------------------|---------------------------|-------------|
| **GitHub Copilot Code Review** | Native inline PR review comments (same thread as human reviewers) | Yes — one-click apply; starting June 2026 costs GitHub Actions minutes | No | Included in GitHub Copilot subscription |
| **CodeRabbit** | Inline PR review comments; walkthrough summary as first comment | Yes — one-click apply via "Commit suggestion" | No dedicated triage feature; accepts `@coderabbitai` commands | Free tier + paid plans |
| **Claude Code Review** (Anthropic managed) | Inline PR review comments + check run annotations (dual surface) | Not mentioned explicitly | No | ~$15–25/review (Team/Enterprise) |
| **claude-code-action** (GitHub Action) | Responds to `@claude` mentions in PR/issue comments; posts responses as comments | Through Claude Code CLI capabilities | No dedicated triage feature | API token cost |
| **Greptile** | Inline review comments; codebase-aware graph analysis | Not specified | No | Paid |
| **Qodo** | Inline PR review comments with severity rankings | One-click fixes | No | Paid |
| **Sourcery** | Inline review comments — "line by line suggestions/comments" | Yes | No | Free + paid |
| **Codacy** | Both check run annotations AND inline review comments | Partial | No | Paid |
| **reviewdog** | Configurable: `github-pr-review` (inline comments) OR `github-pr-check` (annotations) | No | No | Open source |

---

## Verbatim primary-source quotes confirming inline-comment surface (verified May 2026)

### GitHub Copilot
Source: https://dev.to/heraldofsolace/the-best-ai-code-review-tools-of-2026-2mb3

> "You assign Copilot as a reviewer like any teammate. It leaves inline comments with suggested fixes."

### CodeRabbit
Source: https://dev.to/heraldofsolace/the-best-ai-code-review-tools-of-2026-2mb3

> "It runs automatically on new PRs, leaving line-by-line comments with severity rankings and one-click fixes."

### Greptile
Source: https://www.greptile.com/what-is-ai-code-review

> "Inline comments: Precise, line-level suggestions tied to the diff for fast fixes."

> "The feedback left by AI code reviewers lives directly in platforms like GitHub and GitLab, so they integrate into existing workflows."

### Sourcery
Source: https://github.com/sourcery-ai/sourcery (README)

> "review any pull request on any GitHub repository to provide instant feedback on the proposed changes"
> "Every review will include a summary of the changes, high level feedback, and line by line suggestions/comments (where relevant)."

---

## Key finding: triage of others' comments

**No tool found in this survey addresses the specific sub-problem of triaging existing review comments left by OTHER reviewers (human or AI) — classifying them as fix / false positive / ask.**

The industry pattern is:
1. Tool generates NEW findings (original review pass)
2. Human decides per-finding
3. Some tools auto-resolve their own threads when the code is fixed on the next push

The `/triage-pr` skill at `commands/triage-pr.md` is doing something the survey found NO commercial tool doing: acting as an agent that reads threads from OTHER reviewers (Copilot, humans) and classifies them to reduce engineer cognitive load.

---

## What morphllm.com actually contains (verified May 2026)

The morphllm.com page (https://www.morphllm.com/github-ai-code-review) contains the following verified quote about CodeRabbit scale:

> "CodeRabbit is the most widely installed AI code review app on GitHub, connected to over **2 million repositories** with **13 million+ PRs processed**"

The page describes context-switching friction in general terms:
> "The workflow: read the inline comment, understand the suggestion, switch to your editor, find the right file, make the change"
> "For multi-file refactors suggested across several modules, the back-and-forth between GitHub review comments and your editor creates friction"

NOTE: The phrases "No separate report mechanism is mentioned — all tools appear to surface findings through GitHub's native PR interface rather than dedicated dashboards." and "Multi-tool setups demand careful workflow planning, because tools that force context switches to separate dashboards can reduce the productivity they aim to improve." do NOT appear on the live morphllm.com page as of May 2026 fetch. They are NOT quoted in this auxiliary or in SPIKE.md.

---

## Cloudflare's internal approach (source: https://blog.cloudflare.com/ai-code-review/)

Cloudflare built a CI-native orchestration system using up to 7 specialized sub-reviewers. Key cost findings:

> "duplicating even a moderately-sized MR context across seven concurrent reviewers would multiply our token costs by 7x"

Their caching approach:
> "Sub-reviewers read this file instead of having the full MR context duplicated in each of their prompts"

> "They achieved an 85.7% cache hit rate which saves an estimated five figures compared to what we would pay at full input token pricing."

The implication for rendering a local HTML report: if the diff has already been processed to generate the HTML, re-rendering it into HTML does NOT re-read the diff — the token cost is already paid by the time the HTML is composed. The argument "burns tokens" is about the LLM processing the diff, not about whether the output is HTML or a GitHub comment. Both paths consume the same tokens during analysis.
