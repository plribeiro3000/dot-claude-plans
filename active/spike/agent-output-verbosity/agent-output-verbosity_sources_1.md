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

**REVISED scope note (round 4, see entries 24–26 below): this round-1 fetch's prompt did not surface `MessageDisplay`, a hook event that DOES exist in this same documentation and CAN reshape the on-screen render (though not the transcript quoted above). The "No hook can modify Claude's generated message text in the transcript or conversation history" claim remains correct as stated — it is scoped to the transcript — but round 1 did not carve out the on-screen-display exception because its fetch prompt did not ask about it. See SPIKE.md Finding 27.**

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

**See entries 24–25 below (round 4) for the full re-fetch of this document — the system-prompt mechanism, the CLAUDE.md comparison table, and the custom-output-style creation flow.**

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

Significance: the "one-line summary" the author describes is a **session status line in a dashboard/overview**, not the chat transcript text of an individual session. Round-1 Finding 9 applied this quote to "summary-first inside a streaming chat message" — that application over-reaches what the source supports. The source does NOT address where a summary belongs within a single streamed chat message.

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

---

# Revision round 4 — custom output styles (Gap 1) and hook-surface re-check (Gap 2)

Two narrowly-scoped follow-ups requested by the engineer after round 3. This section documents every source fetched for both.

---

## 24. code.claude.com/docs/en/output-styles — full re-fetch, system-prompt mechanism and CLAUDE.md comparison

URL: https://code.claude.com/docs/en/output-styles (fetched twice in this round with different targeted prompts; identical content returned both times — self-check per Citation Discipline rule 5 satisfied)

> Output styles change how Claude responds, not what Claude knows. They modify the system prompt to set role, tone, and output format.

> A custom output style adds your instructions to the system prompt and lets you choose whether to keep Claude Code's built-in software engineering instructions. Keep them when you're changing how Claude communicates but still coding, like always answering with a diagram. Leave them out when Claude isn't doing software engineering at all, like a writing assistant or data analyst.

> Output styles directly modify Claude Code's system prompt.
>
> * All output styles have their own custom instructions added to the end of the system prompt.
> * All output styles trigger reminders for Claude to adhere to the output style instructions during the conversation.
> * Custom output styles leave out Claude Code's built-in software engineering instructions, such as how to scope changes, write comments, and verify work, unless `keep-coding-instructions` is set to `true`.

> Output style is part of the system prompt, which Claude Code reads once at session start. Changes take effect after `/clear` or a new session.

Comparison table ("Comparisons to related features"):

> | Feature | How it works | Use it when |
> | Output styles | Modifies the system prompt | You want a different role, tone, or default response format every turn |
> | CLAUDE.md | Adds a user message after the system prompt | Claude should always know your project conventions and codebase context |
> | `--append-system-prompt` | Appends to the system prompt without removing anything | You want a one-off addition for a single invocation |
> | Agents | Runs a subagent with its own system prompt, model, and tools | You want a separately scoped helper for a focused task |
> | Skills | Loads task-specific instructions when invoked or relevant | You have a reusable workflow |

Frontmatter reference:

> `keep-coding-instructions` | Keep Claude Code's built-in software engineering instructions | Default: `false`

Significance: this is the primary source for SPIKE.md Findings 22 and 23. It directly answers "does a custom output style replace or append" (both — its own text is always appended to the end of the system prompt, but Claude Code's built-in coding instructions are dropped by default unless explicitly kept) and "how does it compare structurally to CLAUDE.md" (different location in the prompt construction — system prompt itself vs. a separate user message after it — with no documented claim about relative enforcement strength).

---

## 25. github.com/drona23/claude-token-efficient — benchmark/SUMMARY.md

URL: https://github.com/drona23/claude-token-efficient/blob/main/benchmark/SUMMARY.md

> N=5, single session, no statistical controls. Directional signal only.

The document compares:
1. Baseline vs. minimal CLAUDE.md profile: ranging from -1% (haiku) to -18% (sonnet)
2. Baseline vs. compressed CLAUDE.md profile: ranging from -22% (haiku) to -62% (opus)

Explicitly does NOT contain any comparison between a CLAUDE.md-only approach and an output-style-based approach — confirmed by a direct, targeted re-fetch that searched specifically for such a comparison and for a "Caveman" style claim (see entry 26).

Significance: the only benchmark located in this research that discloses its own methodology (even if minimal — "N=5, single session, no statistical controls"), but it tests CLAUDE.md against itself in two formulations, not a custom output style against CLAUDE.md. Sustains SPIKE.md Finding 24 (no comparative evidence found) and is the source used to check and reject the "Caveman" claim in Finding 25.

---

## 26. WebSearch synthesis claim — "Caveman" output style, ~65% token reduction — checked and rejected

An initial WebSearch synthesis pass, when asked to compare CLAUDE.md vs. output-style token efficiency, produced:

> The "Caveman" style (ultra-concise output) achieves roughly 65% fewer tokens over a full work session for significant savings in both cost and context window usage.

A direct, targeted WebFetch of `github.com/drona23/claude-token-efficient/blob/main/benchmark/SUMMARY.md` (the document this synthesis appeared to be describing, per entry 25 above), searching explicitly for this exact claim, returned:

> There is no mention of alternative prompt styling approaches or terse output formats in this document for me to quote.

Significance: per Citation Discipline rule 1 (quote-or-drop) and rule 4 (UNVERIFIED tag), this specific numeric claim is REJECTED — it does not verify against its apparent source. Recorded here (mirroring the "AI Brain Fry" treatment in entry 13 above / SPIKE.md Finding 7) to document that the check was performed. This claim does not sustain SPIKE.md Finding 25 as a positive claim — it sustains it only as a documented, checked-and-rejected candidate.

---

## 27. news.ycombinator.com — HN discussion on CLAUDE.md token-reduction effectiveness

URL: https://news.ycombinator.com/item?id=47581701

> the file loads into context on every message, so on low-output exchanges it is a net token increase

> Every single API call to Claude sends the whole context, including prompts, meaning that all this extra text in CLAUDE.md is sent over and over and over again every time you prompt Claude to do something.

> I made a test which runs several different configurations against coding tasks from easy to hard... across 30 tests, this does perform worse

> I too included the last bit about user prompts overriding system prompt, but like any good LLM, it doesn't always follow instructions.

Caveat: informal public forum comments, undisclosed methodology (task set, scoring, sample composition beyond "30 tests"), single commenters. Used only as anecdotal corroboration in SPIKE.md Finding 26, not as a standalone sustaining source for any option.

---

## 28. code.claude.com/docs/en/hooks — targeted re-fetch, MessageDisplay capability

URL: https://code.claude.com/docs/en/hooks (fetched three separate times in this round with progressively narrower prompts; identical substance returned each time — self-check per Citation Discipline rule 5 satisfied)

Fetch 1 (broad capability table for all non-tool hook events):

> `MessageDisplay`: While assistant message text is displayed
>
> `MessageDisplay` | `displayContent` replaces the displayed text on screen. Display-only: the transcript and what Claude sees keep the original

Fetch 2 (targeted specifically at MessageDisplay's trigger, fields, and restrictions):

> **Trigger Condition**: MessageDisplay: While assistant message text is displayed. This hook fires during the streaming display of the assistant's response text.
>
> **Available Output Fields**: `displayContent` replaces the displayed text on screen. Display-only: the transcript and what Claude sees keep the original
>
> **Matcher Support**: `UserPromptSubmit`, `PostToolBatch`, `Stop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `WorktreeCreate`, `WorktreeRemove`, `MessageDisplay` | no matcher support | always fires on every occurrence
>
> **Stop and SubagentStop**: `Stop`, `SubagentStop` | Top-level `decision` | `decision: "block"`, `reason`. Stop and SubagentStop also accept `hookSpecificOutput.additionalContext` for non-error feedback that continues the conversation

Fetch 3 (single exact sentence, character-for-character):

> `displayContent` replaces the displayed text on screen. Display-only: the transcript and what Claude sees keep the original

Fetch 4 (use-case search — redaction, verbosity, summarization):

> The documentation does not provide specific use case examples for the `MessageDisplay` hook event, including redaction of API keys, secrets, or hostnames. The hook is only briefly mentioned in the lifecycle table and decision control reference.

Fetch 5 (PreCompact capability, requested explicitly by the round-4 brief):

> PreCompact fires before context compaction occurs during a Claude Code session. The matcher filters on what triggered compaction: `manual` | Manual compaction, `auto` | Auto compaction. The documentation contains no explicit statement that PreCompact can access, inspect, modify, or gate the assistant's generated response text. PreCompact is compaction-focused and receives only compaction-related metadata (the trigger type: `manual` or `auto`). There is no mention of assistant message content, response text, or the ability to modify Claude's generated output in the PreCompact section.

Significance: primary source for SPIKE.md Findings 27, 29, and 30. `MessageDisplay` is confirmed real and shipped, display-only, with no documented use case naming verbosity/summarization. `PreCompact` is confirmed to carry no response-text access. `Stop`/`SubagentStop` re-confirmed unchanged from round 1's Finding 1. Note: the more granular claims from the WebSearch-synthesis pass (entry 29 below) — specific JSON input field names (`session_id`, `turn_id`, `delta`, etc.), the "redact API keys" use case, and streaming-chunk-batch execution timing — did NOT independently verify against this direct-fetch primary source and are NOT used to sustain any SPIKE.md Finding; they are recorded separately in entry 29 as UNVERIFIED-against-primary-source.

---

## 29. WebSearch synthesis — MessageDisplay introduction version, JSON fields, and use case (secondary, lower-confidence)

A WebSearch pass (not a direct WebFetch of Anthropic's own documentation) produced the following claims:

> The new MessageDisplay hook event was introduced in v2.1.152.

> MessageDisplay is display-only: the replacement text changes only what is rendered on screen. The transcript and what Claude sees keep the original text, so Claude never sees the replacement, and verbose mode shows the original.

> MessageDisplay hooks receive JSON input including fields like session_id, transcript_path, cwd, hook_event_name, turn_id, message_id, index, final, and delta, and can return displayContent to replace the delta on screen.

> MessageDisplay doesn't support matchers and fires for every assistant message that streams text; messages with no text, such as tool-call-only responses, don't trigger it. In non-interactive runs, including Agent SDK queries and claude -p, MessageDisplay runs once per assistant message instead of once per batch of lines.

> MessageDisplay can be used to redact API keys or internal hostnames from Claude's responses.

Caveat: the "display-only, transcript unchanged" claim independently corroborates the directly-fetched hooks.claude.com quote (entry 28) and is treated as verified via that separate primary-source confirmation. The version number (v2.1.152), the specific JSON field list, the streaming-batch-vs-once-per-message execution detail, and the "redact API keys" use case were NOT independently confirmed by direct WebFetch of code.claude.com/docs/en/hooks (a targeted follow-up fetch explicitly searching for these details found none of them — see entry 28, Fetch 2 and Fetch 4). These specific sub-claims are flagged lower-confidence / search-synthesis-only and are used in SPIKE.md only where explicitly marked as coming from a secondary source (Finding 28's version/date claim, sourced instead to entry 30 below, a directly-fetched secondary article, not this search synthesis).

---

## 30. dev.classmethod.jp — "Claude Code v2.1.152 Major Updates"

URL: https://dev.classmethod.jp/en/articles/20260524-claude-code-updates-v2-1-152/

> A new hook event `MessageDisplay` has been added, allowing you to transform or hide the text of displayed assistant messages.

> Claude Code v2.1.152 was released on May 26, 2026.

Caveat: this is a secondary, third-party source (a Japanese developer blog), fetched directly (not search-synthesis) — the article itself discloses no further detail on MessageDisplay beyond this brief description. Used in SPIKE.md Finding 28 specifically for the version/date claim, with the caveat that Anthropic's own changelog was independently attempted (entry 31 below) and did not corroborate or contradict this — it simply did not surface the entry in the portion returned.

---

## 31. Anthropic's own CHANGELOG.md — direct fetch attempted, MessageDisplay entry not surfaced

URL (rendered GitHub page): https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md — returned a GitHub-interface error page, no changelog content extracted.

URL (raw): https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md — fetched successfully; searched explicitly for "MessageDisplay" and related terms.

> No matching entries were found. The changelog contains no references to "MessageDisplay" or hooks designed to transform assistant message display. While there are numerous entries discussing hooks (SessionStart, Setup, PreToolUse, PostToolUse, SubagentStart, Stop, SubagentStop, Notification), none specifically address message verbosity control or assistant-text transformation capabilities.

URL (plain-text view, scoped to versions 2.1.208–2.1.211): https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md?plain=1 — also did not surface a MessageDisplay entry in the portion returned; the tool explicitly noted the content was truncated and versions below 2.1.208 were not covered by that fetch.

Significance: this is a genuine gap, not a negative finding — the changelog file is approximately 437KB (per GitHub's own file-size metadata surfaced on the rendered-page fetch attempt), well past what a single WebFetch pass reliably processes in full (the same intermediate-model-truncation caveat documented for entry 1 above). The absence of a MessageDisplay entry in what WAS returned does not establish it is absent from the file entirely — it establishes only that this round's fetch attempts did not locate it. Finding 28's version/date claim is therefore sourced to the secondary dev.classmethod.jp article (entry 30), not to this attempted direct fetch of the primary changelog.

---

## 32. WebSearch — GitHub issue titles, response-text-gating feature requests beyond #2880

Search query used: "github anthropics/claude-code issue feature request verbosity control response length hook 2026"

Issue titles returned (not independently WebFetched in full):

> [FEATURE] Add verbosity control for MCP tool call display · Issue #14684
> [Feature Request] MCP Tool Output Verbosity Control · Issue #12728
> [FEATURE] /Context is too verbose · Issue #48798
> [Feature Request] Add diffDisplay setting to control Edit tool output verbosity · Issue #21520

Significance: none of these titles, on their face, address gating or reshaping the assistant's own final generated chat response text — they target MCP tool-result display, the `/context` command's own output, and Edit-tool diff display. Used in SPIKE.md Finding 31 as a titles-only, lower-confidence negative result: no new feature request beyond #2880 (entry 2 above) was found targeting the specific mechanism this spike investigates.
