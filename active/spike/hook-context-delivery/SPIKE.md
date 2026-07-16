# SPIKE — Hook context delivery: size limits and sanctioned mechanisms for large rule sets

## Investigation question

4Shark's Claude Code configuration delivers mandatory rules to main sessions and subagents by inlining full document text into hook output (`additionalContext` on PreToolUse/SubagentStart, stdout on SessionStart). Measured on this machine on 2026-07-15: ~1–3.3KB blocks pass intact; a ~20.5KB PreToolUse block is persisted to a `tool-results/` file and replaced with a ~2KB preview; a ~119KB SessionStart stdout block is likewise replaced with `Output too large (118.1KB). Full output saved to: … Preview (first 2KB)`; a ~456KB SubagentStart block reaches the subagent as nothing at all.

Five questions:

1. Is the `additionalContext` / hook-output size limit documented by Anthropic? What is the number? Is the truncate-and-persist behavior documented?
2. What are the sanctioned mechanisms to get a large body of mandatory rules into a session's context, and what does each actually guarantee?
3. How does one give a large rule set to **subagents** specifically? Does a subagent inherit CLAUDE.md? Is the Agent tool's prompt string the only channel?
4. Is there any mechanism to enforce or verify that a model actually read a file?
5. Does the community/Anthropic consider "inline everything up front" an anti-pattern?

## Sources consulted

- https://code.claude.com/docs/en/hooks — the documented 10,000-character cap, `additionalContext` placement per event, `transcript_path` semantics, `InstructionsLoaded`, blocking-event table, timeout defaults. See auxiliary: `hook-context-delivery_doc_1.md`
- https://code.claude.com/docs/en/sub-agents — what reaches a subagent at startup; CLAUDE.md inheritance; `skills` preload field; `--append-subagent-system-prompt`. See auxiliary: `hook-context-delivery_doc_2.md`
- https://code.claude.com/docs/en/memory — `@path` import syntax and four-hop depth; the "imports don't reduce context" statement; "CLAUDE.md files are loaded in full regardless of length"; `.claude/rules/` path scoping. See auxiliary: `hook-context-delivery_doc_3.md`
- https://code.claude.com/docs/en/skills — progressive-disclosure design; "Keep `SKILL.md` under 500 lines"; recurring-token-cost statement. See auxiliary: `hook-context-delivery_doc_4.md` § 4a
- https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills — Anthropic engineering **blog post**; stated design intent for progressive disclosure. See auxiliary: `hook-context-delivery_doc_4.md` § 4b
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents — Anthropic engineering **blog post**; context rot, attention budget, just-in-time loading. See auxiliary: `hook-context-delivery_doc_4.md` § 4c
- https://github.com/anthropics/claude-code/issues/24176 — closed as not planned; `additionalContext` injects as `<system-reminder>` in the message stream. See auxiliary: `hook-context-delivery_doc_4.md` § 4d
- https://github.com/anthropics/claude-code/issues/23885 — closed as duplicate; `additionalContext` appends to user context, may be dropped during pruning. See auxiliary: `hook-context-delivery_doc_4.md` § 4d
- https://gist.github.com/EmanuelFaria/64914bf2f4fbb9e7b9262aff2383a122 — community **gist**; claims a ~28KB threshold. Contradicted by official docs and by 4Shark's own measurement; recorded but not relied on. See auxiliary: `hook-context-delivery_doc_4.md` § 4e

Note on the auxiliaries: the sub-agents and skills doc fetches each exceeded the tool-result cap and were persisted verbatim by the harness — the same truncate-and-persist mechanism this spike investigates. The auxiliary files quote those persisted artifacts by line number.

---

## Findings

### Finding 1: The cap IS documented, and it is 10,000 characters — not a byte threshold

**Evidence:** under the heading "JSON output" on the hooks reference:

> "Hook output strings, including `additionalContext`, `systemMessage`, and plain stdout, are capped at 10,000 characters. Output that exceeds this limit is saved to a file and replaced with a preview and file path, the same way large tool results are handled."

**Source:** https://code.claude.com/docs/en/hooks

**Significance:** this answers question 1 completely. The limit is documented, the truncate-and-persist behavior is documented, and the number is 10,000 **characters** applying uniformly to `additionalContext`, `systemMessage`, and plain stdout. It falls inside the 3.3KB–20.5KB window 4Shark measured empirically, and is consistent with every measured data point except the 456KB SubagentStart case (Finding 2). The documented cap is character-based, which is why the gist's byte-based ~28KB claim (auxiliary § 4e) both contradicts the docs and mispredicts 4Shark's own 20.5KB observation.

*Verification block:*
- URL fetched: https://code.claude.com/docs/en/hooks — yes, three times (initial extraction, targeted self-check, timeout query)
- Verbatim quote checked: "capped at 10,000 characters" and the following sentence
- Quote substring confirmed at: section heading "JSON output"; identical wording returned on two independent fetches

---

### Finding 2: The 456KB SubagentStart → nothing case is NOT explained by any documented behavior

**Evidence:** the documented behavior for oversized output is uniform — "saved to a file and replaced with a preview and file path" (Finding 1). No documented path produces silent total absence. Two candidate explanations were tested against the docs and both failed:

- *Timeout*: the docs state "Defaults: 600 for `command`, `http`, and `mcp_tool`; 30 for `prompt`; 60 for `agent`." A `command` hook has 600 seconds; `SubagentStart` is not listed among the events that lower that default. A targeted fetch asking what happens to `additionalContext` on timeout returned that the documentation contains no explicit statement on this, and nothing SubagentStart-specific.
- *SubagentStart being non-blocking*: the docs list SubagentStart as "Can't block or make decisions (information only)" but explicitly confirm it "Supports `additionalContext` in `hookSpecificOutput`" and that the content appears "at the start of conversation, before first prompt".

**Source:** https://code.claude.com/docs/en/hooks (auxiliary `hook-context-delivery_doc_1.md` §§ 1, 2, 6, 9)

**Significance:** the 456KB case is undocumented behavior — either a bug or an unstated hard ceiling above which the persist-and-preview path itself fails. No fetched source describes it. Searches of the issue tracker surfaced no issue matching this signature (Finding 3). It stays an open question; the evidence shows the documented cap explains the 20.5KB and 119KB cases but not this one.

*Verification block:*
- URL fetched: https://code.claude.com/docs/en/hooks — yes
- Verbatim quote checked: the timeout defaults sentence and the SubagentStart capability bullets
- Quote substring confirmed at: `timeout` field row; "SubagentStart" event section

---

### Finding 3: The two SubagentStart context-injection issues in the tracker are both closed, and neither concerns size

**Evidence:** issue #24176 ("Native support for dynamic, composable context injection into subagents and teammates") is **closed as not planned**. It states:

> "The `SubagentStart` hook's `additionalContext` field injects content as a `<system-reminder>` tag in the message stream, not in the system prompt."

It also describes a workaround architecturally identical to 4Shark's: "A `SubagentStart` hook runs a bash script that reads `agent_type`, looks it up in a `roles.yaml` file, composes context from module files, and injects via `hookSpecificOutput.additionalContext`" — characterized as "Works as a workaround but requires external shell scripts, manual YAML parsing, and a hand-rolled module composition system". The fetch reported the issue does not specify any size limits for `additionalContext`.

**Source:** https://github.com/anthropics/claude-code/issues/24176

**Significance:** the SubagentStart-injection shape 4Shark built is a recognized community workaround, and the request to make it first-class was declined. The placement fact matters independently of size: content arrives as a `<system-reminder>` in the message stream, not in the system prompt — so it is subject to the same non-guarantee as any in-context instruction. Not found: any issue documenting the 456KB→nothing signature.

*Verification block:*
- URL fetched: https://github.com/anthropics/claude-code/issues/24176 — yes
- Verbatim quote checked: the `<system-reminder>` sentence and the workaround description
- Quote substring confirmed at: issue body; status label "Closed as not planned" at top of page

---

### Finding 4: A second closed issue independently reports that `additionalContext` can be dropped during context pruning

**Evidence:** issue #23885 ("SubagentStart hook should support updatedPrompt for direct prompt injection") is **closed as duplicate**. Its problem statement, verbatim:

> "*   additionalContext appends to user context, not system prompt
> *   During context pruning, critical rules may be dropped
> *   Subagents still need to discover and interpret rules from CLAUDE.md"

**Source:** https://github.com/anthropics/claude-code/issues/23885

**Significance:** a durability fact separate from the size cap. Even a sub-10,000-character block that arrives intact is not guaranteed to persist — it sits in user context and can be dropped when context is pruned. This bears on any mechanism that depends on hook injection to carry mandatory rules across a long session. Note this is a reporter's claim in a closed issue, not an Anthropic statement; it corroborates the placement fact in Finding 3, which is why the two are recorded as separate Findings rather than merged.

*Verification block:*
- URL fetched: https://github.com/anthropics/claude-code/issues/23885 — yes
- Verbatim quote checked: the three problem-statement bullets
- Quote substring confirmed at: issue body problem statement; status "Closed as duplicate"

---

### Finding 5: Custom subagents DO load the full CLAUDE.md hierarchy — the Agent tool prompt string is NOT the only channel

**Evidence:** the sub-agents reference, section "What loads at startup", enumerates a non-fork subagent's initial context. Verbatim:

> "**CLAUDE.md and memory**: every level of the memory hierarchy the main conversation loads, including `~/.claude/CLAUDE.md`, project rules, `CLAUDE.local.md`, and managed policy files. The built-in Explore and Plan agents skip this."

And:

> "Explore and Plan are the only subagents that omit CLAUDE.md and git status. There is no frontmatter field or per-agent setting to change which agents skip them."

Earlier in the same document:

> "Explore and Plan skip your CLAUDE.md files and the parent session's git status to keep research fast and inexpensive. Every other built-in and custom subagent loads both."

The same section also lists, as distinct channels: the agent's own system prompt ("not the full Claude Code system prompt"), the task message, git status, **preloaded skills**, and the sibling roster.

**Source:** https://code.claude.com/docs/en/sub-agents (auxiliary `hook-context-delivery_doc_2.md`, persisted artifact lines 33, 831–842)

**Significance:** this directly contradicts the premise recorded in 4Shark's own `CLAUDE.md` § Documentation Loading Model — *"Subagents do not lazy-load pointers (Anthropic confirms the only channel from parent to subagent is the Agent tool's prompt string), so Tier 2 expansion is necessary for the rules to reach the subagent at all."* Per current documentation, every custom 4Shark subagent (`spike`, `plan-researcher`, `pr-review`, the DDD agents — none of which are the built-in `Explore` or `Plan`) already receives `~/.claude/CLAUDE.md` and `~/.claude/rules/*` in full at startup, through the normal memory hierarchy, with no hook involved. The stated rationale for the SubagentStart Tier 2 expansion does not hold against this source. Whether it held when the mechanism was written is not established here — see open questions on version history.

*Verification block:*
- URL fetched: https://code.claude.com/docs/en/sub-agents — yes; response exceeded the tool-result cap and was persisted verbatim by the harness
- Verbatim quote checked: the "CLAUDE.md and memory" bullet; the "Explore and Plan are the only subagents that omit" sentence; the line-33 sentence
- Quote substring confirmed at: persisted artifact `toolu_01SbfiQoE8w1vwRD8tPsueBi.txt` lines 837, 842, 33 (grep-confirmed against the file)

---

### Finding 6: CLAUDE.md has no documented size cap and its `@path` imports load in full at launch, four hops deep

**Evidence:** on imports:

> "CLAUDE.md files can import additional files using `@path/to/import` syntax. Imported files are expanded and loaded into context at launch alongside the CLAUDE.md that references them."

> "Both relative and absolute paths are allowed. Relative paths resolve relative to the file containing the import, not the working directory. Imported files can recursively import other files, with a maximum depth of four hops."

On the absence of a cap:

> "This limit applies only to `MEMORY.md`. CLAUDE.md files are loaded in full regardless of length, though shorter files produce better adherence."

On what imports do and do not buy:

> "Splitting into `@path` imports helps organization but doesn't reduce context, since imported files load at launch."

And the stated size guidance:

> "**Size**: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence."

**Source:** https://code.claude.com/docs/en/memory (auxiliary `hook-context-delivery_doc_3.md`)

**Significance:** answers question 2(a) fully. `@path` imports exist, the syntax is `@path/to/import`, the depth limit is four hops, and there is **no size limit** — CLAUDE.md and its imports load in full regardless of length. This makes CLAUDE.md the one documented channel with no truncation ceiling, which is precisely what the 10,000-character hook cap denies. The trade-off is stated in the same document: imports are an organization device, not a context-reduction device, and the docs' own guidance (under 200 lines) runs against loading a large corpus this way. Adherence is explicitly said to degrade with length.

*Verification block:*
- URL fetched: https://code.claude.com/docs/en/memory — yes
- Verbatim quote checked: the import syntax/depth sentences; "loaded in full regardless of length"; "doesn't reduce context"; the 200-line guidance
- Quote substring confirmed at: headings "Import additional files", "How it works" (auto memory), "My CLAUDE.md is too large", "Write effective instructions"

---

### Finding 7: The `skills` frontmatter field injects full skill content into a subagent at startup

**Evidence:** from the sub-agents reference:

> "Use the `skills` field to inject skill content into a subagent's context at startup. This gives the subagent domain knowledge without requiring it to discover and load skills during execution."

> "The full content of each listed skill is injected into the subagent's context at startup. This field controls which skills are preloaded, not which skills the subagent can access: without it, the subagent can still discover and invoke project, user, and plugin skills through the Skill tool during execution."

Constraint:

> "You can't preload skills that set `disable-model-invocation: true`, since preloading draws from the same set of skills Claude can invoke. If a listed skill is missing or disabled, Claude Code skips it and logs a warning to the debug log."

**Source:** https://code.claude.com/docs/en/sub-agents (auxiliary `hook-context-delivery_doc_2.md`, persisted artifact lines 451–469)

**Significance:** a documented, first-class channel for putting a body of content into a specific subagent's startup context without a hook and without the 10,000-character cap. It is declarative (per-agent frontmatter), which is both its strength (no shell script, no composition logic) and its limit (static per agent — it cannot vary by task). The failure mode for a missing skill is a debug-log warning, i.e. silent from the model's perspective.

*Verification block:*
- URL fetched: https://code.claude.com/docs/en/sub-agents — yes (persisted artifact)
- Verbatim quote checked: the three quoted passages
- Quote substring confirmed at: persisted artifact lines 453, 467, 469 (grep-confirmed)

---

### Finding 8: Anthropic's Skills design explicitly argues for on-demand loading over up-front loading

**Evidence:** from the Skills reference documentation:

> "Unlike CLAUDE.md content, a skill's body loads only when it's used, so long reference material costs almost nothing until you need it."

> "Keep the body itself concise. Once a skill loads, its content stays in context across turns, so every line is a recurring token cost."

Stated size guidance:

> "Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files."

The memory reference states the same division of labour from the other side:

> "Rules load into context every session or when matching files are opened. For task-specific instructions that don't need to be in context all the time, use skills instead, which only load when you invoke them or when Claude determines they're relevant to your prompt."

**Source:** https://code.claude.com/docs/en/skills and https://code.claude.com/docs/en/memory

**Significance:** answers question 2(b) and part of question 5 from **reference documentation** rather than blog material. Anthropic's stated design intent is progressive disclosure: the skill body loads on use, detailed reference material goes into separate files that load only when needed, and the numeric guidance is 500 lines for `SKILL.md`. The "recurring token cost" framing is the documented argument against up-front loading — content in context is paid for on every turn, not once.

*Verification block:*
- URL fetched: https://code.claude.com/docs/en/skills — yes (persisted artifact); https://code.claude.com/docs/en/memory — yes
- Verbatim quote checked: all four quoted passages
- Quote substring confirmed at: persisted artifact `toolu_01TYw4oGJMR3wecC8dWmZY5F.txt` lines 11, 212, 322 (grep-confirmed); memory doc Note box under "Organize rules with `.claude/rules/`"

---

### Finding 9: Anthropic's engineering blog states that recall degrades as context grows

**Evidence:** from "Effective context engineering for AI agents" (an Anthropic engineering **blog post**, not reference documentation):

> "as the number of tokens in the context window increases, the model's ability to accurately recall information from that context decreases."

> "LLMs have an 'attention budget' that they draw on when parsing large volumes of context. Every new token introduced depletes this budget by some amount."

> "As its context length increases, a model's ability to capture these pairwise relationships gets stretched thin, creating a natural tension between context size and attention focus."

And on the alternative:

> "Rather than pre-processing all relevant data up front, agents built with the 'just in time' approach maintain lightweight identifiers (file paths, stored queries, web links, etc.) and use these references to dynamically load data into context at runtime using tools."

**Source:** https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

**Significance:** completes question 5. The evidence bears directly on the counterfactual "would inlining 119KB of rules work if it *did* fit?" — per this source, recall degrades as tokens accumulate, so fitting is not the same as being effective. Anthropic's own recommended alternative is the pointer-plus-tool-load shape (lightweight identifiers, dynamic load at runtime), which is structurally what 4Shark's Tier 2 pointer tier already is and what the Tier 2+ expansion mechanism replaced. This is blog material, weaker than reference docs, and it makes a directional claim without a quantified threshold.

*Verification block:*
- URL fetched: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents — yes
- Verbatim quote checked: all four quoted passages
- Quote substring confirmed at: sections on context rot, the attention budget, and just-in-time context loading

---

### Finding 10: The Agent Skills blog claims bundled context is "effectively unbounded" via filesystem access

**Evidence:** from "Equipping agents for the real world with Agent Skills" (Anthropic engineering **blog post**):

> "Agents with a filesystem and code execution tools don't need to read the entirety of a skill into their context window when working on a particular task."

> "This means that the amount of context that can be bundled into a skill is effectively unbounded."

> "Like a well-organized manual that starts with a table of contents, then specific chapters, and finally a detailed appendix, skills let Claude load information only as needed"

**Source:** https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills

**Significance:** the stated ceiling for progressive disclosure is the filesystem, not the context window — but the guarantee is explicitly conditional on the agent *choosing* to read. "Effectively unbounded" describes what can be *made available*, not what is *guaranteed delivered*. This is the exact trade the 4Shark Full-Read Discipline was written to cover, and the reason the `integration-debug` hook was built to inject docs in full rather than rely on the read. The fetch reported the document gives no numerical guidance on context sizes or token limits.

*Verification block:*
- URL fetched: https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills — yes
- Verbatim quote checked: the three quoted passages
- Quote substring confirmed at: the progressive-disclosure section of the post

---

### Finding 11: `transcript_path` is available on every hook event and PreToolUse can block — but the docs warn the transcript lags

**Evidence:** `transcript_path` is a common input field on all hook events. Verbatim:

> "Path to conversation JSON. The transcript file is written asynchronously and may lag the in-memory conversation, so it may not yet include the current turn's most recent messages when a hook fires. Hooks that need the final assistant text of the current turn should use `last_assistant_message` on Stop and SubagentStop instead of reading the transcript"

The documented PreToolUse input example includes `"transcript_path": "/home/user/.claude/projects/.../transcript.jsonl"`. PreToolUse is listed among the events that can block (exit code 2 / `permissionDecision: "deny"`).

Separately, `InstructionsLoaded` fires "when a CLAUDE.md or `.claude/rules/*.md` file is loaded into context", at session start and on lazy load, with matchers `session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact`. It **cannot** block:

> `InstructionsLoaded` | No | Exit code is ignored

**Source:** https://code.claude.com/docs/en/hooks (auxiliary `hook-context-delivery_doc_1.md` §§ 4, 7, 8)

**Significance:** answers question 4's mechanical half. The ingredients for read-gating exist: PreToolUse receives `transcript_path` and can deny a tool call, so a hook could in principle parse the transcript for a required `Read` and block until it happens. Two documented caveats bound it: the transcript is written asynchronously and may lag, so a very recent Read may not be visible when the hook fires; and `InstructionsLoaded` — the event purpose-built to observe instruction loading — is explicitly non-blocking, so it can log which files loaded but cannot gate on it. **Not found:** any community implementation of transcript-inspecting read-gating. A targeted search returned only generic material on reading `transcript_path` and on exit-code-2 blocking, with no instance of the two combined for read enforcement. The absence of a found implementation is not proof none exists.

*Verification block:*
- URL fetched: https://code.claude.com/docs/en/hooks — yes
- Verbatim quote checked: the `transcript_path` description; the `InstructionsLoaded` exit-code row; the PreToolUse input example
- Quote substring confirmed at: "Common input fields" table; "Exit code 2 behavior per event" table; PreToolUse input example block

---

## Trade-offs surfaced

| Mechanism | What it actually guarantees | Cost / limit | Sustained by |
|---|---|---|---|
| Hook `additionalContext` / stdout (current 4Shark mechanism) | Content ≤10,000 chars arrives as a `<system-reminder>` in the message stream at the documented per-event position. Above the cap: persisted to file + ~2KB preview + path. Not in the system prompt; may be dropped during context pruning | Hard 10,000-character cap. Failure above it is silent from the model's perspective — it sees a preview, not a notice that rules are missing. One case (456KB) produces total absence, undocumented | F1, F2, F3, F4 |
| CLAUDE.md + `@path` imports | Loads in full at launch, **no size cap**, four-hop recursion depth. Reaches main AND every custom subagent (all but built-in Explore/Plan) | Every token is paid on every session and every subagent spawn. Imports organize but do not reduce context. Docs' own guidance is under 200 lines; adherence stated to degrade with length. Delivered as a user message, not system prompt — no strict-compliance guarantee | F5, F6 |
| `.claude/rules/` with `paths:` frontmatter | Loads only when Claude reads a matching file. Rules without `paths` load at launch at `.claude/CLAUDE.md` priority | Trigger is a file Read matching a glob — it does not fire on Bash invocations (the gap that motivated 4Shark's Tier 2+ hooks in the first place) | F6 |
| Subagent `skills:` frontmatter preload | "The full content of each listed skill is injected into the subagent's context at startup" — no hook, no cap | Static per agent; cannot vary by task. Cannot preload a skill with `disable-model-invocation: true`. A missing/disabled skill is skipped with only a debug-log warning | F7 |
| Skill body (on-demand) | Loads only when invoked; reference files load only when read. "Effectively unbounded" bundled material | Guarantee is conditional on the model choosing to read the reference file. Once loaded, content is a recurring per-turn token cost. Stated guidance: `SKILL.md` under 500 lines. After compaction only the first 5,000 tokens per skill are re-attached, within a 25,000-token combined budget | F8, F10 |
| Subagent system prompt (markdown body) / `--append-subagent-system-prompt` | The body **is** the subagent's system prompt. The flag appends to every subagent's system prompt including nested ones | The flag is non-interactive mode only and requires v2.1.205+. The body is per-agent and static | F5 (doc_2 lines 259, 261) |
| `--append-system-prompt` (main session) | Puts instructions at the system-prompt level | "must be passed every invocation, so it's better suited to scripts and automation than interactive use" | F6 (doc_3) |
| PreToolUse read-gating via `transcript_path` | Mechanically possible: the field is present on every event and PreToolUse can deny | Transcript "is written asynchronously and may lag". `InstructionsLoaded` cannot block. No implementation found in the wild | F11 |

Cross-cutting, sustained by F8, F9, F10: every "load it all up front" option is argued against by Anthropic's own stated position — reference docs frame in-context content as a recurring per-turn cost with a 500-line skill guideline, and the engineering blog states recall degrades as tokens accumulate. Fitting under a cap and being adhered to are different properties.

## What remains uncertain

- **The 456KB SubagentStart → nothing behavior is unexplained.** No fetched source documents it. Timeout is ruled out by the 600-second `command` default; the documented oversize path is persist-and-preview, not silence. Whether a second, higher ceiling exists above which persist-and-preview itself fails is not established. Not found: any issue in the tracker matching this signature.
- **Whether the exact boundary is 10,000 characters or 10,000 bytes for multi-byte content** is not stated. The docs say "characters"; 4Shark's measurements are in KB. For ASCII-dominant rule text the two coincide closely enough that the measurements cannot discriminate.
- **Version history of subagent CLAUDE.md inheritance is not established.** Finding 5 documents current behavior. Whether the 4Shark premise ("the only channel is the Agent tool's prompt string") was accurate when written and later changed, or was never accurate, cannot be determined from the fetched sources. The sub-agents doc carries `min-version` annotations on several nearby behaviors (v2.1.196, v2.1.198, v2.1.205, v2.1.206) but none on the "CLAUDE.md and memory" bullet.
- **Whether `<system-reminder>`-delivered hook content is pruned in practice, and under what conditions**, rests on a reporter's claim in a closed issue (F4), not on an Anthropic statement. Not independently confirmed.
- **Whether anyone has built transcript-based read-gating** — one targeted search found nothing. Absence of evidence only.
- **The six issues listed in auxiliary § 4d as located-but-not-fetched are UNVERIFIED** and sustain nothing here. Several concern `additionalContext` not being injected (#19432, #16538) or VSCode-extension-specific failures (#20062, #49063) and may be relevant to a follow-up, but their contents were not read.

## Suggested options for main and the engineer

Each option names the Findings that sustain it. No recommendation is made here.

- **Option A — Move the Tier 1/Tier 2 corpus into CLAUDE.md `@path` imports.** The one documented channel with no size cap, reaching main and every custom subagent alike. Costs full tokens every session and every subagent spawn, and runs against the docs' own 200-line guidance and the degradation claim. Sustained by F5, F6, F9.
- **Option B — Keep hook injection but keep every block under 10,000 characters.** Preserves the existing architecture and the Bash-invocation trigger that `paths:` frontmatter cannot serve. Requires each injected body to fit the cap — i.e. pointers or condensed rules, not full documents. Does not address pruning (F4) or the 456KB anomaly (F2). Sustained by F1, F3, F4.
- **Option C — Drop the SubagentStart Tier 2 expansion as redundant.** Per F5, custom subagents already receive `~/.claude/CLAUDE.md` and `~/.claude/rules/*` in full at startup with no hook involved. This would test the documented behavior rather than assume it. Sustained by F5.
- **Option D — Use `skills:` frontmatter preload per subagent.** Declarative, no hook, no cap, full content at startup. Static per agent and silent on a missing skill. Would fit the `integration-debug`-style "these four docs, in full, always" case. Sustained by F7.
- **Option E — Convert mandatory docs to Skills with reference files (progressive disclosure).** Anthropic's stated design intent; bundled material effectively unbounded. Trades the delivery guarantee for the model's decision to read — the exact gap 4Shark's Full-Read Discipline addresses behaviorally. Sustained by F8, F10.
- **Option F — Build PreToolUse read-gating on `transcript_path`.** Mechanically supported and would convert the Full-Read Discipline from advisory to enforced. Unproven: no implementation found, and the transcript may lag. Sustained by F11.
- **Option G — File an issue for the 456KB anomaly.** No existing issue matches the signature; the behavior contradicts the documented persist-and-preview path. Sustained by F1, F2, F3.

These options are not mutually exclusive; the channels differ in trigger (launch / file-read / Bash invocation / subagent spawn) and several address different gaps.
