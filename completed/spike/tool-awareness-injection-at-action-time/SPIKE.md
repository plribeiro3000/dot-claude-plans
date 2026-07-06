# SPIKE — Making an Agent Reach for the Sanctioned Wrapper at the Moment of Action

## Investigation question

When a Claude Code session has a sanctioned wrapper/skill for an operation (e.g. `ecs-scale.sh` / `/apps` for ECS service scaling) but, at the moment it actually needs to act, forgets the wrapper exists and reaches for the raw primitive (`aws ecs update-service`) — does the community/industry name this failure mode, and where does opinion converge or split on the fix? Specifically: is "always inject a reminder of the sanctioned tool into context at the moment of action" a real, endorsed pattern, or does the evidence point elsewhere (blocking/redirecting the primitive, rewriting the command deterministically, or shrinking/curating the tool surface)? The engineer's hypothesis under test: today's harness "locks at the wrong point" — it blocks known-bad primitives but does not inject awareness of the sanctioned alternative before the agent acts.

## Sources consulted

- `~/.claude/settings.json` — full hook wiring (PreToolUse/PostToolUse/UserPromptSubmit/SessionStart/SubagentStart matchers).
- `~/.claude/scripts/validate-bash-command.sh:538-566` — confirms which raw AWS commands are blocked/asked vs which fall through ungoverned.
- `~/.claude/scripts/ecs-scale.sh` — the sanctioned wrapper being bypassed.
- `~/.claude/scripts/auto-approve-aws-readonly.sh` — confirms `aws ecs update-service` does not qualify for read-only auto-approval.
- `~/.claude/skills/apps/SKILL.md:100-127` — the skill's own textual rule ("never call `aws ecs update-service` directly"), which only reaches context when the skill is invoked.
- `~/.claude/scripts/inject-terraform-context.sh`, `inject-working-dir-reminder.sh`, `inject-skill-tip.sh` — existing INJECT-style hooks, for comparison of trigger design (command-shape trigger vs prompt-keyword trigger).
- `~/.claude/scripts/auto-approve-local-skills.sh` — how the sanctioned skill path avoids the permission prompt once invoked.
- [Anthropic — Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — "bloated tool sets" failure mode; "context rot" definition.
- [Anthropic — Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) — progressive disclosure; description-driven trigger.
- [Anthropic — Code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp) — cost of loading all tool definitions upfront; on-demand loading via filesystem.
- [Anthropic — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) — "degrees of freedom" guidance; description-writing guidance.
- [Claude Code — Hooks reference](https://code.claude.com/docs/en/hooks) — `permissionDecision`, `additionalContext`, the prompt-injection-defense caveat on imperative-styled injected text.
- [Claude Agent SDK — Hooks guide](https://code.claude.com/docs/en/agent-sdk/hooks) — `updatedInput` rewrite mechanism, canonical `redirect_to_sandbox` example.
- [cdelgado70 — "Skills and the discovery ceiling"](https://cdelgado70.github.io/2026/05/06/skills-and-the-discovery-ceiling.html) — practitioner account of hook-injected context failing to change agent behavior; the fix that worked instead.
- [arXiv 2605.24660 — "How Many Tools Should an LLM Agent See? A Chance-Corrected Answer"](https://arxiv.org/html/2605.24660) — tool-count vs selection-accuracy degradation; retrieval/filtering as the fix.
- [arXiv 2605.01771 — "The Compliance Gap: Why AI Systems Promise to Follow Process Instructions but Don't"](https://arxiv.org/abs/2605.01771) — compliance rates under different reward framings; tool removal as the effective fix.
- [Civic — "You need deterministic guardrails for AI agent security"](https://www.civic.com/news/deterministic-guardrails-for-ai-agent-security) — deterministic vs prompt-based guardrail argument.
- General web search corroboration (MCP tool-overload articles, dev.to summaries) — used only for triangulation, not cited as standalone Findings per Citation Discipline (composite/aggregated search-result text is not a fetchable, re-verifiable single source).

## Findings

### Finding 1 — The 4Shark repo already runs two different philosophies, and the ECS-scale gap sits in neither

**Evidence — BLOCK philosophy** (`~/.claude/scripts/validate-bash-command.sh:538-554`):
```bash
if printf '%s' "$normalized_command" | grep -qE '^aws[[:space:]]+ec2[[:space:]]+(start|stop)-instances([[:space:]]|$)'; then
  cat >&2 <<'EOF'
Raw `aws ec2 start-instances` / `aws ec2 stop-instances` — blocked.
...
Fix:
  - To stop:  bash ~/.claude/scripts/stop-instance.sh  [--region <r>] [--profile <p>] <id> [<id>...]
  - To start: bash ~/.claude/scripts/start-instance.sh [--region <r>] [--profile <p>] <id> [<id>...]
EOF
  exit 2
fi
```
This is a hard PreToolUse block (`exit 2`) with a corrective stderr message — the agent's own retry has to notice the message and self-correct. Immediately below it (`:564-566`), the sibling ECS operation gets a much lighter touch:
```bash
if printf '%s' "$normalized_command" | grep -qE '^aws[[:space:]]+ecs[[:space:]]+run-task([[:space:]]|$)'; then
  emit_ask "aws ecs run-task — approval required regardless of env-var or path prefix."
fi
```
`emit_ask` only forces a human approval prompt — it does not redirect to a wrapper. And there is **no** rule at all, anywhere in the file, matching `aws ecs update-service` (the scale operation). Grepping the file's `case`/`grep` conditions confirms `update-service` never appears.

**Evidence — INJECT philosophy** (`~/.claude/scripts/inject-terraform-context.sh:1-20`, `inject-working-dir-reminder.sh:1-30`): both fire on `PreToolUse` with `additionalContext`, one on any `terraform` invocation (rule/convention docs), one on a Ruby/bundler escape-hatch shape (a "there's a simpler way" reminder), each self-filtering on the command text before injecting.

**Evidence — the sanctioned path exists but is never surfaced pre-emptively.** `~/.claude/skills/apps/SKILL.md:102-103`:
```
2. Update the desired count using the `ecs-scale.sh` script — never call `aws ecs update-service` directly:
```
This sentence only reaches the model's context when `/apps` is explicitly invoked. `~/.claude/scripts/auto-approve-aws-readonly.sh` confirms `update-service` is not a `get-*/describe-*/list-*/batch-get-*/wait` operation, so it is not auto-approved either — it falls straight into the ordinary manual permission prompt, every time, exactly the friction the engineer hit.

**Significance:** the repo has a working BLOCK mechanism and a working INJECT mechanism, but the ECS-scale case is covered by **neither**. It is not blocked (no rule matches `update-service`), not asked-with-redirect (unlike `run-task`), and not injected proactively (no PreToolUse hook fires on `aws ecs update-service` the way `inject-terraform-context.sh` fires on `terraform`). This is a hole in the matrix, not a deliberate design choice one way or the other — it confirms the engineer's premise that the gap is real, though the spike's findings below complicate the specific proposed fix ("always inject a reminder").

### Finding 2 — the community names the underlying failure mode "bloated tool sets" / "ambiguous decision points" and treats it as a tool-set design problem, not a per-instance nudging problem

**Evidence:** Anthropic's context-engineering guidance states plainly:

> "One of the most common failure modes we see is bloated tool sets that cover too much functionality or lead to ambiguous decision points about which tool to use. If a human engineer can't definitively say which tool should be used in a given situation, an AI agent can't be expected to do better."

**Source:** https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

**Significance:** this frames the failure not as "the agent forgot" but as "the tool surface made the choice genuinely ambiguous" — the fix implied is upstream (tool/skill design and disambiguation), not a per-call reminder patched on afterward. In the ECS case, both `aws ecs update-service` (raw, always available as a built-in Bash capability) and `bash ~/.claude/scripts/ecs-scale.sh` (the wrapper) are simultaneously "reachable" at all times with no structural signal steering the model toward one over the other — a textbook ambiguous decision point by this definition.

**Verification block:**
URL fetched: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
Verbatim quote checked: "One of the most common failure modes we see is bloated tool sets that cover too much functionality or lead to ambiguous decision points about which tool to use."
Quote substring confirmed at: re-fetch on 2026-07-04, same paragraph, following "Writing tools for AI agents – with AI agents" reference.

### Finding 3 — "context rot": more injected context has a real accuracy cost, which cuts against "inject reminders liberally, just in case"

**Evidence:**

> "Studies on needle-in-a-haystack style benchmarking have uncovered the concept of context rot: as the number of tokens in the context window increases, the model's ability to accurately recall information from that context decreases."

**Source:** https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents

**Significance:** this directly engages the engineer's "always inject" framing. Injection is not free — every injected reminder competes for attention with everything else in the window, and doing it unconditionally (on every Bash call, for every wrapper that exists) reproduces the exact "bloated tool set" pathology at the context layer instead of the tool layer. The existing 4Shark injection hooks already respect this: `inject-working-dir-reminder.sh` is rate-limited to once per session (`marker_dir="/tmp/claude_working_dir_reminder_${session_id:-shared}"`) precisely because "repeating the rule on every command produces context noise" (its own header comment). Any new ECS-scale injection hook would need the same discipline — narrowly triggered, rate-limited — not a blanket reminder.

**Verification block:**
URL fetched: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
Verbatim quote checked: "context rot: as the number of tokens in the context window increases, the model's ability to accurately recall information from that context decreases."
Quote substring confirmed at: re-fetch on 2026-07-04, in the paragraph following the needle-in-a-haystack sentence.

### Finding 4 — a direct, first-hand community account: hook-injected `additionalContext`, even phrased as "IMPORTANT, USE THESE EXACT COMMANDS", did not change agent behavior

**Evidence:** a practitioner building a Claude Code skill-discovery daemon tried injecting the relevant tool documentation via a `UserPromptSubmit` hook's `additionalContext`. Result:

> "The injected text was sitting in its context, plain to see, and it might as well not have been there. I tried the obvious things. I added `IMPORTANT: USE THESE EXACT COMMANDS, DO NOT IMPROVISE` at the top of the hook output. No effect. I tried more emphatic phrasing, formatted the commands differently, prepended the content instead of appending it. None of it changed the agent's behavior in a measurable way. The hook was working. The model was reading the content."

The author's diagnosis, after switching to a different mechanism (prepending content directly into the *user message* rather than the hook's context slot) that did work:

> "Hook-injected text doesn't carry the weight the same text would have if the user had typed it."

**Source:** https://cdelgado70.github.io/2026/05/06/skills-and-the-discovery-ceiling.html

**Significance:** this is the single most direct piece of evidence against the "always inject a reminder via a hook" hypothesis as originally framed. It is not peer-reviewed research — it is one practitioner's blog account — but it is a first-hand, mechanism-specific report (hook `additionalContext`, not prompting in general) that lines up with Anthropic's own hooks documentation (Finding 5) on *why* this happens: Claude Code deliberately down-weights hook-injected text relative to user-typed text.

**Verification block:**
URL fetched: https://cdelgado70.github.io/2026/05/06/skills-and-the-discovery-ceiling.html
Verbatim quote checked: "The injected text was sitting in its context, plain to see, and it might as well not have been there." and "Hook-injected text doesn't carry the weight the same text would have if the user had typed it."
Quote substring confirmed at: re-fetch on 2026-07-04, confirmed present verbatim in context describing the `UserPromptSubmit` hook attempt and the subsequent "PreBrief" fix.

### Finding 5 — Anthropic's own hooks documentation independently confirms injected text is treated with suspicion when it reads like an instruction, not a fact

**Evidence:**

> "Write the text as factual statements rather than imperative system instructions. Phrasing such as 'The deployment target is production' or 'This repo uses `bun test`' reads as project information. Text framed as out-of-band system commands can trigger Claude's prompt-injection defenses, which causes Claude to surface the text to you instead of treating it as context."

**Source:** https://code.claude.com/docs/en/hooks

**Significance:** this converges with Finding 4 from an entirely different source (Anthropic's own reference docs, not a practitioner blog): the model is *designed* to treat forceful, command-shaped injected text with skepticism (prompt-injection defense), and `additionalContext` is documented as being for "environment state" and "conditional project rules" — informational, not directive. A hook that injects "USE `ecs-scale.sh`, NOT raw `aws ecs update-service`" in a commanding tone risks exactly the failure mode both sources describe: either ignored, or flagged and surfaced back to the engineer instead of acted on. Phrasing it as a neutral fact ("the sanctioned way to change desired-count on this cluster is `ecs-scale.sh`") is more aligned with the documented design, though neither source claims that reframing guarantees uptake — Finding 4 shows even emphatic phrasing failed via the hook channel specifically.

**Verification block:**
URL fetched: https://code.claude.com/docs/en/hooks
Verbatim quote checked: "Write the text as factual statements rather than imperative system instructions."
Quote substring confirmed at: re-fetch on 2026-07-04, "Add context for Claude" section, same paragraph as the prompt-injection-defense sentence.

### Finding 6 — a third, distinct lever exists beyond "block" and "inject": deterministic rewrite of the tool call itself (`updatedInput`)

**Evidence:** Claude Code's `PreToolUse` hook output schema supports `updatedInput`, which replaces the tool's arguments before it runs, combined with `permissionDecision: "allow"` to auto-approve the rewritten call. The canonical documented example rewrites a `Write` call's target path:

> "This example intercepts Write tool calls and rewrites the `file_path` argument to prepend `/sandbox`, redirecting all file writes to a sandboxed directory. The callback returns `updatedInput` with the modified path and `permissionDecision: 'allow'` to auto-approve the rewritten operation."

And the general framing of what hooks are for, from the same reference:

> "Transform inputs and outputs — to sanitize data, inject credentials, or redirect file paths"

**Source:** https://code.claude.com/docs/en/agent-sdk/hooks

**Significance:** this is a mechanism 4Shark's current hook set does not use at all — `validate-bash-command.sh` only ever emits `allow`/`ask`/`deny` plus stderr text, never `updatedInput`. For a case as narrow and mechanical as "raw `aws ecs update-service ...` → `bash ~/.claude/scripts/ecs-scale.sh ...`" (a pure 1:1 argument remap: `--cluster`, `--service`, `--desired-count`, `--region`), `updatedInput` removes the model's judgment from the loop entirely — the call is rewritten and auto-approved before the model ever "decides" anything, so there is nothing for the model to forget. This directly answers the engineer's "locking at the wrong point" framing: the three available points are (a) block the primitive and hope the agent notices the corrective text on retry, (b) inject a reminder before the call and hope the model weighs it (Findings 3-5 say this is fragile), or (c) rewrite the call transparently so the agent's choice is moot. The documentation does not include a caution against `updatedInput`, but does note (separately, in the parallel-hooks section) that "When multiple PreToolUse hooks return `updatedInput` to rewrite a tool's arguments, the last one to finish takes effect" — a scoping caution (only one hook should own a given rewrite), not a reliability caution.

**Verification block:**
URL fetched: https://code.claude.com/docs/en/agent-sdk/hooks
Verbatim quote checked: "This example intercepts Write tool calls and rewrites the file_path argument to prepend /sandbox, redirecting all file writes to a sandboxed directory. The callback returns updatedInput with the modified path and permissionDecision: 'allow' to auto-approve the rewritten operation."
Quote substring confirmed at: fetched 2026-07-04, "Modify tool input" example section.

### Finding 7 — tool-count / tool-overlap research: accuracy degrades as the choice set grows, and the proposed fix is curation/retrieval, not per-call reminding

**Evidence:**

> "LongFuncEval and Rabinovich and Anaby-Tavor show that function-calling accuracy degrades as tool catalogs grow or as semantically similar tools are added."

The paper's own fix is a retrieval/ranking layer that decides, per query, how many candidate tools to even show the model — not a reminder mechanism:

> "Before an LLM agent can use a tool, a retrieval system must decide which candidate tools to show to the agent."

**Source:** https://arxiv.org/html/2605.24660 ("How Many Tools Should an LLM Agent See? A Chance-Corrected Answer")

**Significance:** this is the academic mirror of Finding 2 — the community's fix for "wrong tool chosen" is overwhelmingly about **reducing/curating what the model sees before it decides**, not about adding more text urging it toward the right choice after the ambiguous set is already presented. In 4Shark's case, both the raw `aws` CLI (via the generic `Bash` tool, always present) and the wrapper script are simultaneously "shown" at all times; this body of research does not have a lever for that specific shape (a built-in general-purpose tool competing with a narrow custom wrapper) beyond what Finding 6 offers (rewrite) or restricting the raw path (Finding 1's block pattern, extended to cover this case).

**Verification block:**
URL fetched: https://arxiv.org/html/2605.24660
Verbatim quote checked: "Before an LLM agent can use a tool, a retrieval system must decide which candidate tools to show to the agent."
Quote substring confirmed at: fetched 2026-07-04, introduction/framing section.

### Finding 8 — "The Compliance Gap": stated agreement to follow a process instruction and actual behavior diverge sharply, and removing the competing option (not more instruction) is what closes the gap

**Evidence**, from the paper's own abstract:

> "An auditor instructs an AI assistant: 'open each file individually using the Read tool -- no scripts, no agents.' The AI replies 'Yes' -- then issues a single batched call summarizing all fifty files at once."

> "Under default framing, all six exhibit instruction compliance rates of 0% -- Claude Sonnet 4 verbally agrees ten out of ten times then bypasses in all ten."

> "97% compliance where rationale is rewarded (audit trails), 0-4% where it is not (file reading, privacy masking); removing delegation tools raises compliance to 75%...confirming environmental affordance rather than weight-encoded failure."

**Source:** https://arxiv.org/abs/2605.01771 ("The Compliance Gap: Why AI Systems Promise to Follow Process Instructions but Don't")

**Significance:** the paper's own framing — "environmental affordance rather than weight-encoded failure" — means the gap is not a matter of the model "not understanding" or "forgetting" the rule (it verbally agreed every time); the gap is that a competing, easier path remained physically available. Removing that path (not reinforcing the instruction) is what moved compliance from ~0% to 75%. This is structurally the same shape as the ECS-scale case: the agent is not confused about the rule (`SKILL.md` states it plainly when read), the raw `aws` primitive simply remains an equally-available affordance at the moment of action. This is independent corroboration, from a different research angle (process-instruction compliance rather than tool selection), of the same conclusion as Findings 2, 4, 5, 7: the durable fix acts on what is *available* to choose from, not on how hard the instruction is worded.

**Verification block:**
URL fetched: https://arxiv.org/abs/2605.01771
Verbatim quote checked: "removing delegation tools raises compliance to 75%...confirming environmental affordance rather than weight-encoded failure."
Quote substring confirmed at: fetched 2026-07-04, abstract text on the arXiv abstract page.

### Finding 9 — Anthropic's own skill-authoring guidance already prescribes "low freedom" (an exact, non-negotiable script) for exactly this class of fragile/consistency-critical operation

**Evidence:**

> "Low freedom (specific scripts, few or no parameters): Use when: Operations are fragile and error-prone; Consistency is critical; A specific sequence must be followed."
>
> "Database migration — Run exactly this script: `python scripts/migrate.py --verify --backup` — Do not modify the command or add additional flags."

And the framing metaphor:

> "Narrow bridge with cliffs on both sides: There's only one safe way forward. Provide specific guardrails and exact instructions (low freedom). Example: database migrations that must run in exact sequence."

**Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

**Significance:** ECS desired-count scaling is the same shape as the paper's own "database migration" example — a small, fragile, must-be-exact operation where "the model could technically do it another way" is not a virtue. Anthropic's own guidance says this class of operation belongs at the "low freedom" end (a specific script, few/no parameters, explicit "do not modify"), which is a design-time instruction to the *skill/tool author*, not a runtime reminder to the agent mid-task. This lines up with Finding 6 (rewrite) more than with "inject a reminder": the guidance is to make the sanctioned path structurally the only reasonable path, not to argue for it harder in context.

**Verification block:**
URL fetched: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
Verbatim quote checked: "Low freedom (specific scripts, few or no parameters): Use when: Operations are fragile and error-prone; Consistency is critical; A specific sequence must be followed." and "Database migration — Run exactly this script"
Quote substring confirmed at: fetched 2026-07-04, "Set appropriate degrees of freedom" section.

### Finding 10 — skill *description* engineering is a distinct, complementary lever, but it only fires at skill-selection time, not inside an already-started raw-command decision

**Evidence:**

> "The description is critical for skill selection: Claude uses it to choose the right Skill from potentially 100+ available Skills."
>
> "Always write in third person. The description is injected into the system prompt, and inconsistent point-of-view can cause discovery problems."

**Source:** https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

**Significance:** this is the "naming/description engineering" camp named in the research question. It is real and Anthropic-endorsed, but it operates at a different decision point than the ECS-scale failure: it governs whether the model invokes the `/apps` **skill** at all when the engineer's prompt names an intent ("scale shared-001's web service to 2"). It does not govern the *internal* moment, already inside a Bash-command-composing step (possibly even inside the skill's own instructions), where the model chooses between writing `bash ~/.claude/scripts/ecs-scale.sh ...` and `aws ecs update-service ...` — both are just Bash-tool invocations at that point, and skill-description quality has no leverage over which one gets typed.

**Verification block:**
URL fetched: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
Verbatim quote checked: "The description is critical for skill selection: Claude uses it to choose the right Skill from potentially 100+ available Skills."
Quote substring confirmed at: fetched 2026-07-04, "Writing effective descriptions" section.

### Finding 11 — deterministic guardrails vs prompt-based guardrails is an already-named debate in the wider AI-agent-security community, and it converges on "layer both, but the enforceable boundary is deterministic"

**Evidence:**

> "The solution isn't to abandon LLM-based guardrails entirely, but to recognize their limitations and layer them with deterministic guardrails, hard-coded, rule-based protections that operate outside the realm of language manipulation."

> "Current generation LLMs are trained to be compliant, to please whoever is prompting them, whether that's a legitimate user or an attacker."

**Source:** https://www.civic.com/news/deterministic-guardrails-for-ai-agent-security

**Significance:** while written about adversarial security rather than 4Shark's own-agent-forgets-a-wrapper case, the framing transfers directly: a prompt/context-based nudge is probabilistic and layered on top of, never a substitute for, a deterministic mechanism (block, or rewrite) at the boundary where the action actually executes. This is the same conclusion Findings 6, 8, and 9 point to from unrelated angles (Claude Code hooks docs, compliance-gap research, skill-authoring guidance).

**Verification block:**
URL fetched: https://www.civic.com/news/deterministic-guardrails-for-ai-agent-security
Verbatim quote checked: "The solution isn't to abandon LLM-based guardrails entirely, but to recognize their limitations and layer them with deterministic guardrails, hard-coded, rule-based protections that operate outside the realm of language manipulation."
Quote substring confirmed at: fetched 2026-07-04, main body paragraph on deterministic vs. LLM-based guardrails.

## Pattern analysis

Across nine independently-sourced findings (Anthropic engineering blog, Anthropic product docs ×3, one arXiv paper on tool-count, one arXiv paper on process compliance, one practitioner blog, one security-guardrails blog), the same shape recurs: **whenever the fix that actually worked is described, it removed or restricted the competing option (curate the tool set, remove delegation tools, rewrite the call, make the script the only "low-freedom" path) — not "say the rule more emphatically in context."** Where reminder-style injection was tried and its outcome reported (Finding 4), it failed, and the practitioner's own diagnosis (Finding 5, independently corroborated by Anthropic's hooks reference) is that hook-injected context is structurally weighted lower than user-authored text or a deterministic decision. No source in this research surfaced a case where "inject a stronger reminder" was reported as the mechanism that solved a tool-selection failure — the absence itself is notable given how much material was reviewed on this exact question.

This does not mean 4Shark's existing INJECT hooks (`inject-terraform-context.sh`, `inject-working-dir-reminder.sh`) are wrong or useless — they inject **information the model does not otherwise have** (terraform conventions, a working-directory tip) into an otherwise-open decision where either path is roughly equally valid or the "wrong" path is merely sub-optimal, not categorically disallowed. The ECS-scale case is different in kind: there IS a categorically-disallowed shape (`SKILL.md` already says "never call `aws ecs update-service` directly"), and for a categorical rule the research above points to block/rewrite, not reminder.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **Block-and-redirect** (extend `validate-bash-command.sh` to also match `aws ecs update-service`/`create-service`, `exit 2` with corrective text, mirroring the existing `ec2 start/stop-instances` rule) | Deterministic; matches the pattern already proven at Finding 1 for `ec2`; no reliance on the model weighing injected text | Still requires the model to read stderr and retry correctly — one extra round-trip vs. rewrite; a corrective-message block can itself be worded imperatively and, per Finding 5, imperative *injected* text has documented friction — though this is stderr fed back after a real tool-call attempt, not `additionalContext`, so the prompt-injection-defense caveat may not directly apply (not verified either way in sources found) | `~/.claude/scripts/validate-bash-command.sh:538-554` (existing pattern); Finding 1 |
| **Rewrite via `updatedInput`** (PreToolUse hook parses a raw `aws ecs update-service --cluster X --service Y --desired-count N [--region R]` and rewrites it to `bash ~/.claude/scripts/ecs-scale.sh --region R --cluster X --service Y --desired-count N`, `permissionDecision: "allow"`) | Removes the model's choice from the loop entirely — nothing to forget, nothing to weigh; auto-approves so no extra prompt; matches Anthropic's own documented pattern (Finding 6) and "low freedom" guidance (Finding 9) | New mechanism not yet used anywhere in the 4Shark hook set — needs its own careful argument-parsing (mirroring the `ecs-scale.sh` flag set) and testing; only works for calls whose arguments map 1:1 onto the wrapper's flags (a scale-only rewrite, not a general fix); per the docs, only one hook should own a rewrite of a given tool call (non-deterministic if two hooks both set `updatedInput` on the same call) | `code.claude.com/docs/en/agent-sdk/hooks` (Finding 6) |
| **Inject-always reminder before every relevant Bash call** (PreToolUse hook fires whenever the command shape looks like a raw `aws ecs` call and injects "use ecs-scale.sh instead" as `additionalContext`) | Cheap to build (mirrors `inject-terraform-context.sh`/`inject-working-dir-reminder.sh` shape exactly); non-blocking; the engineer's original hypothesis | Directly contradicted by the one first-hand account found (Finding 4) for this exact channel (hook `additionalContext`) even with emphatic phrasing; adds context-window cost on every matching call (Finding 3, "context rot"); Claude Code's own docs recommend *factual* framing over imperative framing for this channel (Finding 5), so a naive "USE X, NOT Y" injection risks being discounted or flagged rather than acted on | Findings 3, 4, 5 |
| **Curate/reduce the tool surface** (e.g. an MCP-style narrow tool exposing only `scale_ecs_service(cluster, service, count)`, so raw `aws` is never the tool being chosen from) | Strongest alignment with the tool-count research (Finding 7) and Anthropic's "ambiguous decision points" framing (Finding 2) — removes the ambiguity structurally, same direction as Finding 8's "removing delegation tools" | Largest engineering lift of the four — 4Shark's current architecture exposes `Bash` generically for everything, so "removing" the raw `aws` capability from the model's reach is not a narrow change, it is an architecture change (would affect every other AWS read/write path, not just ECS scale) | Findings 2, 7, 8 |

## What remains uncertain

- Whether a **stderr-delivered** corrective message (the existing block-and-redirect pattern, Finding 1) suffers the same "discounted because it's hook output, not user text" effect documented for `additionalContext` in Finding 4/5. The practitioner account and the Claude Code docs both speak specifically to `additionalContext`/`UserPromptSubmit`-style context injection — not to a `PreToolUse` `deny` + stderr message that the model reads as the direct result of *its own* failed tool call. No source found directly addresses whether that channel carries the same "advisory, not authoritative" weight problem. This is the single biggest open question for deciding between the block-and-redirect and inject-always rows in the trade-off table above.
- Whether `updatedInput` on a `Bash` tool call (rewriting the full command string, as opposed to the documented `Write` `file_path` example) has any additional friction or edge cases not covered in the fetched docs — the canonical example rewrites a structured field (`file_path`), not a free-text shell command string; 4Shark's own hook set has no precedent for rewriting `command` this way, so this is an execution-detail risk, not a "does the mechanism exist" question (it does — Finding 6).
- Whether the "environmental affordance" framing from Finding 8 (compliance-gap paper) generalizes beyond that paper's specific test setup (an auditor instructing an AI assistant on file-reading discipline) to 4Shark's shape (engineer-authored persistent config, not a per-session verbal instruction). The paper is directionally strong corroboration, not a direct replication of 4Shark's setup.
- No source found addresses the specific case of a **general-purpose built-in tool (`Bash`) simultaneously offering both the sanctioned wrapper and the raw primitive** as a named research topic — every tool-count/tool-selection paper found (Finding 7) discusses discrete named tools/functions competing with each other, not one shell capability that can express either path. This is an gap in the literature, not a gap in this research effort.

## Suggested options for main and the engineer

- **Option A — Extend the existing block pattern.** Add `aws ecs update-service` (and any other ECS-scale-shaped raw command, e.g. `create-service` with a `--desired-count`) to `validate-bash-command.sh`'s blocked set, mirroring the `ec2 start/stop-instances` rule exactly (Finding 1's own pattern, already proven in this repo). Lowest-risk, reuses a mechanism already validated in production.
- **Option B — Add a rewrite hook using `updatedInput`.** A new PreToolUse hook parses a raw `aws ecs update-service` invocation's flags and rewrites it into the equivalent `bash ~/.claude/scripts/ecs-scale.sh` call, auto-approved. Removes the model's choice entirely (Finding 6/9), at the cost of building and testing a new mechanism class for this repo.
- **Option C — Do both.** Rewrite (Option B) as the primary path (silent, zero-friction correction) with block-and-redirect (Option A) as the fallback for any shape the rewrite hook's parser does not recognize (e.g. unusual flag ordering) — defense in depth, matching the "layer deterministic mechanisms" framing from Finding 11.
- **Option D — Add an inject-before-action reminder anyway, narrowly scoped and rate-limited**, matching the shape of `inject-working-dir-reminder.sh` (fires only on the exact command shape, once per session) — accepting the evidence in Findings 3-5 that this is the weakest lever of the three, but potentially still useful as a *supplementary* signal layered under Option A or B, not as the sole fix. This directly tests the engineer's original hypothesis in the weakest form the evidence still supports (a narrow, rate-limited, factually-framed nudge — not a blanket "always inject" policy).
- **Not recommended by the evidence reviewed:** relying on `inject-skill-tip.sh`-style prompt-keyword matching to solve this specific case — that hook fires on the *engineer's* prompt text (UserPromptSubmit), and an ECS-scale request phrased casually ("escala o shared-001 pra 2") is not guaranteed to hit any existing trigger phrase, nor does prompt-time injection address the moment *inside* tool-call composition where the raw-vs-wrapper choice is actually made.

## Resolution — decided and implemented (2026-07-05)

**Decision: Option B (rewrite via `updatedInput`), scale-only.** A new PreToolUse hook `scripts/redirect-ecs-scale.sh` deterministically rewrites the pure-scale shape of a raw `aws ecs update-service` (exactly the four scale flags `--region`/`--cluster`/`--service`/`--desired-count`, optionally a profile, nothing else) into the sanctioned `bash ~/.claude/scripts/ecs-scale.sh` invocation, returning `permissionDecision: "allow"` together with `updatedInput`. Parsing is conservative — it defers (exit 0, prompt unchanged) on compound/quoted commands, an unexpected leading env prefix, any unrecognized flag, or a value failing its charset. A `--profile` flag or a leading `AWS_PROFILE=` env prefix is preserved as an `AWS_PROFILE=` prefix on the rewritten wrapper call (the wrapper takes no profile argument and uses ambient credentials, so auth is identical).

**What was deferred / not adopted:**
- **Option A/C block-and-redirect for the NON-scale shapes** (`--force-new-deployment`, `--task-definition`, …) — deferred, not built. The sanctioned redirect target for a non-scale redeploy is undefined (deploys ship via GitHub Actions, and a manual force-redeploy has no wrapper), and deciding that is a separate design question. Non-scale `aws ecs update-service` therefore keeps today's behavior (the permission prompt) — no regression.
- **Option D (inject-a-reminder)** — not adopted, consistent with the Pattern analysis and Findings 3-5: reminder-injection is the weakest of the three levers and no source validated it as a sole fix.

**Open questions from this spike, now resolved:**
- *"Whether `updatedInput` on a `Bash` tool call (rewriting the full `command` string) has additional friction"* (What remains uncertain, bullet 2) — RESOLVED. The official Claude Code hooks docs confirm `updatedInput` under `hookSpecificOutput`, combinable with `permissionDecision: "allow"`, with a canonical example that rewrites a Bash `command`. The hook was smoke-tested against pure-scale, `--profile`-flag, `AWS_PROFILE=`-env, non-scale (deferred), and a different subcommand (deferred), plus a JSON-parse check — all behaved as intended.
- Multi-hook semantics confirmed: PreToolUse hooks run in parallel with decision priority `deny > defer > ask > allow`, so the rewrite (scale) and any future block (non-scale) must stay disjoint by shape — which they are.

**Prerequisites verified before building:** `bash ~/.claude/scripts/ecs-scale.sh:*` was already in `permissions.allow` (so the rewrite target auto-approves), and `auto-approve-aws-readonly.sh` emits nothing for a mutating `update-service` (so it cannot override the rewrite's `allow`).

**Delivered:** PR #341 — `feat(hooks): redirect raw ECS scale commands to the sanctioned wrapper` — merged into `develop` on 2026-07-05. The engineer's "locking at the wrong point" hypothesis was confirmed partially correct (the lock point did not cover ECS-scale) and answered with rewrite-at-the-boundary rather than inject-a-reminder, matching where the evidence pointed.
