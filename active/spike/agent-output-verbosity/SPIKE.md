# SPIKE — Agent Output Verbosity vs. Parallel-Session Supervision

> **Revision note (round 2):** the engineer identified an analytical error in round 1's Findings 9 and 10 (now corrected below as Findings 14–16) and in the Option B derived from them. Round 1 assumed a static-document reading model (BLUF: the reader's eye lands at the top) without checking whether that assumption holds in a streaming, auto-scrolling chat interface, where the reader's resting position is the bottom. This revision investigates that correction directly (new Findings 17–20), corrects the two over-reaching findings rather than silently rewriting them, splits every round-1 Finding that had grouped multiple sources under one citation (round-1 Findings 3, 5, and 12 are now Findings 3–7, 10–11, and unchanged-but-relabeled respectively), and re-derives the Options section accordingly. Nothing in Findings 1–2, 8–9, 12–13 changed in substance from round 1.
>
> **Revision note (round 3):** the engineer determined the fixed-position-surface option is not viable (the status line payload carries no session-state field, and 4Shark had already deliberately removed its own terminal status line). The findings and option built on that surface — dashboard/agent-view (old Finding 14) and status line/`subagentStatusLine` (old Finding 22) — are removed, along with the options and trade-off rows sustained only by them. Every remaining finding renumbers to a contiguous 1–21 range; every cross-reference below is repaired to the new numbers. No new research was performed for this pass.
>
> **Revision note (round 4):** the engineer requested investigation of exactly two open questions left by round 3, both scoped narrowly and neither reopening any settled finding. **Gap 1 (custom output styles as a brevity mechanism):** how a custom output style actually reaches the model (replace vs. append to the system prompt), whether it is a structurally stronger, equal, or weaker enforcement tier than a CLAUDE.md rule, whether any evidence exists of a custom output style measurably reducing verbosity where a CLAUDE.md rule failed, and any documented interaction/precedence between an output style and a large CLAUDE.md corpus. New Findings 22–26. **Gap 2 (has the hook surface changed since the last fetch):** a fresh, targeted re-fetch of the hooks reference for any hook event, field, or capability — new or previously missed — that can gate, reshape, inspect, or block the assistant's own response text before the human sees it, specifically including `Stop`, `SubagentStop`, and `PreCompact`, plus a changelog/issue-tracker check for anything shipped or announced on this axis. New Findings 27–31, one of which (Finding 27) surfaces `MessageDisplay` as a real, already-shipped hook event this spike's round 1 did not find — the round 2/3 "What remains uncertain" bullet that speculatively named `MessageDisplay` as a hypothetical future capability is corrected below, explicitly and visibly, not silently. Round 4 did NOT re-investigate summary placement (top vs. bottom — settled in Findings 14–20), did NOT re-investigate whether the community names the general problem (Findings 3–7), did NOT re-investigate the verbosity-increase timing claim (Findings 8–11, still inconclusive and left as-is), and did NOT investigate dashboards or fixed-position status surfaces (closed by the engineer in round 3). Every finding from rounds 1–3 stands unchanged except where explicitly marked corrected below.

## Investigation question

How is the coding-agent community (Claude Code in particular, but not exclusively) solving the problem of agent output volume overwhelming the human operator — specifically when that operator is running many parallel agent sessions and cannot read everything each one produces?

The engineer's framing, verbatim:

> "nas últimas semanas você aumentou e muito o volume de texto que gera e não dá para acompanhar e ler tudo quando se está trabalhando em 7 frentes ao mesmo tempo."

> "eu penso que uma forma de resolver isso seria uma regra/hook que garanta que sempre que você terminar de racionalizar, você sempre imprima um marcador separando e depois um último parágrafo sucinto"

And, in round 2, the engineer's correction of round 1's analysis:

> "nao é assim que funciona, conforme voce vai escrevendo a tela vai descendo junto a nao ser que eu deixe parado no topo. entao o padrao ja é eu estar no final de um texto enorme e voce ta sugerindo me obrigar a subir todo o texto para ler o resumo para depois ignorar o resto?"

Five sub-questions were investigated in order: (1) does the community name this failure mode, and is the recent-verbosity-increase claim corroborated; (2) what solutions does the community actually use; (3) is the engineer's specific hypothesis (a hook-enforced marker + terse final paragraph) mechanically viable; (4) what does 4Shark's existing Output Policy already cover; (5) — added in round 2 — what MEDIUM is each cited source actually talking about, and does the streaming/auto-scroll behavior of a chat interface change which end of a response the reader's eye actually rests on. Round 4 added two narrowly-scoped follow-ups: (6) is a custom output style a structurally different enforcement tier from a CLAUDE.md rule; (7) has the documented hook surface changed, or was anything missed, regarding gating the assistant's own response text.

## Sources consulted

- [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) — whether any hook can modify/append to Claude's own response text
- [github.com/anthropics/claude-code#2880](https://github.com/anthropics/claude-code/issues/2880) — a feature request asking for exactly the engineer's enforcement shape, closed "not planned"
- [github.com/anthropics/claude-code#29769](https://github.com/anthropics/claude-code/issues/29769) — verbosity complaint: Claude doubles down on over-explaining when corrected
- [github.com/anthropics/claude-code#65961](https://github.com/anthropics/claude-code/issues/65961) — verbose code comments resist CLAUDE.md instruction (via WebSearch synthesis, not fully WebFetched)
- [github.com/anthropics/claude-code#33414](https://github.com/anthropics/claude-code/issues/33414) — "FireHose" as an isolated proposed term for high-volume agent output
- [github.com/yzhao062/agent-style](https://github.com/yzhao062/agent-style) — community style-guide rules against mechanical AI-tell patterns, including repeated paragraph-closing summaries
- [code.claude.com/docs/en/output-styles](https://code.claude.com/docs/en/output-styles) — built-in output styles; none ships to make Default more concise; re-fetched in round 4 for the system-prompt mechanism and the CLAUDE.md comparison table
- [tomrochette.com/managing-many-llm-agent-sessions](https://tomrochette.com/managing-many-llm-agent-sessions/) — cognitive-load framing of the multi-session bottleneck; re-fetched in round 2 to determine the medium of its "lead with the summary" advice
- [shiplight.ai/blog/human-qa-bottleneck-agent-first-teams](https://www.shiplight.ai/blog/human-qa-bottleneck-agent-first-teams) — "our bottleneck became human QA capacity" (OpenAI eng team, secondhand)
- [superset.sh/blog/parallel-coding-agents-guide](https://superset.sh/blog/parallel-coding-agents-guide) — practical parallel-agent limits and review-throughput math
- [shashi.co — "The Oversight Tax"](https://www.shashi.co/2026/04/the-oversight-tax-why-ai-agents-are-not.html) — named essay framing of sustained-supervision burden
- [dbreunig.com — "How Claude Code Builds a System Prompt"](https://www.dbreunig.com/2026/04/04/how-claude-code-builds-a-system-prompt.html) — third-party reverse-engineering of Claude Code's own built-in conciseness instructions
- [awesomeagents.ai — Claude Sonnet 5 review](https://awesomeagents.ai/reviews/review-claude-sonnet-5/) and [medium.com/@reliabledataengineering — Opus 4.6 vs 4.5](https://medium.com/@reliabledataengineering/claude-opus-4-6-vs-4-5-what-actually-changed-and-whether-you-should-upgrade-ff46550e8a75) — secondhand, unverified-methodology verbosity comparisons
- [github.com/anthropics/claude-code#37627](https://github.com/anthropics/claude-code/issues/37627) — round 2: terminal auto-scroll-to-bottom bug report
- [github.com/anthropics/claude-code#53382](https://github.com/anthropics/claude-code/issues/53382) — round 2: desktop app auto-scroll-to-bottom regression, describes "sticky bottom" as the expected pattern
- [ui.shadcn.com/docs/components/radix/message-scroller](https://ui.shadcn.com/docs/components/radix/message-scroller) — round 2: "sticky bottom" / "live edge" as a named, general chat-UI pattern
- [bitesizelearning.co.uk/resources/bluf-bottom-line-up-front](https://www.bitesizelearning.co.uk/resources/bluf-bottom-line-up-front) — round 2: BLUF's only found application to "chat" scopes to authoring the first outgoing message
- [github.com/drona23/claude-token-efficient — benchmark/SUMMARY.md](https://github.com/drona23/claude-token-efficient/blob/main/benchmark/SUMMARY.md) — round 4: the only disclosed-methodology token/verbosity benchmark located; tests two CLAUDE.md formulations, not output style vs. CLAUDE.md; also used to check and reject a specific "Caveman style" superiority claim
- [news.ycombinator.com/item?id=47581701](https://news.ycombinator.com/item?id=47581701) — round 4: informal community commentary on CLAUDE.md-based verbosity-reduction effectiveness
- [dev.classmethod.jp — "Claude Code v2.1.152 Major Updates"](https://dev.classmethod.jp/en/articles/20260524-claude-code-updates-v2-1-152/) — round 4: secondary source for `MessageDisplay`'s shipped version/date
- [raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md) — round 4: direct fetch attempted; did not surface a `MessageDisplay` entry in the portion returned (file too large for a single reliable pass — see auxiliary)
- Local: `~/.claude/CLAUDE.md` § Output Policy (all five layers), `~/.claude/docs/DECISION-SURFACING.md`, `~/.claude/scripts/inject-output-policy-reminder.sh`, `~/.claude/settings.json` — the existing 4Shark mechanism, read in full before concluding
- See auxiliary: `agent-output-verbosity_sources_1.md` — every quote above, with fetch method and reliability caveats, preserved for revision without re-fetching (round 2 additions appended under "Revision round 2"; round 3 made no new fetches, so the auxiliary file's own entry numbering is unchanged, including entries that sustained a now-removed finding; round 4 additions appended under "Revision round 4")

## Findings

### Finding 1: No hook can modify or append to the assistant's own generated response text — additionalContext is next-turn only

**Evidence:** Per the Claude Code hooks reference: *"Stop — Can output: additionalContext, decision: 'block', reason, systemMessage, continue: false. Cannot do: Modify Claude's actual response text. Effect: additionalContext is injected as a system reminder that Claude sees on the next turn, not appended to the current message."* And: *"The additionalContext field passes a string from your hook into Claude's context window. Claude Code wraps the string in a system reminder and inserts it into the conversation at the point where the hook fired. Claude reads the reminder on the next model request, but it doesn't appear as a chat message in the interface."*

**Source:** [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)

**Significance:** This is the load-bearing fact for sub-question 3, and it is **unaffected by the round-2 correction**. The engineer's hypothesized mechanism — "a hook that guarantees that whenever you finish rationalizing, you print a marker + a final terse paragraph" — cannot be built as a hook that edits or appends to the current turn's message text, because no hook event exposes that capability, regardless of whether the marker+summary should sit at the top or the bottom of the response. The closest available levers are (a) `Stop` returning `decision: "block"` to force Claude to continue generating (i.e., produce another turn, not edit the one just emitted) and (b) `additionalContext`, which reaches Claude only on the *next* model request.

**CORRECTION (round 5, 2026-07-16):** the sentence that originally closed this Finding — *"Both are prompt-level nudges the model can still ignore, not text-level enforcement"* — is **wrong about lever (a), and the error was consequential**: it is the sentence that let every later round treat the whole problem as unsolvable, and it propagated verbatim into `CLAUDE.md` § Output Policy Layer 5 as *"there is no mechanical backstop, by construction"*. A `Stop` block is **not** a nudge the model can ignore: verbatim, from [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) § "Stop decision control", *"When you block a `Stop` event, Claude receives your reason as a system reminder and continues working in the same turn."* The turn does not close. The model can write a bad summary; it cannot decline to be asked, and it cannot end the turn through the block. That is a strictly stronger enforcement tier than `additionalContext` (lever b), which this Finding correctly characterized and then wrongly lumped together with lever (a).

The correction is narrow and does not rescue the engineer's original hypothesis as stated: **the premise of this Finding still holds** — no hook edits or appends to the emitted text, so a hook cannot *write* the marker+paragraph. What a `Stop` block buys is forcing the model to produce it in a continuation of the same turn. Enforcement of *existence*, not of *content*, and not by text manipulation. The loop constraint is documented in the same section: *"If you block unconditionally without checking `stop_hook_active`, Claude will loop forever."*

Acted on: `scripts/validate-closing-summary.sh` (Stop) now gates the Layer 5 rules on this mechanism.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at code.claude.com/docs/en/hooks § "Stop decision control" and § Stop input (`stop_hook_active`), direct WebFetch 2026-07-16. **Round 4 note:** this Finding's claim about the transcript and Claude's own view of its output stands unmodified — see Finding 27 for a narrower, previously-missed exception that applies only to the human-facing on-screen render, not the transcript.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via WebFetch direct retrieval of code.claude.com/docs/en/hooks, cross-consistent with 4Shark's own independently-authored Layer 0 rule.

---

### Finding 2: Anthropic was asked for close to this exact mechanism and declined it

**Evidence:** GitHub issue #2880, "Feature Request: Support summarizing work done after Stop hook?": *"Stop hooks are super useful but their output and subsequent Claude interactions can cause a lot of spam from the nice summary message Claude gave right before the Stop initiated. It would be nice to have Claude not provide the summary message until the Stop hooks succeed."* The issue is closed, labeled `autoclose` / not-planned, with no visible maintainer comment explaining the decision.

**Source:** [github.com/anthropics/claude-code/issues/2880](https://github.com/anthropics/claude-code/issues/2880)

**Significance:** This is not identical to the engineer's proposal (it is about *timing* the summary relative to Stop-hook completion, not about a marker-then-terse-paragraph *shape*), but it is the closest matching feature request found, and it was explicitly declined. Combined with Finding 1, there is no evidence Anthropic has built, or intends to build, any Stop-hook-adjacent mechanism for reshaping or gating a turn's own text.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the issue body, per WebFetch.

---

### Finding 3: "Firehose" appears in exactly one place and is not corroborated as an adopted community term

**Evidence:** A single Claude Code feature request (#33414) proposes a *separate output channel* for high-volume internal reasoning, framed as solving *"insufficient thinking"* visibility, not operator overload: *"As Claude works for longer and uses more tools, presenting the information inline has the potential to swamp other data."* And: *"This output would be possibly extremely high volume, but that fact is indicated by the name Firehose. What users do with that output is up to them."*

**Source:** [github.com/anthropics/claude-code/issues/33414](https://github.com/anthropics/claude-code/issues/33414)

**Significance:** "Firehose" is a proposed feature name in one GitHub issue, not established elsewhere in this research as an adopted community term for the verbosity-overwhelms-the-operator problem.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 4: "The Oversight Tax" is a named essay title scoped to single-agent supervision burden, not multi-agent parallelism

**Evidence:** *"the human is still in the loop. The loop just got longer, less predictable, and harder to step away from."*

**Source:** [shashi.co — "The Oversight Tax: Why AI Agents Are Not the Delegation Win Companies Expected"](https://www.shashi.co/2026/04/the-oversight-tax-why-ai-agents-are-not.html)

**Significance:** A real, named essay framing of sustained-supervision burden, but it does not address multi-agent parallelism or output volume specifically — it is about the persistence of human oversight obligation on a single delegated agent.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 5: "Human QA Bottleneck" is a blog-title framing, quoting an OpenAI engineering-team claim

**Evidence:** *"As code throughput increased, our bottleneck became human QA capacity."* (attributed to an OpenAI engineering team)

**Source:** [shiplight.ai — "The Human QA Bottleneck in Agent-First Teams"](https://www.shiplight.ai/blog/human-qa-bottleneck-agent-first-teams)

**Significance:** Another distinct, real but narrow naming — this one framed around code-review throughput specifically, not output volume/verbosity per se.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 6: tomrochette.com frames the multi-session problem through cognitive-psychology vocabulary rather than a single coined term

**Evidence:** *"When one person can spawn a dozen LLM agent sessions in parallel, the bottleneck is no longer the agents. It is the human trying to keep track of them all."* And: *"With multiple agent sessions running concurrently, many are perpetually unfinished, creating a constant background hum of attention residue."*

**Source:** [tomrochette.com/managing-many-llm-agent-sessions](https://tomrochette.com/managing-many-llm-agent-sessions/)

**Significance:** This source discusses the problem at length (working memory limits, the Zeigarnik effect, decision fatigue) without coining or adopting a single term for it.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 7: A candidate term surfaced by an initial search — "AI Brain Fry" — was checked directly and is absent from its cited source

**Evidence:** An initial WebSearch synthesis attributed the term "AI Brain Fry" to Harvard Business Review via a specific article. Direct WebFetch of that article's full text, searching specifically for the term and any HBR attribution, found neither present anywhere in the text. The article's actual relevant content is: *"the human must allocate attention across competing machine initiatives, resolve ambiguity, validate uncertain outputs, and absorb a continuous stream of alerts."*

**Source:** [medium.com/@maxdolphin — "Human Oversight Under Load in the Age of AI Agents"](https://medium.com/@maxdolphin/human-oversight-under-load-in-the-age-of-ai-agents-e943b6e6720d)

**Significance:** This candidate term is explicitly rejected per Citation Discipline rule 3 (no invented term attributions). Recorded to document the check was performed, not to sustain any claim.

**Verification:** URL fetched / Verbatim quote checked / Term searched for and confirmed absent at the full article text via direct WebFetch.

---

### Finding 8: Multiple independent Claude Code GitHub issues corroborate a verbosity complaint pattern

**Evidence:** Issue #29769 (over-explaining, doubling down when corrected): *"The pattern: when the user asks obvious questions, and especially when they signal that they have received unclear answers, Claude doubles down on verbosity and context-dumping instead of answering the question."*

**Source:** [github.com/anthropics/claude-code/issues/29769](https://github.com/anthropics/claude-code/issues/29769)

**Significance:** Corroborates that verbosity complaints against Claude Code are a live, recurring category of issue. This is not a system-level Anthropic acknowledgment of a *specific, dated* verbosity regression — the evidence is a user-reported complaint, not a confirmed root-caused change on Anthropic's side.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the issue body, direct WebFetch.

---

### Finding 9: A second, lower-confidence issue reports verbose code comments resisting CLAUDE.md-style instruction

**Evidence:** Per WebSearch synthesis (not independently WebFetched): issue #65961 (opened 2026-06-07, roughly five weeks before this spike) reports that verbose code comments are the out-of-the-box default and that a mandatory CLAUDE.md rule does not reliably suppress it, nor does reinforcing the rule via a memory system.

**Source:** [github.com/anthropics/claude-code/issues/65961](https://github.com/anthropics/claude-code/issues/65961)

**Significance:** Its June 2026 open date is consistent with the engineer's "last few weeks" framing, but this finding is lower-confidence than Finding 8 — it was not independently WebFetched, only synthesized from search results.

**Verification:** URL not independently WebFetched — WebSearch synthesis only. Flagged as lower-confidence.

---

### Finding 10: A secondhand comparison claims Claude Sonnet 5 produces measurably more output than a competing model

**Evidence:** *"Sonnet 5 is verbose. Testing by The Human Co found it averaging roughly a third more output tokens than GPT-5.5."* And, on a tokenizer change: *"the updated tokenizer maps the same input text to roughly 1.0 to 1.35 times more tokens than Sonnet 4.6's tokenizer."*

**Source:** [awesomeagents.ai — Claude Sonnet 5 review](https://awesomeagents.ai/reviews/review-claude-sonnet-5/)

**Significance:** This blog does not disclose its own evaluation methodology, and the claim is itself secondhand (attributed to "The Human Co," whose original data was not located or independently fetched). Read as a directional signal that the community perceives Sonnet 5 as more verbose, not a validated benchmark.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch; underlying methodology UNVERIFIED beyond this blog's own claim.

---

### Finding 11: A separate secondhand comparison claims Opus 4.6 produces measurably more output than Opus 4.5

**Evidence:** *"Task: Explain concept in ~200 words. Opus 4.5: 187 words average. Opus 4.6: 267 words average. Change: +43% more verbose."* And: *"Opus 4.5: 68,000 tokens average. Opus 4.6: 91,000 tokens average"* (+34%).

**Source:** [medium.com/@reliabledataengineering — Opus 4.6 vs 4.5](https://medium.com/@reliabledataengineering/claude-opus-4-6-vs-4-5-what-actually-changed-and-whether-you-should-upgrade-ff46550e8a75)

**Significance:** Same caveat as Finding 10 — an independent newsletter, no disclosed methodology (sample size, task set, scoring protocol). Directional, not validated. Together, Findings 10 and 11 corroborate the *direction* of the engineer's claim (recent Claude releases perceived as more verbose) without independently confirming its *magnitude* or its *specific timing* ("last few weeks").

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch; methodology UNVERIFIED beyond this blog's own claim.

---

### Finding 12: Claude Code's own built-in system prompt already carries prompt-level conciseness instructions — the same enforcement tier the engineer is proposing

**Evidence:** Per a third-party reverse-engineering of Claude Code's system prompt: *"Your responses should be short and concise"* and *"IMPORTANT: Go straight to the point. Try the simplest approach first without going in circles. Do not overdo it. Be extra concise."* For Anthropic-internal users specifically: *"keep text between tool calls to ≤25 words. Keep final responses to ≤100 words unless the task requires more detail."*

**Source:** [dbreunig.com — How Claude Code Builds a System Prompt](https://www.dbreunig.com/2026/04/04/how-claude-code-builds-a-system-prompt.html)

**Significance:** This is a third-party reconstruction, not an official Anthropic publication. What it establishes, if accurate, is that Anthropic's default system prompt already contains textual conciseness directives at the same enforcement tier the engineer is proposing — and per Findings 8–11, complaints about verbosity persist despite this. Direct evidence for sub-question 3's "known failure mode of prompting-for-conciseness."

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch; source is a third-party blog, not Anthropic.

---

### Finding 13: No built-in Claude Code output style ships to make responses *more* concise than Default

**Evidence:** *"Claude Code's Default output style is the existing system prompt, designed to help you complete software engineering tasks efficiently."* And: *"The built-in Explanatory and Learning styles produce longer responses than Default by design, which increases output tokens."*

**Source:** [code.claude.com/docs/en/output-styles](https://code.claude.com/docs/en/output-styles)

**Significance:** The mechanism (custom output styles) exists and is documented, but its shipped presets move in the *opposite* direction from what the engineer wants. A custom output style could in principle be authored for brevity, but this is again a system-prompt-level (textual, non-mechanical) instruction, subject to the same limitation as Finding 12. **Round 4 note:** the custom-output-style path this Finding flags as untested is investigated directly in Findings 22–26.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 14 (CORRECTED — see round-1 error): tomrochette.com's "lead with the one-line summary" describes a dashboard/session-card view, NOT the chat transcript text of an individual session

**Evidence:** The "lead with the one-line summary" passage sits under the article's own section header, *"Strategy 6: Progressive Disclosure"* — *"Information should arrive in layers, from summary to detail, on demand."* — and is followed a section later by *"Strategy 8: Build a Session Dashboard"*: *"A dashboard that lists all active sessions with their status, progress, and severity indicators lets you assess the entire fleet in one glance."* And: *"You never need to understand everything about every session to make a decision."*

**Source:** [tomrochette.com/managing-many-llm-agent-sessions](https://tomrochette.com/managing-many-llm-agent-sessions/) (re-fetched specifically to determine the medium)

**Significance:** **Round 1's Finding 9 was an over-reach.** It cited this quote to argue the community converges on "summary-first" placement *inside a streaming chat message*, in tension with the engineer's summary-last hypothesis. Re-reading the source in context shows the "one-line summary" is a **dashboard/session-card status line**, a structurally different medium from an individual session's own generated chat text — it is the same general shape as a session-overview dashboard, a separate aggregated status surface, not an instruction about where inside one message a summary belongs. This source does not actually address, either way, where a summary should sit within a single streamed chat response, and should not have been used to argue for summary-first placement *within chat text*.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch, with explicit surrounding-context check for the section header and medium.

---

### Finding 15: BLUF is a named, established convention favoring summary-first placement — general definition, medium unstated

**Evidence:** Per search synthesis, BLUF is described as *"the practice of beginning a message with its key information"* and is explicitly contrasted with *"BLAB"* (Bottom Line At the Bottom).

**Source:** en.wikipedia.org/wiki/BLUF_(communication) (via WebSearch synthesis; not independently WebFetched in full)

**Significance:** BLUF is a real, citable, long-established (per search synthesis, originating in U.S. military communication) convention. This general-definition finding does NOT by itself establish that BLUF applies to a streaming/scrolling chat medium — see Finding 16, which investigates that question directly and found the opposite of what round 1 assumed.

**Verification:** URL not independently WebFetched — search-synthesis only. Flagged as lower-confidence; the general definition is corroborated across multiple independent search results, but the medium question is not addressed by this finding alone.

---

### Finding 16 (corrects round-1 Finding 10's application): BLUF's own literature, wherever it explicitly addresses "chat," scopes only to composing the FIRST outgoing message — not to where a summary sits within an incoming streamed response

**Evidence:** *"Over email, that could mean putting it in the subject line itself, or on chat, including the request in the first message, rather than a pre-amble of 'you there?' ping-pong."*

**Source:** [bitesizelearning.co.uk — BLUF: Bottom Line Up Front](https://www.bitesizelearning.co.uk/resources/bluf-bottom-line-up-front)

**Significance:** This is the only passage found in accessible BLUF literature that names "chat" explicitly, and it is authoring advice for the human's OWN outgoing message — put your ask up front, skip the ping-pong preamble — not guidance about where an incoming, long, generated response's summary should be placed for a reader who did not write it. **Round 1's Finding 10 applied BLUF's summary-first principle to "where should Claude's summary sit within its own generated chat reply," which is a different question BLUF's own literature does not appear to address.** Every source found in this spike that applies BLUF concretely (memo, email subject line, first chat message) is a static or turn-initiating artifact, never a mid-conversation streamed response a reader is receiving in real time.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch, with explicit search for any passage addressing scroll position or reader viewport — none found.

---

### Finding 17: Claude Code's terminal interface has a directly-reported, independently-confirmed bug of auto-scrolling to the bottom during generation, overriding manual scroll-up

**Evidence:** *"When using Claude Code, I used to be able to scroll up in the terminal to review the plan while work was still in progress. Now, as Claude Code continues working, the terminal automatically jumps to the bottom, making it impossible to read earlier output without being pulled back down."*

**Source:** [github.com/anthropics/claude-code/issues/37627](https://github.com/anthropics/claude-code/issues/37627)

**Significance:** This is independent, third-party corroboration (not the engineer's own claim) that Claude Code's terminal interface auto-scrolls to the bottom during active generation and that this pulls the viewport away from a manually-scrolled-up position — directly bearing on sub-question 5's crux: does the reader's resting position default to the bottom during streaming?

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 18: Claude Code's desktop app has the same reported pattern, explicitly framed by the reporter as "standard sticky bottom behavior," with the release-on-manual-scroll nuance identified as the correct (regressed) behavior

**Evidence:** *"While Claude is streaming a response (token-by-token / phrase-by-phrase), the chat window force-scrolls to the bottom on every update. This happens even when I have explicitly scrolled up to read earlier content — including scrolling all the way to the top of the conversation."* And, the reporter's own framing of correct behavior: *"Standard 'sticky bottom' behavior used in terminals, chat apps and IDE chat panels: If the user is at the bottom of the scroll container, auto-scroll to follow new streaming content. If the user has scrolled up beyond that threshold, do NOT auto-scroll. Leave the viewport exactly where the user put it."* The issue is marked as a regression ("Last Working: app-1.3561.0", "Broken In: app-1.4758.0").

**Source:** [github.com/anthropics/claude-code/issues/53382](https://github.com/anthropics/claude-code/issues/53382)

**Significance:** This independently corroborates BOTH halves of the engineer's description: (a) the default resting position during streaming is the bottom of the message, and (b) manually scrolling away is *supposed* to release that default — matching the engineer's own caveat, *"a não ser que eu deixe parado no topo"* ("unless I stay parked at the top"). It also shows this release mechanism is not always reliable in Claude Code today: the bug report exists precisely because, in the affected version, the release stopped working and the forced-bottom behavior became unconditional.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 19: "Sticky bottom" / "live edge" auto-scroll-with-release-on-manual-scroll is a named, general chat/streaming UI pattern, not a Claude-Code-specific quirk

**Evidence:** *"Follow only while they're following. If they're at the live edge, keep the stream in view. If they scroll away, leave them there."* And: *"Move only when the reader asked to move. If someone is reading, don't pull them somewhere else. Auto-scroll should never be the default."*

**Source:** [ui.shadcn.com — MessageScroller component docs](https://ui.shadcn.com/docs/components/radix/message-scroller)

**Significance:** Independent, Claude-Code-unrelated confirmation that the pattern described in Findings 17–18 (bottom-resting by default while streaming, released on manual scroll-away) is a named, standard, deliberately-designed pattern in the broader chat/streaming UI community — not an accident of Claude Code's implementation. This directly grounds the engineer's mechanical premise: in a streaming chat medium generally, the reader's default resting position during and immediately after generation is the bottom of the message.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 20: No source found argues explicitly for WHY Reddit's TL;DR convention sits at the end — neither "legacy habit" nor "adapted to scrolling" is argued anywhere located

**Evidence:** A targeted search for an explicit rationale ("Reddit TL;DR at the end convention reason why placed at bottom not top scrolling") returned no direct results. A broader follow-up on TL;DR placement rationale returned only general framing — TL;DR can be placed at the top as "a preview and decision aid" or at the bottom "as a classic conclusion" — with no source explaining Reddit's specific end-placement convention, and no source connecting that placement to the scrolling nature of the medium in either direction.

**Source:** Not found — search process documented in the auxiliary file (entry 22); no single URL sustains a claim either way.

**Significance:** This is an explicit negative result, stated plainly per Citation Discipline rather than filled with a guess. Neither the "TL;DR-last is sloppy legacy habit" framing implied by round 1's contrast with BLUF, nor a "TL;DR-last is deliberately medium-adapted" counter-argument, is supported by any source found. This finding does not sustain any option below — it is recorded only to close out the specific request to investigate it.

**Verification:** Not applicable — no source to cite. Absence of evidence documented per Citation Discipline rule 4/7 (an unsustained claim is dropped, not asserted).

---

### Finding 21: 4Shark's own Output Policy already implements several of the community's converged mitigations, but does not gate ordinary narrative/status chat text

**Evidence:** Reading `~/.claude/CLAUDE.md` § Output Policy in full: Layer 2 routes "any visual or comparative content" to an HTML file rather than chat; Layer 5's pacing gate asks *"Found N items. Bring them one at a time, or all at once?"* for >3 decision items; every decision item must carry three named parts — *"**The code excerpt**"*, *"**The flow narrative**"*, and *"**The verdict, options, or question**"* — a structured, bounded shape, not free narration. `~/.claude/docs/DECISION-SURFACING.md` separately documents a decide-vs-ask filter — *"**Tactical** → **decide, do not ask.**"* against *"**Strategic** → **surface it**"* — plus a four-part "Decision Card" format explicitly aimed at replacing the pattern it names *"**The wall of text**"* (where *"A 2000-line plan is not reviewable; the engineer scans it, cannot tell what is load-bearing, and rubber-stamps or bails"*) and the pattern it names *"**The bare technical question**"*. `~/.claude/scripts/inject-output-policy-reminder.sh` fires at `UserPromptSubmit` and `SubagentStart` — i.e., **before** a turn is generated, as a pre-turn reminder, not a post-turn check of what was actually produced.

**Source:** `~/.claude/CLAUDE.md` § Output Policy (read in full); `~/.claude/docs/DECISION-SURFACING.md:13-23` (read in full, lines 1–92); `~/.claude/scripts/inject-output-policy-reminder.sh:1-89` (read in full); `~/.claude/settings.json:82-165` (hooks wiring for `SubagentStart`/`UserPromptSubmit`, read in full)

**Significance:** This is the direct answer to Part 4's question. **What the existing Output Policy already covers**: the *structured, decision-bearing* content shapes — comparisons, findings dumps, code review items, anything with ≥2 options or ≥3 items — get routed out of chat into files, with a pacing gate and a mandated excerpt+narrative+verdict shape per item. This is functionally the same idea as the engineer's hypothesis (force a compact, scannable shape) but scoped narrowly to decision-bearing content. **What it does NOT cover**: ordinary operational narration — the running commentary of "reading file X... now checking Y... now running Z" that accumulates across a long single-session turn or across 7 parallel sessions, none of which is necessarily "3+ items for decision" or "comparative content." The engineer's complaint ("aumentou muito o volume de texto que gera") reads as being about this second category — general narrative bulk — not specifically about undelivered decision items. Additionally, the enforcement mechanism 4Shark already uses is a pre-turn textual reminder — the same tier as Findings 1–2 and 12 establish is the *only* tier available (no hook can check or reshape the response *after* it is generated), so the gap is not "4Shark forgot to build a hook", it is that no such hook is buildable with current Claude Code hook events. **Round 4 note:** Finding 27 narrows this last clause — a hook cannot reshape the *transcript* after generation, but a `MessageDisplay` hook can reshape the *on-screen render*, with the caveats detailed in Findings 27–29.

**Verification:** `file:line` references confirmed via direct `Read` of each file in this session (not web-fetched); quotes are verbatim substrings from the files as read above.

---

### Finding 22: A custom output style, by default, REPLACES Claude Code's built-in coding instructions in the system prompt rather than appending alongside them

**Evidence:** *"Output styles directly modify Claude Code's system prompt."* And: *"Custom output styles leave out Claude Code's built-in software engineering instructions, such as how to scope changes, write comments, and verify work, unless `keep-coding-instructions` is set to `true`."* And: *"All output styles have their own custom instructions added to the end of the system prompt."*

**Source:** [code.claude.com/docs/en/output-styles](https://code.claude.com/docs/en/output-styles)

**Significance:** Answers the first half of round 4's Gap 1 directly. A custom output style's own instructions are always appended to the end of the system prompt, but by default the style REPLACES (drops) Claude Code's built-in coding instructions — the `keep-coding-instructions: true` frontmatter flag is required to keep both. This is a structurally different mechanism from CLAUDE.md, which the same documentation source describes separately (Finding 23) as never replacing anything.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the "How output styles work" section, re-fetched twice in this round (initial fetch and a self-check re-fetch) with an identical result both times.

---

### Finding 23: CLAUDE.md and output styles occupy different locations in Claude Code's own prompt-construction model — documented as a difference in WHERE the text sits, not as a difference in how strongly the model obeys it

**Evidence:** Per the "Comparisons to related features" table: *"Output styles | Modifies the system prompt | You want a different role, tone, or default response format every turn"* and *"CLAUDE.md | Adds a user message after the system prompt | Claude should always know your project conventions and codebase context"*. Separately: *"Output style is part of the system prompt, which Claude Code reads once at session start. Changes take effect after `/clear` or a new session."*

**Source:** [code.claude.com/docs/en/output-styles](https://code.claude.com/docs/en/output-styles)

**Significance:** This is the only documented structural distinction found between the two mechanisms: an output style's text becomes part of the system prompt itself (read once at session start), while CLAUDE.md's content is injected as a separate user message positioned after the system prompt. Neither this doc nor any other source found in this spike states that one location is obeyed more reliably than the other — the distinction documented is structural/positional, not a claim about enforcement strength. No source found in this round makes any comparative claim about model compliance rates between the two locations. This directly bounds round 4's Gap 1 question "is the mechanism structurally stronger, equal, or weaker" — the honest answer, per what was found, is: **differently located, not shown to be differently enforced.**

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the "Comparisons to related features" table, re-fetched twice with an identical result both times.

---

### Finding 24: No source found demonstrates a custom output style measurably reducing verbosity where a CLAUDE.md rule failed

**Evidence:** The one benchmark located that discloses its own methodology explicitly compares two different CLAUDE.md formulations against each other, not an output style against CLAUDE.md: *"N=5, single session, no statistical controls. Directional signal only."* — describing separate comparisons of a "minimal CLAUDE.md profile" and a "compressed CLAUDE.md profile," both against a CLAUDE.md-less baseline.

**Source:** [github.com/drona23/claude-token-efficient — benchmark/SUMMARY.md](https://github.com/drona23/claude-token-efficient/blob/main/benchmark/SUMMARY.md)

**Significance:** Directly answers the "does evidence exist" half of Gap 1. The closest thing to a disclosed-methodology token/verbosity benchmark found in this research does not test the specific comparison Gap 1 asks about (output style vs. CLAUDE.md) — it tests CLAUDE.md against itself in two formulations. No benchmark comparing a custom output style against a CLAUDE.md rule, with any disclosed methodology, was located anywhere in this round's research.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the benchmark document's methodology-caveat line.

---

### Finding 25: A specific numeric claim about an output style's superiority ("Caveman" style, ~65% token reduction), surfaced by a search-synthesis pass, was checked directly against its apparent source and is not present there

**Evidence:** An initial WebSearch synthesis stated: *"The 'Caveman' style (ultra-concise output) achieves roughly 65% fewer tokens over a full work session for significant savings in both cost and context window usage."* A direct WebFetch of the specific benchmark document the synthesis appeared to be describing, searching explicitly for this claim, found: *"There is no mention of alternative prompt styling approaches or terse output formats in this document for me to quote."*

**Source:** Checked against [github.com/drona23/claude-token-efficient — benchmark/SUMMARY.md](https://github.com/drona23/claude-token-efficient/blob/main/benchmark/SUMMARY.md); not found there.

**Significance:** This candidate is explicitly rejected per Citation Discipline rule 4 (UNVERIFIED tag) and rule 1 (quote-or-drop) — the search-synthesis layer produced a specific, plausible-sounding number that does not verify against direct fetch of its apparent source. Recorded to document the check was performed, mirroring Finding 7's treatment of the "AI Brain Fry" term. **This claim MUST NOT sustain any option or derivation below.**

**Verification:** URL fetched / Verbatim quote checked: no — the cited claim is absent / Quote substring confirmed at: not applicable, the "Caveman"/65% claim does not appear in this document.

---

### Finding 26: Informal, undisclosed-methodology community commentary shows no consensus that either mechanism is reliably obeyed, and one report claims a CLAUDE.md verbosity-reduction approach performed WORSE on harder tasks

**Evidence:** From a Hacker News discussion thread: *"I made a test which runs several different configurations against coding tasks from easy to hard... across 30 tests, this does perform worse"* (referring to a CLAUDE.md-based token-reduction approach). And, separately in the same thread: *"I too included the last bit about user prompts overriding system prompt, but like any good LLM, it doesn't always follow instructions."*

**Source:** [news.ycombinator.com/item?id=47581701](https://news.ycombinator.com/item?id=47581701)

**Significance:** Neither quote is about output styles specifically — both are about a CLAUDE.md-based approach — but both corroborate the broader pattern already established in Findings 8–12 and 24: informal community testing finds mixed-to-negative results for prose-level verbosity instructions, and at least one practitioner's direct experience is that instruction-following is unreliable regardless of where in the prompt the instruction sits. This is anecdotal (single commenter, undisclosed task set and scoring method, on a public forum) and is not used to sustain any option below on its own.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at reader comments within the linked HN discussion thread.

---

### Finding 27: MessageDisplay is a real, currently-shipped hook event — missed by this spike's round 1 — that CAN reshape what the human sees on screen, without ever reaching the transcript or Claude's own view

**Evidence:** *"`displayContent` replaces the displayed text on screen. Display-only: the transcript and what Claude sees keep the original"*. And: *"MessageDisplay doesn't support matchers and always fires on every occurrence"* [of an assistant message streaming text]. And: *"MessageDisplay is a display-only event that runs while assistant message text streams"*.

**Source:** [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)

**Significance:** This directly answers Gap 2's core question — "is there ANY hook event, field, or capability — new or previously missed" that touches the assistant's own response text before the human sees it. The answer is a qualified yes: `MessageDisplay` can replace what renders on screen in real time as the response streams. This does **NOT contradict Finding 1** — Finding 1's claim (*"No hook can modify Claude's generated message text in the transcript or conversation history"*) is about the transcript and the model's own view, and this quote explicitly preserves that: *"the transcript and what Claude sees keep the original"*. What Finding 1, as stated in round 1, did not carve out is this narrower on-screen-only exception — round 1's WebFetch prompt asked specifically about modifying/appending to "the assistant's own response text" without distinguishing the on-screen render from the transcript, and `MessageDisplay` was not surfaced in that pass's extracted content (see the round-1 auxiliary entry 1, which lists only `Stop` and `PostToolUse`).

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the "MessageDisplay" row of the hookSpecificOutput / decision-control reference table, re-fetched three times across this round with an identical result each time.

---

### Finding 28: MessageDisplay predates every prior round of this spike — it was shipped well before round 1's research, not an "unshipped/upcoming" mechanism as round 2/3's "What remains uncertain" list had framed the open question

**Evidence:** *"A new hook event `MessageDisplay` has been added, allowing you to transform or hide the text of displayed assistant messages."* And: *"Claude Code v2.1.152 was released on May 26, 2026."*

**Source:** [dev.classmethod.jp — "Claude Code v2.1.152 Major Updates"](https://dev.classmethod.jp/en/articles/20260524-claude-code-updates-v2-1-152/)

**Significance:** This is a secondary, third-party source (a Japanese developer blog), not Anthropic's own changelog — Anthropic's own `CHANGELOG.md` was fetched directly in this round and did not surface a `MessageDisplay` entry in the portion returned (the file is roughly 437KB, well past what a single WebFetch pass reliably processes — see the round-4 auxiliary entry for this fetch attempt). Treated as directional, not definitive, on the exact version/date; what IS independently confirmed by three separate direct fetches of the primary hooks documentation (Finding 27) is that the capability exists and is currently documented as shipped, not proposed or upcoming. **This corrects, explicitly, the open question in round 2/3's "What remains uncertain" list**, which speculatively named *"a future `MessageDisplay`-style capability"* as an example of something unshipped — the capability by that exact name already existed at the time that speculative language was written.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the article's `MessageDisplay` section and its release-date statement.

---

### Finding 29: MessageDisplay's applicability to the engineer's specific marker+terse-paragraph hypothesis is architecturally limited — it reshapes only what a hook script already knows how to produce, and nothing it does reaches Claude's own context

**Evidence:** *"the transcript and what Claude sees keep the original"* — repeated from Finding 27, this is the operative constraint. No passage found in the hooks documentation names verbosity reduction, summarization, or response-shortening as a documented use case for `MessageDisplay`; a follow-up direct fetch searching specifically for use-case language returned: *"The documentation does not provide specific use case examples for the `MessageDisplay` hook event."*

**Source:** [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)

**Significance:** A `MessageDisplay` hook is a shell/script-based hook (the same execution model as every other hook this spike examined) — it can only replace displayed text with content the script itself computes. Producing a genuinely shorter, accurate closing summary of "what was accomplished this turn" requires understanding the turn's content, which is model-level reasoning, not deterministic string logic a shell script performs on its own. A `MessageDisplay` hook could in principle call an LLM API itself to generate a summary from the streamed text, but no source found in this spike documents or reports this being done, and the mechanism would not solve the underlying token-generation cost (Claude still generates the full verbose text; `MessageDisplay` only changes what renders after the fact) or the "does Claude retain awareness of what it said" concern, since *"what Claude sees keep[s] the original"* regardless.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the `MessageDisplay` use-case query response, this round's third targeted fetch of the hooks page.

---

### Finding 30: PreCompact, directly confirmed, has no documented access to the assistant's response text — closing out one of the two hook events the round 4 brief named explicitly

**Evidence:** *"The documentation contains no explicit statement that PreCompact can access, inspect, modify, or gate the assistant's generated response text. PreCompact is compaction-focused and receives only compaction-related metadata (the trigger type: `manual` or `auto`)."* Independently, the matcher table itself states the only two matcher values for `PreCompact` are `manual` ("Manual compaction") and `auto` ("Auto compaction").

**Source:** [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)

**Significance:** Directly answers the `PreCompact` half of Gap 2's explicit list. No new capability found — consistent with, and closing out, Finding 1's original scope for this specific event. `SubagentStop` was also directly re-confirmed in this round to carry the same shape as `Stop` (`decision: "block"` + `reason`, plus `additionalContext` for next-turn feedback) — no capability beyond what Finding 1 already established.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the `PreCompact` matcher table and the tool's explicit negative-finding statement for response-text access.

---

### Finding 31: No GitHub feature request beyond #2880 was found targeting gating or reshaping of the assistant's own final response text; adjacent, more recent requests target a different axis — tool-output/MCP/diff display verbosity, not the assistant's own generated prose

**Evidence:** Search results returned issue titles including *"[FEATURE] Add verbosity control for MCP tool call display"*, *"[Feature Request] MCP Tool Output Verbosity Control"*, *"[Feature Request] Add diffDisplay setting to control Edit tool output verbosity"*, and *"[FEATURE] /Context is too verbose"* — none of which, per their titles, address the assistant's own generated chat response text.

**Source:** WebSearch results across the `anthropics/claude-code` issue tracker (titles only; not independently WebFetched in full for this round).

**Significance:** A negative result for the "has anything shipped or been announced on this axis" half of Gap 2. The verbosity-control conversation happening in currently-open issues is about tool/diff/MCP output display, a different concern from the assistant's own final-response prose that this spike's Findings 1–2, 8–12, and 27–29 address. This lower-confidence finding (titles-only, not independently fetched) is recorded to document the search was performed, not as a strong claim.

**Verification:** URL not independently WebFetched — WebSearch result titles quoted verbatim / Quote substring confirmed at the search result titles themselves, this round's search pass.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Prompt-level rule for closing marker + terse final paragraph — the engineer's original hypothesis, summary-**LAST** | Matches the reader's default resting position in every Claude Code interface variant examined — terminal, desktop app — which is the bottom of the message during and immediately after streaming (Findings 17–19); matches the general "sticky bottom" chat-UI convention, not a Claude-specific quirk (Finding 19); costs nothing extra to scroll up if the reader wants the top instead, since manual scroll-up is supposed to release the auto-follow (Finding 18) | Still advisory-only — no hook can verify or enforce it after generation (Finding 1); Anthropic's own built-in conciseness instructions coexist with ongoing verbosity complaints (Findings 8–12), so a written rule alone has a documented ceiling; the release-on-manual-scroll mechanism is not always reliable in Claude Code today — it has been reported broken in at least one version (Finding 18) | Findings 1, 12, 17, 18, 19 |
| Hook-based enforcement of a marker + terse final paragraph | Would be fully mechanical if it existed | Not buildable with current Claude Code hook events for the transcript/model's own view — no hook can modify/append to the assistant's own generated message text there (Finding 1); the closest matching feature request was declined (Finding 2) | Findings 1, 2 |
| Summary-first placement **inside chat message text** (round-1's proposed alternative) | — | **Weakened in round 2**: the sources originally cited for this (tomrochette.com, BLUF) do not actually support it once their medium is checked — tomrochette.com's "lead with the summary" describes a dashboard/session-card view, not chat text (Finding 14), and BLUF's only found application to "chat" is about the human's own outgoing first message, never an incoming streamed response (Finding 16). Structurally, it would also fight the medium's default resting position (Findings 17–19) — reading a summary-first message written inside a long response requires scrolling UP from the bottom-resting position first, which is the exact objection the engineer raised | Findings 14, 16, 17–19 |
| Route decision-bearing / comparative content to a file, keep chat to a summary (4Shark's existing Layer 2/4) | Already implemented; orthogonal to the summary-position question — applies regardless of which end of a message a summary sits on | Scoped to decision-bearing/comparative content only — does not gate ordinary operational narration, which appears to be the engineer's actual complaint (Finding 21) | Finding 21 |
| Custom output style authored for terseness (unexplored in rounds 1–3, investigated in round 4) | Occupies a different, arguably more prominent prompt location — appended to the end of the system prompt itself rather than as a separate user message (Finding 22, 23); by default it also drops Claude Code's built-in coding instructions, which may or may not be desired depending on whether that is wanted (Finding 22) | No evidence found that this location difference translates to more reliable compliance — no comparative benchmark was located (Finding 24); a specific claim of large measured superiority (~65%) was checked directly and is unsupported (Finding 25); informal community reports show mixed-to-negative results and unreliable instruction-following regardless of location (Finding 26); dropping the built-in coding instructions by default is a real behavioral cost for a coding-focused tool, only avoided via `keep-coding-instructions: true` (Finding 22) | Findings 22, 23, 24, 25, 26 |
| MessageDisplay-based on-screen reshaping (new "third shape" found in round 4) | Could in principle change what the human sees without changing what Claude generates or believes it said — a previously-missed capability (Finding 27); already shipped, not speculative (Finding 28) | Display-only by design — does not reduce actual generation, does not feed back into Claude's context, and is not documented for this use case; a hook has no built-in way to produce an accurate short summary of the turn without either a fixed heuristic or a second, undocumented LLM call (Finding 29) | Findings 27, 28, 29 |

## What remains uncertain

- Whether Claude Code (or the underlying Claude model) specifically became *more* verbose in the exact "last few weeks" window the engineer describes (mid-June to mid-July 2026) was **not confirmed** by any source found. The corroborating evidence (Findings 8–11) establishes that verbosity complaints exist and that some post-cutoff model comparisons claim measurable increases, but none is dated or scoped precisely enough to confirm the engineer's specific timing claim.
- Whether the third-party verbosity-comparison numbers (Findings 10–11) are methodologically sound is unknown — neither source discloses its evaluation protocol in the content fetched.
- Whether "Firehose" (Finding 3) or any other single term is in wider use elsewhere in the community beyond the one GitHub issue found.
- **(Investigated in round 4 — see Findings 22–26; still genuinely uncertain, not merely unexamined.)** Whether a *custom* Claude Code output style (as opposed to CLAUDE.md prose) authored specifically for terseness would outperform the existing CLAUDE.md-level instructions already in place. No comparative benchmark with disclosed methodology was located (Finding 24); a specific superiority claim did not verify against its apparent source (Finding 25); the one documented structural difference (system-prompt-level vs. user-message-level, Finding 23) is not tied by any source found to more reliable compliance. The built-in styles examined (Finding 13) all move toward more verbosity, not less.
- **(Round 2)** Which specific Claude Code interface the engineer is using — terminal, desktop app, VS Code extension — was not confirmed in this spike, though the sticky-bottom-during-streaming pattern was independently corroborated across at least two of those variants (Findings 17–18) and is described as the general, deliberate chat-UI convention regardless (Finding 19).
- **(Round 2)** Whether the "release auto-scroll on manual scroll-up" half of the pattern is currently working correctly in the specific Claude Code version and interface the engineer runs. Finding 18 shows this exact mechanism has been reported broken (forced-bottom overriding manual scroll-up) in at least one desktop-app version range — so the engineer's own described escape hatch ("a não ser que eu deixe parado no topo") may or may not reliably work depending on version, and this spike did not test the currently-installed version's actual behavior.
- **(Round 2)** Finding 20 (Reddit TL;DR placement rationale) is an explicit non-finding — it neither supports nor weakens any option and should not be read as evidence either way.
- The BLUF general-definition finding (Finding 15) rests on search-synthesis rather than a direct WebFetch of a primary source — its substance (the term exists, means summary-first, is contrasted with summary-last) is corroborated across multiple independent search results but was not independently re-verified against a single fetched page. Its *application to a streaming medium* was investigated directly in round 2 (Finding 16) and found unsupported by every source located.
- **(CORRECTED in round 4 — see Findings 27–30.)** Whether Anthropic has any *unshipped* or *upcoming* mechanism (e.g., a future hook event, a future `MessageDisplay`-style capability) that would change the Finding 1 conclusion was previously listed as not investigated. This bullet's own example, `MessageDisplay`, was speculative language in round 2/3, but it turns out to name a capability that already existed at the time it was written — shipped, per a secondary source, around v2.1.152 (~May 26, 2026, Finding 28) — and direct re-fetch of the current hooks documentation (Finding 27, verified three times) confirms it as real, not upcoming. It does **not** change Finding 1's conclusion about the transcript/model's own view — it only reshapes the on-screen render, and only display-only (Findings 27, 29). `PreCompact` and `SubagentStop` were also directly re-checked in this round and confirmed to carry no response-text access beyond what Finding 1 already established (Finding 30). No further undocumented or upcoming mechanism was found beyond these in this round's research.
- **(Round 4)** No GitHub feature request beyond #2880 was found that targets gating or reshaping the assistant's own final response text specifically — see Finding 31. This is a titles-only search, not independently fetched in full for every result; a genuine gap in this round's coverage, not a strong negative claim.
- **(Round 4)** Whether a `MessageDisplay` hook that calls an external LLM to compute a genuinely shorter, accurate on-screen summary has ever been built or reported by anyone in the community was not found either way — this spike found no report of it, but also did not exhaustively search for one; treat the absence as "not found," not as "confirmed nobody does this."
- **(Round 3)** Whether a fixed-position, out-of-band status surface (a dashboard, a status line, or any equivalent) could still address the "which of my 7 sessions needs me" half of the engineer's problem was raised in round 2 and subsequently closed by the engineer as not viable for the surfaces this spike had found; this spike does not re-open or re-investigate that question.

## Suggested options for main and the engineer

- **Option A — Prompt-level rule for a closing marker + terse final paragraph, summary-LAST (the engineer's original hypothesis).** Accepting it is advisory-only (same enforcement tier as the existing Output Policy reminder and Anthropic's own base conciseness instructions — Findings 1, 12), this placement is now the one grounded in how Claude Code's own interfaces actually behave during streaming — the reader's default resting position is the bottom (Findings 17–19), matching where a closing summary would land. Sustained by: Findings 1, 12, 17, 18, 19.
- **Option B — Summary-first placement inside chat text.** **This option is weakened relative to round 1.** The sources originally used to support it do not, on closer reading, actually support placing a summary at the *top of an individual streamed chat message* — they describe a different medium (a session dashboard, or the human's own first outgoing message). Not dropped entirely — the underlying "the reader wants the takeaway without reading the whole body" motivation is still valid — but the community evidence for placing it specifically inside chat-message text, at the top, is unsupported by what this spike found. Sustained by: Findings 14, 16 (both explicitly show why the round-1 support does not hold).
- **Option C — Extend the existing Output Policy's decision-bearing-content gate to also cover long operational narration**, not just comparisons/findings/≥3-item lists — i.e., widen Layer 5's pacing-gate trigger conditions so a long single-session turn or narrated status update also routes to a bounded summary, the same way a code review does today. Orthogonal to the position question — works the same regardless of where a summary sits. Sustained by: Finding 21.
- **Option D — A custom output style authored specifically for terseness.** Investigated in round 4 (Gap 1). Occupies a different location in Claude Code's prompt structure than a CLAUDE.md rule — appended to the system prompt itself, rather than injected as a separate user message (Finding 23) — but no source found in this spike demonstrates this location difference makes the instruction more reliably followed. The one methodologically-disclosed benchmark located tests two CLAUDE.md formulations against each other, not an output style against CLAUDE.md (Finding 24), and a specific superiority claim surfaced by search synthesis did not verify against its apparent source (Finding 25). Adopting it also means deciding whether to drop Claude Code's built-in coding instructions (the default) or keep them via `keep-coding-instructions: true` (Finding 22). Sustained by: Findings 22, 23, 24, 25, 26.
- **Option E — A `MessageDisplay` hook that reshapes the on-screen render.** A genuinely new "third shape" surfaced in round 4 (Gap 2) that none of the earlier three rounds considered, because the capability was not surfaced by round 1's narrower fetch. It could in principle hide or truncate content on the human's screen without touching Claude's own context, but is architecturally display-only: it does not reduce what Claude generates, does not feed a summary back into Claude's own view on the next turn, and is not documented for this use case — any "make it terse" logic would have to come from the hook script itself (a fixed heuristic, or an undocumented second LLM call). Sustained by: Findings 27, 28, 29.

No recommendation is made among these — the mechanical ceiling (Finding 1) applies equally to A, C, and D: none can be *enforced*, only requested, and the evidence in Findings 8–12 is that requesting has a documented but incomplete effect. Option E is mechanically different in kind (it operates at the display layer, not the prompt layer) but is not shown to be practically viable for this specific use case either, per Finding 29. The correction made in round 2 changed the *design* question, not the *enforcement* question: the engineer's summary-last premise is the one grounded in confirmed streaming-UI behavior (Findings 17–19), while round 1's summary-first alternative rested on sources that do not actually address this medium (Findings 14, 16) — that correction is reflected in Options A and B above, not in whether either can be mechanically guaranteed. Round 4 adds two further axes without changing this conclusion: whether to try a different prompt-level *location* (Option D) rather than a different prompt-level *shape* (Option A), and whether a previously-unexamined display-layer mechanism (Option E) is worth prototyping despite its documented limitations. The engineer and main should weigh Option A/B (what shape, if any, a closing summary inside chat text should take, and whether it belongs at the top or the bottom of the response) against Option C (whether to widen the existing Output Policy gate so ordinary narration gets the same bounded, scannable treatment decision-bearing content already gets) against Option D (a differently-located but not differently-enforced prompt mechanism) against Option E (a differently-mechanized but architecturally-limited display mechanism).

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim cites its source (`file:line` + quote, or URL + quote); an uncitable claim is written as "Not found: <…>" instead. Large or structured evidence goes to auxiliary files (`{topic}_{kind}_{n}.{ext}`) in the same directory, each referenced from this document by relative link. The `output-verifier` runs the seven structural checks after the write — including citation integrity and auxiliary-file integrity — and the `policy-verifier` checks convention conformance.
