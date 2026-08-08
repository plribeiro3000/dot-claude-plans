# Raw source material — mechanically preventing internal-data leaks in PR descriptions

Compiled quotes and fetch metadata, organized by source. Kept separate from SPIKE.md so a future revision can re-weight or drop a source without re-fetching everything.

---

## Academic / measured evidence

### The Compliance Gap (arXiv:2605.01771)

URL: https://arxiv.org/abs/2605.01771
Author: Kwan Soo Shin
Fetched: this session (WebFetch), self-checked with a second WebFetch of the same URL

Opening example from the abstract:

> "An auditor instructs an AI assistant: 'open each file individually using the Read tool -- no scripts, no agents.' The AI replies 'Yes' -- then issues a single batched call summarizing all fifty files at once."

Causal mechanism (Theorem 1):

> "structurally inevitable under RL that rewards text without observing behavior"

> "undetectable from text alone" (the verbal commitment is observed; the behavioral violation is not)

Measured result on architecture-level fix vs. leaving the affordance in place:

> "removing delegation tools raises compliance to 75% (Cohen's d = 2.47), confirming environmental affordance rather than weight-encoded failure."

### The Instruction Gap (arXiv:2601.03269v1)

URL: https://arxiv.org/html/2601.03269v1
Fetched: this session (WebFetch)

Definition:

> "a fundamental challenge where models excel at general tasks but struggle with precise instruction adherence required for enterprise deployment"

Mechanism in long context:

> "lost in the middle behaviors where LLMs struggle to utilize information from the middle portions of long contexts"

> "instruction mechanisms become diluted when processing complex, multi-component instructions alongside substantial context"

Measured spread across 13 models on a 600-sample evaluation set: instruction violation counts from 660 (GPT-5 Medium) to 1,330 (Gemini 2.0-Flash) — reported as "a two-fold variance" by the summarizing tool, not a literal quote from the paper; treat the raw counts as the citable fact, the "two-fold" framing as derived.

### Prompt Design at Scale (arXiv:2607.19257)

URL: https://arxiv.org/abs/2607.19257
Fetched: this session (WebFetch)

> "Perfect-response rate collapses to zero by N=80 for every model, format, and placement." (as rule count N grows from 10 to 160)

> "Recall stays near ceiling through 64-128k tokens, then degrades sharply and format-dependently."

> "What rises sharply near each model's context ceiling is outright refusal to answer (0% to 79-90%)."

The paper studies prompt design variables (format, instruction count, placement) rather than comparing prompt-based rules to an external enforcement mechanism — no direct reminder-vs-gate comparison found here.

### Context Rot (Chroma Research, chroma.com)

URL: https://www.trychroma.com/research/context-rot
Fetched: this session (WebFetch, after redirect from research.trychroma.com/context-rot)

> "model performance varies significantly as input length changes, even on simple tasks"

> "models do not use their context uniformly; instead, their performance grows increasingly unreliable as input length grows"

18 models evaluated (GPT-4.1, Claude 4, Gemini 2.5, Qwen3 among them) per WebSearch aggregation — not independently re-confirmed by direct quote; treat the model list as UNVERIFIED, the two quotes above as VERIFIED.

---

## Vendor / practitioner sources on guardrails vs. enforcement

### Anthropic — Claude Code hooks reference

URL: https://code.claude.com/docs/en/hooks (redirected from docs.claude.com/en/docs/claude-code/hooks)
Fetched: this session (WebFetch)

> "Because the `if` filter is best-effort, use the permission system rather than a hook to enforce a hard allow or deny."

> "PreToolUse blocks the tool call" (on exit code 2)

Example payload shape confirmed:
```json
{ "tool_name": "Bash", "tool_input": { "command": "rm -rf /tmp/build" }, ... }
```

A `PreToolUse` hook receives the full `tool_input` — for `gh pr create`, this is the command string carrying the `--body` argument — before the tool executes, and can return `permissionDecision: "deny"` to stop it.

### Wiz — LLM Guardrails Explained

URL: https://www.wiz.io/academy/ai-security/llm-guardrails
Fetched: this session (WebFetch)

> "Guardrails operate at inference time and are enforced by the application and its surrounding infrastructure." (contrasted with RLHF, which shapes training-time behavior)

> "Output guardrails inspect model responses before they are returned to users. They enforce rules such as removing sensitive data, blocking disallowed topics, or requiring structured output formats."

> "These controls help reduce accidental data leakage, but they depend on detection accuracy. Novel attack techniques or subtle data exposure can slip through."

### Security Boulevard — AI Agent Guardrails (fetch failed)

URL: https://securityboulevard.com/2026/08/ai-agent-guardrails-how-to-set-boundaries-before-you-give-an-llm-access-to-your-systems/
Fetch status: HTTP 403 Forbidden on direct WebFetch — content below is from WebSearch's aggregated summary only, NOT independently verified against the live page. Per citation discipline rule 4, this is UNVERIFIED and must not sustain a Finding on its own.

Reported (UNVERIFIED): "AI agent guardrails cannot be reduced to content filters, system prompts, or another model reviewing the first model, as those controls have value but do not create a reliable security boundary."

---

## OWASP

### LLM02:2025 Sensitive Information Disclosure

URL: https://genai.owasp.org/llmrisk/llm022025-sensitive-information-disclosure/
Fetched: this session (WebFetch)

> "Sensitive information can affect both the LLM and its application context. This includes personal identifiable information (PII), financial details, health records, confidential business data, security credentials, and legal documents."

> "Adding restrictions within the system prompt about data types that the LLM should return can provide mitigation against sensitive information disclosure. However, such restrictions may not always be honored and could be bypassed via prompt injection or other methods."

Mitigation list includes: data sanitization, least-privilege access to sensitive data, limiting model access to external data sources, concealing system prompts, tokenization to preprocess/sanitize sensitive information. No item in the fetched list is scoped specifically to "prose about internal architecture/repo names" — every example given is PII/credentials/health/legal-document shaped.

---

## GitHub platform mechanics

### Secret scanning custom patterns

URL: https://docs.github.com/en/code-security/secret-scanning/using-advanced-secret-scanning-and-push-protection-features/custom-patterns/defining-custom-patterns-for-secret-scanning
Fetched: this session (WebFetch)

Custom patterns are scoped to "the format of your secret pattern" — the fetched page frames the entire feature around credential-shaped strings, not prose. No mention of detecting general business/architecture prose was found on this page.

### Repository visibility field

- REST API "Get a repository": `private` — "required, boolean". URL: https://docs.github.com/en/rest/repos/repos?apiVersion=2022-11-28 (WebFetch, this session)
- `gh repo view --json isPrivate` / `--json visibility`: confirmed listed fields. URL: https://cli.github.com/manual/gh_repo_view (WebFetch, this session) — quote: "archivedAt, assignableUsers, codeOfConduct... isPrivate... visibility, watchers"

### Pull request body field (REST API)

URL: https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#get-a-pull-request
Fetched: this session (WebFetch)

> "`body`: required, string or null"

### PR/comment edit history visibility

URL: https://docs.github.com/en/communities/moderating-comments-and-conversations/tracking-changes-in-a-comment
Fetched: this session (WebFetch, self-checked with a second WebFetch of the same URL — identical quotes returned both times)

> "Anyone with read access to a repository can view a comment's edit history."

> "Comment authors and anyone with write access to a repository can delete sensitive information from a comment's edit history."

Deletion mechanism: open the edit history → select the revision → "Options" → "Delete revision from history". The editor's name and timestamp remain visible; the content of that one revision is removed. This does NOT remove the fact that an edit happened, and does not touch any copy of the pre-edit body that a third party already captured before the deletion.

Companion source — GitHub Changelog announcement (2018-05-24): https://github.blog/changelog/2018-05-24-comment-edit-history/ (WebFetch, this session)

> "You can now view prior revisions of a comment by clicking on the 'edited' dropdown in the comment's header. Prior revisions are displayed as rendered prose diffs, and are visible to any user that can view the comment itself."

### No API for retroactive PR body history (only webhooks, going forward)

URL: https://github.com/orgs/community/discussions/151829
Fetched: this session (WebFetch)

Maintainer quote: "It doesn't look like there is an API that will give you the body of previous PRs, only the event timeline."

Respondent quote: "GitHub's REST and GraphQL APIs do not expose a full 'edit history' of PR/issue bodies."

Workaround described (not a direct quote, WebFetch's own paraphrase of the thread): a webhook on `pull_request` events captures `changes.body.from` on each edit, so any external service subscribed to webhooks at the time of the edit receives the pre-edit body in that payload — independent of what GitHub's own UI later allows deleting.

### GH Archive — third-party permanent public-event archive

URL: https://www.gharchive.org/
Fetched: this session (WebFetch)

> "GH Archive is a project to record the public GitHub timeline, archive it, and make it easily accessible for further analysis."

> Archives available "starting February 12, 2011" (2011–2014 from the Timeline API, 2015 onward from the Events API), updated hourly, queryable via a public BigQuery dataset.

The page confirms events carry a JSON "payload" field whose shape depends on event type, but does not, on the fetched page itself, spell out that a `PullRequestEvent` payload's `pull_request` object carries `body`. That specific link is inferred by composing this fact with the REST API's confirmed `body` field on the pull request object (same GitHub data model, exposed both via REST and via the Events API that feeds GH Archive) — flagged as an inference, not a directly quoted fact.

---

## Real-world incident (adjacent failure mechanism, not the same trigger)

### GitLost — GitHub Agentic Workflows leaking private repos (Noma Security)

URL: https://noma.security/blog/gitlost-how-we-tricked-githubs-ai-agent-into-leaking-private-repos/
Fetched: this session (WebFetch)

> "adding the keyword 'Additionally' triggered unintended behavior in the model, causing it to reframe its output rather than refuse it"

> "GitHub had restrictive guardrails in place to prevent exactly this scenario, but they failed to protect the repositories as intended"

Confirmed exfiltrated content example: "the contents of README.md from: sasinomalabs/poc (public repo)...sasinomalabs/testlocal (private repo)."

Important distinction from 4Shark's failure: GitLost is prompt-injection-triggered (a malicious public GitHub Issue instructs the agent) — an external adversary induces the leak. 4Shark's incident is the model's own unprompted judgment call classifying internal-repo-provenance and architecture-description prose as legitimate technical rationale, with no adversarial input in the loop. Both land in the same place — private/internal information reaching a public GitHub surface via an AI agent — through different triggers.

---

## Data Loss Prevention — Exact Data Match (adjacent technique, structured data only)

Sources (WebSearch aggregation, NOT independently WebFetched — treat as UNVERIFIED for exact wording, but the concept is corroborated across multiple independent vendor pages so the concept itself is not in serious doubt):
- https://www.strac.io/blog/exact-data-match-data-protection
- https://www.zscaler.com/resources/security-terms-glossary/what-is-exact-data-match
- https://www.digitalguardian.com/blog/exact-data-match-explained-how-it-enhances-data-security

Reported concept: EDM compares data character-by-character against a live, refreshable dataset of records the organization has decided to protect (customer PII, account numbers), rather than a static hardcoded regex pattern — "EDM supports scalable indexing databases that can be refreshed according to your needs, making it flexible as employees, clients or patients come and go." This is the same shape of idea as "derive the denylist from a live source instead of hardcoding it" — but EDM as documented is scoped to structured, record-shaped PII (SSNs, account numbers), not to prose mentioning an organization's own repository/product names. No source found that names a technique for the prose case specifically.

---

## Open-sourcing sanitization guidance

### GitGuardian — Safely open-source software

URL: https://blog.gitguardian.com/safely-open-source-software-best-practices/
Fetched: this session (WebFetch)

> "Internal emails used in development that don't match the authors' public email addresses on the public hosting platform"

> "Internal product names that don't match the public ones"

> "Censoring internal domains used in tests"

> "Replacing internal bot emails with accountable developer emails"

This source treats "internal product/project names" as a distinct sanitization category from credential scanning — the same class of leak as 4Shark's "names of the organization's other private repositories". The page does not state whether automated tooling exists to scan for this category the way secret scanning exists for credentials; it reads as a manual checklist item.

### CFPB / DSACMS open-source checklists (WebSearch aggregation only, not independently WebFetched)

URLs: https://github.com/cfpb/open-source-checklist/blob/master/opensource-checklist.md , https://github.com/DSACMS/repo-scaffolder/blob/main/tier3/checklist.md
Status: UNVERIFIED — reported by WebSearch's aggregation, not confirmed by direct WebFetch in this session. Not used to sustain a Finding on their own.

---

## In-context learning / narrow generalization (searched, inconclusive)

Searched specifically for an established term describing "a policy's illustrative examples teach the model to recognize only the categories shown, not the underlying principle." No source found that names this exact phenomenon. The closest adjacent findings:

- "Emergent Misalignment via In-Context Learning" (arXiv:2510.11288, WebSearch only, not WebFetched) — reports the opposite direction (narrow bad in-context examples generalizing broadly to unrelated misaligned outputs), not the same shape as an insufficiently-general rule failing to generalize to unlisted-but-analogous good-faith cases. Not used as a Finding — noted only to record that it was checked and rejected as off-target.
- No arXiv or industry source was found using a specific name for the 4Shark-observed pattern (rule examples all customer-shaped → model treats org-internal-shaped leaks as out of scope). This is recorded as an open gap, not filled with a manufactured term.
