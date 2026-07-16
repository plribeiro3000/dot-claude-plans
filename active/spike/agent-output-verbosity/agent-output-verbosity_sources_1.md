<!-- Auxiliary source file for SPIKE.md — raw fetched quotes, preserved for revision without re-fetching. -->

# Raw sources — agent output verbosity spike

Each entry: URL, fetch method, quote(s) extracted, and any caveat about the quote's reliability given the fetch mechanism (see "What remains uncertain" in SPIKE.md re: WebFetch's intermediate-model paraphrase risk).

---

## 1. Claude Code hooks reference

URL: https://code.claude.com/docs/en/hooks (redirected from docs.claude.com/en/docs/claude-code/hooks)

Fetched via WebFetch, prompt asked specifically whether any hook can modify/append to the assistant's own response text.

Key extracted content:

> Stop — Can output: additionalContext, decision: "block", reason, systemMessage, continue: false. Cannot do: Modify Claude's actual response text. Effect: additionalContext is injected as a system reminder that Claude sees on the next turn, not appended to the current message.

> PostToolUse — Can output: updatedToolOutput (replaces the tool result, not Claude's message), additionalContext, decision: "block", reason. Cannot do: Modify Claude's response text. Effect: Can only rewrite what the tool returned, not what Claude said about it.

> The additionalContext field passes a string from your hook into Claude's context window. Claude Code wraps the string in a system reminder and inserts it into the conversation at the point where the hook fired. Claude reads the reminder on the next model request, but it doesn't appear as a chat message in the interface.

> No hook can modify Claude's generated message text in the transcript or conversation history.

Caveat: WebFetch uses an intermediate model to process fetched HTML against the prompt, so these are the tool's rendering of the source, not a raw HTML dump. Treated as reliable because the tool explicitly labeled the additionalContext paragraph as a direct quote and the surrounding synthesis is internally consistent with 4Shark's own CLAUDE.md § Documentation Loading Model, which independently states the 10,000-character cap and the additionalContext/next-turn mechanism.

---

## 2. GitHub issue #2880 — anthropics/claude-code

URL: https://github.com/anthropics/claude-code/issues/2880
Title: "Feature Request: Support summarizing work done after Stop hook?"

> Stop hooks are super useful but their output and subsequent Claude interactions can cause a lot of spam from the nice summary message Claude gave right before the Stop initiated.
> It would be nice to have Claude not provide the summary message until the Stop hooks succeed.

Status: Closed, labeled `autoclose` / "not planned". No visible maintainer comment explaining the decision.

---

## 3. GitHub issue #29769 — anthropics/claude-code

URL: https://github.com/anthropics/claude-code/issues/29769
Title: "Claude Code over-explains and talks past direct questions instead of answering them"

> During a technical session, Claude Code repeatedly: (1) Responded to direct factual questions ("what is SIFS?") with multiple paragraphs re-explaining the user's own codebase before eventually answering (2) Defaulted to re-deriving context the user already has instead of giving direct answers (3) Required multiple corrections before actually addressing what was asked (4) Produced lengthy "here's what your system does" summaries when the user asked about external concepts.

> The pattern: when the user asks obvious questions, and especially when they signal that they have received unclear answers, Claude doubles down on verbosity and context-dumping instead of answering the quesiton [sic].

---

## 4. GitHub issue #65961 — anthropics/claude-code

URL: https://github.com/anthropics/claude-code/issues/65961
Title: "[MODEL] Claude verbose code comments by default — ignores instructions to stop."
Opened: 2026-06-07

Per WebSearch synthesis (not independently WebFetched in full): the issue reports that verbose code comments are the out-of-the-box default, that a mandatory CLAUDE.md rule does not reliably suppress it, and that reinforcing the rule via the memory system does not stop it either — the default is strong enough to override explicit user instructions.

Caveat: this entry came from WebSearch's synthesized snippet, not a direct WebFetch of the issue page — treat the exact wording as approximate, the substance (issue exists, is about verbose defaults resisting CLAUDE.md instruction) as corroborated by the issue title and search-result framing.

---

## 5. GitHub issue #33414 — anthropics/claude-code ("FireHose monitoring")

URL: https://github.com/anthropics/claude-code/issues/33414

> This is a feature distinct from, but might be a solution to many of the problems have with Claude showing insufficient thinking. There are a lot of Issues regarding the loss of functionality through increased conciseness in the output [#8477] [#8586] [#33163] [#8371]. Much of the debate seems to be about where the appropriate place for this information should be. As Claude works for longer and uses more tools, presenting the information inline has the potential to swamp other data.

> This output would be possibly extremely high volume, but that fact is indicated by the name Firehose. What users do with that output is up to them.

Significance: "Firehose" is used here as a proposed feature name (a separate output channel for high-volume internal reasoning), not established elsewhere as an adopted community term for the verbosity-overwhelms-the-operator problem. Treated as a single, isolated usage.

---

## 6. yzhao062/agent-style (GitHub repo)

URL: https://github.com/yzhao062/agent-style

> Make your AI agent write like a tech pro.

21 rules (RULE-01 through RULE-12 canonical, RULE-A through RULE-I field-observed) targeting "AI-tell" mechanical patterns. Relevant:

> RULE-04: Do not include needless words.
> RULE-E: Do not close every paragraph with a summary sentence.

Significance: a community style-guide project exists specifically to make agent output read less mechanically verbose; it explicitly discourages a paragraph-closing summary pattern as an "AI-tell", though this targets per-paragraph summaries, not a single end-of-response marker+summary.

---

## 7. Claude Code output-styles doc

URL: https://code.claude.com/docs/en/output-styles

> Claude Code's Default output style is the existing system prompt, designed to help you complete software engineering tasks efficiently.

> The built-in Explanatory and Learning styles produce longer responses than Default by design, which increases output tokens.

Significance: no built-in output style ships to make Default *more* concise than it already is; the only built-in verbosity-adjacent styles (Explanatory, Learning) go the opposite direction (more verbose, by design).

---

## 8. Claude Code "Run agents in parallel" doc

URL: https://code.claude.com/docs/en/agents

> Subagents — Delegated workers inside one session that do a side task in their own context and return a summary. Use it when: A side task would flood your main conversation with search results, logs, or file contents you won't reference again.

> Agent view — One screen to dispatch and monitor sessions running in the background, opened with `claude agents`. Research preview. Use it when: You have several independent tasks and want to hand them off, check status at a glance, and step in only when one needs you.

> For background sessions, `claude agents` opens agent view: one screen showing every session, its state, and which ones need your input.

Significance: this is Anthropic's own shipped feature aimed at the parallel-session-monitoring half of the engineer's problem — a dashboard/notification layer, not an output-shape constraint on any individual session's chat text.

---

## 9. tomrochette.com — "Managing Many Concurrent LLM Agent Sessions"

URL: https://tomrochette.com/managing-many-llm-agent-sessions/

> When one person can spawn a dozen LLM agent sessions in parallel, the bottleneck is no longer the agents. It is the human trying to keep track of them all.

> With multiple agent sessions running concurrently, many are perpetually unfinished, creating a constant background hum of attention residue.

> Lead with the one-line summary... If the summary says no action needed, you move on. You never read the details unless the summary demands it.

Significance: frames the multi-session problem via cognitive-psychology concepts (working memory, Zeigarnik effect, decision fatigue) rather than a single coined term.

**REVISED on re-fetch (round 2, see entry 17 below): this "lead with the one-line summary" quote lives under the article's "Strategy 6: Progressive Disclosure" section, describing a DASHBOARD/session-card view — not the chat transcript text of an individual session. The original round-1 finding over-applied this quote to "summary-first inside a streaming chat message." Corrected in SPIKE.md Finding 15.**

---

## 10. shiplight.ai — "The Human QA Bottleneck in Agent-First Teams"

URL: https://www.shiplight.ai/blog/human-qa-bottleneck-agent-first-teams

> As code throughput increased, our bottleneck became human QA capacity. [attributed to OpenAI engineering team]

Three attempted workarounds the article says do not solve the underlying problem: relaxing CI gates, requiring human review (leads to "reviewer fatigue and rubber-stamping within weeks"), adding QA staff.

Proposed direction: move verification into the agent's own loop (browser automation, self-checked screenshots) rather than structured output/dashboards for humans.

---

## 11. superset.sh — "The Complete Guide to Running Parallel AI Coding Agents"

URL: https://superset.sh/blog/parallel-coding-agents-guide

> On a modern laptop, 5-7 concurrent agents are comfortable. Beyond that, you may want to stagger agent launches or limit concurrent builds.

> Start with 2-3 until you're comfortable with the review workflow. Scaling to 10 before you can review at speed creates a backlog that slows everything down.

> If you run 10 agents and each produces a diff in 15 minutes, you have 10 diffs to review per hour.

---

## 12. shashi.co — "The Oversight Tax: Why AI Agents Are Not the Delegation Win Companies Expected"

URL: https://www.shashi.co/2026/04/the-oversight-tax-why-ai-agents-are-not.html

> the human is still in the loop. The loop just got longer, less predictable, and harder to step away from

No formal definition of "the oversight tax" beyond the essay title; does not address multi-agent parallelism specifically, focuses on single-agent supervision burden.

---

## 13. medium.com/@maxdolphin — "Human Oversight Under Load in the Age of AI Agents"

URL: https://medium.com/@maxdolphin/human-oversight-under-load-in-the-age-of-ai-agents-e943b6e6720d

> the human must allocate attention across competing machine initiatives, resolve ambiguity, validate uncertain outputs, and absorb a continuous stream of alerts

Note: an earlier WebSearch snippet attributed the term "AI Brain Fry" to Harvard Business Review via this article. Direct WebFetch of the article did NOT find this term present anywhere in the text, nor an HBR attribution. Per Citation Discipline rule 3 (no invented term attributions) and rule 4 (UNVERIFIED tag), this term is NOT used as a Finding in SPIKE.md and is recorded here only to document that it was checked and rejected.

---

## 14. Third-party model verbosity comparisons (secondhand claims — flagged)

### awesomeagents.ai — "Claude Sonnet 5 Review"
URL: https://awesomeagents.ai/reviews/review-claude-sonnet-5/

> Sonnet 5 is verbose. Testing by The Human Co found it averaging roughly a third more output tokens than GPT-5.5

> the updated tokenizer maps the same input text to roughly 1.0 to 1.35 times more tokens than Sonnet 4.6's tokenizer

Caveat: this is a secondhand claim (awesomeagents.ai citing "The Human Co"'s testing, which was not independently located or fetched). The chain of custody is unverified beyond this one blog's citation.

### medium.com/@reliabledataengineering — "Claude Opus 4.6 vs 4.5"
URL: https://medium.com/@reliabledataengineering/claude-opus-4-6-vs-4-5-what-actually-changed-and-whether-you-should-upgrade-ff46550e8a75

> Task: Explain concept in ~200 words. Opus 4.5: 187 words average. Opus 4.6: 267 words average. Change: +43% more verbose

> Opus 4.5: 4.2 comments average, 85 words total. Opus 4.6: 6.1 comments average, 143 words total. Change: +68% more verbose

> Opus 4.5: 68,000 tokens average. Opus 4.6: 91,000 tokens average [+34%]

> Adding 'be concise' to prompts: Helps ~20% but still results in +10-15% token usage

Caveat: independent blog/newsletter source, methodology (sample size, task set, evaluation protocol) not disclosed in the fetched content. Treated as a directional data point, not a validated benchmark.

---

## 15. dbreunig.com — "How Claude Code Builds a System Prompt"

URL: https://www.dbreunig.com/2026/04/04/how-claude-code-builds-a-system-prompt.html

> Only use emojis if the user explicitly requests it. Avoid using emojis in all communication unless asked.

> Your responses should be short and concise. [for external/non-Anthropic users]

> IMPORTANT: Go straight to the point. Try the simplest approach first without going in circles. Do not overdo it. Be extra concise.

> [For Anthropic-internal users] keep text between tool calls to ≤25 words. Keep final responses to ≤100 words unless the task requires more detail.

Caveat: third-party reverse-engineering of Claude Code's system prompt, not an official Anthropic publication. Presented as evidence that Anthropic's OWN shipped default already instructs conciseness textually (prompt-level), which is the same enforcement tier (advisory, not mechanical) as the engineer's hypothesized rule.

---

## 16. BLUF (Bottom Line Up Front) — Wikipedia / background

URL (search-derived, not directly WebFetched): en.wikipedia.org/wiki/BLUF_(communication)

Per WebSearch synthesis: BLUF is "the practice of beginning a message with its key information"; the search results explicitly distinguish it from "BLAB" (Bottom Line At the Bottom, "the traditional approach") and note Reddit's TL;DR-at-the-end convention as a contrasting summary-LAST placement.

Significance (revised — see entry 17 below): this establishes BLUF as a real, named convention, but its application to a *scrolling, streaming chat medium* was not established by any source found in round 1 or round 2 — every source scopes it to static documents (memo, email, report) or to authoring the FIRST outgoing message in a conversation, never to where a summary sits within a long incoming generated response. See SPIKE.md Finding 16/17 for the corrected scoping.

---

# Revision round 2 — medium/viewport investigation (engineer's scroll-position correction)

The engineer identified that Findings 9 and 10 (round 1) assumed a static-document reading model (eye lands at top) without checking whether that assumption holds in a streaming, auto-scrolling chat interface. This section documents the sources fetched to investigate that correction.

---

## 17. tomrochette.com — re-fetch, medium-specific

URL: https://tomrochette.com/managing-many-llm-agent-sessions/ (re-fetched with a prompt asking specifically what MEDIUM "lead with the one-line summary" refers to)

> Lead with the one-line summary. Every session status should begin with a single sentence that tells you whether action is needed: 'Session blocked, needs your decision on X' or 'Session running normally, 60% complete.' If the summary says no action needed, you move on.

This is under "Strategy 6: Progressive Disclosure": *"Information should arrive in layers, from summary to detail, on demand."*

Also under "Strategy 8: Build a Session Dashboard": *"A dashboard that lists all active sessions with their status, progress, and severity indicators lets you assess the entire fleet in one glance."* And: *"You never need to understand everything about every session to make a decision."*

Significance: the "one-line summary" the author describes is a **session status line in a dashboard/overview**, not the chat transcript text of an individual session's response. Round-1 Finding 9 applied this quote to "summary-first inside a streaming chat message" — that application over-reaches what the source supports. The source does NOT address where a summary belongs within a single streamed chat message.

---

## 18. GitHub issue #37627 — anthropics/claude-code

URL: https://github.com/anthropics/claude-code/issues/37627
Title: "[Bug] Terminal auto-scrolls to bottom while Claude Code is working, preventing manual scroll"

> When using Claude Code, I used to be able to scroll up in the terminal to review the plan while work was still in progress. Now, as Claude Code continues working, the terminal automatically jumps to the bottom, making it impossible to read earlier output without being pulled back down. Could you please fix this so the terminal stays in place when I've scrolled up?

Labels: `area:tui`, `bug`, `platform:macos`. Version: 2.1.81.

Significance: direct, independent confirmation (not the engineer's own claim) that Claude Code's terminal interface auto-scrolls to the bottom during active generation, and that this pulls the viewport away from a manually-scrolled-up position.

---

## 19. GitHub issue #53382 — anthropics/claude-code

URL: https://github.com/anthropics/claude-code/issues/53382
Title: "[BUG] Desktop app: chat window auto-scrolls to bottom during streaming even when user has scrolled up"

> While Claude is streaming a response (token-by-token / phrase-by-phrase), the chat window force-scrolls to the bottom on every update. This happens even when I have explicitly scrolled up to read earlier content — including scrolling all the way to the top of the conversation. The viewport is yanked back down on every new chunk, making it impossible to read previous messages while a response is being generated.

> Standard "sticky bottom" behavior used in terminals, chat apps and IDE chat panels: If the user is at the bottom of the scroll container, auto-scroll to follow new streaming content. If the user has scrolled up beyond that threshold, do NOT auto-scroll. Leave the viewport exactly where the user put it.

Confirmed as a regression bug (marked "Last Working: app-1.3561.0", "Broken In: app-1.4758.0") — i.e., the reporter's own framing is that "sticky bottom WITH release-on-manual-scroll" is the *correct*, previously-working behavior, and the all-the-time-forced-bottom behavior is the bug.

Significance: this independently corroborates BOTH halves of the engineer's description — (a) the default resting position during streaming is the bottom, and (b) manually scrolling away is supposed to release that default (matching "a não ser que eu deixe parado no topo"). It also shows this release mechanism is not always reliable in practice — the bug report exists precisely because the release stopped working in one version.

---

## 20. ui.shadcn.com — MessageScroller component docs

URL: https://ui.shadcn.com/docs/components/radix/message-scroller

> Follow only while they're following. If they're at the live edge, keep the stream in view. If they scroll away, leave them there.

> When the reader is at the live edge, either because they stayed there or returned there, `autoScroll` keeps streamed replies in view as they grow. Scrolling away from the live edge releases the view, whether by wheel, touch, keyboard scroll keys, or dragging the scrollbar.

> Move only when the reader asked to move. If someone is reading, don't pull them somewhere else. Auto-scroll should never be the default.

Significance: independent, Claude-Code-unrelated confirmation that "sticky bottom with release on manual scroll-away" ("live edge") is a named, standard implementation pattern for chat/streaming UI generally, not a Claude Code-specific quirk. This is the general community pattern the Claude Code bug reports (entries 18–19) are describing as the intended/expected behavior.

---

## 21. bitesizelearning.co.uk — BLUF applied to chat

URL: https://www.bitesizelearning.co.uk/resources/bluf-bottom-line-up-front

> Over email, that could mean putting it in the subject line itself, or on chat, including the request in the first message, rather than a pre-amble of 'you there?' ping-pong.

Significance: the only passage found in accessible BLUF literature that explicitly mentions "chat" scopes it to **composing the human's own initiating/outgoing message** (authoring advice — put your ask in your first message, don't ping-pong) — NOT to where a summary should sit within a long incoming generated response the human is reading. This directly weakens round-1 Finding 10's application of BLUF to "where should Claude's summary sit within its own streamed reply."

---

## 22. Reddit TL;DR-at-the-end placement — searched, no explicit medium argument found

Search query: "Reddit TL;DR at the end convention reason why placed at bottom not top scrolling" — no direct hits. A follow-up broader search on TL;DR placement rationale returned only general framing (TL;DR can be placed at top as "a preview and decision aid" or at bottom "as a classic conclusion"), with no source explaining WHY Reddit's specific convention defaults to the end, and no source connecting that placement to the scrolling nature of the medium (for or against).

Significance: explicitly a negative result. Neither "Reddit's TL;DR-at-the-end is a legacy/sloppy habit" nor "Reddit's TL;DR-at-the-end is deliberately adapted to a scrolling medium" is argued anywhere found. Recorded as "not found" per Citation Discipline rather than assumed either way.

---

## 23. code.claude.com/docs/en/statusline — direct raw fetch

URL: https://code.claude.com/docs/en/statusline (fetched via WebFetch; oversized response persisted to a local tool-results file and read directly via `Read`, so this is the literal source markdown, not an intermediate-model paraphrase)

> The status line is a customizable bar at the bottom of Claude Code that runs any shell script you configure. It receives JSON session data on stdin and displays whatever your script prints, giving you a persistent, at-a-glance view of context usage, costs, git status, or anything else you want to track.

> Work across multiple sessions and need to distinguish them [listed as one of the reasons status lines are useful]

> The subagentStatusLine setting renders a custom row body for each subagent shown in the agent panel below the prompt. Use it to replace the default `name · description · token count` row with your own formatting.

> The command runs once per refresh tick with all visible subagent rows passed as a single JSON object on stdin.

Significance: this is a genuine "third shape" that sidesteps the summary-position-within-scrolling-text question entirely — both the main status line and the per-subagent status rows occupy a **fixed screen position** (a bar/row rendered outside the scrolling message stream), updated on an independent refresh cycle, so a takeaway placed there does not compete with scroll position at all.
