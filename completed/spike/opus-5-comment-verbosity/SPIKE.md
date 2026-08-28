# SPIKE: Opus 5 comment verbosity, and why the default model is pinned to Opus 4.8

## Question

Comment volume in agent-generated code rose sharply "about a month ago." The engineer's claim: the change tracked the switch to Opus 5, not any 4Shark configuration change, and no rule, hook, or prompt written since has reduced it. Is that true, and what is the correct remediation?

## Outcome

Confirmed. The behavior change tracks the Opus 5 release, is documented by Anthropic itself, and is not reachable by written rules. The default model was pinned to `claude-opus-4-8` in the shared `settings.json` (dot-claude PR #576, merged), which is the remediation the community converges on for code work. This spike is the rationale behind that `model` key.

## Findings

### F1 — The behavior change tracks the Opus 5 release date

Opus 5 was released **2026-07-24** (Anthropic announcement; corroborated by Axios, TechCrunch, Fortune). The engineer's "about a month ago" matches. The comment problem predates it — anthropics/claude-code#61305 is 2026-05-21 and #65961 is 2026-06-07 — but what appears from 2026-07-24 onward is a distinct wave of reports that **name Opus 5** and describe regression against a configuration that already worked.

### F2 — Anthropic documents the longer output as a property of the model

The official prompting guide for Opus 5 (platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5), § Response length and verbosity:

> "Claude Opus 5's default user-facing responses run longer than prior Opus models'. The effort parameter controls how much the model thinks rather than how much it says: lowering effort can reduce thinking volume without reliably shortening the visible response. To control response length, prompt for it explicitly."

A separate section, § Written deliverable length, covers files written to disk (the category nearest the comment problem):

> "Separate from conversational verbosity, files that Claude Opus 5 writes to disk (reports, Markdown documents, summaries) are often longer than on prior models."

The guide has sections for response verbosity, progress narration, document length, scope, subagents, and self-correction. It carries **no** section, instruction, or example about comments inside code.

### F3 — The community named the exact defect: "Verbose comment replacement"

r/ClaudeAI thread "My Opus 5 experience in a nutshell" (2026-08-06), analyzed by explainx.ai (2026-08-07):

> Users reported "Verbose comment replacement" where short, precise code annotations were silently swapped out for lengthy paragraph-length explanations without being flagged in diffs or requested.

Same thread, adjacent patterns: "paranoid, over-engineering mess" / "insufferable"; "Self-generated briefs, then over-execution"; "Unsolicited artifacts."

### F4 — CodeRabbit measured it on the release day, isolating the model

CodeRabbit ran Opus 5 as a code reviewer against the same pull requests as the prior model, changing only the model (coderabbit.ai/blog/opus-5-model-review, 2026-07-24):

| metric | Opus 5 | baseline (Opus 4.8) |
|---|---|---|
| nitpicks generated | 92 | 23 |
| precision, full post-pipeline stream | 28.6% | 32.8% |

> "Opus 5 reads about 50% more and writes about 65% more than the frontier models" […] "generated roughly four times as many nitpicks" […] "Opus 4.8 remains the family's balanced option for code review."

This is the only comparative measurement of code-review output volume between the two models found in the research.

### F5 — Written rules do not reach it (three independent reports)

- **#87209** "[MODEL] Opus 5 Over Verbose Output" (2026-08-16, closed completed). Reporter had a custom output style with `keep-coding-instructions: true` and the rule `"Do not add comments explaining obvious lines."` The model, per the reporter, "just says that this is it's 'bias' and there's nothing i can do about it."
- **#89244** "[MODEL] Rules that constrain or halt work stop binding, while rules that expand work continue to bind" (2026-08-24). "The configuration is not new and was not changed. It had been in place and working reliably for a long time. What changed is whether the model acts on it." The title is the general shape: rules that restrict stop binding, rules that expand keep binding. Commenting more expands; not commenting restricts.
- **#85105** "Opus 5 in Claude Code: the model can author a rule, recall it verbatim, cite it by name mid-violation, and still not apply it" (2026-08-08). This is why writing more rule did not help: the failure is not knowledge of the rule.
- **#86176** "Recent versions of Claude are extremely verbose, and requests to fix this in CLAUDE.ms and hooks are ignored" (2026-08-12).

### F6 — The two remediation fields, and why field 1 was chosen

The community split into two camps, not one. **There is no published poll or telemetry** apportioning the split — any percentage would be invented. What exists is direction, not proportion.

- **Field 1 — switch the model.** CodeRabbit keeps Opus 4.8 as the code-review default; mindstudio.ai (2026-08-01) records users who "reverted to Opus 4.8 specifically because it 'feels way better'"; botmonster (2026-08-22): "Roll back to Opus 4.8 […] Plenty of people are taking that deal anyway."
- **Field 2 — keep Opus 5, constrain its output.** Six dedicated articles in ~3 weeks (reporails, hjerpbakk, stork.ai, botmonster, modemguides, explainx). The primary tool is the built-in `Concise` output style, shipped in Claude Code 2.1.237 (2026-08-20), whose announcement crossed 500k views in hours. hjerpbakk measured it: 663 words default → 330 words Concise, on the same task.

**Why field 1 for 4Shark specifically** — two facts decided it, neither of them popularity:

1. **`Concise` does not reach comments.** explainx.ai (2026-08-20): "It changes the default verbosity of response prose—not code comments or the underlying reasoning process. […] It's a presentation layer change, not a content filter." The whole field 2 toolset shortens the chat reply, not the comment in the file — which is the reported problem.
2. **The installed CLI is 2.1.231**, and `Concise` needs 2.1.237+. The tool does not exist on the machine without a CLI update.

### F7 — Cost: identical rate card, and the "2x tokens" claim is unsourced

Both models bill at $5 / 1M input and $25 / 1M output (Fast Mode $10/$50, Batch $2.50/$12.50). Opus 5 runs thinking on by default and thinking bills at the output rate, which Opus 4.8 did not — so the direction favors the 4.8 pin on invoice, as reasoning from configuration, not measurement. The widely repeated "Opus 5 spends ~2x the output tokens" claim does not survive its own source: layer3labs.io states "Anthropic does not publish a per-task token count for either model, and neither does anyone else. […] any site that gives you an exact number for a task like yours made it up." No field is "much more expensive" by the rate card.

### F8 — The false trails, recorded so they are not re-run

Two diagnoses were pursued and disproved before F1–F7 settled it:

- **"The neighbouring files are the fuel."** Hypothesis: the harness instruction "Write code that reads like the surrounding code: match its comment density" was reading dense 4Shark files and matching them. Measured and **false** — the business codebase is near-comment-free: `app` 0.79%, `integrator` 0.78%, `app-webclient` 0.55% comment density. Only `dot-claude/scripts` is dense (40.5%), and that is the agent's own output. There is no verbose neighbour to match, and the comments still appear.
- **"The short system prompt is the cause."** The installed bundle (`~/.local/share/claude/versions/2.1.231`) carries two comment sentences and a `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT`-gated branch that returns only the first (density). Setting the env var to `0` routes to the long variant, which adds the sentence restricting what a comment may say. This was the first PR #576 draft. Dropped because F2–F5 show the behavior is the model, not a truncated prompt: reports with the anti-comment rule present in the strongest channel (#87209) still fail.

## Anthropic's own migration guidance — an adjacent finding

The Opus 5 guide, § Task scope and over-verification and § Self-correction, prescribes **removing** verification instructions and legacy harness scaffolding:

> "If your prompt contains explicit verification instructions […] remove them: instructions like these cause over-verification on Claude Opus 5, and removing them reduces wasted tokens with no loss in quality. The same applies to legacy harness scaffolding that adds separate verification steps."

4Shark's `CLAUDE.md` carries three verifier agents (`output-verifier`, `policy-verifier`, `code-policy-verifier`) and a mandatory-verification-after-every-subagent section. By Anthropic's guidance this scaffolding now costs tokens without improving results on Opus 5. This is a candidate for a follow-up review, independent of the model pin, and applies whichever model is default. Two of Anthropic's recommended instructions — the scope instruction and the correction instruction — already exist near-verbatim in `CLAUDE.md` and are correct as they stand.

## Decision

`"model": "claude-opus-4-8"` set in the shared `settings.json` (dot-claude PR #576, merged). Reversible in one line: remove the key and the picker's default returns. An output-style change is read once at session start, so the pin applies from the next session or after `/clear`.

## Sources

- Anthropic — [Prompting Claude Opus 5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5) (read in full) · [Introducing Claude Opus 5](https://www.anthropic.com/news/claude-opus-5)
- CodeRabbit — [Opus 5 code-review benchmark](https://www.coderabbit.ai/blog/opus-5-model-review) (2026-07-24)
- explainx.ai — [Reddit reaction](https://www.explainx.ai/blog/opus-5-over-engineering-reddit-reaction-august-2026) · [Concise output style](https://www.explainx.ai/blog/claude-code-concise-output-style-config-august-2026)
- mindstudio.ai — [mixed reception](https://www.mindstudio.ai/blog/claude-opus-5-mixed-reception) · hjerpbakk — [two ways to make Opus 5 concise](https://hjerpbakk.com/blog/2026/08/20/making-opus-5-concise) · botmonster — [make Opus 5 less verbose](https://botmonster.com/ai/make-opus-5-less-verbose/) · layer3labs — [token usage](https://www.layer3labs.io/comparisons/claude-opus-5-token-usage-vs-opus-4-8)
- anthropics/claude-code — [#87209](https://github.com/anthropics/claude-code/issues/87209) · [#89244](https://github.com/anthropics/claude-code/issues/89244) · [#85105](https://github.com/anthropics/claude-code/issues/85105) · [#86176](https://github.com/anthropics/claude-code/issues/86176) · [#82032](https://github.com/anthropics/claude-code/issues/82032) · [#65961](https://github.com/anthropics/claude-code/issues/65961)
- Installed bundle inspection (`~/.local/share/claude/versions/2.1.231`, `strings`) and local comment-density measurement — first-hand observation, not web
