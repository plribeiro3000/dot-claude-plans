# SPIKE — GitHub-native AI PR review and triage

## Investigation question

Should the 4Shark `@agent-code-reviewer` and `/triage-pr` skills shift from producing local HTML reports to operating natively inside GitHub (posting inline review comments, suggested changes, resolving threads)? And for each skill, what are the practical trade-offs of each path?

---

## Sources consulted

- `agents/code-reviewer.md` — current code-reviewer agent definition; returns findings to main; main composes HTML
- `commands/triage-pr.md` — current triage-pr skill; fetches threads, classifies, renders HTML, then resolves/replies via GraphQL
- `scripts/triage-pr.sh` — fetches unresolved threads via GraphQL; already uses `resolveReviewThread` and `addPullRequestReviewThreadReply`
- https://code.claude.com/docs/en/code-review — Anthropic's own managed Code Review product; how it posts findings natively on GitHub
- https://docs.github.com/en/rest/pulls/reviews — GitHub REST API: create PR review with inline comments + suggestion blocks
- https://docs.github.com/en/rest/pulls/comments — GitHub REST API: line parameters (`line`, `side`, `start_line`, `start_side`)
- https://github.com/orgs/community/discussions/24848 — confirmed: suggestion markdown works via API; "a specific set of formatting that can be used in line comments"
- https://github.com/anthropics/claude-plugins-official/issues/423 — verbatim API call shape for posting suggestions via REST
- https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api — GraphQL rate limits; mutation cost
- https://github.blog/news-insights/product-news/introducing-check-runs-and-annotations/ — check run annotations vs review comments trade-offs
- https://github.com/reviewdog/reviewdog — reviewdog tool: surfaces PR findings via three configurable reporters
- https://medium.com/@haya14busa/reviewdog-github-check-improved-automated-review-experience-58f89e0c95f3 — check run annotations advantage for out-of-diff findings
- https://www.morphllm.com/github-ai-code-review — CodeRabbit scale data; context-switching friction quote
- https://dev.to/heraldofsolace/the-best-ai-code-review-tools-of-2026-2mb3 — 2026 survey; Copilot and CodeRabbit inline-comment surface confirmed verbatim
- https://www.greptile.com/what-is-ai-code-review — Greptile inline-comment surface confirmed verbatim
- https://github.com/sourcery-ai/sourcery — Sourcery inline-comment surface confirmed verbatim from README
- https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review — Copilot: posts inline comments + suggested changes; does not reply to Copilot's own comments
- https://blog.cloudflare.com/ai-code-review/ — Cloudflare internal multi-agent review; token cost data; posts to GitLab natively
- https://github.blog/ai-and-ml/generative-ai/agent-pull-requests-are-everywhere-heres-how-to-review-them/ — GitHub blog on reviewing agent PRs; no triage-of-others'-comments tooling mentioned
- See auxiliary: `github_native_pr_review_doc_1.md` — Anthropic Code Review product full documentation excerpt
- See auxiliary: `github_native_pr_review_doc_2.md` — GitHub REST API reference, suggestion syntax, GraphQL mutations, rate limits
- See auxiliary: `github_native_pr_review_doc_3.md` — Tool survey table; triage gap finding; Cloudflare token cost data; morphllm.com scope note
- See auxiliary: `github_native_pr_review_doc_4.md` — Primary-source inline-comment confirmation for 5 tools individually (Copilot, CodeRabbit, Greptile, Sourcery, Claude Code Review)

---

## Findings

### Finding 1: Five of the major AI code review tools confirmed to use native GitHub inline review comments as primary output surface

**Evidence:**
Every tool in the following primary-source-confirmed sample posts findings as inline review comments on the PR diff — not as separate HTML reports or external dashboards.

From the 2026 survey at https://dev.to/heraldofsolace/the-best-ai-code-review-tools-of-2026-2mb3:

**GitHub Copilot:**
> "You assign Copilot as a reviewer like any teammate. It leaves inline comments with suggested fixes."

**CodeRabbit:**
> "It runs automatically on new PRs, leaving line-by-line comments with severity rankings and one-click fixes."

From https://www.greptile.com/what-is-ai-code-review:

**Greptile:**
> "Inline comments: Precise, line-level suggestions tied to the diff for fast fixes."
> "The feedback left by AI code reviewers lives directly in platforms like GitHub and GitLab, so they integrate into existing workflows."

From https://github.com/sourcery-ai/sourcery (README):

**Sourcery:**
> "Every review will include a summary of the changes, high level feedback, and line by line suggestions/comments (where relevant)."

From https://code.claude.com/docs/en/code-review (full text in `github_native_pr_review_doc_1.md`):

**Claude Code Review (Anthropic managed):**
> "Code Review analyzes your GitHub pull requests and posts findings as inline comments on the lines of code where it found issues."

Scale context for CodeRabbit, from https://www.morphllm.com/github-ai-code-review:
> "CodeRabbit is the most widely installed AI code review app on GitHub, connected to over **2 million repositories** with **13 million+ PRs processed**"

**Scope note:** This sample covers 5 of the 9 tools in the survey table (`github_native_pr_review_doc_3.md`). Codacy, Qodo, reviewdog, and claude-code-action were not individually primary-source confirmed for their output surface in this spike — those 4 entries in the survey table come from secondary survey articles. The convergence claim is therefore scoped to the 5 confirmed tools. The full 9-tool primary-source audit was not completed.

**Source:** https://dev.to/heraldofsolace/the-best-ai-code-review-tools-of-2026-2mb3; https://www.greptile.com/what-is-ai-code-review; https://github.com/sourcery-ai/sourcery; https://code.claude.com/docs/en/code-review; https://www.morphllm.com/github-ai-code-review; `github_native_pr_review_doc_4.md`

**Significance:** For the 5 confirmed tools, local HTML reports are not used as the primary output surface. The 4Shark local-HTML pattern is the outlier within this confirmed sample. Whether the remaining 4 tools follow the same pattern is not verified in this spike.

---

### Finding 2: Anthropic's own Code Review product uses native inline comments + check run annotations (dual surface)

**Evidence:**
From the official Anthropic Code Review documentation:
> "Code Review analyzes your GitHub pull requests and posts findings as inline comments on the lines of code where it found issues."
> "Beyond the inline review comments, each review populates the **Claude Code Review** check run that appears alongside your CI checks."
> "Each finding also appears as an annotation in the **Files changed** tab, marked directly on the relevant diff lines. Annotations and the severity table are written to the check run independently of inline review comments, so they remain available even if GitHub rejects an inline comment on a line that moved."

Anthropic also supports pre-PR local review:
> "If you want to run reviews locally before opening a PR... a code-review plugin for running on-demand reviews locally before pushing."

**Source:** https://code.claude.com/docs/en/code-review; `github_native_pr_review_doc_1.md`

**Significance:** Anthropic itself has already answered the question for the PR-stage case: inline comments + check run. The local plugin exists for the pre-PR case. This is a hybrid by design.

---

### Finding 3: Suggested changes work via the REST API — no dedicated endpoint needed

**Evidence:**
GitHub's suggestion feature works by embedding a `suggestion` markdown code fence in the review comment body. The REST API (`POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews`) accepts `comments[].body` with this syntax and GitHub renders the "Apply suggestion" button automatically.

Verbatim API call shape from a filed issue on `anthropics/claude-plugins-official` (#423):
```json
{
  "path": "path/to/file.kt",
  "start_line": 10,
  "line": 12,
  "side": "RIGHT",
  "start_side": "RIGHT",
  "body": "Description of the issue.\n\n```suggestion\nfixed code here\n```"
}
```

From community discussion #24848 (https://github.com/orgs/community/discussions/24848), user romeara confirmed:
> "there is a specific set of formatting that can be used in line comments"

The discussion establishes that suggestions work through this markdown formatting in the comment body. The conclusion that there is no separate dedicated REST endpoint for suggestions is this spike's synthesis from reading the GitHub REST API docs (https://docs.github.com/en/rest/pulls/reviews) — the API docs show no `suggestions` endpoint; the only path is the `body` field of a review comment. This is synthesis, not a direct quote.

**Source:** https://github.com/anthropics/claude-plugins-official/issues/423; https://github.com/orgs/community/discussions/24848; https://docs.github.com/en/rest/pulls/reviews; `github_native_pr_review_doc_2.md`

**Significance:** The technical primitive exists. Posting a suggested change via the existing `gh api` call in `/triage-pr` is a matter of formatting the body string. No new API capability is required.

---

### Finding 4: The /triage-pr skill already operates natively on GitHub for Phase 5–6 — only Phase 1 (classification report) is local-HTML

**Evidence (codebase):**

`commands/triage-pr.md:193–211` (Phase 5 — "### API calls" header through end of GraphQL block):
```markdown
### API calls

Post the comment via `addPullRequestReviewThreadReply`, then resolve via `resolveReviewThread`:

gh api graphql -f query='
  mutation($threadId: ID!, $body: String!) {
    addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
      comment { id }
    }
  }' -F threadId="<thread_id>" -F body="<body>"
```

`commands/triage-pr.md:96–98` (Phase 1 — the HTML output block):
```markdown
**All at once mode (default for ≥1 thread):** render an HTML triage board to `/tmp/triage_pr_{repo}_{pr}_{timestamp}.html` using the `~/.claude/templates/html/code-review-board.html` template, then open it. Each thread becomes a card in the HTML with: classification badge (`[FP]` / `[FIX]` / `[ASK]`), file path + line, author, code excerpt, comment quote, verdict. Filter buttons let the engineer drill by classification or by author. The chat carries only the one-line summary (`Total: N threads — X fix · Y false positive · Z ask back. Report: /tmp/...`) and the decision prompt. The engineer reviews the HTML, then replies in chat with the decision list.
```

The skill is already a hybrid: classification happens locally (HTML), execution happens natively on GitHub (resolve + reply mutations). The engineer's complaint is specifically about the HTML classification report being too terse.

**Source:** `commands/triage-pr.md:96–98` and `commands/triage-pr.md:193–211`

**Significance:** The path to "operate fully on GitHub" for triage requires changing only Phase 1 (how classification is presented to the engineer before they decide), not the already-working Phase 5–6 infrastructure.

---

### Finding 5: No tool in the industry does triage of OTHERS' review comments

**Evidence:**
The survey of all major AI code review tools (GitHub Copilot, CodeRabbit, Greptile, Qodo, Sourcery, Codacy, Claude Code Review, claude-code-action, reviewdog) found no tool that:
- Reads threads from other reviewers (human or other AI bots)
- Classifies them as fix / false positive / ask-back
- Proposes resolution actions for the engineer to approve

From the GitHub Blog post on reviewing agent PRs (2025):
> The article "does not address AI triaging of existing reviewer comments or how agents should respond to feedback threads."

CodeRabbit accepts `@coderabbitai` commands to re-review specific items but does not classify threads from other reviewers.

**Source:** Survey in `github_native_pr_review_doc_3.md`; https://github.blog/ai-and-ml/generative-ai/agent-pull-requests-are-everywhere-heres-how-to-review-them/

**Significance:** `/triage-pr` is doing something the industry has not built yet. This finding is relevant because it means there is no established "how others do it" pattern to copy for the triage sub-problem. The hybrid approach (local classification + native execution) is currently the only known working design.

---

### Finding 6: Token cost argument requires clarification — HTML rendering does not duplicate token consumption

**Evidence:**
From Cloudflare's internal multi-agent review system (https://blog.cloudflare.com/ai-code-review/):

> "duplicating even a moderately-sized MR context across seven concurrent reviewers would multiply our token costs by 7x"

Their caching solution:
> "Sub-reviewers read this file instead of having the full MR context duplicated in each of their prompts"

The Cloudflare context is a multi-agent orchestration scenario (7 concurrent sub-reviewers each receiving the full MR context). This is distinct from the 4Shark scenario where a single agent reads the diff once and then chooses between HTML output vs. a GitHub API call.

The following is this spike's analysis (not a quote): the token cost is incurred during LLM analysis of the diff — not during rendering of output. Whether output is HTML or a GitHub comment, the same analysis tokens are consumed. The Cloudflare 7x argument applies to duplicating context across multiple concurrent agents, not to choosing between HTML and GitHub-native output in a single-agent flow.

The engineer's framing "duplicating into HTML burns tokens" conflates two phases:
- **Analysis phase**: reading the diff + code context → same cost regardless of output surface
- **Rendering phase**: composing HTML vs. calling GitHub API → tokens differ slightly but not materially (the HTML template adds ~500 tokens of structure; a GitHub API call body is similar in size)

What the token argument does address accurately: if a **second pass** is needed (e.g., fetching the full code from GitHub to enrich the HTML), that would be extra tokens. But the current design reads the diff locally, so no second pass occurs.

**Source:** https://blog.cloudflare.com/ai-code-review/; `github_native_pr_review_doc_3.md`

**Significance:** The Cloudflare token cost evidence applies to multi-concurrent-agent architectures, not to single-agent HTML-vs-API output choice. The real argument for going GitHub-native is engineer workflow (context stays on GitHub, no window switching) and audit trail (findings persist on the PR), not token savings.

---

### Finding 7: GitHub review comments have a rate limit of 80 content-generating requests/minute

**Evidence:**
From GitHub GraphQL rate limit documentation:
> "no more than 80 content-generating requests per minute and no more than 500 content-generating requests per hour"
> "GraphQL requests with mutations [cost] 5 points per request"
> Primary rate limit: "5,000 points per hour per user"

For a PR with 20 unresolved threads: 20 resolve calls + 20 reply calls = 40 mutations. At 5 points each = 200 points. Well within both the per-minute (80 calls = 400 points) and per-hour limits.

For the code-reviewer posting a new review: a single `POST /repos/.../reviews` call with N inline comments is ONE API call. No rate limit concern for typical PRs.

**Source:** https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api; `github_native_pr_review_doc_2.md`

**Significance:** Rate limits are not a practical constraint for 4Shark's PR volumes.

---

### Finding 8: Check run annotations are an alternative surface with different UX trade-offs

**Evidence:**
From the reviewdog documentation comparison:

Check run annotations:
- "don't clutter PR with comments"
- "can see findings which is not in Pull Request diff in check summary pages"
- Requires clicking the "Checks" tab to see details — one extra navigation step
- Used by: Codacy (alongside review comments), Claude Code Review (as secondary/fallback surface)

PR review comments:
- Immediately visible in the diff view alongside human reviewer comments
- "Will not clean up duplicated comments from violations that exist after multiple pushes, which can cause a lot of extra comments"
- Supports suggested changes (one-click apply)
- Does not support findings outside the diff

From the GitHub blog (introducing check runs):
> "Seeing annotations inline for a check run when reviewing a pull request provides the reviewer with more information in order to perform a more thorough review."

**Source:** https://medium.com/@haya14busa/reviewdog-github-check-improved-automated-review-experience-58f89e0c95f3; https://github.blog/news-insights/product-news/introducing-check-runs-and-annotations/; `github_native_pr_review_doc_2.md`

**Significance:** For the code-reviewer agent, check run annotations are a viable third option between "local HTML" and "inline PR comments" — less intrusive but requires tab navigation and cannot carry suggested changes.

---

### Finding 9: Pre-PR (working-tree changes) — local output remains the only viable path

**Evidence:**
- GitHub review comments require an open PR and a commit SHA to attach to. There is no PR before one is created.
- Anthropic's own product acknowledges this: their local `code-review` plugin exists specifically for "running on-demand reviews locally before pushing."
- `agents/code-reviewer.md:84–91` runs `git diff develop --stat`, `git diff develop`, etc. — these operate on the local working tree, not a PR.

**Source:** https://code.claude.com/docs/en/code-review; `agents/code-reviewer.md:84–91`

**Significance:** For `@agent-code-reviewer` invoked before a PR exists, local output (HTML or chat) is the only option. The question of GitHub-native applies only when a PR already exists.

---

## Trade-offs surfaced

| Factor | GitHub-native inline comments | Local HTML report |
|--------|------------------------------|-------------------|
| **Context** | All code, diff, previous discussion visible in one GitHub UI | Engineer must open HTML + diff in GitHub side-by-side |
| **Suggested changes** | One-click "Apply suggestion" button available to PR author | Engineer must manually apply from HTML |
| **Audit trail** | Findings persist permanently on the PR; visible to all reviewers | Lives only in `/tmp/` on engineer's laptop; ephemeral |
| **Multi-reviewer visibility** | AI findings appear in same thread as human reviewer comments | Only the engineer using the tool sees the report |
| **Token cost** | Same analysis cost; rendering cost comparable | Same analysis cost; HTML template adds ~500 tokens |
| **Rollback if AI hallucinates** | Comments stay on PR until manually dismissed/resolved; no one-step undo | Delete the HTML file; nothing posted to shared repo |
| **Engineer review gate** | In current tools: AI posts immediately (no gate). A gate could be added via pending review draft | HTML shown to engineer locally before any action; natural gate |
| **Offline / pre-PR use** | Not possible — requires open PR + commit SHA | Works on local working tree changes |
| **Comment noise** | Risk of many comments accumulating across pushes if not auto-resolved | No PR comment noise |
| **GitHub API dependency** | Requires network + GitHub token | Fully local; works airgapped |
| **Out-of-diff findings** | Check run annotations surface them; inline comments cannot | HTML can show any finding regardless of diff scope |

---

## What remains uncertain

1. **Engineer review gate for GitHub-native posting**: if `@agent-code-reviewer` posted directly to a PR, the engineer would not see the findings before they appear on GitHub. The current local-HTML flow gives the engineer a chance to review before anything is posted. The industry tools (Copilot, CodeRabbit) post immediately without a gate — but they do not carry the "main session reviews before posting" model that 4Shark uses. Whether a "post as PENDING review, show engineer, then submit" pattern would work is untested.

2. **Suggested changes for multi-line blocks in Ruby/Rails**: the suggestion syntax works for replacing a range of lines, but the exact behavior when the suggestion body itself contains code blocks (triple backticks) is documented as requiring tilde-fence escaping (source: community discussion #76840). The 4Shark codebase is primarily Ruby/Rails; this edge case needs a test.

3. **Auto-resolve on next push**: Copilot and Claude Code Review auto-resolve their own threads when the issue is fixed on a subsequent push. Whether `/triage-pr` should do the same for FIX items (rather than resolving immediately after the fix commit) is an open design question. Resolving immediately is the current behavior; auto-resolve-on-push would require a GitHub Action webhook.

4. **Rate limit for large PRs**: the 80 content-generating requests/minute limit applies to posting multiple inline comments. A single `POST .../reviews` with 50+ inline comments is ONE call — but what GitHub counts as "content-generating" for the review comments array is not explicitly documented. Needs empirical testing for PRs with >50 findings.

5. **Copilot's behavior when you reply to its threads**: from GitHub Docs: "Any comments you add to Copilot's review comments will be visible to humans, but they won't be visible to Copilot, and Copilot won't reply." This means `/triage-pr`'s draft reply for [ASK] items directed at Copilot threads will reach the PR but Copilot will not respond to them — the reply only informs human reviewers of the triage decision.

6. **`@agent-code-reviewer` + GitHub-native path requires a PR to exist**: the agent is currently invoked before PR creation (local working-tree review). If the role is split into "pre-PR local" and "post-PR GitHub-native," that is a workflow change with downstream effects on when and how engineers invoke the agent.

7. **Full 9-tool primary-source audit not completed**: Finding 1 is scoped to 5 confirmed tools. Codacy, Qodo, reviewdog, and claude-code-action were not individually primary-source confirmed for output surface. Whether the convergence claim holds for all 9 tools is an open question.

---

## Suggested options for main and the engineer

### Option A: Keep both skills local-HTML — enrich the HTML instead
Expand the HTML triage board to include: the original comment thread (full text), the diff chunk around the flagged line, and the proposed fix side-by-side. This addresses the engineer's stated complaint ("too terse to decide from") without changing where the output lives. Trade-off: context still requires switching between HTML and GitHub; no suggested-change one-click apply; no persistent audit trail.

### Option B: `@agent-code-reviewer` stays local; `/triage-pr` Phase 1 moves to GitHub-native
`/triage-pr` already executes natively on GitHub (Phases 5–6). Moving Phase 1 to post classification as GitHub comments (rather than HTML) means the triage decisions appear on the PR where the threads already live. The engineer reviews triage decisions inside GitHub's PR UI, then confirms back in chat. `@agent-code-reviewer` stays local-HTML because it often runs before a PR exists.

### Option C: Split `@agent-code-reviewer` by context — pre-PR stays local; PR-stage goes GitHub-native
When invoked with a PR number, `@agent-code-reviewer` posts findings as a pending review draft (not submitted), shows the engineer the draft summary in chat, and the engineer says "submit" or edits before posting. When invoked on local changes (no PR), produces the current HTML. This matches Anthropic's own product hybrid pattern.

### Option D: `/triage-pr` eliminates the HTML entirely — presents triage in-chat, executes on GitHub
The pacing gate in `triage-pr.md:86–98` already produces a one-line chat summary. Remove the HTML step; present triage blocks inline in chat (the "walk-through-one-by-one" mode already exists); execute Phase 5–6 as now. The chat becomes the interface and GitHub becomes the execution surface. Trade-off: no archival HTML for post-hoc reference; requires the engineer to be in the chat session for the full triage cycle.

### Option E: Add check run annotations as a third surface alongside inline comments
For `@agent-code-reviewer` on a PR, post findings as a check run with annotations (no inline comments). Cleaner PR, no comment noise, findings visible in the Files Changed tab as color-coded markers. Trade-off: cannot carry suggested changes; engineer must navigate to the Checks tab. Used by Codacy and Claude Code Review as their secondary surface.
