# Auxiliary: GitHub API documentation — PR reviews and suggested changes

## Source 1: GitHub REST API — Create a pull request review
URL: https://docs.github.com/en/rest/pulls/reviews

### Endpoint
```
POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

### Key parameters
- `commit_id` (optional): SHA of commit — defaults to most recent
- `body`: required for REQUEST_CHANGES or COMMENT events
- `event`: `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`; omit for PENDING state
- `comments` (optional array): inline comments with:
  - `path` (required): relative file path
  - `line` (integer): line in the blob
  - `side` (`LEFT` | `RIGHT`): LEFT for deletions, RIGHT for additions
  - `start_line` (integer): for multi-line comments — first line of range
  - `start_side`: matching side for start_line
  - `body` (required): the comment text

> "This endpoint triggers notifications. Creating content too quickly using this endpoint may result in secondary rate limiting."

### Suggested changes via body field
The `suggestion` markdown code fence in the body field renders as an "Apply suggestion" button in the GitHub UI.

**Format (from community issue https://github.com/anthropics/claude-plugins-official/issues/423):**
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

> Key finding from community discussion #24848: "there is a specific set of formatting that can be used in line comments" — the suggestion markdown is rendered by GitHub as a native one-click-apply button. There is NO dedicated REST API endpoint for suggestions; it works through markdown formatting in the comment body.

---

## Source 2: GitHub GraphQL API — Mutations used by /triage-pr

### addPullRequestReviewThreadReply
Already used by `/triage-pr` at `scripts/triage-pr.sh` + `commands/triage-pr.md:196–210`.

```graphql
mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
    comment { id }
  }
}
```

### resolveReviewThread
Already used by `/triage-pr` at `commands/triage-pr.md:196–210`.

```graphql
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}
```

### Rate limits (source: https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api)

> "For users: 5,000 points per hour per user."
> "GraphQL requests with mutations [cost] 5 points per request"
> "no more than 80 content-generating requests per minute and no more than 500 content-generating requests per hour"

Practical implication: 80 mutation calls per minute. A PR with 20 review threads (resolve + reply per thread = 40 calls) fits comfortably within limits.

---

## Source 3: Check runs vs review comments
URL: https://github.blog/news-insights/product-news/introducing-check-runs-and-annotations/

> "Checks provide line annotations, more detailed messaging, and are only available for use with GitHub Apps."
> "When inline comments are on the same line as an annotation, two separate indicators appear: a diamond symbol for the annotations and a circle for comments."

Key trade-off (from reviewdog documentation):
- Check run annotations: don't clutter PR with comments; can show issues outside diff context in summary tab; requires tab navigation to see
- PR review comments: immediately visible in diff view to all reviewers; risk of accumulating duplicate comments across pushes
