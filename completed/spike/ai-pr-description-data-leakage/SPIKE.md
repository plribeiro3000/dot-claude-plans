# SPIKE — AI Agent PR Description Data Leakage

## Investigation question

AI coding agents (Claude Code, GitHub Copilot, Cursor, Codex, Devin) that automatically author Pull Request descriptions write rich "motivation + what happened" narratives. In doing so, they organically include data that should NOT appear in a permanent, often-public GitHub record — customer names, database hostnames, usernames, volume figures, and internal infrastructure topology. This is distinct from the well-documented "secrets committed to diff" problem.

Four questions to answer:

1. Is the community talking about this specific "AI agent over-shares in PR prose" problem?
2. What solutions exist or are being proposed?
3. What is the coverage gap — do standard secret-scanning tools actually cover the PR-description-prose case?
4. What would a 4Shark-side solution look like given the existing hook infrastructure?

**Concrete incident (context):** A 4Shark agent-authored Terraform PR description spelled out the customer (Atento CO), QA vs. prod hostnames (glazrdbvp051.database.windows.net → sql4shark.database.windows.net), the DB name (CO_4Shark_DB), the DB username (userCO_4Shark_DB), and the user count (6593) — all in the PR narrative prose. The diff itself may be fine.

## Sources consulted

- [https://github.blog/ai-and-ml/generative-ai/agent-pull-requests-are-everywhere-heres-how-to-review-them/](https://github.blog/ai-and-ml/generative-ai/agent-pull-requests-are-everywhere-heres-how-to-review-them/) — GitHub's May 2026 guide on reviewing agent PRs; establishes agent verbosity as a documented characteristic. See auxiliary: `ai-pr-description-data-leakage_doc_1.txt`
- [https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning](https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning) — official scope of GitHub Secret Scanning. See auxiliary: `ai-pr-description-data-leakage_doc_2.txt`
- [https://docs.github.com/en/code-security/secret-scanning/introduction/supported-secret-scanning-patterns](https://docs.github.com/en/code-security/secret-scanning/introduction/supported-secret-scanning-patterns) — the three pattern categories GitHub Secret Scanning detects. See auxiliary: `ai-pr-description-data-leakage_doc_2.txt`
- [https://docs.anthropic.com/en/docs/claude-code/hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — Claude Code hook API: PreToolUse event structure, block/redirect/rewrite output shapes. See auxiliary: `ai-pr-description-data-leakage_doc_4.txt`
- `/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh:1-130` — existing 4Shark PreToolUse hook; establishes the implementation pattern. See auxiliary: `ai-pr-description-data-leakage_doc_3.txt`
- `/Users/plribeiro3000/.claude/settings.json:158-200` — existing hook registration structure showing `if` field usage. See auxiliary: `ai-pr-description-data-leakage_doc_4.txt`
- [https://trufflesecurity.com/the-kitchen/scanning-github-with-trufflehog-v3](https://trufflesecurity.com/the-kitchen/scanning-github-with-trufflehog-v3) — TruffleHog `--pr-comments` flag documentation; confirms PR body text can be scanned. See auxiliary: `ai-pr-description-data-leakage_doc_5.txt` and `ai-pr-description-data-leakage_doc_8.txt`
- [https://github.com/nightfallai/nightfall_dlp_action/blob/master/README.md](https://github.com/nightfallai/nightfall_dlp_action/blob/master/README.md) — Nightfall DLP Action README; confirms scan scope is code diffs, NOT PR body text. See auxiliary: `ai-pr-description-data-leakage_doc_6.txt`
- [https://blog.gitguardian.com/introducing-gitguardian-agent-skills/](https://blog.gitguardian.com/introducing-gitguardian-agent-skills/) — GitGuardian agent skills blog; five slash commands all credential-focused; no PR body scanning. See auxiliary: `ai-pr-description-data-leakage_doc_7.txt`
- [https://www.morphllm.com/agents-md-guide](https://www.morphllm.com/agents-md-guide) — AGENTS.md specification guide; no guidance on PR description content restrictions. See auxiliary: `ai-pr-description-data-leakage_doc_9.txt`
- [https://developers.openai.com/codex/guides/agents-md](https://developers.openai.com/codex/guides/agents-md) — OpenAI Codex AGENTS.md guide; no guidance on sensitive data in PR descriptions. See auxiliary: `ai-pr-description-data-leakage_doc_9.txt`
- [https://www.freecodecamp.org/news/how-to-write-a-pull-request-description/](https://www.freecodecamp.org/news/how-to-write-a-pull-request-description/) — PR description best practices guide; only security guidance is "don't put secret keys there." See auxiliary: `ai-pr-description-data-leakage_doc_9.txt`
- [https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2](https://stripe.dev/blog/minions-stripes-one-shot-end-to-end-coding-agents-part-2) — Stripe Minions blog (1,300+ weekly AI PRs); no PR description content restrictions documented. See auxiliary: `ai-pr-description-data-leakage_doc_10.txt`
- [https://arxiv.org/abs/2601.17627](https://arxiv.org/abs/2601.17627) — Academic study of 33,596 agent PRs vs 6,618 human PRs; studies description quality, not content governance. See auxiliary: `ai-pr-description-data-leakage_doc_11.txt`
- [https://arxiv.org/abs/2604.19965](https://arxiv.org/abs/2604.19965) — Academic study of 675 security-related agent PRs; studies code vulnerability patterns, not PR prose data governance. See auxiliary: `ai-pr-description-data-leakage_doc_12.txt`

## Findings

### Finding 1: The organic PR-prose over-sharing problem is under-documented as a distinct category

**Evidence:** Web searches for "AI agent PR description sensitive data leak", "AI coding agent over-shares PR body", "GitHub Copilot PR description data leakage" consistently return results about two different problems: (a) adversarial prompt injection — an attacker-controlled PR body hijacks an AI agent reading that body, and (b) accidental credential commit in code diff — secrets in tracked files. The specific 4Shark failure mode — an agent organically narrating infrastructure and customer context into PR prose because it is being thorough — does not appear as a named, discussed problem in any community source found.

GitHub's May 2026 guide does document the agent verbosity characteristic: "Coding agents are productive, literal, and pattern-following contributors that lack contextual knowledge about incident history, team practices, or operational constraints." (Source: `ai-pr-description-data-leakage_doc_1.txt`, GitHub blog May 7 2026). The lack of contextual knowledge of what is sensitive is precisely why agents over-share — they include infrastructure details because they have no signal that those details are sensitive.

**Source:** Web search results; `ai-pr-description-data-leakage_doc_1.txt`

**Significance:** The absence of named community discussion means there is no off-the-shelf solution designed for this case. Every tool found targets either adversarial injection or credential-pattern detection — the organic, non-adversarial over-sharing of non-credential sensitive data in PR prose is a gap in the tooling ecosystem, not just a gap in the 4Shark workflow.

URL fetched: https://github.blog/ai-and-ml/generative-ai/agent-pull-requests-are-everywhere-heres-how-to-review-them/
Verbatim quote checked: "Coding agents are productive, literal, and pattern-following contributors that lack contextual knowledge about incident history, team practices, or operational constraints."
Quote substring confirmed at: `ai-pr-description-data-leakage_doc_1.txt`, paragraph 2 under "Understanding the Challenge"

---

### Finding 2: GitHub Secret Scanning scans PR body prose but covers credential patterns only — zero coverage for the 4Shark incident pattern

**Evidence:** GitHub's documentation confirms that Secret Scanning covers "Titles, descriptions, and comments in pull requests." (Source: `ai-pr-description-data-leakage_doc_2.txt`, About Secret Scanning page). The supported patterns fall into three categories: (1) generic patterns ("Secrets not tied to a specific provider, such as private keys and database connection strings"), (2) AI-detected patterns (generic passwords via Copilot), (3) provider patterns ("Secrets tied to a specific service provider such as AWS, Azure, Stripe"). (Source: `ai-pr-description-data-leakage_doc_2.txt`, Supported Patterns page).

Mapping the Atento CO incident against these categories:
- Customer name "Atento CO": not a credential pattern — not detected
- QA hostname `glazrdbvp051.database.windows.net`: a hostname without credentials — not a recognized secret
- Production hostname `sql4shark.database.windows.net`: same
- DB name `CO_4Shark_DB`: not a credential — not detected
- DB username `userCO_4Shark_DB`: username without accompanying password — not a credential — not detected
- User count `6593`: a business metric — not detected

**Source:** `ai-pr-description-data-leakage_doc_2.txt` (GitHub documentation)

**Significance:** GitHub Secret Scanning is correctly scoped to credentials. It is the right tool for preventing token/password leakage in PR bodies. It is structurally incapable of detecting the 4Shark incident pattern because none of the exposed data qualifies as a credential.

URL fetched: https://docs.github.com/en/code-security/secret-scanning/introduction/supported-secret-scanning-patterns
Verbatim quote checked: "Secrets not tied to a specific provider, such as private keys and database connection strings"
Quote substring confirmed at: `ai-pr-description-data-leakage_doc_2.txt`, Three Pattern Categories section

URL fetched: https://docs.github.com/en/code-security/secret-scanning/introduction/about-secret-scanning
Verbatim quote checked: "Titles, descriptions, and comments in pull requests"
Quote substring confirmed at: `ai-pr-description-data-leakage_doc_2.txt`, PR Content Scanning section

---

### Finding 3: Pre-commit hooks (gitleaks, trufflehog, detect-secrets, git-secrets) have zero architectural coverage for PR body prose

**Evidence:** Pre-commit hooks intercept `git commit` and scan staged file changes. PR body/description is created only when `gh pr create` (or the GitHub web UI) is invoked — it is not a file in the repository, it is API metadata stored at GitHub. It never passes through `git commit` or any local git hook. (Source: `ai-pr-description-data-leakage_doc_3.txt`, Pre-commit hooks section).

**Source:** `ai-pr-description-data-leakage_doc_3.txt`

**Significance:** Pre-commit tooling is the wrong insertion point entirely. The constraint is architectural, not configuration: the PR body does not exist at the time pre-commit hooks run. Deploying gitleaks more aggressively would not change anything about the 4Shark incident pattern.

---

### Finding 4: Claude Code PreToolUse hooks fire before `gh pr create` executes and can intercept, warn, or rewrite the PR body

**Evidence:** Claude Code's hook system supports a PreToolUse event on `Bash` commands with an `if` field for precise matching. The documented structure (Source: `ai-pr-description-data-leakage_doc_4.txt`, Anthropic hooks documentation):

```json
{
  "if": "Bash(gh pr create *)",
  "type": "command",
  "command": "$HOME/.claude/scripts/validate-pr-body.sh",
  "timeout": 10
}
```

This exact `if`-field pattern is already in use in 4Shark's `settings.json` for terraform commands (lines 183-191):
```json
{
  "if": "Bash(terraform *)",
  "type": "command",
  "command": "$HOME/.claude/scripts/inject-terraform-context.sh",
  "timeout": 10
}
```
(Source: `/Users/plribeiro3000/.claude/settings.json:183-191`)

The PreToolUse hook receives JSON on stdin including `tool_input.command` containing the full `gh pr create` invocation. A hook can exit 2 to block, return `additionalContext` to inject a warning without blocking, or return `updatedInput` to rewrite the command before execution.

The `updatedInput` path is the only approach that intercepts data BEFORE it reaches GitHub.

**Source:** `ai-pr-description-data-leakage_doc_4.txt`; `/Users/plribeiro3000/.claude/settings.json:183-191`

**Significance:** A 4Shark-native hook could intercept `gh pr create` before execution, extract the `--body` content, check it against known sensitive patterns, and either block or rewrite. This fits the existing hook infrastructure without any new external dependency.

URL fetched: https://docs.anthropic.com/en/docs/claude-code/hooks
Verbatim quote checked: (hook documentation describes updatedInput, if field, and event structure — confirmed at ai-pr-description-data-leakage_doc_4.txt)
Quote substring confirmed at: `ai-pr-description-data-leakage_doc_4.txt`, multiple sections

---

### Finding 5: The existing validate-bash-command.sh establishes the exact implementation pattern for a new PR-body validation hook

**Evidence:** `validate-bash-command.sh` opens at lines 92-121 with:
```bash
hook_input="$(cat)"
tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"
...
Bash)
    command="$(printf '%s' "$hook_input" | jq -r '.tool_input.command // empty')"
```
(Source: `/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh:92-121`)

The pattern: reads full hook JSON from stdin via `hook_input="$(cat)"`, extracts `tool_name` and `command` via `jq`, applies pattern checks against `$command`, exits 2 with a message on stderr to block or emits JSON to auto-approve.

**Source:** `/Users/plribeiro3000/.claude/scripts/validate-bash-command.sh:92-121`

**Significance:** The implementation skeleton already exists. Complexity concentrates in: (a) robustly parsing the `--body` argument from a shell command string, and (b) deciding what patterns to flag and at what strictness level.

---

### Finding 6: The `updatedInput` rewrite path is technically feasible but fragile for shell command string parsing

**Evidence:** `updatedInput` requires rewriting the full `tool_input.command` string. For a command like:
```bash
gh pr create --title 'feat(db): point Atento CO DB to production' --body 'This PR updates the Atento CO integrator connection from glazrdbvp051.database.windows.net to sql4shark.database.windows.net...'
```
The hook would need to detect the `--body` argument and its value, replace sensitive content within it, reconstruct the full command, and return the reconstructed command as `updatedInput.command`. Shell string parsing of `--body '...'` is fragile when the body contains embedded quotes, newlines, or special characters.

**Source:** `ai-pr-description-data-leakage_doc_4.txt`; derived from Finding 4

**Significance:** This trade-off is structural: `updatedInput` is powerful (transparent redaction) but requires robust body-parsing. The simpler `deny`/exit-2 path is more reliable but requires the model to regenerate the PR body — which only works if the model receives a clear signal about what to remove.

---

### Finding 7: The GitHub Actions body-regex-validator pattern provides server-side coverage but cannot block PR creation — only block merge

**Evidence:** A GitHub Actions workflow can trigger on `pull_request` events, read `github.event.pull_request.body`, check for forbidden patterns using regex, and fail a status check. If the status check is required for merge (via branch protection), this creates a merge gate but NOT a creation gate. The data is already in GitHub's permanent record the moment the PR is opened.

**Source:** `ai-pr-description-data-leakage_doc_3.txt` (GitHub Actions body validator section)

**Significance:** A GitHub Actions validator is defense-in-depth, not prevention. It catches leakage that the pre-creation hook missed, but the sensitive data already exists in GitHub. For the 4Shark risk model (concern is data permanently recorded on GitHub, not only data that gets deployed), a merge gate is insufficient.

---

### Finding 8: Nightfall DLP Action scans code diffs upon PR — NOT PR body text

**Evidence:** The Nightfall DLP Action README states: "The Nightfall DLP Action scans your code commits upon Pull Request for sensitive information." (Source: `ai-pr-description-data-leakage_doc_6.txt`). The scan scope is file diffs (staged changes in commits), not PR body/description text. The README does not mention any capability to scan PR body or PR title fields.

The GitHub Marketplace listing repeats the same scope: "scans your code commits upon Pull Request for sensitive information - like credentials & secrets, PII, credit card numbers & more - and posts review comments to your code hosting service automatically." The "review comments" are code annotations on diff lines, not body-level comments.

Custom detectors are supported (word lists, regex patterns), but these apply to code diffs — not to PR body text.

**Source:** `ai-pr-description-data-leakage_doc_6.txt` (Nightfall DLP Action README)

**Significance:** Nightfall is a strong tool for detecting credentials and custom patterns in committed code. It is architecturally incapable of covering the 4Shark incident pattern — the sensitive data in that incident was in the PR body prose, not in any committed file.

URL fetched: https://github.com/nightfallai/nightfall_dlp_action/blob/master/README.md
Verbatim quote checked: "The Nightfall DLP Action scans your code commits upon Pull Request for sensitive information."
Quote substring confirmed at: `ai-pr-description-data-leakage_doc_6.txt`, Opening description section

---

### Finding 9: TruffleHog `--pr-comments` CAN scan PR description text — but is post-creation and credential-focused in practice

**Evidence:** TruffleHog's GitHub scanner includes the flag: `--[no-]pr-comments         Include pull request descriptions and comments in scan.` (Source: `ai-pr-description-data-leakage_doc_8.txt`, Truffle Security documentation). This makes TruffleHog the only widely-used open-source security scanner confirmed to scan PR body text (not just code diffs).

TruffleHog also supports custom regex detectors: "TruffleHog supports detection and verification of custom regular expressions." (Source: `ai-pr-description-data-leakage_doc_8.txt`, GitHub README). Custom detectors are not architecturally limited to credential patterns — they can match arbitrary text.

However, three constraints limit its applicability for the 4Shark incident pattern:
1. **Post-creation only**: TruffleHog runs after the PR is created (in CI/GitHub Actions). The PR body is already stored in GitHub when the scan runs.
2. **Credential-focused in practice**: The 800+ built-in detectors cover API keys, tokens, certificates. Covering customer names, bare hostnames, and DB names requires custom detector configuration.
3. **Motivation**: The `--pr-comments` flag was introduced to address credentials accidentally pasted in PR review threads — the use case is credential detection in conversational text, not business data governance.

**Source:** `ai-pr-description-data-leakage_doc_8.txt`; `ai-pr-description-data-leakage_doc_5.txt`

**Significance:** TruffleHog + `--pr-comments` + custom regex detectors is the closest available community tool to the 4Shark incident pattern. It is the only tooling-layer approach that reaches PR body text using an open-source scanner. The gap between "closest available" and "adequate for the 4Shark case" is: post-creation scope, custom detector configuration burden, and no pre-existing detector for business/infra data types.

URL fetched: https://trufflesecurity.com/the-kitchen/scanning-github-with-trufflehog-v3
Verbatim quote checked: "--[no-]pr-comments         Include pull request descriptions and comments in scan."
Quote substring confirmed at: `ai-pr-description-data-leakage_doc_8.txt`

---

## Community Practices & Convergence

This section documents what the community is actually doing across six practice areas related to the 4Shark incident pattern. Each area was researched exhaustively; where no community practice was found, that absence is stated explicitly.

### Practice Area 1: PR/commit hygiene — is "describe what & why, not data values" an articulated norm?

**Research conducted:** Searched for "PR description hygiene", "pull request description best practices", "what to exclude from PR descriptions", "data minimization PR body", and reviewed four PR best-practice guides (FreeCodeCamp, DeployHQ, CloudCity, Atlassian).

**Finding:** No guide articulates a norm of "describe what happened without including data values." The community norm is the inverse: guides recommend including context, motivation, and specifics that help reviewers understand the change. The FreeCodeCamp guide's only security-related guidance is: "(Don't put the secret keys there, just include the key names and how to get the secrets.)" (Source: `ai-pr-description-data-leakage_doc_9.txt`). This is credential-specific, not a general data-minimization principle.

Conventional Commits, Semantic Release, and other commit convention frameworks define message FORMAT (feat, fix, chore, etc.) — none address what data values should not appear in the body.

**Conclusion:** The norm of "include context and specifics" is the dominant documented practice. There is no counter-norm for "exclude infrastructure/customer data values." Not found after exhaustive search.

---

### Practice Area 2: How teams handle AI agent output review — documented practices at scale

**Research conducted:** Reviewed GitHub's May 2026 agent PR guide, Stripe Minions blog posts (Part 1 and Part 2), academic study of 33,596 agent PRs (arXiv 2601.17627), and search results from companies running agents at scale.

**GitHub's May 2026 guide** (the most authoritative community document on reviewing agent PRs): covers workflow vulnerabilities (prompt injection via PR body), security of the agent's tool access, and code review discipline. The guide lists four categories of agent PR considerations — none address PR description content restrictions. (Source: `ai-pr-description-data-leakage_doc_1.txt`)

**Stripe Minions** (1,300+ weekly AI PRs): The Part 2 blog post describes infrastructure (devboxes), blueprints, and context gathering. No content restrictions for PR description prose are documented. The blog does not describe what Minions include or exclude from PR body text. (Source: `ai-pr-description-data-leakage_doc_10.txt`)

**Academic study** (arXiv 2601.17627, 33,596 agent PRs): Studies description QUALITY — whether descriptions accurately reflect code changes. Key finding: "Agents generate stronger commit-level messages (semantic similarity 0.72 vs. 0.68) but lag humans at PR-level summarization (PR-commit similarity 0.86 vs. 0.88)." The study does not examine what data types appear in descriptions. (Source: `ai-pr-description-data-leakage_doc_11.txt`)

**Conclusion:** No company running agents at scale has published a practice of restricting PR description content for data governance. The review guidance focuses on code correctness and workflow security (prompt injection), not on PR prose data minimization.

---

### Practice Area 3: LLM output redaction — patterns and libraries for sanitizing model output before it leaves a boundary

**Research conducted:** Searched for "LLM output redaction", "sanitize LLM output before PR", "AI output DLP middleware", "prevent sensitive data LLM response", and reviewed Microsoft Presidio documentation.

**Microsoft Presidio** is the most widely-cited open-source framework for PII detection and redaction in LLM output pipelines. It supports custom recognizers (regex + NLP entity types) and can be wired into LLM output processing via LiteLLM. Default recognizers cover standard PII: SSNs, credit card numbers, phone numbers, email addresses, names.

The critical limitation: Presidio's default recognizer set covers legal PII categories — it has no built-in recognizer for infrastructure hostnames, customer names as organizational entities (vs. personal names), database names, or business volume figures. Covering the 4Shark pattern requires custom recognizer development.

No existing LLM output redaction middleware product was found that ships with infrastructure hostname detection or customer name detection as a default capability.

**Conclusion:** LLM output redaction tooling exists (Presidio, LiteLLM DLP hooks) but targets PII categories. Adapting it for business/infra data requires custom recognizer development — the same problem as custom secret-scanning detectors. The community has not articulated this adaptation pattern for the PR-body use case specifically.

---

### Practice Area 4: DLP applied to GitHub PRs in the wild — real company write-ups

**Research conducted:** Searched for "DLP GitHub pull request body text scan company blog", "enterprise DLP applied to PR descriptions", "company PR description sensitive data policy", and reviewed the two tools with GitHub PR integration (Nightfall and GitHub Secret Scanning).

**GitHub Secret Scanning**: scans PR body text, covers credential patterns only. (Finding 2)

**Nightfall DLP GitHub Action**: "The Nightfall DLP Action scans your code commits upon Pull Request for sensitive information." — scans code diffs only, NOT PR body text. (Finding 8, Source: `ai-pr-description-data-leakage_doc_6.txt`)

**GitGuardian ggshield** (agent skills): instructs agents to "perform the scan for secrets in paths, staged changes, and commits" — no PR body scanning documented. (Source: `ai-pr-description-data-leakage_doc_7.txt`)

No company write-up was found describing an internal DLP policy applied specifically to PR description prose for non-credential business data. All DLP-for-GitHub writing found covers credential/secret detection in code diffs.

**Conclusion:** Commercial DLP applied to GitHub is universally code-diff-focused. No real-world write-up of DLP applied to PR body prose for non-credential data was found. Not found after exhaustive search.

---

### Practice Area 5: Data classification norms — "don't put internal/customer data in source hosts"

**Research conducted:** Searched for "data classification pull request description", "customer data GitHub PR policy", "source code repository data classification", "don't include customer data in commit messages policy", and reviewed general data classification frameworks.

No data classification framework or company blog was found that explicitly names PR descriptions or commit messages as a forbidden location for customer data, internal infrastructure details, or business volume figures. Data classification frameworks (ISO 27001, SOC 2, general information security standards) define classification levels and handling requirements for data at rest, in transit, and in use — they do not typically address what narrative text may appear in version control metadata.

The AGENTS.md spec and guides (MorphLLM, OpenAI Codex): no guidance on data classification for PR prose. The only restriction mentioned is "Never commit .env files." (Source: `ai-pr-description-data-leakage_doc_9.txt`)

**Conclusion:** Data classification norms have not been applied to PR description content in any community source found. The problem is that PR body text occupies an ambiguous category — it is metadata, not code, not a data file — and data classification frameworks were not designed with this surface in mind. Not found after exhaustive search.

---

### Practice Area 6: Custom secret-scanning patterns repurposed for non-credential org data

**Research conducted:** Searched for "gitleaks custom rules PR body", "GitHub custom secret scanning patterns non-credential", "trufflehog custom detector hostname", "secret scanning custom patterns customer data", and reviewed the three tools that support custom patterns.

**TruffleHog custom regex detectors**: "TruffleHog supports detection and verification of custom regular expressions." (Source: `ai-pr-description-data-leakage_doc_8.txt`) Custom detectors are not credential-limited architecturally. Combined with `--pr-comments`, this is the closest available community tooling for the 4Shark pattern. The limitation: no community write-up exists of this combination being deployed for non-credential business data detection.

**Gitleaks custom TOML rules**: Gitleaks supports custom rules defined in TOML config. However, gitleaks scans code diffs and staged files — it has no PR body scanning capability. Custom rules here would help detect customer names or hostnames in committed code files, not in PR body prose.

**GitHub Custom Patterns**: GitHub Secret Scanning's custom patterns feature allows org-specific regex patterns. GitHub documents this for org-specific credential formats (e.g., internal API key formats). Custom patterns can be defined for any text pattern, but they scan the same surfaces as built-in patterns — which includes PR body text. This means GitHub Custom Patterns + PR body scanning is technically possible for non-credential data, though no community write-up of this use case was found.

**Conclusion:** The technical capability to apply custom regex to PR body text exists via two paths: TruffleHog `--pr-comments` + custom detectors (post-creation CI), and GitHub Custom Patterns (post-creation, GitHub's own scanning). Neither path is documented in the community as a practice for non-credential business/infra data governance. Custom pattern deployment for this use case would be novel.

---

### Evidence-based convergence assessment

The community is converging in three directions — none of which addresses the 4Shark incident pattern:

**Direction 1: Credential scanning in code diffs** — Pre-commit hooks (gitleaks, trufflehog, ggshield), GitHub Secret Scanning, and Nightfall DLP all provide strong, multi-layered coverage for credentials accidentally committed to tracked files. This is a solved problem with well-documented tooling.

**Direction 2: Code review checklists for agent PRs** — GitHub's May 2026 guide, Stripe's Minions writeups, and academic research all treat AI agent PR review as a code quality and workflow security problem. The review discipline is about code correctness, prompt injection resistance, and test coverage — not about PR prose content governance.

**Direction 3: Agent behavior configuration via AGENTS.md / CLAUDE.md** — The community is converging on configuration files (AGENTS.md for Codex, CLAUDE.md for Claude Code, .cursorrules for Cursor) as the primary mechanism for constraining agent behavior in a codebase. However, no AGENTS.md specification or guide contains guidance about PR description content restrictions. The community's use of these files is for coding style, test requirements, and tooling preferences — not for data governance of PR prose.

**The gap the community has not addressed:** Non-credential sensitive data in PR body prose — customer names, infrastructure hostnames, database names, volume figures, internal topology — is not discussed as a problem, not tooled for, and not present in any agent behavior guide. The problem sits between three communities that each claim it belongs to someone else: security (who owns credentials, not PR text), data governance (who owns customer data, not source control metadata), and AI agent tooling (who owns agent output quality, not data classification).

The closest available community tool is TruffleHog `--pr-comments` + custom regex detectors, which can scan PR body text post-creation. No deployment of this pattern for non-credential business/infra data governance was found in any community source.

---

## Trade-offs surfaced

| Approach | Enforcement point | Covers 4Shark incident? | False positive risk | Maintenance burden | External dependency | Pros | Cons | Source |
|---|---|---|---|---|---|---|---|---|
| GitHub Secret Scanning (existing) | Post-creation, pre/post-merge | No — credential patterns only | Low (credential-specific) | Low (built-in) | None | Already deployed, zero cost | Zero coverage for customer/infra names, bare hostnames, user counts | Finding 2 |
| Pre-commit hooks (gitleaks, trufflehog) | Pre-commit, local | No — PR body never staged | Low (file diff only) | Low-medium | None | Strong for diff leakage | Architecturally cannot touch PR body prose | Finding 3 |
| Nightfall DLP GitHub Action | Post-creation, code diff only | No — scans code diffs, not PR body | Low for PII; medium for infra | High (custom config + external vendor) | Yes (SaaS) | Broad built-in detector library for code diffs | Architecturally cannot scan PR body text; requires custom detectors even for code diffs | Finding 8 |
| TruffleHog --pr-comments + custom detectors | Post-creation CI | Partial — reaches PR body, requires custom regex | Medium (custom config) | Medium-high (custom detector config) | None (open source) | Only open-source scanner that reaches PR body text; custom regex is not credential-limited | Post-creation: data already in GitHub; requires custom detector config; no pre-built detectors for business/infra data | Finding 9 |
| GitHub Custom Patterns | Post-creation, GitHub's own scanning | Partial — reaches PR body with custom regex | Medium | Medium (regex curation) | None | Server-side, no CI setup required | Post-creation: data already in GitHub; community write-up of this use case for non-credentials does not exist | Finding 9, Practice Area 6 |
| Claude Code PreToolUse hook — block on pattern | Pre-creation (`gh pr create`) | Yes, for known patterns | Medium (pattern-based) | Medium (pattern list must be curated) | None | Fits existing 4Shark hook infrastructure; pre-creation interception; only approach that prevents GitHub storage | Pattern list is finite; novel sensitive data not yet in the list is not caught | Findings 4, 5 |
| Claude Code PreToolUse hook — warn + context inject | Pre-creation (`gh pr create`) | Partial (model gets a signal; may still include data) | Low (non-blocking) | Low-medium | None | Prompts model to self-sanitize; lower false-positive cost than blocking | Relies on model behavior after the hint; not guaranteed to prevent leakage | Findings 4, 5 |
| Claude Code PreToolUse hook — updatedInput redaction | Pre-creation (`gh pr create`) | Yes, for patterns matched | Medium | High (body-parsing is fragile) | None | Transparent; PR is created with sanitized body; only approach that prevents storage AND allows PR to proceed | Shell string parsing of `--body` is fragile; complexity risk | Finding 6 |
| GitHub Actions body-regex-validator | Post-creation, pre-merge | Partial — data already in GitHub | Medium | Medium (regex curation) | None | Defense-in-depth layer; works for human-authored PRs too | Does not prevent storage in GitHub; only blocks merge | Finding 7 |
| CLAUDE.md prompt constraint only | Pre-creation (model behavior) | Partial — model compliance is probabilistic | Low | Low | None | Zero implementation cost | Probabilistic, not deterministic; demonstrated insufficient by itself | Finding 1, Community Practices |

## What remains uncertain

- What is the full list of sensitive patterns 4Shark would need to guard against? Customer names, hostnames, and DB names from the Atento CO incident are known, but the full taxonomy is not enumerated.
- How robust is the Claude Code `updatedInput` mechanism in practice for multi-line body content with embedded quotes? The documentation describes it but real-world edge cases with PR bodies are not documented in community sources found.
- Does the `if: "Bash(gh pr create *)"` matcher fire when `gh pr create` is invoked with `--body` passed as a shell variable rather than an inline literal? If the model writes `BODY=$(cat <<'EOF'...)` and then `gh pr create --body "$BODY"`, the command string visible to the hook is `gh pr create --body "$BODY"` — the content is not inline and cannot be pattern-matched in the hook.
- What is the exact boundary of TruffleHog's `--pr-comments` flag? The documentation groups "pull request descriptions and comments" together — it does not distinguish between PR body text and reply comments. The scan scope may include both or only comments.
- Whether GitHub Custom Patterns applies to PR body text is documented (Secret Scanning covers "Titles, descriptions, and comments in pull requests"), but no write-up of deploying custom patterns specifically for non-credential infra data in PR bodies was found — the edge cases of regex pattern performance on free-form prose are undocumented.
- Does the current 4Shark CLAUDE.md Output Policy (§ "Pull Request Policy") already contain language that would have prevented the Atento CO incident if followed? If so, the problem may be prompt-adherence, not missing tooling.

## Suggested options for main and the engineer

**Option A: Prompt constraint only (CLAUDE.md rule)**
Add a rule to CLAUDE.md § "Pull Request Policy" that explicitly forbids including customer names, infrastructure hostnames, database names, usernames, connection strings, and volume figures in PR body prose. The rule would read: "NEVER include customer names, infrastructure hostnames, database credentials (including bare usernames), DB names, or business volume figures (user counts, record counts) in PR descriptions or commit messages — these become permanent records in GitHub. The PR body should describe WHAT changed and WHY, not the specific data values involved."

Zero implementation cost. Addresses the root cause (model behavior) rather than a downstream layer. Probabilistic, not deterministic.

**Option B: Claude Code PreToolUse hook — block with instructive message**
Add `validate-pr-body.sh` to `~/.claude/scripts/` following the `validate-bash-command.sh` pattern. Register it in `settings.json` with `"if": "Bash(gh pr create *)"`. The hook extracts the `--body` content from the command, checks for a configurable list of forbidden patterns (known customer names, known hostnames, connection-string shapes), exits 2 with a specific corrective message naming what was found and instructing the model to sanitize it.

Deterministic for known patterns. Extends existing hook infrastructure without new dependencies. Requires pattern curation. Does not cover patterns not yet in the list.

**Option C: Claude Code PreToolUse hook — warning/context injection**
Same hook, but instead of blocking, emit `additionalContext` with the sensitive patterns found, prompting the model to regenerate the PR body. The PR creation does not fail — the model receives a warning that it can act on. Lower friction; still relies on model compliance; but the warning is targeted and specific rather than a vague "be careful" prompt rule.

**Option D: Option B or C + GitHub Actions body-regex-validator as defense-in-depth**
Add a GitHub Actions workflow that scans the PR body for known-sensitive patterns (using the same pattern list as the hook) and fails a required status check if violations are found. This provides a server-side gate that catches cases where the hook was bypassed or a PR was created manually. Defense-in-depth: the hook is the primary gate, the Actions workflow is the fallback.

**Option E: Structured PR body template with explicit "no sensitive data" fields**
Rather than scanning free-form prose, constrain what the agent writes. The CLAUDE.md PR format could require a structured template with specific section headings (What changed, Why, Tests, Notes) and a pre-flight checklist that the model must explicitly complete — including "I confirm this description contains no customer names, hostnames, DB names, or volume figures." Relies on model compliance but with a structured forcing function.

**Option F: TruffleHog --pr-comments + custom regex detectors (post-creation CI gate)**
Configure TruffleHog in a GitHub Actions workflow with `--pr-comments` enabled and custom regex detectors targeting known-sensitive patterns (hostnames matching `*.database.windows.net`, customer name patterns). This adds a post-creation CI gate using an open-source tool with no external SaaS dependency, leveraging the only community scanner that reaches PR body text. The limitation is post-creation scope — data is already in GitHub when the gate runs, so this is defense-in-depth rather than prevention.

(NO recommendation — surface options, let main and the engineer choose)
