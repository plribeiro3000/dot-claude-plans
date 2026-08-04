# Auxiliary source material — CLAUDE_AUTOCOMPACT_PCT_OVERRIDE at 1M context

Raw excerpts preserved verbatim from fetched sources, for revision without re-fetching.

## 1. Official env-vars reference — `code.claude.com/docs/en/env-vars`

Fetched 2026-08-03.

### `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`

> `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Set the percentage (1-100) of the auto-compaction window at which auto-compaction triggers. Use lower values like `50` to compact earlier. This variable only causes earlier compaction when Claude Code compacts proactively: when `CLAUDE_CODE_AUTO_COMPACT_WINDOW` is set, in cloud sessions, and on Sonnet 4.6 and Opus 4.6 without extended context, which compact at the 200K boundary by default. On Sonnet 5, proactive compaction applies at the model's default threshold. In other cases, such as a local session on Opus 4.8, auto-compaction triggers when the conversation reaches the model's context limit. The override can only lower the threshold, so values above the default have no effect. Applies to both main conversations and subagents

### `CLAUDE_CODE_AUTO_COMPACT_WINDOW`

> `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Set the context capacity in tokens used for auto-compaction calculations. Defaults to the model's context window, 200K for standard models or 1M for extended context models, except on Sonnet 5, which has its own default threshold. Use a lower value like `500000` on a 1M model to treat the window as 500K for compaction purposes. The value is capped at the model's actual context window. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is applied as a percentage of this value. Setting this variable decouples the compaction threshold from the status line's `used_percentage`, which always uses the model's full context window

## 2. Official settings reference — `code.claude.com/docs/en/settings`

### `autoCompactEnabled`

> `autoCompactEnabled` — Default: `true`. Automatically compact the conversation when context approaches the limit. Appears in `/config` as **Auto-compact**. To disable via environment variable, set `DISABLE_AUTO_COMPACT` in `env`

### `env` key scope

> Environment variables applied to every session and to subprocesses Claude Code spawns from it. Set a variable to `""` to override a shell export with an empty string, which Claude Code treats as unset for provider selection. Subprocesses still inherit the empty value. `NO_COLOR` and `FORCE_COLOR` set here reach only subprocesses; to change Claude Code's own interface colors, set them in your shell before launching `claude`.

This is the documented precedent for a category of `env`-block variables that reach spawned subprocesses but do NOT reach Claude Code's own internal application logic (interface colors, in the documented case).

## 3. Official model-config reference — `code.claude.com/docs/en/model-config`

### Extended context (1M window availability)

> Fable 5, Sonnet 5, Opus 4.6 and later, and Sonnet 4.6 support a 1 million token context window for long sessions with large codebases.
>
> Availability varies by model and plan. On the Anthropic API, Fable 5, Sonnet 5, and Opus 4.7 and later always run with the 1M window.

### Sonnet 5 context window (§ "Sonnet 5 context window")

> On the Anthropic API, Sonnet 5 always runs with the 1M context window. There is no 200K variant, no `[1m]` suffix to select, and no usage credits required on any plan. Sessions auto-compact before the window fills, at about 967K tokens by default; set `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to choose a different threshold.
>
> Two configurations budget the window at 200K instead and auto-compact at that boundary:
> - **LLM gateway**: when `ANTHROPIC_BASE_URL` points at a gateway, Claude Code can't verify 1M support...
> - **`CLAUDE_CODE_DISABLE_1M_CONTEXT=1`**: treats Sonnet 5 sessions as having a 200K window...

967,000 / 1,000,000 = **96.7%** of the window — this is the current default proactive-compaction threshold for Sonnet 5 sessions on the Anthropic API.

## 4. Official context-windows reference — `platform.claude.com/docs/en/build-with-claude/context-windows`

> As token count grows, accuracy and recall degrade, a phenomenon known as *context rot*. This makes curating what's in context just as important as how much space is available.

> Claude Sonnet 5, Claude Sonnet 4.6, Claude Sonnet 4.5, and Claude Haiku 4.5 have **context awareness**: these models track their remaining context window (their "token budget") throughout a conversation... The budget matches the context window available to your request: 1M tokens for Claude Sonnet 5 and Claude Sonnet 4.6, and 200k tokens for Claude Sonnet 4.5 and Claude Haiku 4.5.

## 5. GitHub issue #31806 (closed) — raw body via `api.github.com`

Title: "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE cannot raise threshold above default (~83%)"
State: closed. Created: 2026-03-07.

> `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` is documented as allowing users to control when auto-compaction triggers, but it can only **lower** the threshold below the default — never raise it. Setting it to `95` (meaning "compact at 95% usage") has no effect because of a `Math.min` clamp in the threshold calculation.
>
> ```javascript
> function getAutoCompactThreshold(model) {
>   let effectiveWindow = getEffectiveWindow(model);
>   let defaultThreshold = effectiveWindow - 13000;     // ~83.5% of 200k
>   let override = process.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE;
>   if (override) {
>     let pct = parseFloat(override);
>     if (!isNaN(pct) && pct > 0 && pct <= 100) {
>       let userThreshold = Math.floor(effectiveWindow * (pct / 100));
>       return Math.min(userThreshold, defaultThreshold);
>     }
>   }
>   return defaultThreshold;
> }
> ```

Note: this deobfuscated snippet describes behavior from March 2026, on a 200K-window model. `effectiveWindow - 13000` on a 200,000-token window is 187,000, i.e. 93.5% — not the "~83.5%" the issue's own inline comment states. The arithmetic in the issue body is internally inconsistent, and the snippet is a community member's reverse-engineered reconstruction, not Anthropic source code. Treated as a directional community data point (override cannot exceed a built-in default), NOT as an authoritative percentage figure. The current authoritative figure for Sonnet 5 (967K/1M = 96.7%) comes from source #3 above, dated to the current docs snapshot, and clearly is a different (higher) percentage than this issue's 200K-era report — consistent with the default having changed rather than the issue's own math being right.

## 6. GitHub issue #36381 (closed) — raw body via `api.github.com`

Title: "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE not triggering at configured threshold"
State: closed. Created: 2026-03-19.

> `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=55` is set as an environment variable but auto-compaction does not trigger at 55% context usage. The main session regularly exceeds the configured threshold without compacting — observed at 67% in one session and over 80% in another before compaction finally occurred.
>
> Environment: Claude Code version 2.1.79, Claude Opus 4.6 (Max plan), macOS.

## 7. GitHub issue #63186 (OPEN) — raw body + comments via `api.github.com`

Title: "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE in settings.json env block silently ignored by autocompact logic"
State: **open**. Created: 2026-05-28.

Body summary (fetched, not a direct field quote — see caveat below): setting `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` in the `env` section of `~/.claude/settings.json` fails to affect the application's autocompact threshold, while the same variable successfully reaches subprocess tools like Bash when invoked. Reporter observed context reaching 86% without triggering autocompact despite a 75% threshold configured in `settings.json`. Exporting the variable as a shell environment variable before launching Claude Code worked as expected.

Comments (5 total, no maintainer reply present in the thread as fetched):
- `ryota-murakami`: reproducible on v2.1.156/macOS/Opus 4.8 — variable appears in subprocess calls but the app's autocompact logic ignores it, evaluated against the 1M context window.
- `dalilion`: reproducible on 2.1.178 inside an IDE extension — variable present in process env (a Bash tool call echoes it correctly) but autocompact logic ignores it; suggests a first-class `autoCompactThresholdPercent` settings key.
- `AgainPsychoX`: general comment about long-standing issues being silently closed rather than fixed (references issue #53801, not independently verified here).
- `ElliotDrel`: confirms on v2.1.187 — variable reaches the subprocess/echoes in tool calls but autocompact logic never acts on it; notes `CLAUDE_CODE_AUTO_COMPACT_WINDOW` works as a workaround.

**Caveat**: this issue's body and comments were retrieved via `api.github.com` but summarized by the fetch tool rather than returned as an exact field dump (unlike #31806 and #36381, which came back as literal `body` field text). Treat the paraphrased portions as directionally reliable community reports, not verbatim quotes.

## 8. Chroma "Context Rot" research — `trychroma.com/research/context-rot`

Direct WebFetch of the paper's own page did not surface an explicit statement of a specific absolute-token degradation-onset threshold (e.g. "32K–100K") in a form quotable per the citation discipline — the direct fetch returned only: "model performance degrades as input length increases, often in surprising and non-uniform ways" and confirmed 18 frontier models were tested across 8 input lengths. The "32K to 100K absolute threshold, not a percentage" framing appeared only in third-party summary articles (search snippets), not in a directly quotable sentence from the source paper itself as fetched. **This specific numeric claim is UNVERIFIED per citation discipline** and is not used as a sustaining Finding in SPIKE.md; it is reported as a signal from secondary sources only.

## 9. Anthropic Opus 4.6 announcement — `anthropic.com/news/claude-opus-4-6`

> A common complaint about AI models is 'context rot,' where performance degrades as conversations exceed a certain number of tokens.

> Opus 4.6 features a 1M token context window in beta.

> ...on the 8-needle 1M variant of MRCR v2 ... Opus 4.6 scores 76%, whereas Sonnet 4.5 scores just 18.5%.

> This is a qualitative shift in how much context a model can actually use while maintaining peak performance.
