# SPIKE — `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70` at a 1M Context Window

## Investigation question

Does 4Shark's `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=70` setting (`~/.claude/settings.json:5`) still make sense now that Claude Code's context window is 1M tokens, or should it be removed and Claude Code's own default auto-compaction be left alone? Sub-questions: (1) does the variable still exist and get honored; (2) what is the current default threshold and is it a percentage or a fixed-headroom rule; (3) does model-quality degradation still track a fixed ~70% figure at 1M, or does it track absolute tokens; (4) can the engineer's observed "~970K tokens saved" compaction be reconciled with a 70% trigger; (5) what does each option (remove / keep 70 / keep a different value) cost.

## Sources consulted

- [code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars) — current, official description of `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` and `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, including the "can only lower, never raise" behavior.
- [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings) — `autoCompactEnabled` default and the documented scope of the `env` settings key (subprocess vs. application logic).
- [code.claude.com/docs/en/model-config](https://code.claude.com/docs/en/model-config) — § "Extended context" and § "Sonnet 5 context window": current 1M-window availability and the Sonnet 5 default auto-compact point (~967K tokens).
- [platform.claude.com/docs/en/build-with-claude/context-windows](https://platform.claude.com/docs/en/build-with-claude/context-windows) — "context rot" definition, context-awareness token budgets by model.
- [platform.claude.com/docs/en/build-with-claude/compaction](https://platform.claude.com/docs/en/build-with-claude/compaction) — API-level server-side compaction feature (a different mechanism from Claude Code's own auto-compact; see Finding 4).
- [github.com/anthropics/claude-code/issues/31806](https://github.com/anthropics/claude-code/issues/31806) (closed) — community report, override cannot raise the threshold above a built-in default.
- [github.com/anthropics/claude-code/issues/36381](https://github.com/anthropics/claude-code/issues/36381) (closed) — community report, override not honored at all in one case.
- [github.com/anthropics/claude-code/issues/63186](https://github.com/anthropics/claude-code/issues/63186) (**open**) — community reports across 4 independent users: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` set via `settings.json`'s `env` block reaches spawned subprocesses but not the app's own autocompact logic.
- [research.trychroma.com/context-rot](https://www.trychroma.com/research/context-rot) — Chroma's "Context Rot" study; direct fetch did not yield a directly quotable absolute-token threshold (see Finding 6, marked UNVERIFIED for the specific numbers).
- [anthropic.com/news/claude-opus-4-6](https://www.anthropic.com/news/claude-opus-4-6) — Anthropic's own framing of "context rot" and the 1M-window MRCR v2 benchmark result.
- [anthropic.com/engineering/effective-context-engineering-for-ai-agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — architectural explanation of why long context degrades (attention dilution across n² token relationships).
- See auxiliary: `autocompact_sources_1.md` — full verbatim excerpts of every source above, including the raw GitHub issue bodies fetched via `api.github.com`, preserved for revision without re-fetching.

## Findings

### Finding 1: The variable exists, is documented, and is honored — but only in one direction

**Evidence:** `code.claude.com/docs/en/env-vars` states:

> "Set the percentage (1-100) of the auto-compaction window at which auto-compaction triggers. Use lower values like `50` to compact earlier. ... The override can only lower the threshold, so values above the default have no effect."

**Source:** [code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars), § `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (fetched 2026-08-03; full text in `autocompact_sources_1.md` § 1).

**Significance:** This settles the three-way distinction the investigation asked for. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is **documented and supported** — state (a), not (b) undocumented-but-working or (c) removed. It is a genuine settings.json/environment-variable mechanism, current as of the latest docs snapshot, with an explicit alternative for when the percentage framing is not what's wanted: `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, which "set[s] the context capacity in tokens used for auto-compaction calculations" so the percentage is computed against a chosen base rather than the model's full window. The override being lower-only is a documented constraint, not a bug report — `4Shark's =70 is inside that direction (below any observed default), so the clamp itself does not explain any anomaly at 4Shark`.

### Finding 2: A second, independently-reported failure mode — `settings.json`'s `env` block may not reach the app's own logic at all

**Evidence:** `code.claude.com/docs/en/settings` describes the `env` key's scope:

> "Environment variables applied to every session and to subprocesses Claude Code spawns from it. ... `NO_COLOR` and `FORCE_COLOR` set here reach only subprocesses; to change Claude Code's own interface colors, set them in your shell before launching `claude`."

Independently, GitHub issue [#63186](https://github.com/anthropics/claude-code/issues/63186) (open, filed 2026-05-28) carries four separate reproductions (`ryota-murakami`, `dalilion`, `ElliotDrel`, plus the original reporter) all describing the same shape: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` set in `settings.json`'s `env` block is visible inside a spawned Bash tool call (i.e. reaches the subprocess) but does not change when the app's own autocompact logic fires — one report states usage "reached 86% without triggering autocompact despite a 75% threshold configured in `settings.json`", and another confirms exporting the same variable as a real shell variable before launching `claude` works as expected.

**Source:** [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings), § "Available settings" / `env` (fetched 2026-08-03); [github.com/anthropics/claude-code/issues/63186](https://github.com/anthropics/claude-code/issues/63186) (fetched via `api.github.com`, 2026-08-03; full excerpts in `autocompact_sources_1.md` § 7).

**Significance:** 4Shark's local fact #2 — `printenv CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` returning `70` inside a live session, which the investigation brief correctly flags as proof of delivery, not proof of being read — matches this exact documented/reported pattern precisely. The official docs establish a *general* precedent that `env`-block variables can reach subprocesses while not reaching Claude Code's own internal logic (the `NO_COLOR`/`FORCE_COLOR` case is the documented example); the GitHub issue is a *specific, unresolved, and uncorroborated-by-a-maintainer* report that `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` itself falls into that category when set via `settings.json`. No Anthropic maintainer comment confirming or denying this appears in the issue thread as fetched. This is the strongest single candidate explanation for why 4Shark's `=70` setting, delivered exclusively through `settings.json`'s `env` block (per local fact #1), may not be doing anything to the app's own compaction trigger at all.

### Finding 3: The current Sonnet 5 default at 1M is ~96.7% of the window — a fixed proportion of the FULL 1M, not the 83%-of-200K figure the engineer recalls

**Evidence:** `code.claude.com/docs/en/model-config`, § "Sonnet 5 context window":

> "On the Anthropic API, Sonnet 5 always runs with the 1M context window. There is no 200K variant, no `[1m]` suffix to select, and no usage credits required on any plan. Sessions auto-compact before the window fills, at about 967K tokens by default; set `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to choose a different threshold."

967,000 / 1,000,000 = 96.7%.

**Source:** [code.claude.com/docs/en/model-config](https://code.claude.com/docs/en/model-config), § "Extended context" → "Sonnet 5 context window" (fetched 2026-08-03; full text in `autocompact_sources_1.md` § 3).

**Significance:** This directly answers Q2. The default is expressed by Anthropic as a **fixed token count** (~967K) on a **fixed 1M window** — for the specific case of Sonnet 5, this happens to correspond to a percentage (96.7%) because Sonnet 5 has no smaller variant, but the mechanism computing it (`CLAUDE_CODE_AUTO_COMPACT_WINDOW`, "Defaults to the model's context window, 200K for standard models or 1M for extended context models, except on Sonnet 5, which has its own default threshold") is described model-by-model, not as one universal percentage rule that scaled up automatically when the window grew from 200K to 1M. The engineer's recollection of "80% or 90%" from the 200K era is consistent with the closed community report in [#31806](https://github.com/anthropics/claude-code/issues/31806), which describes an approximately 83–93%-of-200K default computed as `effectiveWindow - 13000` (187,000/200,000 = 93.5%; the issue's own inline comment says "~83.5%", which is arithmetically inconsistent with its own formula — see the caveat in `autocompact_sources_1.md` § 5). Whichever exact 200K-era figure was correct, the current, authoritative, dated Sonnet 5 figure (96.7%) is measurably higher than either. **The default did not scale proportionally by a fixed multiplier — it changed to a different, higher proportion of the (now much larger) window.**

### Finding 4: 4Shark's setting predates the current Sonnet 5 default and was bundled with a now-removed feature

**Evidence:** Local facts #3 and #4 (given): the setting was added 2026-02-11 in commit `165eeaa` ("add auto-compaction threshold, notifications, git branch and elapsed time"), bundled with a terminal status line that was removed 2026-07-08 in commit `d4d6ba2`; the env var is the only surviving piece of that commit. Sonnet 5 requires "Claude Code v2.1.197 or later" per `code.claude.com/docs/en/model-config` (`autocompact_sources_1.md` § 3, note under "Model aliases"), i.e. a materially later Claude Code release than the February 2026 commit that introduced the setting.

**Source:** Local facts as given in the investigation brief (`~/.claude/settings.json:5`, commit `165eeaa`, commit `d4d6ba2`); [code.claude.com/docs/en/model-config](https://code.claude.com/docs/en/model-config) for the Sonnet 5 version requirement.

**Significance:** The setting's origin (February 2026) is chronologically compatible with the 200K-era default the engineer recalls, and precedes both the GA of the 1M context window and Sonnet 5's existence. The setting's *rationale* was never documented at 4Shark (local fact #5 — no `AUTOCOMPACT` mention anywhere in `CLAUDE.md`/`CHANGELOG.md`/`docs/`), so there is no 4Shark-internal record of what threshold or behavior `=70` was originally chosen to produce, or against which model/window size.

### Finding 5: Anthropic's own framing of "context rot" is architectural (attention dilution), not tied to a specific percentage-of-window figure

**Evidence:** `anthropic.com/engineering/effective-context-engineering-for-ai-agents`:

> "LLMs are based on the transformer architecture, which enables every token to attend to every other token across the entire context. This results in n² pairwise relationships for n tokens." As contexts expand, "a model's ability to capture these pairwise relationships gets stretched thin, creating a natural tension between context size and attention focus." Models "develop their attention patterns from training data distributions where shorter sequences are typically more common than longer ones."

`platform.claude.com/docs/en/build-with-claude/context-windows`:

> "As token count grows, accuracy and recall degrade, a phenomenon known as *context rot*."

**Source:** [anthropic.com/engineering/effective-context-engineering-for-ai-agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) (fetched 2026-08-03); [platform.claude.com/docs/en/build-with-claude/context-windows](https://platform.claude.com/docs/en/build-with-claude/context-windows) (fetched 2026-08-03).

**Significance:** Anthropic's own explanation of why degradation happens is a property of the transformer attention mechanism operating over a growing absolute token count (n² pairwise relationships for n tokens), not a fixed fraction of whatever window size a given model happens to ship with. This is consistent with — though it does not on its own establish a specific number for — the possibility that a percentage-of-window trigger tuned for a 200K window does not transfer unchanged to a 1M window, because the absolute token count at "70%" is a very different quantity (140K vs. 700K).

### Finding 6: Chroma's "Context Rot" study is widely cited for an absolute-token (not percentage) degradation pattern, but the specific numeric threshold could not be directly verified against the paper's own text

**Evidence:** Multiple third-party summaries (search-result snippets, not independently fetched and confirmed) describe Chroma's study — evaluating 18 frontier models across 8 input lengths — as showing degradation onset closer to an absolute token range than a fixed percentage of whatever window size is in play. A direct `WebFetch` of `trychroma.com/research/context-rot` returned only the general statement that "model performance degrades as input length increases, often in surprising and non-uniform ways," and did not surface a directly quotable sentence establishing a specific absolute-token threshold (e.g. "32K–100K").

**Source:** [trychroma.com/research/context-rot](https://www.trychroma.com/research/context-rot) (fetched 2026-08-03, direct verbatim quote not obtained for the specific numeric claim).

**Significance:** Per the citation discipline governing this spike, the specific "32K–100K absolute threshold" figure circulating in secondary sources is marked **UNVERIFIED** and does not sustain any conclusion on its own. What IS directly attributable to Chroma's own framing (via Anthropic's citation of the same "context rot" term, Finding 5) is the qualitative claim that degradation is a function of how much is asked of the model over how much context, not a clean percentage rule — but the specific numbers should not be treated as established until re-verified against the paper directly (e.g. downloading the PDF/paper rather than the marketing page).

### Finding 7: Anthropic reports the 1M-window Opus 4.6 model measurably reduces (but the record does not claim eliminates) degradation at long context, evaluated on a needle-in-haystack retrieval benchmark

**Evidence:** `anthropic.com/news/claude-opus-4-6`:

> "A common complaint about AI models is 'context rot,' where performance degrades as conversations exceed a certain number of tokens." "... on the 8-needle 1M variant of MRCR v2 ... Opus 4.6 scores 76%, whereas Sonnet 4.5 scores just 18.5%." "This is a qualitative shift in how much context a model can actually use while maintaining peak performance."

**Source:** [anthropic.com/news/claude-opus-4-6](https://www.anthropic.com/news/claude-opus-4-6) (fetched 2026-08-03).

**Significance:** This is Anthropic's own characterization of a real, measured improvement in one specific retrieval benchmark (MRCR v2, 8-needle, 1M-token variant) for Opus 4.6 relative to the 200K-window Sonnet 4.5. It is evidence that *some* current 1M-context models handle a full 1M window measurably better than earlier, smaller-window models handled their own full windows — it is NOT evidence that degradation is absent at 70%, 90%, or 96.7% of a 1M window specifically, nor is it evidence about Sonnet 5 (the benchmark cited is for Opus 4.6). No source found in this investigation states a specific percentage-of-1M-window point at which quality measurably drops for Sonnet 5.

### Finding 8: The engineer's observed "~970K tokens saved" is arithmetically consistent with the built-in ~967K default firing — NOT with a 70% (700K) trigger

**Evidence:** Combining Finding 3 (Sonnet 5 default compaction point: ~967K tokens of a 1M window) against the engineer's own local observation (a compaction event reporting "~970K tokens saved"). 967K and ~970K are within rounding/measurement distance of each other. 70% of 1,000,000 is 700,000 — a gap of roughly 270K tokens (27 percentage points) from the observed figure.

**Source:** Local fact given in the investigation brief (the engineer's observed compaction message); Finding 3 above (`code.claude.com/docs/en/model-config`).

**Significance:** No source found in this investigation documents precisely what number the Claude Code CLI's compaction-completion message reports (whether it is the size of the conversation that got summarized, the count of input tokens at the moment compaction fired, or something else) — this remains a genuine gap (see "What remains uncertain," below), and the investigation brief's instruction to not construct a theory that fits is honored: no source confirms the message's exact semantics. What CAN be stated on the sourced evidence: the ~970K figure lines up with the documented ~967K default trigger point far more closely than it lines up with a 70%/700K trigger point. Combined with Finding 2 (a specific, multiply-reported failure mode for `settings.json`-block `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` not reaching the app's own logic) and Finding 1 (the variable's existence and documented lower-only behavior), the observed number is consistent with the override having no effect on this session and Claude Code simply running its own built-in Sonnet 5 default — but this is not a maintainer-confirmed root cause, only the most closely-fitting explanation among the sourced evidence gathered here.

## Trade-offs surfaced

| Approach | What the reader gets before compaction (Sonnet 5, 1M window) | Risk on the other side | Source |
|---|---|---|---|
| **Remove the override** | Whatever Claude Code's own current default delivers — ~967K tokens (96.7%) per current docs (Finding 3) | If long-context quality genuinely degrades well before 967K on some tasks, more of the session runs in a degraded state before compaction fires; no 4Shark-specific tuning | Finding 3 |
| **Keep `=70`** | Intended: compaction at 700K (70% of 1M) — but per Finding 2/8, may not be reaching the app's logic at all when set via `settings.json`'s `env` block, in which case the actual behavior is identical to "remove the override" (967K) despite the setting being present | If it IS being honored in some code paths (Finding 1's wording, "applies to both main conversations and subagents," implies the mechanism is meant to work), 700K on 1M keeps 30% of the window permanently unused as headroom — much larger absolute headroom (300K tokens) than at 200K (60K tokens), for a benefit (avoiding some absolute degradation zone) that no source here quantifies precisely for Sonnet 5 | Findings 1, 2, 8 |
| **Keep an override, but recompute the value / switch to `CLAUDE_CODE_AUTO_COMPACT_WINDOW`** | A deliberately chosen absolute token budget (e.g. treat the window as 500K, or as some other researched figure) rather than a percentage that silently means something different at 1M than it meant at 200K | Requires deciding on a target absolute-token headroom from first principles, since no source in this investigation gives a validated absolute-token degradation threshold specifically for Sonnet 5 at 1M (Finding 6 is UNVERIFIED for its specific numbers) | Findings 1, 6 |

## What remains uncertain

- **Whether `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` set via `settings.json`'s `env` block is actually reaching Claude Code's own autocompact logic in the current, installed version.** No Anthropic maintainer confirmation exists in the one open, directly relevant issue found ([#63186](https://github.com/anthropics/claude-code/issues/63186)); the evidence is four independent community reproductions plus a documented precedent (`NO_COLOR`/`FORCE_COLOR`) for the same general class of bug, but not a maintainer statement that this specific variable is affected the same way.
- **What the Claude Code CLI's own compaction-completion message ("saved N tokens") actually measures.** Not found in any source consulted — the platform-level `compaction` API docs describe a different mechanism (server-side, an API-level `iterations` array; see the auxiliary source file § "Compaction Summary and Token Savings" excerpt) that is not confirmed to be the same code path as Claude Code CLI's own auto-compact feature. Not found: an authoritative description of the CLI-specific message's semantics.
- **Whether Sonnet 5's ~96.7% default is itself informed by a validated degradation-onset study, or is an engineering/product choice independent of a specific measured quality cliff.** No source found states the reasoning behind the 967K figure.
- **The exact absolute-token degradation-onset figure(s) from Chroma's "Context Rot" study.** Marked UNVERIFIED (Finding 6) — the specific numbers require re-verification directly against the paper (not the marketing page), which this investigation's `WebFetch` of the page did not surface in quotable form.
- **Whether a live, low-risk test (e.g., temporarily raising `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` or watching `/status`'s reported percentage against the point compaction actually fires) would settle Findings 2 and 8 directly.** Such a test was explicitly out of scope for this investigation (hard constraint: "do NOT run a live experiment that would change the session's behavior").

## Suggested options for main and the engineer

- **Option A — Remove `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` entirely.** Falls back to Claude Code's own current, actively-maintained default (~967K/96.7% for Sonnet 5, per Finding 3). Removes an undocumented (at 4Shark), possibly-inert (per Findings 2/8) setting whose original rationale was never recorded and whose bundled feature (the status line) is already gone.
- **Option B — Keep `=70` as-is.** Preserves the original intent (compact earlier, at 70% rather than Anthropic's default) IF the setting is in fact reaching the app's logic — which Finding 2/8's evidence casts specific doubt on for a `settings.json`-block delivery. If it turns out inert, this option is behaviorally identical to Option A while still carrying an undocumented, unexplained line in shared config.
- **Option C — Keep an override, but re-derive the target and/or switch mechanism.** Decide a deliberate absolute-token headroom for Sonnet 5 sessions (rather than reusing a percentage figure carried over from the 200K era), and set it via `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (which the current docs describe as decoupling the compaction threshold from a percentage of the model's raw window — Finding 1) or a recalculated `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` value, with the choice and its rationale documented in 4Shark's own docs (closing the gap in local fact #5).
- Before choosing among these, resolving the two open uncertainties above (whether the `settings.json`-block delivery path works at all for this variable, and what the observed "saved N tokens" message actually measures) would remove the single largest source of doubt in this analysis — a direct, low-risk way to settle it is a `/status` check against actual compaction firing point, which was out of scope for this research-only spike.
