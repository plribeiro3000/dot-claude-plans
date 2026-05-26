# SPIKE — Centralized Session History Archival for Engineering Team

**Conducted by:** Claude Code (research) + Engineer (decisions)
**Date:** 2026-02-27
**Updated:** 2026-03-23
**Status:** CANCELLED — after reassessment, team decided not to archive sessions (see Section H and updated Conclusions)

---

## Goal

**Primary question:** How should 4Shark archive Claude Code session history to a centralized location (S3) before local cleanup, preserving institutional knowledge while reducing local disk usage and security risk?

**Why this investigation is needed:**
- Claude Code stores full conversation history in `~/.claude/projects/` as JSONL files
- A single engineer accumulated 796MB in ~7 weeks; another user reported 6.5GB growth
- Sessions contain rich institutional knowledge (architectural decisions, debugging insights, business discussions)
- Local storage creates security risk (laptop theft, unauthorized access) and disk pressure
- The existing Mem0 plan (see `../claude-shared-memory/`) covers semantic memory but not raw session archival
- No one in the community has built a complete automated pipeline for this yet

**Requirements:**
1. **Per-engineer folders** — each engineer's sessions isolated in their own S3 prefix
2. **Encrypted at rest** — SSE-KMS with audit trail via CloudTrail
3. **Automatic archival** — triggered by SessionEnd hook, zero manual effort
4. **Lifecycle management** — Standard → IA → Glacier → Deep Archive
5. **Searchable** — engineers can find and retrieve past sessions when needed
6. **Terraform-managed** — consistent with 4Shark infrastructure patterns
7. **LGPD compliant** — data in sa-east-1, retention policy documented

---

## Method

- Web search across 80+ sources covering session management, archival patterns, S3 best practices
- Analysis of Claude Code hooks documentation and JSONL format
- Review of community tools for session export and sync
- Cross-referencing AWS documentation for IAM per-user patterns
- Assessment of LGPD implications for storing AI conversation data

---

## Evidence

### A. Session Storage Format

Claude Code sessions are stored as JSONL files in `~/.claude/projects/<url-encoded-path>/<session-uuid>.jsonl`. Each line is a JSON object containing:
- Message type (user, assistant, system, progress)
- Content blocks (text, tool_calls, thinking)
- Token usage per turn
- Git state snapshots
- File history snapshots
- Timestamps

References:
- [Inside Claude Code: Session File Format](https://databunny.medium.com/inside-claude-code-the-session-file-format-and-how-to-inspect-it-b9998e66d56b)
- [Analyzing Logs with DuckDB](https://liambx.com/blog/claude-code-log-analysis-with-duckdb)
- [How Claude Code Manages Local Storage](https://milvus.io/blog/why-claude-code-feels-so-stable-a-developers-deep-dive-into-its-local-storage-design.md)

### B. Hook Mechanism

The `SessionEnd` hook is the ideal trigger point:
- Fires when session terminates
- Receives: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `reason`
- `reason` values: `clear`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled`, `other`
- Non-blocking (does not prevent session termination)
- Supports `type: "command"` (shell script)

Source: [Claude Code Hooks Documentation](https://code.claude.com/docs/en/hooks)

### C. Community Approaches to Session Preservation

| Tool | Approach | Limitation |
|------|----------|-----------|
| [claude-code-sync](https://github.com/perfectra1n/claude-code-sync) | Bidirectional sync via Git (Rust) | Git not ideal for large binary-ish JSONL files |
| [convx](https://github.com/pascalwhoop/convx) | Export to git as Markdown + JSON, auto-redacts secrets | Git-based, no cloud storage |
| [claude-code-logs](https://www.cengizhan.com/p/building-a-permanent-archive-of-every) | Export to git + HTML viewer | Git-based, no lifecycle management |
| [claude-conversation-extractor](https://github.com/ZeroSumQuant/claude-conversation-extractor) | Batch export to Markdown/JSON/HTML | Local export only, no upload |
| [claude-sync](https://github.com/tawanorg/claude-sync) | Sync to S3/R2/GCS with age encryption | Closest to our goal but manual, not hook-triggered |
| [episodic-memory](https://github.com/obra/episodic-memory) | SQLite + vector search archive | Local only, no cloud backup |
| [Claudebin](https://claudebin.com/) | Share sessions as URLs | Third-party hosted — data leaves your control |
| [SpecStory](https://specstory.com/) | Auto-save to `.specstory/history/` | Local only, optional cloud |

**Key finding:** No one has built the complete pipeline: `SessionEnd hook → compress → encrypt → S3 upload → lifecycle to Glacier`. The building blocks exist but have not been assembled.

### D. S3 Architecture Patterns

**Per-engineer folder isolation (AWS official pattern):**
```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::bucket-name/${aws:username}/*"
}
```
Source: [AWS IAM S3 Home Directory Pattern](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_examples_s3_home-directory-console.html)

**Lifecycle tiers:**

| Tier | Duration | Class | Cost/GB/month | Use Case |
|------|----------|-------|---------------|----------|
| Hot | 0-30 days | Standard | $0.023 | Recent sessions, frequent access |
| Warm | 30-90 days | Standard-IA | $0.0125 | Occasional reference |
| Cold | 90-365 days | Glacier Flexible | $0.004 | Rare retrieval (minutes to hours) |
| Archive | 365+ days | Glacier Deep Archive | $0.00099 | Compliance/historical (12h retrieval) |

**Encryption:**
- SSE-KMS with S3 Bucket Keys — reduces KMS API cost by up to 99%
- CloudTrail integration for audit trail of all access
- Key policy can restrict decryption to specific IAM roles/users

**Terraform modules available:**
- [cloudposse/s3-bucket/aws](https://registry.terraform.io/modules/cloudposse/s3-bucket/aws) — versioning, lifecycle, encryption
- [cloudposse/iam-s3-user/aws](https://github.com/cloudposse/terraform-aws-iam-s3-user) — IAM per-user S3 access

### E. Compression Analysis

JSONL files compress extremely well (repetitive JSON structure):

| Method | Typical Ratio | Speed | Tool |
|--------|--------------|-------|------|
| gzip | 5-8x | Fast | Built-in |
| zstd | 7-10x | Fastest | `zstd` CLI |
| xz | 8-12x | Slow | Built-in |

For a 796MB corpus, gzip would reduce to ~100-160MB. zstd recommended for best ratio/speed balance.

### F. Security and Compliance

**LGPD considerations:**
- Sessions may contain personal data, business strategy, customer information
- S3 in `sa-east-1` (São Paulo) keeps data in Brazil
- Retention policy must be documented (data controller obligation)
- Engineers must be informed about what is collected (transparency principle)
- Right to deletion must be supported (per-engineer folder makes this straightforward)

**Known Claude Code vulnerabilities (Feb 2026):**
- [CVEs discovered](https://www.theregister.com/2026/02/26/clade_code_cves/) in hooks mechanism — settings.json files committed to repos can execute shell commands
- Mitigation: the archive script runs from `~/.claude/scripts/` (not from project repos)

**Privacy perception:**
- 38% of Fortune 500 with AI coding tools reported security incidents ([Knostic](https://www.knostic.ai/blog/ai-coding-assistant-security))
- Transparency about collection scope and purpose is critical for engineer buy-in

### G. Relationship with Mem0 Plan

The S3 archival and Mem0 serve different purposes:

| Aspect | Mem0 (semantic memory) | S3 (raw archival) |
|--------|----------------------|-------------------|
| **What** | Discrete memories (facts, decisions, patterns) | Complete conversation transcripts |
| **Size** | Small (KB per memory) | Large (MB per session) |
| **Search** | Semantic + knowledge graph | Full-text (after retrieval) |
| **Value** | Quick recall, cross-engineer sharing | Deep context, compliance, audit |
| **Infrastructure** | EC2 + Docker Compose | S3 bucket + IAM |

They are complementary layers. The S3 bucket can be added to the same Terraform project or as a sibling module.

### H. Reassessment: Is Archiving Sessions Actually Useful? (2026-03-23)

A follow-up investigation was conducted to answer the fundamental question the original spike did not address: **should sessions be archived at all?**

**Research method:** Web search across GitHub discussions, Reddit, Hacker News, security blogs, and official Anthropic documentation. Focus on real-world usage patterns and community sentiment, not theoretical benefits.

#### Do people actually use old sessions?

**Rarely, and only situationally.** The cases found were:
- Resuming debugging after a crash (lost context mid-session)
- Recovering a prompt that worked well ("what did I use last Tuesday?")
- Revisiting architectural decisions made during a session

All cases follow the pattern "I lost something I needed right now" — not "I regularly consult old sessions." No evidence of systematic, recurring use of archived sessions was found.

Sources:
- [DEV Community - claude-vault](https://dev.to/kuroko1t/i-built-a-tool-to-stop-losing-my-claude-code-conversation-history-5500)
- [GitHub Issue #12646](https://github.com/anthropics/claude-code/issues/12646)
- [DEV Community - 4 tools for session history](https://dev.to/gonewx/i-tested-4-tools-for-browsing-claude-code-session-history-17ie)

#### Community sentiment on centralizing session logs

**Divided, leaning against long-term archival:**

- **Simon Willison** set `cleanupPeriodDays: 99999` and publishes transcripts ([claude-code-transcripts](https://github.com/simonw/claude-code-transcripts)) — but he is a notable outlier.
- Multiple tools exist (claude-vault, claude-code-log, claude-history, claude-replay, search-sessions) — indicating demand from a vocal minority.
- **The prevailing pragmatic view:** use `CLAUDE.md`, well-documented commits, and ADRs as the source of truth. Sessions are ephemeral scratch pads, not permanent records.
- Experienced developers on HN: *"nothing works better than simply keeping my own library of markdown files for each project specification"* ([HN](https://news.ycombinator.com/item?id=46426624))

| Group | Behavior | Estimated size |
|-------|----------|---------------|
| Silent majority | Let sessions expire, use CLAUDE.md as memory | Large |
| Power users | High cleanup period, build custom tools | Small but vocal |
| Pragmatists | Export specific sessions when relevant (`/export`) | Medium |

#### Security risks of storing sessions

This is where the evidence is strongest **against** archival:

1. **Credentials in plaintext:** Sessions contain secrets fetched during debugging — API keys, tokens, database credentials. A user on HN: *"You can witness first-hand how it stores credentials it fetches via the API of a secrets manager for stuff in plaintext too."* ([HN](https://news.ycombinator.com/item?id=44619624))

2. **Proton (privacy company) warns** that AI logs are more dangerous than search history — they contain detailed conversations with thoughts, decisions, and confidential data. They recommend **zero data logging by default**. ([Proton Blog](https://proton.me/blog/ai-chat-logs))

3. **Krebs on Security (March 2026):** Misconfigured AI agent interfaces expose complete conversation history including credentials. Researcher Jamieson O'Reilly: *"You can pull the full conversation history across every integrated platform, meaning months of private messages and file attachments, everything the agent has seen."* ([Krebs](https://krebsonsecurity.com/2026/03/how-ai-assistants-are-moving-the-security-goalposts/))

4. **Knostic (AI Security):** Secrets appear in prompts during debugging, in code comments models read, and in CI logs that AI assistants summarize. Session logs accumulate all of this. ([Knostic](https://www.knostic.ai/blog/ai-coding-assistant-security))

5. **Centralizing logs in S3 amplifies the risk:** A compromised bucket exposes the complete history of all engineers at once — architectural decisions, business logic, credentials, customer data discussions.

6. **Only 1 of 4 community tools** (Mantra) performs secret redaction before sharing. The others store everything as-is. ([DEV Community - 4 tools](https://dev.to/gonewx/i-tested-4-tools-for-browsing-claude-code-session-history-17ie))

#### Official Anthropic position

No recommendation on whether to preserve or discard local sessions. The `cleanupPeriodDays` setting exists but Anthropic provides no guidance on what value to use. Default is 30 days.

**Known bug:** `cleanupPeriodDays: 0` silently disables transcript persistence entirely ([GitHub Issue #23710](https://github.com/anthropics/claude-code/issues/23710)).

---

## Conclusions

### Original Findings (2026-02-27) — SUPERSEDED

~~1. No one has built this exact pipeline yet.~~
~~2. The building blocks are mature.~~
~~3. The SessionEnd hook is the right trigger.~~
~~4. Compression is essential.~~
~~5. Cost is negligible.~~
~~6. LGPD requires attention.~~
~~7. This pairs naturally with the Mem0 plan.~~

### Updated Conclusions (2026-03-23)

The original spike answered "how to archive sessions" thoroughly but did not adequately address "should we archive sessions." After reassessment:

1. **The value of archived sessions is marginal.** Real use cases are situational ("I lost something"), not systematic ("I regularly consult old sessions"). No engineer on the team has ever needed to revisit a past session.

2. **The security risk is real and disproportionate.** Sessions contain credentials, business logic, and sensitive data in plaintext. Centralizing them in S3 creates a high-value target with no proportional benefit.

3. **4Shark's existing workflow already captures durable knowledge.** Plans (`~/.claude/plans/`), CLAUDE.md files, well-documented commits, and ADRs serve as the permanent source of truth. Sessions are ephemeral by nature.

4. **The community consensus supports letting sessions expire.** The majority of developers use the default cleanup and rely on curated documentation, not raw logs.

5. **The right approach is shorter retention, not archival.** Setting `cleanupPeriodDays: 7` reduces local disk usage and security exposure without losing anything the team actually uses.

### Decision

**This initiative is CANCELLED.** The team will not archive Claude Code sessions to S3.

Instead:
- Set `cleanupPeriodDays: 7` in the shared `settings.json`
- Continue relying on plans, CLAUDE.md, and commits as permanent knowledge
- No S3 bucket, no SessionEnd hook, no archival infrastructure

### What remains useful from this spike

- The IAM users migration to groups (Step 4 of the PLAN) is valuable independently and should be extracted to its own initiative if needed.
- The Mem0 plan (`../claude-shared-memory/`) remains valid — semantic memory extraction is a different concern from raw log archival.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
