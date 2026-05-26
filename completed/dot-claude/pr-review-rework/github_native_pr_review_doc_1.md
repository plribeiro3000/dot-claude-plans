# Auxiliary: Anthropic Code Review official documentation

Source: https://code.claude.com/docs/en/code-review

## How findings are posted

> "Code Review analyzes your GitHub pull requests and posts findings as inline comments on the lines of code where it found issues."

> "When a review runs, multiple agents analyze the diff and surrounding code in parallel on Anthropic infrastructure. Each agent looks for a different class of issue, then a verification step checks candidates against actual code behavior to filter out false positives. The results are deduplicated, ranked by severity, and posted as inline comments on the specific lines where issues were found, with a summary in the review body."

## Dual surface: inline review comments + check run

> "Beyond the inline review comments, each review populates the **Claude Code Review** check run that appears alongside your CI checks. Expand its **Details** link to see a summary of every finding in one place, sorted by severity."

> "Each finding also appears as an annotation in the **Files changed** tab, marked directly on the relevant diff lines. Important findings render with a red marker, nits with a yellow warning, and pre-existing bugs with a gray notice. Annotations and the severity table are written to the check run independently of inline review comments, so they remain available even if GitHub rejects an inline comment on a line that moved."

## Pre-PR local review also exists

> "If you want to run reviews locally before opening a PR, need a self-hosted setup [...] Plugins: browse the plugin marketplace, including a code-review plugin for running on-demand reviews locally before pushing"

## Pricing

> "Each review averages $15–25 in cost, scaling with PR size, codebase complexity, and how many issues require verification."

## Severity levels

| Marker | Severity     | Meaning                                                             |
| :----- | :----------- | :------------------------------------------------------------------ |
| 🔴     | Important    | A bug that should be fixed before merging                           |
| 🟡     | Nit          | A minor issue, worth fixing but not blocking                        |
| 🟣     | Pre-existing | A bug that exists in the codebase but was not introduced by this PR |
