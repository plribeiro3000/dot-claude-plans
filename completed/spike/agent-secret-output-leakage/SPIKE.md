# SPIKE — Agent Secret Output Leakage

## Decision (engineer, 2026-06-26) — DO NOTHING MECHANICAL

After two research phases, the engineer's decision is: **no mechanical enforcement of any kind.** No PreToolUse deny, no PostToolUse scrub, and **not even the `MessageDisplay` display-mask.**

Rationale: there is **no real solution** under the constraints. The credential arrives by email from an external client (e.g. Atento) who always sends passwords that way — 4Shark cannot change the source. The only mechanical way to guarantee the agent never echoes the value is to deny the agent access to email bodies — which destroys a core, valuable capability (fetch + summarize email) over a single client's mistake. That trade is unacceptable. Every available mechanical control either fails to cover this case or cripples the feature; even `MessageDisplay` only masks the on-screen render while the plaintext stays in the session JSONL and in context, so it buys partial cover at the cost of false confidence.

What is delivered instead (documentation only):

1. **A behavioral document for Claude Code** — advisory, not enforced: a `CLAUDE.md` rule + Tier 2 doc (`SECRETS-IN-OUTPUT.md`) telling the model not to print credential values, to return only link/metadata when only a link was requested, and to acknowledge a credential by category (never the value). This is intent-signalling, explicitly NOT a guarantee.
2. **A cleanup runbook** — `docs/runbooks/security/LEAKED-CREDENTIAL-CLEANUP.md`: when a credential does land in a session/terminal, how to respond (treat as compromised → rotate; purge local artifacts).

This research is retained as the record of WHY no enforcement was built. The findings below stand; the options they surface were considered and deliberately not adopted.

---

## Investigation question (original)

When a Claude Code agent is asked to locate an email containing a database password and return only the link to that email, the agent instead extracts the password and prints it in plaintext in the chat/terminal output. This happened on two consecutive days. The investigation question is: **What mechanisms exist to prevent an AI coding agent from surfacing/echoing credential values in its output when that was not requested — and what are the trade-offs between each approach?**

## Investigation question (sharpened — Phase 2)

Given three hard constraints that eliminate most Phase 1 options:

1. The secret arrives via email from an external client (e.g. Atento) who always sends passwords by email. 4Shark cannot change how the client transmits it. Vault-reference and "fix the source" approaches do NOT solve this.
2. Claude Code's ability to fetch and summarize email bodies via Gmail MCP tools is a core feature the engineer will NOT give up. Any solution that strips the email body or redacts content BEFORE it enters model context (PreToolUse deny, PostToolUse updatedToolOutput scrub on email tools, aggressive redaction) is REJECTED — it cripples the feature.
3. The acceptable direction is exactly one: prevent the secret from being ECHOED/DISPLAYED in the assistant's OUTPUT, without touching what enters context. The model keeps reading the body; it must not surface the secret value in its visible reply.

**Phase 2 question:** Does Claude Code have a `MessageDisplay` hook (or any other mechanism) that can mask a credential in the assistant's rendered output WITHOUT altering what enters the model's context? If yes: what exactly does it do, what does it NOT do, and what residual risk remains? Deliver a definitive verdict: fully achievable (i), partially achievable (ii), or not achievable (iii)?

## Sources consulted

**Phase 1 sources:**
- [Claude Code hooks reference (official)](https://code.claude.com/docs/en/hooks) — complete hook capability matrix
- [Claude Code permissions reference (official)](https://code.claude.com/docs/en/permissions) — deny rule syntax
- [GitHub issue #44868 (OPEN)](https://github.com/anthropics/claude-code/issues/44868) — grep exposed a token despite CLAUDE.md prohibitions
- [GitHub issue #32523 (CLOSED: NOT PLANNED)](https://github.com/anthropics/claude-code/issues/32523) — credentials printed despite explicit CLAUDE.md rules
- [GitHub issue #29434 (CLOSED: NOT PLANNED)](https://github.com/anthropics/claude-code/issues/29434) — feature request for context-window redaction
- [GitHub issue #21528 (CLOSED: NOT PLANNED)](https://github.com/anthropics/claude-code/issues/21528) — env-var redaction feature request
- [GitHub issue #20966 (CLOSED: DUPLICATE)](https://github.com/anthropics/claude-code/issues/20966) — high-priority secrets in tool output
- [cc-redact (open source)](https://github.com/ShindouMihou/cc-redact/) — PreToolUse hook for file content redaction
- [Redaction hooks gist (ruvnet)](https://gist.github.com/ruvnet/332336ad5e0516daa810d98f8f0ddca9) — PostToolUse hook implementation
- [Stop Leaking Secrets to Claude Code (strongly.ai)](https://www.strongly.ai/blog/stop-leaking-secrets-claude-code.html) — CLAUDE.md limits documented
- [PostToolUse output replacement (agentpatterns.ai)](https://www.agentpatterns.ai/tool-engineering/posttooluse-output-replacement/) — updatedToolOutput mechanism
- [OWASP AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html) — output filtering pipeline

**Phase 2 sources (new):**
- [Claude Code hooks reference (official)](https://code.claude.com/docs/en/hooks) — re-fetched to verify MessageDisplay existence and exact schema
- [Claude Code hooks reference (official) — MessageDisplay anchor](https://code.claude.com/docs/en/hooks#messagedisplay) — exact JSON schema and timing behavior
- [Claude Code Hooks Complete Guide (hidekazu-konishi.com)](https://hidekazu-konishi.com/entry/claude_code_hooks_complete_guide.html) — "MessageDisplay can rewrite assistant text before the user sees it"
- [Claude Code Hooks 2026 Reference (morphllm.com)](https://www.morphllm.com/claude-code-hooks) — 10s default timeout for MessageDisplay; event list
- [Session file format (databunny.medium.com)](https://databunny.medium.com/inside-claude-code-the-session-file-format-and-how-to-inspect-it-b9998e66d56b) — JSONL stores original text, location: `~/.claude/projects/.../sessions/`
- [ClipGate pipe-based redaction (clipgate.github.io)](https://clipgate.github.io/blog/pipe-terminal-output-to-claude-cursor-aider/) — external stdout filter architecture
- [Claude Code hooks schema gist (FrancisBourre)](https://gist.github.com/FrancisBourre/50dca37124ecc43eaf08328cdcccdb34) — hook input field reference
- See auxiliary: `leakage_hooks_doc_1.txt` — Phase 1 hook capability matrix
- See auxiliary: `leakage_permissions_doc_2.txt` — Phase 1 permissions verbatim
- See auxiliary: `leakage_issues_log_3.txt` — Phase 1 GitHub issue digest
- See auxiliary: `leakage_community_patterns_4.txt` — Phase 1 community patterns
- See auxiliary: `leakage_output_hook_deepdive_5.txt` — Phase 2 deep-dive source material: MessageDisplay schema, timing, JSONL behavior, ecosystem DLP

## Phase 1 Findings

### Finding 1: This is a recognized, named, and widely-reported behavior

**Evidence:** Between November 2025 and June 2026, at least five distinct GitHub issues were filed against `anthropics/claude-code` specifically about credential/secret exposure in terminal output: #44868 (OPEN), #32523 (CLOSED: NOT PLANNED), #29434 (CLOSED: NOT PLANNED), #21528 (CLOSED: NOT PLANNED), #20966 (CLOSED: DUPLICATE). Community blog posts (strongly.ai, scottspence.com, patrickmccanna.net) all appeared in 2025–2026 addressing the same pattern.

**Source:** github.com/anthropics/claude-code issues listed above; blog posts in Sources

**Significance:** The behavior is a recognized failure mode named with terms including "secret echoing", "credential exposure in tool output", "sensitive data in agent output". Anthropic has declined to implement built-in redaction (multiple issues closed "not planned").

Verification block: URLs fetched, issue titles confirmed as described above.

---

### Finding 2: The fundamental split — preventing READ vs preventing ECHO

**Evidence:** Official Claude Code hooks documentation:

> "There is no hook event that intercepts Claude's generated response text before it displays."
> "MessageDisplay — display-only: the transcript and what Claude sees keep the original."

| Surface | Can hooks modify? | Mechanism |
|---|---|---|
| Tool input (file path, command) | Yes | PreToolUse + `updatedInput` |
| Tool output (file content, stdout) | Yes | PostToolUse + `updatedToolOutput` |
| Model assistant text | **No** | No hook event exists for this |
| On-screen display only | Display-only | MessageDisplay (model still sees original) |

**Source:** `https://code.claude.com/docs/en/hooks` (fetched 2026-06-26)

**Significance:** Two fundamentally different problems exist: preventing READ (mechanical, reliable — hooks and deny rules operate before context ingestion) versus preventing ECHO (much harder — once in context, no hook can modify the model's generated text). Phase 2 investigates whether the display layer can be intercepted.

Verification block: URL fetched / key quote confirmed in official docs.

---

### Finding 3: CLAUDE.md instructions are explicitly insufficient as sole defense

**Evidence:** Official permissions documentation: "Instructions in your prompt or CLAUDE.md shape what Claude tries to do, but they don't change what Claude Code allows." Issue #44868: CLAUDE.md prohibited credential reading; Claude Code still ran `grep -n curl .dev.vars` and printed the token. Issue #32523: similar case, closed not planned.

**Source:** `https://code.claude.com/docs/en/permissions`; issues #44868, #32523; strongly.ai

**Significance:** CLAUDE.md rules are advisory behavioral shaping only. They fail under ambiguous prompts, compound tool calls, and diagnostic sequences. Work as one layer among several, not as a primary defense.

Verification block: URLs fetched / quotes confirmed.

---

### Finding 4: PostToolUse can prevent context ingestion — REJECTED under Phase 2 constraints

**Evidence:** `updatedToolOutput` replaces what the model receives from a tool call, preventing ingestion at the source. This would prevent the email body from entering context at all.

**Source:** `https://code.claude.com/docs/en/hooks`; agentpatterns.ai

**Significance:** Would have addressed the 4Shark incident but violates Constraint 2 (cripples email body summarization). REJECTED under the sharpened constraints. Included here for completeness.

Verification block: `updatedToolOutput` field confirmed in hooks documentation.

---

### Finding 5–7 (condensed): Other Phase 1 approaches — all REJECTED under Phase 2 constraints

- **Deny rules** (Finding 5): prevent READ — violated by Constraint 2 (email body reading is a feature to keep).
- **Vault references** (Finding 6): structural elimination — violated by Constraint 1 (external client controls email format).
- **Anthropic's stance** (Finding 7): no native redaction planned. Five issues closed "not planned." No platform solution is coming.

---

## Phase 2 Findings — Deep-Dive on Output-Layer Interception

### Finding 8: MessageDisplay hook EXISTS — verified against current official docs

**Evidence:** The `MessageDisplay` hook is present in the current official Claude Code hooks documentation. Verbatim from the lifecycle table:

> "MessageDisplay | While assistant message text is displayed"

Verbatim from the decision control table:

> "MessageDisplay | hookSpecificOutput | displayContent replaces the displayed text on screen. Display-only: the transcript and what Claude sees keep the original"

The exact JSON the hook must return:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "MessageDisplay",
    "displayContent": "replacement text to show on screen"
  }
}
```

The hook receives these fields on stdin:

```
session_id, transcript_path, cwd, hook_event_name ("MessageDisplay"),
turn_id, message_id, index, final (boolean), delta (the batch text)
```

The `delta` field contains the batch of assistant text to be rendered. The hook script can do any computation on it — including regex substitution — and return the processed text as `displayContent`. This is a shell script; any arbitrary logic is possible.

**Source:** `https://code.claude.com/docs/en/hooks` (fetched 2026-06-26, two separate page loads, both confirmed); `https://code.claude.com/docs/en/hooks#messagedisplay`

**Significance:** The previous spike section that mentioned `MessageDisplay` + `displayContent` was NOT fabricated. The hook exists and the field is documented. The "cosmetic only" characterization was accurate — see Finding 9 for the exact scope of what "display-only" means.

Verification block: URL fetched twice / verbatim quotes "MessageDisplay | hookSpecificOutput | displayContent replaces the displayed text on screen" and "Display-only: the transcript and what Claude sees keep the original" confirmed in both fetches.

---

### Finding 9: Exact behavior of MessageDisplay — what it DOES and what it does NOT do

**Evidence:**

**(A) Timing in interactive terminal mode:**

From web search synthesis confirmed by multiple sources (hidekazu-konishi.com, morphllm.com, official docs, 2026-06-26):

> "Claude Code displays the message in increments: each time a batch of newly completed lines is ready to render, the hook runs once with those lines and Claude Code renders the hook's replacement text in their place."

The hook fires **before** the batch renders. Claude Code holds the batch until the hook returns. The hook is a blocking step in the rendering pipeline. A long message produces multiple hook calls (one per batch); a short message may produce only one. The `displayContent` return value is what appears on screen — the original `delta` is NOT shown.

**(B) Timing in non-interactive mode (claude -p, Agent SDK):**

From official docs and morphllm.com (2026-06-26):

> "In non-interactive runs, including Agent SDK queries and claude -p, MessageDisplay runs once per assistant message instead of once per batch of lines. The single call arrives after the message completes and carries the full message text: index is 0, final is true, and delta holds the entire message."

The word "arrives after the message completes" is critical. In non-interactive mode, the message text has already been written to stdout BEFORE the hook fires. The `displayContent` has no practical effect on what already appeared in stdout.

**(C) JSONL transcript on disk:**

From official docs (verbatim):
> "Display-only: the transcript and what Claude sees keep the original"

From the session file format article (databunny.medium.com):
> Session JSONL files store "the full message-by-message record" including "The visible reply. Everything Claude writes to you." as `text` content blocks.

File location: `~/.claude/projects/<url-encoded-project-path>/sessions/<session-uuid>.jsonl`

The JSONL records the ORIGINAL text. The credential value appears verbatim in the on-disk transcript even when MessageDisplay masks it on screen.

**(D) Verbose mode:**

From multiple sources (morphllm.com, official docs):
> "verbose mode shows the original"

Running Claude Code with `--verbose` bypasses the `displayContent` replacement. The engineer or another team member running with this flag sees the unmasked credential.

**(E) Hook failure / timeout:**

From web search synthesis (2026-06-26):
> "If a MessageDisplay hook fails or times out, Claude Code displays the original text, ensuring that the original content is preserved as a fallback mechanism."

Default timeout: 10 seconds (from morphllm.com timeout table). If the hook script crashes or exceeds 10s, the unmasked credential appears on screen.

**(F) Model context for future turns:**

From official docs (verbatim):
> "the transcript and what Claude sees keep the original"

The model's context for future turns in the same session retains the original value. If the engineer asks "what was the password?", the model will repeat it from its context window.

**(G) No other hook intercepts assistant text:**

- **Stop**: fires when Claude finishes responding. Can block (exit 2) or inject `additionalContext`. Cannot modify the already-generated response text.
- **SubagentStop**: same shape, same limitation.
- **No other hook**: confirmed in official docs capability matrix — the only surface with display-modification capability is `MessageDisplay`.

**Source:** `https://code.claude.com/docs/en/hooks` (both fetches 2026-06-26); `https://hidekazu-konishi.com/entry/claude_code_hooks_complete_guide.html`; `https://databunny.medium.com/inside-claude-code-the-session-file-format-and-how-to-inspect-it-b9998e66d56b`; morphllm.com search synthesis

**Significance:** `MessageDisplay` + `displayContent` achieves on-screen masking in interactive mode. It does NOT affect the JSONL transcript, the model's context, verbose mode output, or non-interactive stdout. The engineer must decide whether the on-screen masking alone is sufficient given the residual risks.

Verification block: URL fetched / verbatim "Display-only: the transcript and what Claude sees keep the original" confirmed. "verbose mode shows the original" confirmed in morphllm.com synthesis. Non-interactive timing "arrives after the message completes" confirmed in official docs and morphllm.com.

---

### Finding 10: The Stop hook as a detection signal — not a redactor

**Evidence:** From official docs:

> "Stop | When Claude finishes responding | decision: 'block', reason. Stop and SubagentStop also accept hookSpecificOutput.additionalContext for non-error feedback that continues the conversation"

The Stop hook can receive the `transcript_path` and read the session JSONL to inspect the last assistant turn. A Stop hook script could detect credential-shaped values in the last turn and inject `additionalContext`: "Your previous response contained a credential value. In future turns, refer to it by name only, never by value."

This does NOT redact what was already displayed. It primes the next turn.

**Source:** `https://code.claude.com/docs/en/hooks` (fetched 2026-06-26)

**Significance:** A Stop hook adds a behavioral nudge at the session level without touching context. It does not solve the display problem but slightly reduces the chance of re-echoing in subsequent turns. Layer value only; not a primary defense.

Verification block: URL fetched / "Stop and SubagentStop also accept hookSpecificOutput.additionalContext" confirmed in official docs.

---

### Finding 11: Ecosystem DLP — external stdout pipe as output-layer filter

**Evidence:** ClipGate and similar tools operate at the terminal pipe level, outside Claude Code's hook system. From clipgate.github.io:

> "The classifier runs a secret detector at capture time, and any substring matching a known token shape gets quarantined. `ghp_`-prefixed GitHub tokens, `sk_`-prefixed OpenAI keys, `AKIA`-prefixed AWS access keys, JWTs, high-entropy strings of plausible token length — all of it gets flagged."
> "Quarantined secrets exist in a separate, in-memory-only store with a five-minute TTL — never persisted to disk"

The architecture: `claude-code 2>&1 | redact-filter` — the filter intercepts at the OS pipe before the text reaches the terminal buffer.

This approach addresses what `MessageDisplay` misses: it intercepts the raw stdout stream, operates outside Claude Code's hook system, and can be applied in non-interactive mode. However, it does NOT address the JSONL transcript (written directly to disk by Claude Code, not via stdout).

**Source:** `https://clipgate.github.io/blog/pipe-terminal-output-to-claude-cursor-aider/`

**Significance:** A stdout pipe filter is an additional layer that can complement `MessageDisplay`. It closes the non-interactive stdout gap that `MessageDisplay` leaves open. The combination: `MessageDisplay` for interactive display masking + stdout pipe for non-interactive stdout filtering. Neither touches the JSONL transcript.

Verification block: URL fetched / "classifier runs a secret detector at capture time" confirmed in fetched content.

---

## Verdict (Question D)

**The engineer's exact want: keep full email-body reading/summarizing AND never display the raw secret in the assistant's output.**

### Verdict: (ii) PARTIALLY ACHIEVABLE

**What IS achievable:**

The on-screen terminal display in interactive mode can be masked via `MessageDisplay` + a `displayContent` hook script that regex-detects credential-shaped values (connection strings, common token prefixes, high-entropy strings) and replaces them in each rendered batch. The hook fires before the batch renders — the engineer does not see the credential on screen.

An external stdout pipe filter (ClipGate pattern) can close the non-interactive stdout gap, providing a complementary layer for `claude -p` and Agent SDK invocations.

A CLAUDE.md behavioral rule reduces the baseline probability that the model echoes the credential at all (behavioral shaping, not mechanical enforcement).

**What is NOT achievable without violating the engineer's constraints:**

| Residual risk | Why it exists | Can it be closed? |
|---|---|---|
| JSONL transcript on disk (`~/.claude/projects/.../sessions/*.jsonl`) contains the plaintext credential | "the transcript and what Claude sees keep the original" — by design | No. Closing this requires removing the secret from context (Constraint 2 rejected). |
| Model's context for future turns retains the credential | Model reads the full email body (Constraint 2 kept) — value is in context | No. Same constraint. |
| `--verbose` mode displays the original unmasked text | verbose bypasses `displayContent` | Only by policy: never run `--verbose` when Gmail MCP email fetching is active |
| Non-interactive stdout (`claude -p`) shows the original before MessageDisplay fires | Hook fires after message completes in non-interactive mode | Partially: stdout pipe filter can redact the stream, but JSONL is still unredacted |
| Hook failure (crash or 10s timeout) → original displays | Fallback behavior by design | Only by keeping the hook fast and crash-resistant |
| Regex miss (unrecognized credential shape) | Pattern-based detection is heuristic | Only by broadening patterns (risk: false positives masking legitimate output) |

### The bottom line, stated plainly

The `MessageDisplay` hook gives the engineer **display masking in the interactive terminal** — the credential does not appear on screen in the engineer's normal usage. This is the most practical defense available given the constraints.

It does NOT give **confidentiality** — the credential exists in the session JSONL on disk and in the model's context for the remainder of the session. Anyone with filesystem access, or anyone who runs `--verbose`, or any future Claude turn where the model decides to repeat it, can surface the value. The risk is reduced from "visible on screen" to "on disk and in model context" — a meaningful improvement, but not elimination.

---

## Documentation shape (for main to implement via PR — do NOT implement here)

### Shape of the ADR (Architecture Decision Record)

A new `ADR-NNN-email-credential-display-risk.md` in `~/.claude/docs/adr/` should contain:

**Title:** Accept residual display risk for credentials in email bodies fetched via Gmail MCP

**Context:** Clients (e.g. Atento) send production database passwords by email. Claude Code's Gmail MCP integration is used to fetch and summarize those emails. The external client controls the email format — vault references and source control cannot be applied. The PostToolUse scrubbing approach would strip the email body before the model sees it, crippling email summarization. The accepted trade-off: allow the model to read the full email body (and therefore hold the credential in context), and apply display-layer masking only.

**Decision:** Deploy `MessageDisplay` hook with regex-based `displayContent` masking + CLAUDE.md behavioral rule. Do NOT deploy PostToolUse scrubbing on Gmail MCP tools.

**Consequences (to document):**

- On-screen display: masked (protected)
- JSONL transcript at `~/.claude/projects/.../sessions/*.jsonl`: contains plaintext credential
- Model context: contains plaintext credential for session duration
- `--verbose` mode: displays plaintext credential — MUST NOT be used when Gmail MCP is active
- Non-interactive mode: requires additional stdout pipe filter or is unprotected
- Hook failure fallback: credential displays on screen

**Known residual risk accepted deliberately:** the credential lives in the session JSONL on disk. The JSONL is not encrypted at rest by default. Engineers must be aware that session files are sensitive when email-fetching workflows involving credentials are used.

**Who must act on this:** All engineers on the team must know the JSONL residual risk. Sessions involving credential-containing emails should be treated as sensitive files and not synced to unsecured locations.

---

### Shape of the CLAUDE.md behavioral rule

A new rule to be added under a section such as `### Email Credential Handling` in `~/.claude/CLAUDE.md`:

The rule must:

1. Name the specific scenario: when asked to locate, find, or reference an email — return ONLY the message link, subject line, and sender name. Never include the email body in the response.
2. Name the prohibited action: never print the content of an email body when only the link or metadata was requested. If the email body contains a credential value (password, connection string, API key), acknowledge its category only — e.g. "The email contains a database password" — never the value itself.
3. Scope it to the request, not the content: the constraint is about what was asked for. If the engineer explicitly asks "show me the full email", the body can be shown but credential values within it must still be acknowledged by category only, never printed verbatim.
4. Acknowledge the mechanism: the CLAUDE.md rule is behavioral shaping. It does not mechanically prevent the behavior. The `MessageDisplay` hook is the enforcement layer; the CLAUDE.md rule is the intent signal.

---

## What remains uncertain

- Whether the `delta` field in MessageDisplay receives the batch as a literal string that can be modified by arbitrary regex substitution — this was confirmed by community sources but no official documentation explicitly documents the regex-capable use case with an example
- The exact behavior of the stdout pipe filter pattern in combination with Claude Code's streaming output — whether the pipe intercepts the full stdout or only parts of it
- Whether the Gmail MCP tool result fires `PostToolUse` (and thus would be hookable as a separate layer if the engineer changes their mind on Constraint 2 in the future)
- The exact location and permissions of the JSONL files — whether they are accessible only to the current user or to other processes on the machine
- Whether Claude Code encrypts JSONL session files at rest in any configuration

## Trade-offs table (updated with Phase 2 findings)

| Approach | Covers | Does NOT cover | Constraint status |
|---|---|---|---|
| **PostToolUse scrub on email tool result** | Context ingestion — prevents the credential from entering model context | Email body summarization is lost | REJECTED (violates Constraint 2) |
| **permissions.deny on email read** | Prevents reading email body at all | Email body summarization is lost | REJECTED (violates Constraint 2) |
| **Vault references** | Structural — no plaintext to echo | Requires client to change how they send passwords | REJECTED (violates Constraint 1) |
| **MessageDisplay + displayContent** | On-screen display in interactive mode | JSONL transcript, model context, --verbose mode, non-interactive stdout, hook failure | ACCEPTED direction |
| **stdout pipe filter (ClipGate pattern)** | Non-interactive stdout | JSONL transcript, model context | Complementary layer |
| **CLAUDE.md behavioral rule** | Reduces baseline probability of echoing | Advisory only — no mechanical enforcement | Complementary layer |
| **Stop hook + additionalContext** | Primes next turn to avoid re-echoing | Does not change current turn's display | Complementary layer |
| **ADR + documented residual risk** | Team awareness, future session hygiene | Does not change the technical reality | Required regardless |

(NO recommendation — verdict and trade-offs surfaced; engineer and main decide)
