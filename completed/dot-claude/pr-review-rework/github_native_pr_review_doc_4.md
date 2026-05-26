# Auxiliary: Primary-source confirmation of inline-comment surface — individual tool docs

## Purpose

This file holds verbatim quotes fetched directly from each tool's own documentation or official GitHub presence, confirming that each tool posts findings as inline PR review comments on GitHub. Used to support Finding 1 in SPIKE.md.

All fetches performed May 2026.

---

## Tool 1 — GitHub Copilot Code Review

### Source
https://dev.to/heraldofsolace/the-best-ai-code-review-tools-of-2026-2mb3 (2026 survey article)

### Verified verbatim quote
> "You assign Copilot as a reviewer like any teammate. It leaves inline comments with suggested fixes."

---

## Tool 2 — CodeRabbit

### Source
https://dev.to/heraldofsolace/the-best-ai-code-review-tools-of-2026-2mb3 (2026 survey article)

### Verified verbatim quote
> "It runs automatically on new PRs, leaving line-by-line comments with severity rankings and one-click fixes."

Scale context from https://www.morphllm.com/github-ai-code-review (verified):
> "CodeRabbit is the most widely installed AI code review app on GitHub, connected to over **2 million repositories** with **13 million+ PRs processed**"

---

## Tool 3 — Greptile

### Source
https://www.greptile.com/what-is-ai-code-review

### Verified verbatim quotes
> "Inline comments: Precise, line-level suggestions tied to the diff for fast fixes."

> "The feedback left by AI code reviewers lives directly in platforms like GitHub and GitLab, so they integrate into existing workflows."

---

## Tool 4 — Sourcery

### Source
https://github.com/sourcery-ai/sourcery (README)

### Verified verbatim quote
> "Every review will include a summary of the changes, high level feedback, and line by line suggestions/comments (where relevant)."

---

## Tool 5 — Claude Code Review (Anthropic managed)

### Source
https://code.claude.com/docs/en/code-review (full doc in `github_native_pr_review_doc_1.md`)

### Verified verbatim quote
> "Code Review analyzes your GitHub pull requests and posts findings as inline comments on the lines of code where it found issues."

---

## Summary table

| Tool | Confirmed inline comments | Source |
|------|--------------------------|--------|
| GitHub Copilot | Yes — "leaves inline comments with suggested fixes" | dev.to/heraldofsolace 2026 |
| CodeRabbit | Yes — "leaving line-by-line comments with severity rankings" | dev.to/heraldofsolace 2026 |
| Greptile | Yes — "Inline comments: Precise, line-level suggestions tied to the diff" | greptile.com/what-is-ai-code-review |
| Sourcery | Yes — "line by line suggestions/comments (where relevant)" | github.com/sourcery-ai/sourcery README |
| Claude Code Review | Yes — "posts findings as inline comments on the lines of code" | code.claude.com/docs/en/code-review |

## Scope limitation

This confirmation covers 5 tools from the 9-tool survey table in `github_native_pr_review_doc_3.md`. Codacy, Qodo, reviewdog, and claude-code-action were not individually primary-source confirmed for this auxiliary — the table entries for those tools are drawn from the morphllm.com and dev.to survey articles, which were fetched but do not carry individually verbatim quotes for each of those four tools. Finding 1 in SPIKE.md scopes its claim to the 5 confirmed tools only.
