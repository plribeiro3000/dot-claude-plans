# SPIKE — Context-Threshold Plan-Reconciliation Nudge

## Investigation question

Can a Claude Code hook (or equivalent mechanism) fire when a session
approaches its context-window limit (e.g. 90–95%) and inject a message into
the MAIN session instructing it to pause non-critical work and reconcile
what has actually been built against the planning documents (`PLAN.md` /
`TASKS.md`) before compaction discards the detail needed to judge that?

### Settled premise (not re-investigated here)

A prior spike already concluded that gating session **start** on the
existence of a plan is bad practice (Anthropic/OpenAI guidance both advise
against a mandatory plan gate, since many sessions are trivial). This spike
is about a different point in the session lifecycle — an **end-of-context**
nudge, not a start-of-session gate. That conclusion is treated as given.

## Decision (final) — CLOSED, do NOT build

**Status: CLOSED. Decision (2026-07-22): do NOT build the automatic
context-threshold reconciliation hook (none of Options A–D's hook variants).**
This section exists so a future session finds this spike and does not redo the
study. If the topic is revisited, start here.

**Why not recommended.** The feature only delivers value if FOUR probabilistic
gates all hold in sequence, and none of them is guaranteed:

1. The trigger fires at the right moment — but no hook payload carries a live
   context-usage percentage (Finding 2). Either `PreCompact` (Anthropic's
   threshold, not a chosen one) or a self-estimate that two independent authors
   reported breaking silently when the context window size changed from 200K to
   1M (Finding 8).
2. The injected message actually reaches the model — undocumented for
   `PreCompact` (Finding 4); blocking it may just suppress compaction silently
   without delivering the reconciliation instruction.
3. The model obeys the nudge — it is a soft reminder, not a mechanical
   guarantee.
4. The reconciliation finishes before the real compaction cuts it off — it
   starts with only ~33K tokens of headroom (Finding 3) and consumes some of
   that itself.

The decisive point sits on top of those four: the task being asked for —
auditing the built work against `PLAN.md`/`TASKS.md` — is a **model
self-audit performed at the end of a long, degraded context**, which is
exactly where the model is least reliable. Anthropic names "context rot" and
calls compaction inherently lossy (Finding 12), and 4Shark's own Subagent
Contract exists because models claim to have verified work they did not. The
likely outcome is therefore not "it fails to run" but "it runs, produces a
shallow or fabricated reconciliation, marks everything fine, and the engineer
trusts it" — a **silent failure**, which is worse than not having the
mechanism at all. Against the engineer's explicit bar ("only build it if it
works; a half-measure that guarantees nothing and just creates more problems
is worse than nothing"), the automatic hook does not qualify.

**What is kept instead.** The endorsed, mechanically-reliable parts of the
practice already exist in 4Shark: externalizing the plan to `PLAN.md`/`TASKS.md`
in a file that survives compaction and `/clear` (backed by Anthropic guidance —
see Findings 11, 12, 17 in "Is the practice itself endorsed?"). The only
deterministic way to add a reconciliation pass is **manual** — the engineer
triggers it on seeing the native context-low warning — because the engineer
decides the moment, removing gates 1–3 entirely. No new hook is built.

**Relationship to the sections below.** The "Suggested options" section still
makes no recommendation *among* the four mechanism options — that was the
research's stance, and it is unchanged. This Decision layers on top of it: the
team, having read the research, chose to build *none* of them. The two are
consistent, not contradictory.

## Sources consulted

- https://code.claude.com/docs/en/hooks — the hooks reference: full event
  catalog, `PreCompact`/`PostCompact`/`Stop` mechanics, decision-control
  tables, output size cap. Fetched in five separate targeted passes plus one
  cross-check re-fetch (self-check per Citation Discipline rule 5).
- https://code.claude.com/docs/en/statusline — the `statusLine` mechanism:
  full JSON schema including `context_window.used_percentage` /
  `remaining_percentage` / `context_window_size`; confirms display-only
  scope.
- https://code.claude.com/docs/en/env-vars — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
  and `CLAUDE_CODE_AUTO_COMPACT_WINDOW` verbatim descriptions.
- https://code.claude.com/docs/en/model-config — `#sonnet-5-context-window`
  and `#extended-context` sections; the ~967K-of-1M default auto-compact
  point. Read directly from the persisted fetch output with the `Read` tool
  (not through a summarizing pass) — see auxiliary file § 14.
- https://code.claude.com/docs/en/costs — confirms auto-compaction exists as
  a cost-reduction mechanism; no percentage given on this page.
- https://github.com/anthropics/claude-code/issues/34340 — "Expose context
  window usage to hooks via environment variable". Closed as not planned.
- https://github.com/anthropics/claude-code/issues/25689 — "Context usage
  threshold hook event with plan-and-continue workflow" — requests almost
  exactly the mechanism 4Shark is asking about. Closed as not planned.
- https://github.com/anthropics/claude-code/issues/46695 — "context_threshold
  setting for auto-compact in settings.json". Closed as duplicate.
- https://github.com/anthropics/claude-code/issues/66475 — "autoCompactThreshold
  setting". Labeled duplicate/stale.
- https://github.com/anthropics/claude-code/issues/39099 — "PreCompact /
  PostCompact hook events" feature request. Closed as not planned, though the
  events it requested now exist in the shipped docs (relationship unclear —
  see "What remains uncertain").
- https://claudefa.st/blog/tools/hooks/context-recovery-hook — a real,
  shipped community implementation of PreCompact-based checkpointing.
- https://www.developersdigest.tech/guides/pre-post-compact-hook — general
  PreCompact/PostCompact guide; yielded only a weak, unquotable match for a
  "progress summary" use case (see Finding 7).
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
  — Anthropic's own context-engineering guidance: structured note-taking,
  compaction, and "context rot" (Findings 11–13).
- https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents
  — Anthropic's own guidance on long-running, multi-session agents:
  persisted progress/feature-status files read at session start (Finding
  14).
- https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf
  — OpenAI's official "A practical guide to building agents", read in full,
  all 32 pages (Finding 15).
- https://cognition.com/blog/dont-build-multi-agents — Cognition's "Don't
  Build Multi-Agents" (Finding 16).
- https://www.langchain.com/blog/context-engineering-for-agents — LangChain's
  "Context Engineering for AI Agents", including a quoted account of
  Anthropic's own multi-agent researcher system (Finding 17).
- https://www.trychroma.com/research/context-rot — checked directly for the
  literal phrase "context rot" in body text; not found there (title only) —
  see Finding 12's sourcing note.
- See auxiliary: `context-threshold_doc_1.md` — verbatim excerpts of every
  quote used below, with source URLs, preserved so a future revision of this
  spike does not need to re-fetch.

## Findings

### Finding 1: The hook event catalog includes `PreCompact` and `PostCompact`, with a manual-vs-auto matcher

**Evidence:**

| Event | When it fires |
|---|---|
| `PreCompact` | Before context compaction |
| `PostCompact` | After context compaction completes |

Matcher table: `PreCompact`, `PostCompact` — matcher filters on "what
triggered compaction", values `manual`, `auto`.

**Source:** https://code.claude.com/docs/en/hooks (fetched 2026-07-22; full
text in auxiliary § 1–2)

**Significance:** The trigger the team is asking about exists and is
distinguishable from a manual `/compact`. A hook configured with
`"matcher": "auto"` on `PreCompact` fires specifically when Claude Code's own
auto-compaction logic decides the context is full enough to compact — which
is the closest built-in analogue to "context approaching its limit."

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at the "Hook lifecycle" and "Matcher patterns" tables of
`code.claude.com/docs/en/hooks`.

### Finding 2: No hook payload carries a live context-usage percentage or token count — the only place that data is exposed is `statusLine`, and it is display-only

**Evidence:** The Stop event's full input schema (the richest of the events
checked) is:

```json
{
  "session_id": "abc123",
  "prompt_id": "550e8400-...",
  "transcript_path": "/home/user/.claude/projects/.../transcript.jsonl",
  "cwd": "/home/user/my-project",
  "permission_mode": "default",
  "effort": { "level": "medium" },
  "hook_event_name": "Stop",
  "last_assistant_message": "..."
}
```

No `context_window` field appears anywhere in this or in the common input
fields shared by every hook event. The one place token/percentage data is
exposed is the `statusLine` mechanism's JSON payload:

```json
"context_window": {
  "total_input_tokens": 15500,
  "total_output_tokens": 1200,
  "context_window_size": 200000,
  "used_percentage": 8,
  "remaining_percentage": 92
}
```

`context_window_size` is documented as "200000 by default, or 1000000 for
models with extended context" — so `statusLine` does carry the 1M-window
case 4Shark runs on. But `statusLine` is explicitly a rendering channel:
"Claude Code displays whatever your script prints" — there is no documented
path from a `statusLine` script's stdout back into the model's context.

**Source:** https://code.claude.com/docs/en/hooks (Stop input schema) and
https://code.claude.com/docs/en/statusline (context_window schema and "how
status lines work" prose), both fetched 2026-07-22.

**Significance:** A hook cannot natively ask "what percentage of context am
I at?" — this is the central mechanical gap. Anything a hook does that needs
to react to "90/95% used" must either (a) piggyback on the `auto` PreCompact
trigger, which fires at Anthropic's own threshold (not 4Shark's chosen
number) and cannot itself report the percentage, or (b) have the hook script
independently read `transcript_path` and estimate token usage itself (see
Finding 8) — an approximation, not the ground truth the model's own request
uses.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at both cited pages.

### Finding 3: The default auto-compact point for Sonnet 5 (the model that carries a native 1M window) is ~967K of 1M tokens (~96.7%), and it is adjustable — with a caveat

**Evidence:** "On the Anthropic API, Sonnet 5 always runs with the 1M context
window. There is no 200K variant, no `[1m]` suffix to select, and no usage
credits required on any plan. Sessions auto-compact before the window fills,
at about 967K tokens by default; set `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to
choose a different threshold."

The adjustment path: "`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`: Set the percentage
(1-100) of the auto-compaction window at which auto-compaction triggers. ...
This variable only causes earlier compaction when Claude Code compacts
proactively: when `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set, in cloud
sessions, and on Sonnet 4.6 and Opus 4.6 without extended context ... On
Sonnet 5, proactive compaction applies at the model's default threshold."

**Source:** https://code.claude.com/docs/en/model-config
(`#sonnet-5-context-window`) and https://code.claude.com/docs/en/env-vars,
both fetched 2026-07-22 — the model-config quote was read directly from the
persisted raw fetch via the `Read` tool, not through a summarizing pass (see
auxiliary § 14 for the exact line numbers).

**Significance:** 967K of 1M leaves ~33K tokens before the hard limit — in
the same order of magnitude as the ~50K the team estimated ("even at 95%
there are ~50k tokens left"), though the documented number is closer to
96.7% used (3.3% remaining) than a flat 95%/5%. The env-var text explicitly
warns that lowering the threshold via `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
"only causes earlier compaction when Claude Code compacts proactively,"
and names Sonnet 5's own default threshold as a separate case from the
percentage override — meaning it is not settled from documentation alone
whether setting `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90` actually moves a local
Sonnet 5 session's auto-compact point earlier without also setting
`CLAUDE_CODE_AUTO_COMPACT_WINDOW`. This is listed under "What remains
uncertain."

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at `code.claude.com/docs/en/model-config` line 555 (persisted
fetch) and `code.claude.com/docs/en/env-vars`.

### Finding 4: `PreCompact` can block compaction via `decision: "block"`, but the documented "system reminder, continue in the same turn" behavior is stated only for `Stop`/`SubagentStop` — not confirmed for `PreCompact`

**Evidence:** The decision-control table lists `PreCompact` among the events
supporting the top-level `decision` pattern (`decision: "block"`, `reason`),
but the same row states: "Stop and SubagentStop also accept
`hookSpecificOutput.additionalContext` for non-error feedback that continues
the conversation" — singling those two events out. The specific sentence
"Claude receives your reason as a system reminder and continues working in
the same turn" is documented under the Stop-specific "decision control"
section, not under a general or PreCompact-specific one. A follow-up,
narrowly-scoped fetch asking specifically whether this behavior is
documented for `PreCompact` returned: "The documentation does not explicitly
state that the `reason` text reaches Claude as feedback for all events using
`decision: 'block'`. The behavior appears event-specific."

**Source:** https://code.claude.com/docs/en/hooks, fetched 2026-07-22 in two
separate passes (self-check per Citation Discipline rule 5).

**Significance:** Blocking `PreCompact` reliably prevents that specific
compaction attempt from happening (the exit-code-2 table is unambiguous:
"Blocks compaction"). What is NOT established by the fetched documentation
is whether the `reason` text given on that block is surfaced to the model as
actionable feedback the same way a blocked `Stop` is — or whether it is
purely a silent refusal (compaction just doesn't happen this time, and the
session keeps running at ~96.7% full with no reconciliation instruction
delivered). This is the single largest unresolved point for the "PreCompact
nudge" design option.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at the "Decision control" table and the narrowly-scoped follow-up
fetch, both against `code.claude.com/docs/en/hooks`.

### Finding 5: `Stop` reliably supports "block + inject reason as a system reminder, continue in the same turn" and is loop-guarded — but it fires on every turn, not selectively

**Evidence:** "Claude receives your reason as a system reminder and
continues working in the same turn, so you can give Claude feedback without
breaking the agentic loop." Loop safety: "`stop_hook_active`: boolean,
present and `true` when a `Stop` hook has already blocked this turn to
prevent infinite loops. If your hook returns `decision: 'block'` when
`stop_hook_active` is already `true`, Claude Code shows your reason but
doesn't block again, and the turn ends." The `Stop` event fires "When Claude
finishes responding" — every turn's end, not only when a task or session is
judged complete.

**Source:** https://code.claude.com/docs/en/hooks, fetched 2026-07-22.

**Significance:** A `Stop`-hook-based reconciliation gate is the mechanism
4Shark already uses elsewhere (`validate-closing-summary.sh`, per this
team's own `CLAUDE.md`) and is documented, reliable, and loop-safe. But
because `Stop` fires every turn, a reconciliation gate built on it needs its
own condition for "are we near the context limit" — which, per Finding 2, is
not available to the hook natively. It would have to self-estimate (Finding
8) or fire unconditionally on some other signal (e.g. only after N turns, or
only when a `PLAN.md`/`TASKS.md` exists in the working tree), which is a
weaker proxy for "context is running out" than a real percentage.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at `code.claude.com/docs/en/hooks`, "Stop decision control" and
common input fields sections.

### Finding 6: Anthropic has been asked for exactly this mechanism at least three times and closed each request without shipping it

**Evidence:**

- #25689, "Context usage threshold hook event with plan-and-continue
  workflow," proposed a `ContextThreshold` hook event carrying
  `context_usage_pct`, `context_used_tokens`, `context_max_tokens`, plus a
  `contextThresholds` setting supporting staged values like `[60, 80, 90]`
  — closed as not planned.
- #46695, "context_threshold setting for auto-compact in settings.json,"
  proposed firing a `pre_compact_hook` at a configurable
  `auto_compact_threshold` before compaction — closed as duplicate.
- #34340, "Expose context window usage to hooks via environment variable,"
  proposed `CLAUDE_CONTEXT_PERCENT` etc. for use in `PreToolUse`/`Stop`
  hooks — closed as not planned.

**Source:** https://github.com/anthropics/claude-code/issues/25689,
https://github.com/anthropics/claude-code/issues/46695,
https://github.com/anthropics/claude-code/issues/34340 — all fetched
2026-07-22.

**Significance:** The specific gap 4Shark's proposed mechanism needs filled
— a hook that knows the percentage and can act on a configurable threshold
— has been requested multiple times by other users independently, for
close to the identical use case (long-running agentic sessions losing state
at compaction), and Anthropic has declined each time. This does not mean
the mechanism is impossible to approximate (see Finding 8's workaround
pattern), but it does mean there is no first-class, vendor-supported path
to it today.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at all three issue pages.

### Finding 7: A real community implementation exists for PreCompact-based state preservation, but it is a backup/recovery pattern, not a plan-reconciliation pattern

**Evidence:** "PreCompact hooks fire right before compaction happens - your
last chance to capture state." The implementation's checkpointing cadence is
driven by a **StatusLine** payload, not any hook payload: "StatusLine is
different. It receives a JSON payload on every turn with
`context_window.remaining_percentage`" and explicitly notes: "Most Claude
Code hooks don't receive context metrics. PreToolUse, PostToolUse, Stop -
none of them know how much context you've consumed." Its recovery workflow
is: "Run /clear: Start a fresh session (cleaner than continuing with
compacted context). Load the backup: Read the markdown file to restore
context." No step in the described workflow reconciles the saved state
against a separate plan/task document — it restores the session's own prior
state, not a cross-check against planning artifacts.

A second source (developersdigest.tech's PreCompact/PostCompact guide) was
checked for a "write a progress summary" pattern closer to reconciliation;
the fetch could not find a quotable match beyond a single bullet
("Snapshotting state to disk before a compaction you're worried about") with
no code example — flagged as a weak, non-sustaining source and not used to
derive any option below.

**Source:** https://claudefa.st/blog/tools/hooks/context-recovery-hook,
fetched 2026-07-22.

**Significance:** The closest real, shipped precedent is checkpoint/restore
of the session's own work, not a reconciliation pass against an external
plan document. "Reconcile built work against `PLAN.md`/`TASKS.md`" is a
4Shark-specific idea that does not have a found community precedent under
that name.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at `claudefa.st/blog/tools/hooks/context-recovery-hook`.

### Finding 8: Hooks can read `transcript_path` directly and self-estimate token usage — the documented workaround for the missing percentage

**Evidence:** "`transcript_path` | Path to conversation JSON. The transcript
file is written asynchronously and may lag the in-memory conversation, so it
may not yet include the current turn's most recent messages when a hook
fires." Community precedent for this exact workaround, from issue #46695:
"A `context-monitor.sh` runs on every `PreToolUse` hook, counting tool calls
as a proxy for context usage. At estimated 80%, it prints a warning that
agent rules tell it to act on." Issue #34340's author describes the same
shape failing when the context window size changed: "Currently it
approximates context usage by counting heavy tool calls ... This breaks when
the context window size changes. I recently got upgraded from 200K to 1M
context (Opus 4.6) and my hook started firing at ~25% instead of ~60%
because the threshold was calibrated for the old window size."

**Source:** https://code.claude.com/docs/en/hooks (transcript_path field)
and GitHub issues #46695, #34340, all fetched 2026-07-22.

**Significance:** A hook COULD approximate "are we near the limit" by
reading `transcript_path` and counting/estimating tokens itself (or by
tallying heavy tool calls as a rougher proxy), then firing its own
`decision: "block"` + `reason` on `UserPromptSubmit` or `Stop`. Two
independent GitHub issue authors report this exact pattern in production
use — but both also report it as fragile: the transcript lags the live
conversation (documented), and a hardcoded/calibrated threshold breaks
silently when the context window size changes (a live problem reported when
a user's model was upgraded from 200K to 1M). This is a workable but
imprecise approximation, not the ground-truth percentage the model itself
uses.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at `code.claude.com/docs/en/hooks` and both GitHub issues.

### Finding 9: `UserPromptSubmit` reliably supports `additionalContext` injection, landing "alongside the submitted prompt"

**Evidence:** Under the hooks reference's "Add context for Claude" heading:
"[UserPromptSubmit] and [UserPromptExpansion]: alongside the submitted
prompt." This is the same event 4Shark's own `inject-output-policy-reminder.sh`
and several other existing hooks already rely on (per this team's `CLAUDE.md`).

**Source:** https://code.claude.com/docs/en/hooks, fetched 2026-07-22.

**Significance:** Unlike the `PreCompact`-reason uncertainty in Finding 4,
`UserPromptSubmit`'s ability to inject text the model will read is
unambiguous and already validated in production by this team's own hook
set. A periodic reminder built here does not carry the same open question
Finding 4 raises for `PreCompact`.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at `code.claude.com/docs/en/hooks`, "Add context for Claude"
section.

### Finding 10: Hook output is capped at 10,000 characters and `hookSpecificOutput.hookEventName` must name the firing event

**Evidence:** "Hook output strings, including `additionalContext`,
`systemMessage`, and plain stdout, are capped at 10,000 characters. Output
that exceeds this limit is saved to a file and replaced with a preview and
file path, the same way large tool results are handled."

**Source:** https://code.claude.com/docs/en/hooks, fetched 2026-07-22.

**Significance:** Directly bounds the design: any reconciliation-nudge
message injected by a hook (whether `PreCompact`, `Stop`, or
`UserPromptSubmit`) must fit in 10,000 characters and must echo the correct
`hookEventName`, matching this team's own documented constraint elsewhere in
`CLAUDE.md`.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed at `code.claude.com/docs/en/hooks`.

## Trade-offs surfaced

| Approach | Pros | Cons | Source (Findings) |
|---|---|---|---|
| **A. `PreCompact` (matcher `auto`) block + reconciliation reason** | Fires at the real, vendor-computed near-limit moment (~96.7% for Sonnet 5's 1M window); no self-estimation needed; blocking is documented to work ("Blocks compaction") | Whether the `reason` text reaches the model as actionable feedback (vs. a silent no-op refusal) is undocumented for this event (Finding 4); only ~33K tokens of buffer remain by the time it fires — a reconciliation pass itself consumes some of that; fires only once compaction is already imminent, leaving little margin if the reconciliation pass runs long | Findings 1, 3, 4, 10 |
| **B. `Stop`-hook reconciliation gate, conditioned on a self-estimated token count** | `Stop`'s block mechanics are fully documented and already used by this team (`validate-closing-summary.sh`); loop-safe via `stop_hook_active`; reliably injects `reason` as a "system reminder" that "continues working in the same turn" | `Stop` fires every turn, so the hook needs its own approximate threshold check by reading `transcript_path` (Finding 8) — the same fragile, calibration-dependent pattern two GitHub issue authors reported breaking when their context window size changed | Findings 5, 8 |
| **C. `UserPromptSubmit` periodic reminder, conditioned on a self-estimated token count** | `additionalContext` injection on this event is unambiguous and already validated in this team's own hook set (Finding 9); does not depend on the uncertain `PreCompact`-reason behavior | Only fires when the engineer submits a new prompt — a long uninterrupted agentic turn with no new prompt would never see it; still needs the same fragile self-estimation as Option B | Findings 8, 9 |
| **D. Do nothing — rely on compaction's own summary plus the existing `CLAUDE.md`/`PLAN.md`/`TASKS.md` filesystem discipline** | No new hook to build or maintain; the team already writes planning docs to a persistent, git-ignored filesystem location that survives compaction and even `/clear` (per this team's own Plans Storage model) | Nothing prompts an explicit reconciliation pass — compaction's summary is a lossy compression of the conversation, not a verification that the built work matches the plan; the gap this spike investigates stays open | Settled premise; Findings 1–3 (context on what compaction already does) |

## What remains uncertain

- Whether a blocked `PreCompact` event's `reason` text reaches the model as
  actionable, in-context feedback the same way a blocked `Stop` does, or is a
  silent refusal with no delivered instruction (Finding 4). This is the
  single fact that would most change Option A's viability, and it was not
  resolved by the fetched documentation.
- Whether `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` actually lowers the auto-compact
  point on a **local** Sonnet 5 session (1M native window) without also
  setting `CLAUDE_CODE_AUTO_COMPACT_WINDOW` — the env-var text names Sonnet
  5 as a case governed by "the model's default threshold" separately from
  the general override behavior (Finding 3).
- Whether GitHub issue #39099 (which requested exactly the `PreCompact`/
  `PostCompact` events, closed "not planned") has any causal relationship to
  those events now existing in the shipped hooks reference, or whether they
  were shipped independently and the issue was simply closed as
  superseded/stale without comment. Not resolvable from the fetched content
  (see auxiliary § 15).
- Whether reading `transcript_path` inside a hook to self-estimate token
  usage can be made reliable enough for a 90/95% threshold, given two
  independent reports (issues #34340, #46695) of this exact approach
  breaking or requiring re-calibration when the model's context window size
  changed.
- Not found: any published, named community practice that combines
  PreCompact-style checkpointing with reconciliation against a separate
  planning artifact (as opposed to restoring the session's own prior
  state). Finding 7 covers the closest precedent found and explicitly notes
  it is not this.
- Whether Anthropic's own documented harness pattern (Finding 14) ever
  performs an explicit AUDIT of previously-marked-complete work — as
  opposed to reading the progress artifact only to decide what to build
  next — was checked directly and the fetched text describes only the
  latter ("Read the features list file at the beginning of a session.
  Choose a single feature to start working on."). No sentence describing
  a re-verification of already-marked-complete items was found in the
  fetched page.

## Is the practice itself endorsed? (vendor & community guidance)

Findings 1–10 above settled a MECHANISM question: whether a Claude Code
hook can know the live context-usage percentage and act on a configurable
threshold (it cannot, natively — Finding 2 — and Anthropic has declined to
add this three times — Finding 6). This section asks a different,
PRACTICE-level question the engineer raised after reading that result: is
the underlying practice — externalizing a plan/notes to a persisted file,
periodically re-anchoring an agent to it, and checkpointing state before
context fills — itself something Anthropic, OpenAI, or the broader
agent-engineering community recommend, independent of whether Claude Code
supports the trigger mechanism natively.

### Finding 11: Anthropic explicitly recommends a persisted plan/notes file the agent re-reads to survive long tasks — "structured note-taking"

**Evidence:** "Structured note-taking, or agentic memory, is a technique
where the agent regularly writes notes persisted to memory outside of the
context window. These notes get pulled back into the context window at
later times. This strategy provides persistent memory with minimal
overhead." And, naming Claude Code's own behavior as the reference case:
"Like Claude Code creating a to-do list, or your custom agent maintaining
a NOTES.md file, this simple pattern allows the agent to track progress
across complex tasks, maintaining critical context and dependencies that
would otherwise be lost across dozens of tool calls."

**Source:** https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
(Anthropic engineering blog, "Effective context engineering for AI
agents"), fetched 2026-07-22, self-check re-fetch confirmed both quoted
sentences verbatim.

**Significance:** This is a direct, first-party Anthropic endorsement of
the "externalize the plan to a file and re-read it" half of the practice
the engineer asked about. It is stated as a general agent-engineering
technique, not scoped to any particular hook or trigger mechanism — so it
stands independent of the Finding 1–10 mechanism gap.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed via a dedicated self-check re-fetch against
`anthropic.com/engineering/effective-context-engineering-for-ai-agents`.

### Finding 12: Anthropic names "context rot" and describes compaction as inherently lossy — the rationale for checkpointing independent of any hook

**Evidence:** "Studies on needle-in-a-haystack style benchmarking have
uncovered the concept of context rot: as the number of tokens in the
context window increases, the model's ability to accurately recall
information from that context decreases." On compaction: "The art of
compaction lies in the selection of what to keep versus what to discard,
as overly aggressive compaction can result in the loss of subtle but
critical context whose importance only becomes apparent later."

**Source:** https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents,
fetched 2026-07-22, self-check re-fetch confirmed the "context rot"
sentence verbatim. Note on sourcing the term itself: Chroma's research page
(https://www.trychroma.com/research/context-rot, checked directly) titles
itself "Context Rot" but the literal two-word phrase was not found in that
page's body text on a direct check — so this finding attributes the term
"context rot" to Anthropic's own quoted sentence, not to the Chroma page,
per Citation Discipline rule 3 (no invented term attributions).

**Significance:** Anthropic itself names the failure mode ("context rot")
that motivates wanting a checkpoint/reconciliation practice, and states
plainly that compaction is a lossy, judgment-dependent operation, not a
lossless save. This is the vendor's own stated reason a team might not
want to rely on compaction's summary alone — it corroborates the
engineer's underlying concern, independent of whether a hook can trigger
on it.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed via a dedicated self-check re-fetch, same URL as Finding 11.

### Finding 13: Anthropic frames note-taking and compaction as two distinct, task-dependent techniques — not a single combined workflow

**Evidence:** Per a targeted fetch of the same page's structure: "Note-taking
excels for iterative development with clear milestones" while "Compaction
maintains conversational flow for tasks requiring extensive
back-and-forth." The two techniques are presented under separate
subsections of the page, chosen based on task characteristics rather than
combined into one described workflow.

**Source:** https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents,
fetched 2026-07-22 (targeted structural fetch distinguishing the two
sections).

**Significance:** This narrows Finding 11's endorsement: Anthropic
recommends note-taking specifically for "iterative development with clear
milestones" — a description that matches the shape of a `PLAN.md`/
`TASKS.md`-driven session — but does not describe combining note-taking
WITH a compaction-time trigger. The engineer's proposed mechanism (nudge
right before compaction, specifically to reconcile against a plan) would
be a novel combination of two techniques Anthropic documents separately,
not a documented combination itself.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed via the same URL, targeted structural re-fetch.

### Finding 14: Anthropic's separate "long-running agents" harness blog documents the closest vendor precedent — a persisted progress/feature-status file read at the START of each new session — but it is a next-session handoff, not an in-session context-threshold reconciliation, and it is not described as an audit of prior work

**Evidence:** "The core challenge of long-running agents is that they must
work in discrete sessions, and each new session begins with no memory of
what came before." The documented solution: "an initializer agent that
sets up the environment on the first run, and a coding agent that is
tasked with making incremental progress in every session, while leaving
clear artifacts for the next session" — concretely, "a claude-progress.txt
file that keeps a log of what agents have done" plus a feature-requirements
file where "we prompt coding agents to edit this file only by changing the
status of a passes field." On why compaction alone does not solve this:
"However, compaction isn't sufficient... This happens even with
compaction, which doesn't always pass perfectly clear instructions to the
next agent." On how the file is used at the start of a session: "Read the
features list file at the beginning of a session. Choose a single feature
to start working on." — a targeted follow-up fetch checking specifically
for an audit/re-verification step found none: the described read is to
decide what to build next, not to re-check whether previously-marked-complete
items are actually complete.

**Source:** https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents,
fetched 2026-07-22 across three passes (initial fetch, a targeted
follow-up on the compaction-insufficiency passage, and a self-check
re-fetch confirming three quoted sentences verbatim).

**Significance:** This is the single closest first-party precedent to the
engineer's proposed mechanism, and it is close but not identical. It
endorses: externalizing progress to a file (matches), noting that
compaction alone is insufficient for long-running coherence (matches the
engineer's underlying worry), and having the NEXT session read that file
before acting (partially matches — this is a session-boundary handoff, not
an in-session, context-percentage-triggered reconciliation). It does NOT
document reading the file to verify that already-completed work still
matches what was claimed — the shape 4Shark's proposed nudge would need
("reconcile what has actually been built against the planning documents")
is not what this pattern does; this pattern decides what to build next,
assuming prior status entries are trustworthy.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed via a dedicated self-check re-fetch of three sentences against
`anthropic.com/engineering/effective-harnesses-for-long-running-agents`.

### Finding 15: OpenAI's own official "A practical guide to building agents" (32 pages, read in full) does not discuss context-window management, compaction, or persisted plan/progress files anywhere

**Evidence:** The guide's four sections — "What is an agent?", "When
should you build an agent?", "Agent design foundations" (models, tools,
instructions, orchestration patterns, single- vs multi-agent systems), and
"Guardrails" (relevance/safety classifiers, PII filter, moderation, tool
safeguards, human intervention) — were read in full, page by page. No
section, heading, or paragraph addresses context-window limits,
compaction, session handoff, or a persisted plan/progress file of any
kind. The guide's closest adjacent topic is "Plan for human intervention,"
which covers escalating to a human on failure-threshold or high-risk
actions — a different concern (escalation on risk) from the engineer's
question (reconciling built work against a plan before context is lost).

**Source:** https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf,
fetched and read in full (all 32 pages via direct PDF read) 2026-07-22.

**Significance:** This is a "not found" finding, and it is informative on
its own terms: OpenAI's flagship, official guidance for building agents —
the document a team would reach for first — is silent on the exact
question this spike investigates. It neither endorses nor contradicts the
practice; it simply does not address long-running context management at
all. Any claim that "OpenAI recommends X" about context/plan persistence
cannot be sourced to this document.

**Verification:** PDF fetched (initial WebFetch attempt failed on binary
content; the persisted PDF was then read directly and completely via the
`Read` tool, all 32 pages, page by page) / Every page's content quoted or
summarized above / No relevant substring found, so no quote is presented
as a positive claim — this is a documented absence, not a soft-failed
fetch.

### Finding 16: Cognition's "Don't Build Multi-Agents" names "context engineering" as the evolution of prompt engineering and describes compressing agent history with a dedicated model, but does not discuss a todo/plan-file pattern or reconciliation against a plan

**Evidence:** "'Prompt engineering' was coined as a term for the effort
needing to write your task in the ideal format for a LLM chatbot.
'Context engineering' is the next level of this." On compressing an
agent's own history: "we introduce a new LLM model whose key purpose is to
compress a history of actions & conversation into key details, events, and
decisions." On sub-agent context loss (a different but adjacent concern):
"The subtask agent lacks context from the main agent that would otherwise
be needed to do anything beyond answering a well-defined question." A
targeted fetch for a todo-list/plan-file pattern and for reconciliation
against an original plan/task found neither present in this page's
content.

**Source:** https://cognition.com/blog/dont-build-multi-agents, fetched
2026-07-22 (redirected from cognition.ai/blog/dont-build-multi-agents,
301).

**Significance:** Cognition is a frequently-cited voice on context
engineering for agents, and this page does treat context engineering as a
serious, named discipline — but its content, as fetched, does not extend
to a todo-list/plan-file pattern or to reconciling an agent's work against
a separate plan document. This page does not sustain a claim that
Cognition endorses the specific practice the engineer asked about.

**Verification:** URL fetched (after following the 301 redirect) / Verbatim
quotes checked / Quote substrings confirmed at
`cognition.com/blog/dont-build-multi-agents`. The absence claims (no
todo-list pattern, no reconciliation pattern) are reported as "not found in
the fetched content," not as a claim about the whole site.

### Finding 17: Anthropic's own multi-agent research system saves its plan to persisted memory SPECIFICALLY because the context window will be truncated — the clearest documented link between "persist the plan" and "context will run out"

**Evidence:** "The LeadResearcher begins by thinking through the approach
and saving its plan to Memory to persist the context, since if the context
window exceeds 200,000 tokens it will be truncated and it is important to
retain the plan." This sentence is quoted by LangChain from Anthropic's
own published account of its multi-agent Claude researcher system, under
a "Write Context" / "Scratchpads" heading.

**Source:** https://www.langchain.com/blog/context-engineering-for-agents
("Context Engineering for AI Agents"), fetched 2026-07-22, self-check
re-fetch confirmed the sentence verbatim. The same page separately
confirms, verbatim: "Claude Code runs '[auto-compact]' after you exceed
95% of the context window and it will summarize the full trajectory of
user-agent interactions" — an independent third-party corroboration of the
~95-96.7% auto-compact figure already established in Finding 3 from
Anthropic's own docs.

**Significance:** This is the most direct documented link found between
"persist a plan to survive context loss" and an explicit context-limit
trigger ("since if the context window exceeds 200,000 tokens it will be
truncated") — closer to the engineer's framing than Findings 11–14. It is
still a "save the plan so it is not lost" pattern, not a "reconcile what
was actually built against the plan" pattern — the sentence describes
persisting the plan itself, not auditing completed work against it. The
page attributes the term "context engineering" itself to Andrej Karpathy,
not to LangChain or to this multi-agent system account — noted here so
this finding is not read as LangChain claiming to coin the term.

**Verification:** URL fetched / Verbatim quote checked / Quote substring
confirmed via a dedicated self-check re-fetch against
`langchain.com/blog/context-engineering-for-agents`.

### Summary — what is endorsed, what is 4Shark-original

Two components of the practice the engineer described are each backed by
at least one first-party vendor source: **externalizing a plan/notes to a
persisted file** is endorsed by Anthropic directly (Findings 11, 13, 17),
and **treating compaction as lossy, insufficient on its own** is likewise
an explicit Anthropic statement (Findings 12, 14). The **specific
combination** 4Shark described — reconciling what has actually been BUILT
against a separate `PLAN.md`/`TASKS.md` at the moment context is about to
be compacted — is not found stated by name or by pattern in any fetched
source. The closest precedent (Finding 14) reads a progress artifact to
decide what to build next, not to audit whether completed work matches
what was planned; Finding 17 persists a plan to survive truncation, not to
check built work against it. This mirrors and sharpens what Finding 7
already found for the mechanism side: the practice of persisting state is
endorsed, but the specific reconciliation shape 4Shark is asking about
remains 4Shark-original as far as this research could establish.

## Suggested options for main and the engineer

- **Option A** — Build the nudge on `PreCompact` with `matcher: "auto"`,
  accepting the open question in Finding 4 as a risk to validate empirically
  (a throwaway hook, run once, checking whether the model's next output
  shows awareness of the injected `reason` — the same kind of live-test
  methodology this team used to settle the `$HOME`-path and multi-line-Bash
  questions elsewhere in `CLAUDE.md`) before committing to it as the primary
  mechanism.
- **Option B** — Build the nudge on `Stop`, gated by a self-estimated token
  count read from `transcript_path`, accepting the calibration fragility
  Finding 8 documents and budgeting for periodic recalibration if the
  context window size or model changes.
- **Option C** — Build the nudge on `UserPromptSubmit` with the same
  self-estimation gate as Option B, accepting that it only fires when a new
  prompt is submitted (a gap during a long, uninterrupted autonomous turn).
- **Option D** — Do not build a new hook; rely on the existing filesystem
  planning-document discipline and compaction's own summarization, and
  treat the reconciliation as something the engineer triggers manually (e.g.
  by watching the native context-low warning noted in Finding 2's auxiliary
  material and asking Claude to reconcile at that point).
- A combination is also possible — e.g., Option A as the primary trigger
  with Option B or C as a fallback in case Finding 4's open question
  resolves unfavorably (silent-refusal) — but this spike does not evaluate
  a combined design's implementation cost.

No recommendation is made among these — the open question in Finding 4 is
significant enough that the choice between Option A and Options B/C is a
judgment call for the engineer, not a fact this research settled. The new
section above ("Is the practice itself endorsed?") answers a separate
question: the practice of persisting a plan and treating compaction as
lossy is vendor-endorsed; the specific reconciliation-against-a-plan shape
of the mechanism is not found precedented under any name. That distinction
does not change which mechanism option (A–D) is preferable — it is a
separate axis the engineer asked to have answered alongside the mechanism
findings.
