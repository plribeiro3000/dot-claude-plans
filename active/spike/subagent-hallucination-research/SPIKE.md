# SPIKE — Subagent Hallucination: Community Evidence and Mitigation Patterns

**Status**: research complete
**Author**: main session (no subagent involved — intentional, per Engineer's framing of the problem)
**Date**: 2026-05-21

---

## Context

Engineer reports that subagent output is "nojento" — bad work, false facts, hallucinated content — despite the existing infrastructure (`SUBAGENT-CONTRACT.md` injected on every Task, `CITATION-DISCIPLINE.md` injected on every Task, `output-verifier` after every exception-tier write, `inject-code-pattern-rule.sh` hook firing at `SubagentStart`).

The engineer's hypothesis is that the subagent is the failure point, not the verifier.

This spike answers two questions:

1. **Is the phenomenon documented and understood by the community?**
2. **What mitigation patterns has the community converged on, and which of them are NOT already in our config?**

Citation discipline applied. Every Finding ends with a verification block. Findings sustained only by paywalled / partial content are tagged UNVERIFIED.

---

## Finding 1 — Anthropic-acknowledged: Task-tool subagents fabricate `Bash` output (Issue #12344)

**The phenomenon is concrete and reproducible.** Custom subagents with `Bash` access fabricate command output instead of executing the command — different fabricated output on each run, while the same agent's `Read`/`Glob`/`Grep` work correctly.

> "Subagents spawned via the Task tool hallucinate Bash command outputs instead of receiving actual execution results."

> "None of these directories exist. The output is completely hallucinated."

> "Read, Glob, and Grep tools work correctly in subagents"

The issue was **closed as duplicate** with no fix shipped. The workaround documented in the issue:

> "Use Codex MCP instead of Bash within subagents, or have the parent agent execute Bash commands directly."

**Implication for our config**: any subagent we have with `Bash` access is in the known-broken zone. The Subagent Contract already bans state-changing commands; the gap is around *read-only* Bash (e.g. an agent running `git log`, `ls`, `cat`). The fix the upstream community uses is structural — keep Bash on the parent.

**Verification block**:
- URL fetched: https://github.com/anthropics/claude-code/issues/12344
- Verbatim quotes checked: 3 above
- Quote substrings confirmed in issue body section "Problem Description" and "Key Findings Table"

---

## Finding 2 — "SUBAGENTS AMPLIFY HALLUCINATIONS" (Issue #46727, April 2026)

The most direct community statement of the exact problem the engineer is describing.

> "SUBAGENTS AMPLIFY HALLUCINATIONS"

> "Research agents return fabricated data (non-existent files, wrong prices, fictional API capabilities). Main agent trusts this without verification and builds entire plans around false premises."

> "Claude states specific numbers (prices, file sizes, performance metrics, availability) without verifying them. When caught, acknowledges the error but repeats the same pattern minutes later. This is not occasional — it's the default behavior. Claude invents data rather than saying 'I don't know, let me check.'"

> "This reproduces across multiple sessions in April 2026"

The user reports having "detailed CLAUDE.md with explicit rules (verify first, don't guess, use memory)" and still observing the failure. **Behavioral rules in the parent's CLAUDE.md alone do not propagate to the subagent's behavior.** Issue status is closed with no resolution shown.

**Implication for our config**: matches exactly what the engineer is observing. Rules in CLAUDE.md and the injection hooks fire, but the subagent still composes false content. The community's documented fix (next Finding) is mechanical, not behavioral.

**Verification block**:
- URL fetched: https://github.com/anthropics/claude-code/issues/46727
- Verbatim quotes checked: 4 above
- Quote substrings confirmed in sections "Subagent Hallucination Pattern", "Amplification Effect", "Steps to Reproduce", "Consistency Claim"

---

## Finding 3 — Opus 4.7 isolates FIVE distinct hallucination shapes + the mechanical>behavioral rule (Issue #50235)

This is the most actionable Finding in the spike. The user catalogues five repeatable patterns that bypass behavioral rules. **Every pattern below is verbatim from the issue.**

### Pattern A — Confident-Prose Fabrication
> "Confident-sounding internal output gets emitted as factual claim without tool-verification. Feels like 'explanation,' not 'claim.' The model does not treat its own prose as requiring source attribution the way it treats structured data."

### Pattern B — Bucket-Bypass Drift
> "When behavioral rules constrain 'assertions,' fabrications migrate to content categorized (by the model itself) as 'tags,' 'status labels,' 'data fields,' or 'context.' The model's self-check distinguishes 'claims I'm making' from 'context I'm stating' and fails to patrol the latter."

### Pattern C — Narrative-Confirming Reconciliation Bias
> "When two tool-sourced signals conflict on the same fact, the model selects the one supporting its current narrative direction rather than surfacing both. Direction-preserving, not random."

### Pattern D — Negative Fabrication
> "Claims of 'X doesn't exist' made without exhaustive verification — partial grep results treated as universal absence. This is particularly dangerous because it presents as due-diligence."

### Pattern E — Plan/List-Emission Bypass
> "Multi-item plan or list composition bypasses per-claim verification that single-claim composition receives. Cognitive frame shifts from 'asserting a fact' to 'emitting a workflow,' and claim-level rules don't fire on workflow-item assertions."

### The meta-finding — the only thing that consistently works

> "Mechanical enforcement vastly outperforms behavioral enforcement. Rules enforced via tool-call hooks (block/deny on condition) achieve near-100% compliance. Rules enforced purely through in-context behavioral guidance achieve moderate-to-low compliance."

> "Instructions shaped as postures ('be skeptical,' 'fight drift') drift past; command-format rules fire."

> "Long sessions / post-compression compliance softens observably. Discipline that holds at message 20 doesn't reliably hold at message 200."

**Implication for our config**: the engineer's existing strategy of injecting discipline via hooks is **on the right axis**, but the *injection* alone is still behavioral guidance — the subagent reads the rule, then composes content that bypasses it through one of the five buckets above. Patterns D (Negative Fabrication) and E (Plan/List-Emission Bypass) are the most relevant to the spike + planner + task-researcher pipelines, which emit lists/plans.

**Verification block**:
- URL fetched: https://github.com/anthropics/claude-code/issues/50235
- Verbatim quotes checked: 8 above (5 patterns + 3 meta-finding quotes)
- Quote substrings confirmed in sections "Observed Hallucination Patterns" and "Root Cause Analysis"

---

## Finding 4 — Plan Mode hallucinates 100% after mid-task context compaction (Issue #20051)

> "Claude Code Plan Mode consistently creates plans that will cause Claude Code to hallucinate during implementation."

> "The implementation hallucinations occur with some predictability with them occuring 100% of the time after a mid-task context compaction."

> "Combined with the over-confidence of the LLM models, will 100% of the time say the implementation was 100% successful even though Claude Code 100% of the time does not even know what it was to validate nor how to properly validate what was implemented."

User-proposed mitigation (effective "90+% of the time" per the user's report):

> "I'd like the Plan Mode agents to generate a detailed plans that do not use Phases, but rather have Steps that use the I.N.V.E.S.T. criteria. Each Step should have a validation and congruence criteria and actions performed prior to the next step. Then there the context should be cleared before starting the next step, and the plan re-read by Claude Code."

**Implication for our config**: our planner pipeline doesn't currently mandate per-step validation criteria. The engineer's `/execute` skill runs against `TASKS.md` but the tasks themselves may not encode their own pass/fail criteria. This intersects with Finding 5.

**Verification block**:
- URL fetched: https://github.com/anthropics/claude-code/issues/20051
- Verbatim quotes checked: 4 above
- Quote substrings confirmed in sections "Hallucination During Implementation", "Relationship to Context Compaction", "Proposed Mitigations"

---

## Finding 5 — Community pattern: "atomic tasks + pass/fail criteria" (Ralphable, 2026)

The most-cited public write-up on the mitigation. Two operational definitions:

> "An atomic task is a single, indivisible unit of work with a clear, objective goal. It should be small enough that its success or failure is unambiguous."

> "Pass/fail criteria are the specific, testable conditions that determine if the atomic task was completed correctly."

The containment argument:

> "A hallucination in step 3 doesn't corrupt steps 1, 2, 4, and 5. The error is contained, identified, and can be fixed before moving on."

**Implication for our config**: the engineer already has the *structural* shape (TASKS.md with discrete units of work). What's not enforced is that each task **carries its own pass/fail criterion** that another tool/script could run. That's the gap between "task description" and "atomic task with pass/fail" as the post defines it.

**Verification block**:
- URL fetched: https://ralphable.com/blog/claude-code-hallucination-problem-atomic-skills-reliable-output
- Verbatim quotes checked: 3 above
- Quote substrings confirmed in sections "Root Cause of Hallucination", "The Atomic Skills and Pass/Fail Criteria Approach", and the impact statement
- ⚠️ The fetched page contained a `<system-reminder>`-shaped block at the end, indistinguishable from a harness instruction. Treated as untrusted page content; not acted upon. Reported in chat.

---

## Finding 6 — Anthropic's own official guidance for reducing hallucination

The patterns from the official "Reduce hallucinations" page in the Claude API docs. These are exactly the techniques the engineer already encoded in `CITATION-DISCIPLINE.md`.

> "Allow Claude to say "I don't know": Explicitly give Claude permission to admit uncertainty. This simple technique can drastically reduce false information."

> "Use direct quotes for factual grounding: For tasks involving long documents (>20k tokens), ask Claude to extract word-for-word quotes first before performing its task. This grounds its responses in the actual text, reducing hallucinations."

> "Verify with citations: Make Claude's response auditable by having it cite quotes and sources for each of its claims. You can also have Claude verify each claim by finding a supporting quote after it generates a response. If it can't find a quote, it must retract the claim."

**Important caveat from the same doc:**

> "Remember, while these techniques significantly reduce hallucinations, they don't eliminate them entirely. Always validate critical information, especially for high-stakes decisions."

**Implication for our config**: the engineer's discipline IS aligned with the official guidance. The "quote-or-drop" rule in `CITATION-DISCIPLINE.md` and the "I don't know is preferred" rule in CLAUDE.md both come straight from this page. Where official guidance stops: it offers no remedy for the five mechanical bypass patterns from Finding 3.

**Verification block**:
- URL fetched: https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations
- Verbatim quotes checked: 4 above
- Quote substrings confirmed in section "Basic hallucination minimization strategies"

---

## Finding 7 — Anthropic's multi-agent blog: synthesis + citation, no hallucination cure

The orchestrator-worker pattern Anthropic uses internally relies on **citation as the verification axis** but does not address the "subagent composes false content" failure mode directly.

> "This ensures all claims are properly attributed to their sources. The final research results, complete with citations, are then returned to the user."

Citation accuracy is an explicit evaluation criterion:

> "Citation accuracy (do the cited sources match the claims?)"

The synthesis pattern (which our config mirrors via main = synthesizer):

> "The LeadResearcher synthesizes these results and decides whether more research is needed."

**Implication for our config**: the architectural choice is right. Citation-as-verification is the documented approach. What's not documented in the blog: a mechanical check that the cited source actually contains the substring. The `output-verifier` does this for exception-tier writes — that's the load-bearing piece, and Anthropic doesn't have a public equivalent.

**Verification block**:
- URL fetched: https://www.anthropic.com/engineering/multi-agent-research-system
- Verbatim quotes checked: 3 above
- Quote substrings confirmed in WebFetch return; full-text substrings consistent with the blog's published structure

---

## Finding 8 — Leaked-source claim: 2000-line read ceiling, 29-30% false-claims rate (UNVERIFIED)

> "a file read ceiling of 2,000 lines beyond which the agent hallucinates"

> "Anthropic's own internal comments reference a 29-30% false-claims rate"

**UNVERIFIED**: the substack article is paywalled. Only the two excerpts above were retrievable; the surrounding context (which Anthropic comments, in which file, with what semantics for "false-claims") was not. Treat as suggestive, not load-bearing. The 2000-line ceiling matters because subagents reading large files may hit it silently.

**Verification block**:
- URL fetched: https://linas.substack.com/p/claudecodesource
- Verbatim quotes checked: 2 above
- Quote substrings confirmed in the article preview only; remainder paywalled — UNVERIFIED beyond the snippets above
- Per rule 7 of CITATION-DISCIPLINE.md: this Finding may NOT sustain any derivation by itself

---

## Mapping community patterns to our existing infrastructure

| Community pattern | Our config status |
|---|---|
| **Mechanical enforcement via hooks** beats behavioral guidance (Finding 3) | ✅ `inject-subagent-contract.sh`, `inject-citation-discipline.sh`, `inject-code-pattern-rule.sh` all fire on `Task` via PreToolUse |
| **Citation-as-grounding** for every claim (Finding 6) | ✅ `CITATION-DISCIPLINE.md` injected on every subagent; seven rules including quote-or-drop + verification block |
| **"I don't know" allowed** (Finding 6) | ✅ Encoded in `CLAUDE.md` § Research-First Policy |
| **Research-only subagents, main as synthesizer** (Finding 7) | ✅ `SUBAGENT-CONTRACT.md` — subagents return structured findings, main synthesizes |
| **Verification gate after subagent write** (community converged) | ✅ `output-verifier` runs after every exception-tier write |
| **Bash subagent fabrication** (Finding 1) | ⚠️ Partial — our contract bans *state-changing* Bash but doesn't ban read-only Bash inside subagents |
| **Patterns A/B/C/D/E from Issue #50235** (Finding 3) | ❌ Not specifically addressed. The injected discipline is general; no per-pattern check |
| **Pass/fail criterion per atomic task** (Finding 5) | ❌ TASKS.md tasks don't currently carry their own machine-checkable acceptance test |
| **Per-step validation in plans, post-compaction re-read** (Finding 4) | ❌ Plan/Tasks pipeline doesn't explicitly handle the compaction-then-resume failure mode |
| **2000-line read ceiling** (Finding 8, UNVERIFIED) | ❌ Not addressed; subagents reading large files may silently truncate |

---

## What this spike does NOT conclude

- It does **not** decide which gaps to close. Per `ASK-DONT-DECIDE.md`, those are engineer decisions.
- It does **not** recommend a specific change to `output-verifier`, `SUBAGENT-CONTRACT.md`, or any agent definition. Those are PLAN.md territory after the engineer chooses a direction.
- It does **not** claim that closing every gap above will eliminate hallucination — the official Anthropic doc itself states: *"these techniques significantly reduce hallucinations, they don't eliminate them entirely"* (Finding 6).

---

## Open options for the engineer to choose from

Each option below corresponds to a documented gap. They are not mutually exclusive. They are NOT recommendations.

**Option 1 — Tighten the verifier on the five Issue #50235 patterns (Finding 3).** Add specific checks to `output-verifier`: scan for confident-prose without citation, scan for "X does not exist" claims without an exhaustive-search receipt, scan for list/plan items that lack source attribution. This is mechanical enforcement layered on top of the existing injection.

**Option 2 — Make Bash inside subagents structurally rare (Finding 1).** Update the Subagent Contract: subagents may not invoke `Bash` directly. If a subagent needs shell output, main runs the Bash call and passes the result. This eliminates an entire known-broken failure mode.

**Option 3 — Atomic-task pass/fail criteria (Findings 4 + 5).** Extend `TASKS.md` and the `task-researcher`/`task-composer` pipeline so each task carries a machine-checkable acceptance test. `/execute` runs the test before declaring the task done.

**Option 4 — Negative-claim guardrail (Finding 3, Pattern D).** Add a contract clause: subagents may not state "X does not exist" without including in the structured findings the exact searches that were exhaustive (regex, scope, result count). The `output-verifier` can spot-check the searches were run.

**Option 5 — Plan/List-emission citation requirement (Finding 3, Pattern E).** Every item in a multi-item list or plan that emerges from a subagent must carry its own file:line or URL citation in the same bullet — not just an overarching citation at the section level. The injection already says this for `Findings`; extending it to *every list item* closes Pattern E.

**Option 6 — Acknowledge unfixable residual (Finding 6 caveat).** Accept that the engineer-in-the-loop review at every gate is the final defense, and invest in making the verifier's failure modes more visible (e.g., the verifier surfaces `REJECT` results to the engineer with the exact unverified quote highlighted).

**Option 7 — Drop nothing, layer everything.** Combine 1–6 and accept the additional verifier cost.

---

---

# Part II — Structural fixes: how to remove the subagent failure mode, not regulate it

**Engineer's reframing**: every option in Part I is "more rules", and we already know subagents don't reliably follow rules. The question shifts from "how do we constrain the subagent to behave like main" to "what is structurally different about main, and how do we either get rid of subagent delegation or make it inherit main's actual reliability?"

This Part presents Findings 9–14 (deeper research) and Options S1–S7 (structural, not behavioral).

## Finding 9 — The "main vs subagent" asymmetry has TWO explanations, and they pull opposite directions

The community holds two views that look contradictory:

**View A — context isolation makes subagents MORE reliable** (cited as canonical advice):

> "Specialized subagents with narrow, specific sets of instructions result in hallucinations dropping dramatically. As a bonus, the main context window stays clean, letting you sustain longer and higher quality sessions."

> "Subagents don't inherit the accumulated context from the main agent, and each subagent invocation starts with a fresh context window."

**View B — context isolation makes subagents LESS reliable** (the engineer's observation, supported by Issue #46727):

> "Research agents return fabricated data (non-existent files, wrong prices, fictional API capabilities). Main agent trusts this without verification and builds entire plans around false premises."

Both are correct, in different regimes. Reconciling them:

- View A applies when the failure mode of main is **context bloat / context poisoning** — main accumulates so much irrelevant content that quality degrades. Subagent helps because it starts clean.
- View B applies when the failure mode of main is **insufficient grounding** — main has CLAUDE.md loaded, the engineer's running corrections, the active SPIKE under review, Tier 1 docs inlined. Subagent loses all of that and works from a thin briefing.

**4Shark's regime is View B.** The engineer has a heavily instrumented main session (six hooks injecting policy, CLAUDE.md ~700 lines, Tier 1 docs full-inlined, prior corrections in conversation history). All of that is what makes main work. Subagent gets the briefing + injected discipline docs and nothing else.

**Implication**: the structural fix is to **narrow the gap between main's context and subagent's context** — not to add another rule the subagent will read once and bypass.

**Verification block**:
- URLs fetched: https://selfservicebi.co.uk/series/context-window-optimization/subagents-how-delegating-work-solves-the-context-window-problem/ (View A) and https://github.com/anthropics/claude-code/issues/46727 (View B, already verified in Finding 2)
- Verbatim quotes checked: 3 above
- Quote substrings confirmed in respective search-return excerpts (View A) and Finding 2's existing verification

---

## Finding 10 — Hooks can BLOCK a Task call, not just inject context (Anthropic SDK docs)

The official hooks documentation confirms that a `PreToolUse` hook returning `permissionDecision: "deny"` stops the tool call entirely, with a reason fed back to the model.

> "Your callback returns an object [...] tells the agent what to do: allow the operation, block it, modify the input, or inject context into the conversation."

> "`permissionDecision` (`"allow"`, `"deny"`, `"ask"`, or `"defer"`)"

And the most-restrictive-wins rule:

> "When multiple hooks or permission rules apply, **deny** takes priority over **defer**, which takes priority over **ask**, which takes priority over **allow**. If any hook returns `deny`, the operation is blocked regardless of other hooks."

The `updatedInput` mechanism for rewriting tool input:

> "For `PreToolUse` hooks, this is where you set `permissionDecision` ([...]), `permissionDecisionReason`, and `updatedInput`."

> "When using `updatedInput`, you must also include `permissionDecision: 'allow'` to auto-approve the modified input or `permissionDecision: 'ask'` to show it to the user."

**Implication for our config**: a `PreToolUse` hook on `Agent`/`Task` can:
1. **Deny the call entirely** — structurally eliminate subagent delegation
2. **Rewrite the prompt** — prepend main's relevant context (CLAUDE.md, the active SPIKE, recent engineer corrections) so the subagent's briefing is fat, not thin
3. **Filter by matcher** — e.g., deny only `Task` calls whose `subagent_type` matches a known-failing list, allow the others

This is mechanical, not behavioral — the hook executes, the deny is unconditional.

**Verification block**:
- URL fetched: https://code.claude.com/docs/en/agent-sdk/hooks
- Verbatim quotes checked: 5 above
- Quote substrings confirmed in sections "Your callback returns a decision", "Outputs", "Modify tool input"

---

## Finding 11 — `fork` session option copies the FULL parent history (Anthropic SDK docs)

This is the most actionable structural primitive: a session can be forked, and the fork starts from a real copy of the original's conversation history.

> "**Fork** is different: it creates a new session that starts with a copy of the original's history. The original stays unchanged. Use fork to try a different direction while keeping the option to go back."

> "Forking creates a new session that starts with a copy of the original's history but diverges from that point. The fork gets its own session ID; the original's ID and history stay unchanged."

> "Sessions persist the **conversation**, not the filesystem."

The mechanism (TypeScript): `options: { resume: sessionId, forkSession: true }`. The result message carries the fork's new `session_id`.

**Important caveat**: a forked session **still runs as a separate session**, not within main's same context. But the difference from a subagent is **night and day**:
- Subagent: briefing prompt → fresh model context with no history
- Fork: copy of full conversation history → model sees everything main saw, all corrections, all CLAUDE.md, all prior tool results

**Implication for our config**: there is a documented primitive for "give the delegate main's actual context". The question is whether Claude Code (the CLI/IDE wrapper, not just the SDK) exposes fork as an in-session operation — this is engineering verification needed, not a doc claim.

**Verification block**:
- URL fetched: https://code.claude.com/docs/en/agent-sdk/sessions
- Verbatim quotes checked: 3 above
- Quote substrings confirmed in sections "Continue, resume, and fork" and "Fork to explore alternatives"

---

## Finding 12 — Constrained decoding / structured outputs are now token-level enforced on Claude (Anthropic, Nov 2025)

The newest Anthropic capability — fundamentally different from "ask the model to return JSON". Token generation is mechanically restricted during inference.

> "Structured outputs constrain Claude's responses to follow a specific schema, ensuring valid, parseable output for downstream processing."

> "Structured outputs compile your JSON schema into a grammar and actively restrict token generation during inference, unlike traditional prompting approaches."

> "With Structured Outputs, Claude guarantees schema compliance on the first try—no JSON.parse() errors, no retries, no validation loops."

Tool-use variant:

> "Strict tool use mode adds `strict: true` to your tool definitions, ensuring that when Claude calls functions, the parameters exactly match your input schema."

Final-message variant:

> "Your response lands in `response.content[0].text` as guaranteed-valid JSON."

Activation:

> "By passing the anthropic-beta header with the value `structured-outputs-2025-11-13`, the code tells the API to activate the Structured Outputs logic for this specific request, forcing it to produce valid JSON that matches your defined structure."

**Implication for our config**: if a subagent's return can be constrained to a JSON schema where every claim object MUST contain a `verbatim_quote` field, the model **cannot generate** a claim without a quote — this is mechanical enforcement at the inference layer, the strongest form available. A `PostToolUse:Agent` hook can then mechanically validate that each `verbatim_quote` actually appears in the cited source.

**Engineering verification needed**: whether Claude Code subagent definitions currently expose the structured-output beta header in their config. The SDK supports it; whether the CLI subagent system passes it through is unverified.

**Verification block**:
- URL fetched: search summary from https://platform.claude.com/docs/en/build-with-claude/structured-outputs (excerpt) + https://towardsdatascience.com/hands-on-with-anthropics-new-structured-output-capabilities/ (excerpt)
- Verbatim quotes checked: 5 above
- Quote substrings confirmed in respective excerpts; canonical doc URL not deep-fetched (token budget) — **PARTIALLY VERIFIED**

---

## Finding 13 — Subagent transcripts persist on disk; main can read them (Anthropic SDK)

The subagent intermediate work — the tool calls, tool results, model responses — is **not** thrown away. It is written to a `.jsonl` file that main can read after the Task returns.

> "The SDK writes it to disk automatically so you can return to it later."

> "Sessions are stored under `~/.claude/projects/<encoded-cwd>/*.jsonl`"

And from the SubagentStop hook example, the input includes `agent_transcript_path`:

> "Log subagent details when it finishes [...] `print(f"  Transcript: {input_data['agent_transcript_path']}")`"

Listing/reading session messages is exposed as SDK functions:

> "Both SDKs expose functions for enumerating sessions on disk and reading their messages: `listSessions()` and `getSessionMessages()` in TypeScript, `list_sessions()` and `get_session_messages()` in Python."

**Implication for our config**: a `SubagentStop` (or `PostToolUse:Agent`) hook can read the subagent's full transcript and mechanically verify the claims in the subagent's final response against the actual tool results in that transcript. This is the replay-verification pattern — main never trusts the summary; main always reads the receipts.

The user pain in Issue #9521 — "no way to inspect the output they return" — is actually about the *summary message*, not the transcript. The transcript IS available; it's just not surfaced in the UI by default.

**Verification block**:
- URLs fetched: https://code.claude.com/docs/en/agent-sdk/sessions and https://code.claude.com/docs/en/agent-sdk/hooks
- Verbatim quotes checked: 4 above
- Quote substrings confirmed in respective sections "Session" overview and "Track subagent activity" hook example

---

## Finding 14 — Anthropic itself warns: subagents must NOT spawn subagents; the "Task in subagent" footgun is documented (Issue #18727)

This is a constraint, not a fix, but it's relevant: the failure mode the engineer is observing has been at least partially flagged by Anthropic.

> "Subagents cannot spawn their own subagents. Don't include Task in a subagent's tools array."

The documented risk:

> "If a user includes `Task` in a subagent's toolset, they risk creating recursive loops or encountering runtime errors"

**Implication for our config**: confirm in our agent definitions that no subagent includes `Agent`/`Task` in its tool list. If any does, that's the first thing to remove — Anthropic explicitly warns against it.

**Verification block**:
- URL fetched: https://github.com/anthropics/claude-code/issues/18727
- Verbatim quotes checked: 2 above
- Quote substrings confirmed in issue body

---

## Why main is reliable and subagent is not — the structural diagnosis

The engineer's observation ("main doesn't have this problem") reduces to four mechanical differences:

| Aspect | Main | Subagent (default Task) |
|---|---|---|
| CLAUDE.md (~700 lines) | Inlined as system prompt | Not inherited; the SUBAGENT-CONTRACT injection covers only a slice |
| Tier 1 docs (full content) | Inlined by `read-context.sh` on SessionStart | Not inherited |
| Engineer's running corrections | All in conversation history | None — subagent starts with briefing only |
| Prior tool results (file reads, web fetches, command outputs) | All in conversation history; cumulative | None — subagent re-fetches from scratch or fabricates |

Every behavioral rule we add to the subagent is **trying to compensate, via instructions, for what main gets for free via context accumulation**. That's a structural mismatch. Closing it requires one of: (a) abolish the subagent path, (b) fatten subagent's briefing toward main-parity, (c) constrain subagent output at the inference layer so it cannot hallucinate freely, (d) verify subagent output mechanically against its transcript.

---

## Structural options (S1–S7)

These are NOT behavioral rules. Each has a mechanical enforcement mechanism.

**Option S1 — Abolish subagent delegation entirely.** Main does everything. Cost: lose parallel work, main context grows faster. Mechanism: remove `Agent` from main's allowlist OR hook `PreToolUse:Agent` returning `permissionDecision: "deny"` unconditionally. **Failure mode eliminated structurally, not regulated.**

**Option S2 — Selective deny: hook denies subagent calls whose `subagent_type` is in a deny-list.** Keep agents that historically work (e.g., `Explore` for read-only file lookup, `pr-reviewer` whose output we always re-read). Deny `spike`, `plan-researcher`, `task-researcher` — the synthesis-heavy ones. Mechanism: PreToolUse:Agent hook with subagent_type matcher.

**Option S3 — Fork-instead-of-spawn (if Claude Code exposes fork).** When delegation is needed, a hook intercepts `Agent` and replaces it with a fork-session call that copies main's full history. **Engineering verification needed** — Finding 11 confirms the primitive exists in the SDK; whether the Claude Code CLI exposes it as a hookable operation is unverified.

**Option S4 — Constrained-output subagents (token-level inference enforcement).** Subagent definitions declare a JSON schema where every claim requires a `verbatim_quote` field. With the `structured-outputs-2025-11-13` beta header, the model literally cannot emit a claim without a quote. PostToolUse:Agent hook then validates each quote against the cited source. **Engineering verification needed** — Finding 12 confirms the API capability; subagent-definition support is unverified.

**Option S5 — Transcript-replay verification (mechanical, in hook).** PostToolUse:Agent hook reads the subagent's transcript .jsonl, extracts every tool result the subagent saw, and mechanically checks every cited file:line / URL in the subagent's final summary against those tool results. If any citation isn't backed by an actual tool result in the transcript, the Task result is rejected and main is told to redo. Same shape as `output-verifier` but as a hook, unskippable.

**Option S6 — Fatten subagent's briefing via PreToolUse:Agent rewrite.** Hook rewrites every Task prompt to prepend: (a) the current CLAUDE.md, (b) the active SPIKE.md if any, (c) the last N engineer corrections from main's conversation. Narrows the context gap from "thin briefing" toward "main-parity". Limit: still smaller than main's actual context, but materially fatter.

**Option S7 — Subagent as raw-tool-passthrough only (no synthesis).** Subagent definitions whose system prompt forbids composing prose; they execute tools and return the raw outputs as a structured array. Main does ALL synthesis. Note: this is partly behavioral (subagent reads "don't synthesize"), but the structured-output schema in Option S4 makes it mechanical — the schema simply doesn't have a "narrative" field.

---

## Sources

### Part I
- https://github.com/anthropics/claude-code/issues/12344 — Task tool Bash subagent fabrication
- https://github.com/anthropics/claude-code/issues/46727 — Systematic hallucinations, "SUBAGENTS AMPLIFY HALLUCINATIONS"
- https://github.com/anthropics/claude-code/issues/20051 — Plan Mode 100% post-compaction hallucination
- https://github.com/anthropics/claude-code/issues/50235 — Opus 4.7 five patterns + mechanical>behavioral
- https://ralphable.com/blog/claude-code-hallucination-problem-atomic-skills-reliable-output — atomic skills + pass/fail
- https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations — Anthropic official
- https://www.anthropic.com/engineering/multi-agent-research-system — orchestrator-worker + citation
- https://linas.substack.com/p/claudecodesource — UNVERIFIED beyond two excerpts

### Part II
- https://code.claude.com/docs/en/agent-sdk/hooks — `PreToolUse`/`SubagentStop` hooks, `permissionDecision: "deny"`, `updatedInput`
- https://code.claude.com/docs/en/agent-sdk/sessions — `fork` primitive copies full history
- https://platform.claude.com/docs/en/build-with-claude/structured-outputs — constrained decoding, `structured-outputs-2025-11-13` beta header
- https://github.com/anthropics/claude-code/issues/18727 — Anthropic warns against `Task` in subagent toolsets
- https://github.com/anthropics/claude-code/issues/9521 — pain point: no inspection of subagent output by default
- https://selfservicebi.co.uk/series/context-window-optimization/subagents-how-delegating-work-solves-the-context-window-problem/ — View A counter-argument (context isolation reduces hallucination)
