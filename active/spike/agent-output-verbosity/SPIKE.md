# SPIKE — Agent Output Verbosity vs. Parallel-Session Supervision

> **Revision note (round 2):** the engineer identified an analytical error in round 1's Findings 9 and 10 (now corrected below as Findings 15–17) and in the Option B derived from them. Round 1 assumed a static-document reading model (BLUF: the reader's eye lands at the top) without checking whether that assumption holds in a streaming, auto-scrolling chat interface, where the reader's resting position is the bottom. This revision investigates that correction directly (new Findings 18–22), corrects the two over-reaching findings rather than silently rewriting them, splits every round-1 Finding that had grouped multiple sources under one citation (round-1 Findings 3, 5, and 12 are now Findings 3–7, 10–11, and unchanged-but-relabeled respectively), and re-derives the Options section accordingly. Nothing in Findings 1–2, 8–9, 12–14 changed in substance from round 1.

## Investigation question

How is the coding-agent community (Claude Code in particular, but not exclusively) solving the problem of agent output volume overwhelming the human operator — specifically when that operator is running many parallel agent sessions and cannot read everything each one produces?

The engineer's framing, verbatim:

> "nas últimas semanas você aumentou e muito o volume de texto que gera e não dá para acompanhar e ler tudo quando se está trabalhando em 7 frentes ao mesmo tempo."

> "eu penso que uma forma de resolver isso seria uma regra/hook que garanta que sempre que você terminar de racionalizar, você sempre imprima um marcador separando e depois um último parágrafo sucinto"

And, in round 2, the engineer's correction of round 1's analysis:

> "nao é assim que funciona, conforme voce vai escrevendo a tela vai descendo junto a nao ser que eu deixe parado no topo. entao o padrao ja é eu estar no final de um texto enorme e voce ta sugerindo me obrigar a subir todo o texto para ler o resumo para depois ignorar o resto?"

Five sub-questions were investigated in order: (1) does the community name this failure mode, and is the recent-verbosity-increase claim corroborated; (2) what solutions does the community actually use; (3) is the engineer's specific hypothesis (a hook-enforced marker + terse final paragraph) mechanically viable; (4) what does 4Shark's existing Output Policy already cover; (5) — added in round 2 — what MEDIUM is each cited source actually talking about, and does the streaming/auto-scroll behavior of a chat interface change which end of a response the reader's eye actually rests on.

## Sources consulted

- [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) — whether any hook can modify/append to Claude's own response text
- [github.com/anthropics/claude-code#2880](https://github.com/anthropics/claude-code/issues/2880) — a feature request asking for exactly the engineer's enforcement shape, closed "not planned"
- [github.com/anthropics/claude-code#29769](https://github.com/anthropics/claude-code/issues/29769) — verbosity complaint: Claude doubles down on over-explaining when corrected
- [github.com/anthropics/claude-code#65961](https://github.com/anthropics/claude-code/issues/65961) — verbose code comments resist CLAUDE.md instruction (via WebSearch synthesis, not fully WebFetched)
- [github.com/anthropics/claude-code#33414](https://github.com/anthropics/claude-code/issues/33414) — "FireHose" as an isolated proposed term for high-volume agent output
- [github.com/yzhao062/agent-style](https://github.com/yzhao062/agent-style) — community style-guide rules against mechanical AI-tell patterns, including repeated paragraph-closing summaries
- [code.claude.com/docs/en/output-styles](https://code.claude.com/docs/en/output-styles) — built-in output styles; none ships to make Default more concise
- [code.claude.com/docs/en/agents](https://code.claude.com/docs/en/agents) — official parallel-session tooling (subagents, agent view)
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
- [code.claude.com/docs/en/statusline](https://code.claude.com/docs/en/statusline) — round 2: fixed-position status line / subagent status rows as a position-independent third shape
- Local: `~/.claude/CLAUDE.md` § Output Policy (all five layers), `~/.claude/docs/DECISION-SURFACING.md`, `~/.claude/scripts/inject-output-policy-reminder.sh`, `~/.claude/settings.json` — the existing 4Shark mechanism, read in full before concluding
- See auxiliary: `agent-output-verbosity_sources_1.md` — every quote above, with fetch method and reliability caveats, preserved for revision without re-fetching (round 2 additions appended under "Revision round 2")

## Findings

### Finding 1: No hook can modify or append to the assistant's own generated response text — additionalContext is next-turn only

**Evidence:** Per the Claude Code hooks reference: *"Stop — Can output: additionalContext, decision: 'block', reason, systemMessage, continue: false. Cannot do: Modify Claude's actual response text. Effect: additionalContext is injected as a system reminder that Claude sees on the next turn, not appended to the current message."* And: *"The additionalContext field passes a string from your hook into Claude's context window. Claude Code wraps the string in a system reminder and inserts it into the conversation at the point where the hook fired. Claude reads the reminder on the next model request, but it doesn't appear as a chat message in the interface."*

**Source:** [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks)

**Significance:** This is the load-bearing fact for sub-question 3, and it is **unaffected by the round-2 correction**. The engineer's hypothesized mechanism — "a hook that guarantees that whenever you finish rationalizing, you print a marker + a final terse paragraph" — cannot be built as a hook that edits or appends to the current turn's message text, because no hook event exposes that capability, regardless of whether the marker+summary should sit at the top or the bottom of the response. The closest available levers are (a) `Stop` returning `decision: "block"` to force Claude to continue generating (i.e., produce another turn, not edit the one just emitted) and (b) `additionalContext`, which reaches Claude only on the *next* model request. Both are prompt-level nudges the model can still ignore, not text-level enforcement.

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

**Significance:** The mechanism (custom output styles) exists and is documented, but its shipped presets move in the *opposite* direction from what the engineer wants. A custom output style could in principle be authored for brevity, but this is again a system-prompt-level (textual, non-mechanical) instruction, subject to the same limitation as Finding 12.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 14: Anthropic ships a dedicated dashboard/notification layer for the parallel-session-monitoring half of the problem — "agent view"

**Evidence:** *"Agent view — One screen to dispatch and monitor sessions running in the background, opened with `claude agents`. Research preview. Use it when: You have several independent tasks and want to hand them off, check status at a glance, and step in only when one needs you."* And, on subagents: *"Delegated workers inside one session that do a side task in their own context and return a summary."*

**Source:** [code.claude.com/docs/en/agents](https://code.claude.com/docs/en/agents)

**Significance:** A real, shipped Anthropic feature addressing the "N concurrent sessions, one human" framing — but via a **separate status UI**, not by constraining what any individual session's chat text looks like. Answers "how do I keep track of 7 fronts" structurally, not "how do I stop each front from producing a wall of text when I do look at it."

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 15 (CORRECTED — see round-1 error): tomrochette.com's "lead with the one-line summary" describes a dashboard/session-card view, NOT the chat transcript text of an individual session

**Evidence:** The "lead with the one-line summary" passage sits under the article's own section header, *"Strategy 6: Progressive Disclosure"* — *"Information should arrive in layers, from summary to detail, on demand."* — and is followed a section later by *"Strategy 8: Build a Session Dashboard"*: *"A dashboard that lists all active sessions with their status, progress, and severity indicators lets you assess the entire fleet in one glance."* And: *"You never need to understand everything about every session to make a decision."*

**Source:** [tomrochette.com/managing-many-llm-agent-sessions](https://tomrochette.com/managing-many-llm-agent-sessions/) (re-fetched specifically to determine the medium)

**Significance:** **Round 1's Finding 9 was an over-reach.** It cited this quote to argue the community converges on "summary-first" placement *inside a streaming chat message*, in tension with the engineer's summary-last hypothesis. Re-reading the source in context shows the "one-line summary" is a **dashboard/session-card status line**, a structurally different medium from an individual session's own generated chat text — it is the same kind of artifact as Claude Code's own "agent view" (Finding 14), not an instruction about where inside one message a summary belongs. This source does not actually address, either way, where a summary should sit within a single streamed chat response, and should not have been used to argue for summary-first placement *within chat text*.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch, with explicit surrounding-context check for the section header and medium.

---

### Finding 16: BLUF is a named, established convention favoring summary-first placement — general definition, medium unstated

**Evidence:** Per search synthesis, BLUF is described as *"the practice of beginning a message with its key information"* and is explicitly contrasted with *"BLAB"* (Bottom Line At the Bottom).

**Source:** en.wikipedia.org/wiki/BLUF_(communication) (via WebSearch synthesis; not independently WebFetched in full)

**Significance:** BLUF is a real, citable, long-established (per search synthesis, originating in U.S. military communication) convention. This general-definition finding does NOT by itself establish that BLUF applies to a streaming/scrolling chat medium — see Finding 17, which investigates that question directly and found the opposite of what round 1 assumed.

**Verification:** URL not independently WebFetched — search-synthesis only. Flagged as lower-confidence; the general definition is corroborated across multiple independent search results, but the medium question is not addressed by this finding alone.

---

### Finding 17 (NEW — round 2, corrects round-1 Finding 10's application): BLUF's own literature, wherever it explicitly addresses "chat," scopes only to composing the FIRST outgoing message — not to where a summary sits within an incoming streamed response

**Evidence:** *"Over email, that could mean putting it in the subject line itself, or on chat, including the request in the first message, rather than a pre-amble of 'you there?' ping-pong."*

**Source:** [bitesizelearning.co.uk — BLUF: Bottom Line Up Front](https://www.bitesizelearning.co.uk/resources/bluf-bottom-line-up-front)

**Significance:** This is the only passage found in accessible BLUF literature that names "chat" explicitly, and it is authoring advice for the human's OWN outgoing message — put your ask up front, skip the ping-pong preamble — not guidance about where an incoming, long, generated response's summary should be placed for a reader who did not write it. **Round 1's Finding 10 applied BLUF's summary-first principle to "where should Claude's summary sit within its own generated chat reply," which is a different question BLUF's own literature does not appear to address.** Every source found in this spike that applies BLUF concretely (memo, email subject line, first chat message) is a static or turn-initiating artifact, never a mid-conversation streamed response a reader is receiving in real time.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch, with explicit search for any passage addressing scroll position or reader viewport — none found.

---

### Finding 18 (NEW — round 2): Claude Code's terminal interface has a directly-reported, independently-confirmed bug of auto-scrolling to the bottom during generation, overriding manual scroll-up

**Evidence:** *"When using Claude Code, I used to be able to scroll up in the terminal to review the plan while work was still in progress. Now, as Claude Code continues working, the terminal automatically jumps to the bottom, making it impossible to read earlier output without being pulled back down."*

**Source:** [github.com/anthropics/claude-code/issues/37627](https://github.com/anthropics/claude-code/issues/37627)

**Significance:** This is independent, third-party corroboration (not the engineer's own claim) that Claude Code's terminal interface auto-scrolls to the bottom during active generation and that this pulls the viewport away from a manually-scrolled-up position — directly bearing on sub-question 5's crux: does the reader's resting position default to the bottom during streaming?

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 19 (NEW — round 2): Claude Code's desktop app has the same reported pattern, explicitly framed by the reporter as "standard sticky bottom behavior," with the release-on-manual-scroll nuance identified as the correct (regressed) behavior

**Evidence:** *"While Claude is streaming a response (token-by-token / phrase-by-phrase), the chat window force-scrolls to the bottom on every update. This happens even when I have explicitly scrolled up to read earlier content — including scrolling all the way to the top of the conversation."* And, the reporter's own framing of correct behavior: *"Standard 'sticky bottom' behavior used in terminals, chat apps and IDE chat panels: If the user is at the bottom of the scroll container, auto-scroll to follow new streaming content. If the user has scrolled up beyond that threshold, do NOT auto-scroll. Leave the viewport exactly where the user put it."* The issue is marked as a regression ("Last Working: app-1.3561.0", "Broken In: app-1.4758.0").

**Source:** [github.com/anthropics/claude-code/issues/53382](https://github.com/anthropics/claude-code/issues/53382)

**Significance:** This independently corroborates BOTH halves of the engineer's description: (a) the default resting position during streaming is the bottom of the message, and (b) manually scrolling away is *supposed* to release that default — matching the engineer's own caveat, *"a não ser que eu deixe parado no topo"* ("unless I stay parked at the top"). It also shows this release mechanism is not always reliable in Claude Code today: the bug report exists precisely because, in the affected version, the release stopped working and the forced-bottom behavior became unconditional.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 20 (NEW — round 2): "Sticky bottom" / "live edge" auto-scroll-with-release-on-manual-scroll is a named, general chat/streaming UI pattern, not a Claude-Code-specific quirk

**Evidence:** *"Follow only while they're following. If they're at the live edge, keep the stream in view. If they scroll away, leave them there."* And: *"Move only when the reader asked to move. If someone is reading, don't pull them somewhere else. Auto-scroll should never be the default."*

**Source:** [ui.shadcn.com — MessageScroller component docs](https://ui.shadcn.com/docs/components/radix/message-scroller)

**Significance:** Independent, Claude-Code-unrelated confirmation that the pattern described in Findings 18–19 (bottom-resting by default while streaming, released on manual scroll-away) is a named, standard, deliberately-designed pattern in the broader chat/streaming UI community — not an accident of Claude Code's implementation. This directly grounds the engineer's mechanical premise: in a streaming chat medium generally, the reader's default resting position during and immediately after generation is the bottom of the message.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via direct WebFetch.

---

### Finding 21 (NEW — round 2): No source found argues explicitly for WHY Reddit's TL;DR convention sits at the end — neither "legacy habit" nor "adapted to scrolling" is argued anywhere located

**Evidence:** A targeted search for an explicit rationale ("Reddit TL;DR at the end convention reason why placed at bottom not top scrolling") returned no direct results. A broader follow-up on TL;DR placement rationale returned only general framing — TL;DR can be placed at the top as "a preview and decision aid" or at the bottom "as a classic conclusion" — with no source explaining Reddit's specific end-placement convention, and no source connecting that placement to the scrolling nature of the medium in either direction.

**Source:** Not found — search process documented in the auxiliary file (entry 22); no single URL sustains a claim either way.

**Significance:** This is an explicit negative result, stated plainly per Citation Discipline rather than filled with a guess. Neither the "TL;DR-last is sloppy legacy habit" framing implied by round 1's contrast with BLUF, nor a "TL;DR-last is deliberately medium-adapted" counter-argument, is supported by any source found. This finding does not sustain any option below — it is recorded only to close out the specific request to investigate it.

**Verification:** Not applicable — no source to cite. Absence of evidence documented per Citation Discipline rule 4/7 (an unsustained claim is dropped, not asserted).

---

### Finding 22 (NEW — round 2): Claude Code ships two persistent, fixed-position status elements independent of the scrolling message stream — the status line and per-subagent status rows

**Evidence:** *"The status line is a customizable bar at the bottom of Claude Code that runs any shell script you configure. It receives JSON session data on stdin and displays whatever your script prints, giving you a persistent, at-a-glance view of context usage, costs, git status, or anything else you want to track."* Listed explicitly as a use case: *"Work across multiple sessions and need to distinguish them."* And: *"The subagentStatusLine setting renders a custom row body for each subagent shown in the agent panel below the prompt."*

**Source:** [code.claude.com/docs/en/statusline](https://code.claude.com/docs/en/statusline)

**Significance:** This is a genuine "third shape" that sidesteps the summary-position-within-scrolling-text question entirely — both the main status line and the per-subagent status rows occupy a fixed screen position (rendered outside the scrolling message stream, updated on an independent refresh cycle), so a takeaway placed there does not compete with scroll position at all. It sits in the same family as "agent view" (Finding 14) — an out-of-band status surface rather than a placement decision inside the message body.

**Verification:** URL fetched (oversized response persisted locally and read directly, so this is literal source text, not an intermediate-model paraphrase) / Verbatim quote checked / Quote substring confirmed at the fetched page's "Subagent status lines" and introductory sections.

---

### Finding 23: 4Shark's own Output Policy already implements several of the community's converged mitigations, but does not gate ordinary narrative/status chat text

**Evidence:** Reading `~/.claude/CLAUDE.md` § Output Policy in full: Layer 2 routes "any visual or comparative content" to an HTML file rather than chat; Layer 5's pacing gate asks *"Found N items. Bring them one at a time, or all at once?"* for >3 decision items; every decision item must carry three named parts — *"**The code excerpt**"*, *"**The flow narrative**"*, and *"**The verdict, options, or question**"* — a structured, bounded shape, not free narration. `~/.claude/docs/DECISION-SURFACING.md` separately documents a decide-vs-ask filter — *"**Tactical** → **decide, do not ask.**"* against *"**Strategic** → **surface it**"* — plus a four-part "Decision Card" format explicitly aimed at replacing the pattern it names *"**The wall of text**"* (where *"A 2000-line plan is not reviewable; the engineer scans it, cannot tell what is load-bearing, and rubber-stamps or bails"*) and the pattern it names *"**The bare technical question**"*. `~/.claude/scripts/inject-output-policy-reminder.sh` fires at `UserPromptSubmit` and `SubagentStart` — i.e., **before** a turn is generated, as a pre-turn reminder, not a post-turn check of what was actually produced.

**Source:** `~/.claude/CLAUDE.md` § Output Policy (read in full); `~/.claude/docs/DECISION-SURFACING.md:13-23` (read in full, lines 1–92); `~/.claude/scripts/inject-output-policy-reminder.sh:1-89` (read in full); `~/.claude/settings.json:82-165` (hooks wiring for `SubagentStart`/`UserPromptSubmit`, read in full)

**Significance:** This is the direct answer to Part 4's question. **What the existing Output Policy already covers**: the *structured, decision-bearing* content shapes — comparisons, findings dumps, code review items, anything with ≥2 options or ≥3 items — get routed out of chat into files, with a pacing gate and a mandated excerpt+narrative+verdict shape per item. This is functionally the same idea as the engineer's hypothesis (force a compact, scannable shape) but scoped narrowly to decision-bearing content. **What it does NOT cover**: ordinary operational narration — the running commentary of "reading file X... now checking Y... now running Z" that accumulates across a long single-session turn or across 7 parallel sessions, none of which is necessarily "3+ items for decision" or "comparative content." The engineer's complaint ("aumentou muito o volume de texto que gera") reads as being about this second category — general narrative bulk — not specifically about undelivered decision items. Additionally, the enforcement mechanism 4Shark already uses is a pre-turn textual reminder — the same tier as Findings 1–2 and 12 establish is the *only* tier available (no hook can check or reshape the response *after* it is generated), so the gap is not "4Shark forgot to build a hook", it is that no such hook is buildable with current Claude Code hook events.

**Verification:** `file:line` references confirmed via direct `Read` of each file in this session (not web-fetched); quotes are verbatim substrings from the files as read above.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Prompt-level rule for closing marker + terse final paragraph — the engineer's original hypothesis, summary-**LAST** | Matches the reader's default resting position in every Claude Code interface variant examined — terminal, desktop app — which is the bottom of the message during and immediately after streaming (Findings 18–20); matches the general "sticky bottom" chat-UI convention, not a Claude-specific quirk (Finding 20); costs nothing extra to scroll up if the reader wants the top instead, since manual scroll-up is supposed to release the auto-follow (Finding 19) | Still advisory-only — no hook can verify or enforce it after generation (Finding 1); Anthropic's own built-in conciseness instructions coexist with ongoing verbosity complaints (Findings 8–12), so a written rule alone has a documented ceiling; the release-on-manual-scroll mechanism is not always reliable in Claude Code today — it has been reported broken in at least one version (Finding 19) | Findings 1, 12, 18, 19, 20 |
| Hook-based enforcement of a marker + terse final paragraph | Would be fully mechanical if it existed | Not buildable with current Claude Code hook events — no hook can modify/append to the assistant's own generated message text (Finding 1); the closest matching feature request was declined (Finding 2) | Findings 1, 2 |
| Summary-first placement **inside chat message text** (round-1's proposed alternative) | — | **Weakened in round 2**: the sources originally cited for this (tomrochette.com, BLUF) do not actually support it once their medium is checked — tomrochette.com's "lead with the summary" describes a dashboard/session-card view, not chat text (Finding 15), and BLUF's only found application to "chat" is about the human's own outgoing first message, never an incoming streamed response (Finding 17). Structurally, it would also fight the medium's default resting position (Findings 18–20) — reading a summary-first message written inside a long response requires scrolling UP from the bottom-resting position first, which is the exact objection the engineer raised | Findings 15, 17, 18–20 |
| Route decision-bearing / comparative content to a file, keep chat to a summary (4Shark's existing Layer 2/4) | Already implemented; orthogonal to the summary-position question — applies regardless of which end of a message a summary sits on | Scoped to decision-bearing/comparative content only — does not gate ordinary operational narration, which appears to be the engineer's actual complaint (Finding 23) | Finding 23 |
| Dashboard/notification layer for parallel sessions (Claude Code's "agent view") and fixed-position status elements (status line, subagent status rows) | Addresses the "7 fronts" framing directly and is already shipped by Anthropic; sidesteps the summary-position-within-text question entirely by putting the takeaway in a screen position independent of scroll (Findings 14, 22) | Research-preview status for agent view (maturity/stability not established in this research); does not reduce verbosity within a session's own chat text once the engineer does read it | Findings 14, 22 |
| Subagent-returns-a-summary pattern | Already the exact shape of 4Shark's own subagent contract; bounds a worker's full process to a return value by construction | Only applies to subagent/delegated work, not to the main session's own turn-by-turn narration during a single long task | Finding 14 |

## What remains uncertain

- Whether Claude Code (or the underlying Claude model) specifically became *more* verbose in the exact "last few weeks" window the engineer describes (mid-June to mid-July 2026) was **not confirmed** by any source found. The corroborating evidence (Findings 8–11) establishes that verbosity complaints exist and that some post-cutoff model comparisons claim measurable increases, but none is dated or scoped precisely enough to confirm the engineer's specific timing claim.
- Whether the third-party verbosity-comparison numbers (Findings 10–11) are methodologically sound is unknown — neither source discloses its evaluation protocol in the content fetched.
- Whether "Firehose" (Finding 3) or any other single term is in wider use elsewhere in the community beyond the one GitHub issue found.
- Whether a *custom* Claude Code output style (as opposed to CLAUDE.md prose) authored specifically for terseness would outperform the existing CLAUDE.md-level instructions already in place — not tested; the built-in styles examined (Finding 13) all move toward more verbosity, not less.
- **(Round 2)** Which specific Claude Code interface the engineer is using — terminal, desktop app, VS Code extension — was not confirmed in this spike, though the sticky-bottom-during-streaming pattern was independently corroborated across at least two of those variants (Findings 18–19) and is described as the general, deliberate chat-UI convention regardless (Finding 20).
- **(Round 2)** Whether the "release auto-scroll on manual scroll-up" half of the pattern is currently working correctly in the specific Claude Code version and interface the engineer runs. Finding 19 shows this exact mechanism has been reported broken (forced-bottom overriding manual scroll-up) in at least one desktop-app version range — so the engineer's own described escape hatch ("a não ser que eu deixe parado no topo") may or may not reliably work depending on version, and this spike did not test the currently-installed version's actual behavior.
- **(Round 2)** Finding 21 (Reddit TL;DR placement rationale) is an explicit non-finding — it neither supports nor weakens any option and should not be read as evidence either way.
- The BLUF general-definition finding (Finding 16) rests on search-synthesis rather than a direct WebFetch of a primary source — its substance (the term exists, means summary-first, is contrasted with summary-last) is corroborated across multiple independent search results but was not independently re-verified against a single fetched page. Its *application to a streaming medium* was investigated directly in round 2 (Finding 17) and found unsupported by every source located.
- Whether Anthropic has any *unshipped* or *upcoming* mechanism (e.g., a future hook event, a future `MessageDisplay`-style capability) that would change the Finding 1 conclusion was not investigated — this spike covers the currently-documented hook surface only, as of the fetch date in this session.

## Suggested options for main and the engineer

- **Option A — Prompt-level rule for a closing marker + terse final paragraph, summary-LAST (the engineer's original hypothesis).** Accepting it is advisory-only (same enforcement tier as the existing Output Policy reminder and Anthropic's own base conciseness instructions — Findings 1, 12), this placement is now the one grounded in how Claude Code's own interfaces actually behave during streaming — the reader's default resting position is the bottom (Findings 18–20), matching where a closing summary would land. Sustained by: Findings 1, 12, 18, 19, 20.
- **Option B — Summary-first placement inside chat text.** **This option is weakened relative to round 1.** The sources originally used to support it do not, on closer reading, actually support placing a summary at the *top of an individual streamed chat message* — they describe a different medium (a session dashboard, or the human's own first outgoing message). Not dropped entirely — the underlying "the reader wants the takeaway without reading the whole body" motivation is still valid — but the community evidence for placing it specifically inside chat-message text, at the top, is unsupported by what this spike found. Sustained by: Findings 15, 17 (both explicitly show why the round-1 support does not hold).
- **Option C — Extend the existing Output Policy's decision-bearing-content gate to also cover long operational narration**, not just comparisons/findings/≥3-item lists — i.e., widen Layer 5's pacing-gate trigger conditions so a long single-session turn or narrated status update also routes to a bounded summary, the same way a code review does today. Orthogonal to the position question — works the same regardless of where a summary sits. Sustained by: Finding 23.
- **Option D — Lean on the fixed-position, out-of-band surfaces (`claude agents` / agent view, the status line, `subagentStatusLine`) for the "7 fronts" framing specifically**, sidestepping the summary-position-within-text question entirely by putting the at-a-glance takeaway somewhere with a screen position independent of scroll. Treat within-session verbosity as a separate, harder problem that prompt-level rules can only partially address given Finding 1's mechanical ceiling. Sustained by: Findings 14, 22.
- **Option E — Combine A + D**: a summary-LAST prompt convention for what appears inline in chat (matching the medium's actual reading position), plus the dashboard/status-line layer so the engineer is not forced to read every session's chat at all to know which of the 7 fronts needs attention. Sustained by: Findings 1, 12, 14, 18–20, 22.

No recommendation is made among these — the mechanical ceiling (Finding 1) applies equally to A and C: neither can be *enforced*, only requested, and the evidence in Findings 8–12 is that requesting has a documented but incomplete effect. What round 2 changes is the *design* question, not the *enforcement* question: the engineer's summary-last premise is now the one grounded in confirmed streaming-UI behavior (Findings 18–20), while round 1's summary-first alternative turned out to rest on sources that do not actually address this medium (Findings 15, 17) — that correction is reflected in Options A and B above, not in whether either can be mechanically guaranteed. The engineer and main should weigh how much of the actual complaint is "content that should be in chat is too long, and if it is going to be long the takeaway should be where I'm already looking" (Options A/C) versus "I cannot see which of 7 sessions needs me at all" (Option D), since the sources diverge on which of these is the more tractable half of the problem.

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim cites its source (`file:line` + quote, or URL + quote); an uncitable claim is written as "Not found: <…>" instead. Large or structured evidence goes to auxiliary files (`{topic}_{kind}_{n}.{ext}`) in the same directory, each referenced from this document by relative link. The `output-verifier` runs the seven structural checks after the write — including citation integrity and auxiliary-file integrity — and the `policy-verifier` checks convention conformance.
