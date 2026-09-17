# SPIKE — Message-Drafting Failure: Why a Two-Paragraph Slack Message Took 10+ Correction Turns

## Investigation question

In session `9b16cef9-3c24-44f6-9498-08c9e9ba4852` (Claude Desktop app, 2026-09-15/16), the engineer asked the agent for a short, one-paragraph, internal Slack message to his employee Camila, explaining what she needs to relay to a third party (the client contact, Bruna). The agent needed more than 10 correction turns to converge. The engineer's own framing of the question (turn 36, verbatim): *"isso é um problema de prompt? Meu prompt não está sendo claro o suficiente? Isso é um problema de entendimento? Isso é uma alucinação?"*

This spike answers, with turn-by-turn citations against the session transcript:
1. What was the root cause, per failure category, and how much of the 10+ turns is agent failure vs. prompt ambiguity?
2. Did the standing per-turn hook injections (Output Policy, Code Pattern Discipline) contribute?
3. What is the smallest mechanical/doc surface that would have prevented this, and what does it trade off?

## Sources consulted

- The session's own JSONL transcript (primary source, read via `jq` extraction and direct `Read` of the distilled excerpt) — every citation below is `transcript_excerpt_1.md:<line>`, itself a byte-verbatim, timestamp-preserving distillation of the raw JSONL with only two categories of content removed: (a) the per-turn hook `additionalContext` blocks are counted and measured but not inlined a second time (their exact text is quoted directly from the JSONL, not from the distillation, where noted), and (b) `tool_result` blocks (hook success/attachment noise), which carry no engineer or agent authored content.
- See auxiliary: `transcript_excerpt_1.md` — the full distilled transcript (1,137 lines), every real user prompt and every assistant text/tool_use block, in order, with original ISO timestamps. This is what every `transcript_excerpt_1.md:<line>` citation below resolves against.
- Raw JSONL (not copied into the spike folder — it lives at `~/.claude/projects/-Users-plribeiro3000-Library-Application-Support-Claude-scratch-workspaces-8f665862-1ef3-4d28-8f21-62fb3334ec37-9a7ec5f2-7bb8-44d1-995e-84c63754a262-scratch-2026-09-15-8df81f/9b16cef9-3c24-44f6-9498-08c9e9ba4852.jsonl`, personal session data outside the plans repo) — consulted directly via `jq` for the two data points the distillation deliberately strips: the per-turn hook injection text and sizes (Finding 6), and the raw `.message.content` of individual user turns (used to confirm turn 26 carries no prepended system-reminder, i.e. its content is 100% engineer-authored).

## Findings

### Finding 1: The false "we already ran the first integration test" claim was not an unprompted invention — it was one of two clauses the engineer himself typed and then rejected in the same message, and it also contradicted the agent's own already-established, cited findings from earlier in the same session

**Evidence — the source of the claim, in the engineer's own prompt:**

`transcript_excerpt_1.md:993`:
> "É legal falar: 'Olha, o time foi fazer a integração, fazer o primeiro teste da integração, mas deu erro porque o token não tá mais válido.' Aí você pode falar: 'A gente até tinha feito um processo para rodar diariamente, mas não funcionou, deu pau.' Mas a pessoa acha que isso é meio injeção de saco. É só falar, cara: 'A gente precisa de um token novo. O token expirou.'"

The engineer floats two example framings ("team ran the first test and it failed"; "we had a daily process but it broke"), then in the same breath rejects both as `"injeção de saco"` (padding) and settles on the minimal version: "we need a new token, it expired."

**Evidence — the agent's turn-26 draft, `transcript_excerpt_1.md:998`:**
> "Oi Camila! Já me situei aqui no que ficou pendente da Magnatech, então nem precisamos de call — te adianto por aqui. **O time foi rodar o primeiro teste da integração e não deu certo porque o token de acesso ao Tiny da Magnatech expirou.** Pra destravar, a gente precisa de um token novo [...]"

The agent correctly filtered OUT the second rejected clause ("processo diário que quebrou" — confirmed by its own trailer at `transcript_excerpt_1.md:1001`: *"Cortei a parte do 'processo diário que quebrou' (é a tal enrolação que ela não vai processar)."*) but kept the FIRST rejected clause ("team ran the first test") as literal fact. This is selective, not wholesale, filtering: the agent had the information needed to recognize both clauses were offered-then-retracted, and applied that recognition to only one of the two.

**Evidence — this also contradicts the agent's own earlier, cited, same-session conclusion.** Nineteen hours earlier in the same session, the agent had already established, with a direct Slack quote, that the integration script had never been created and nothing had ever run:

`transcript_excerpt_1.md:219`:
> "**2. Script de integração/coleta de dados — ESSE nunca foi feito.** [...] em **03/08/2026** a Camila mandou o arquivo `produtos_2026-07-30-11-03-32.xls` com a mensagem *'segue o arquivo de produtos/categorias da Magna Tech **para quando for possível criar o script**'*. Ou seja, em agosto ainda estavam esperando alguém criar."

`transcript_excerpt_1.md:235` restates the same conclusion (*"nunca foi feito, exatamente como você lembrava"*), and the engineer's own turn 21 message (`transcript_excerpt_1.md:860`, sent 16 minutes before turn 26) still frames the integration as something he is *going* to do ("aí depois eu vou fazer a integração com esse token"), future tense — confirming nothing had changed between the 09-15 finding and the 09-16 message draft.

**Evidence — the engineer names the falsity directly, `transcript_excerpt_1.md:1004`:**
> "A Camila sabe que é mentira. A Camila sabe que a gente não foi fazer o primeiro teste de integração, cara. A gente não está fazendo ainda porque a gente estava focado num cliente maior."

**Significance:** the mechanism is more precise than "hallucination" in the sense of inventing content from nothing. It is a comprehension failure over an ambiguous, self-revising instruction (picking the example clause instead of the settled clause within one message), compounded by a failure to cross-check the resulting claim against findings the agent itself had already established and cited earlier in the same session. Both are real, citable defects; neither is "the agent made something up unprompted." This distinction matters for Finding 8 (fix selection): a rule that says "never invent facts" does not target either actual mechanism.

### Finding 2: Non-incremental rewriting caused previously-accepted content to silently disappear, and reappear only after the engineer explicitly asked for it back — twice

**Evidence — the "we don't need a call" opener, present in the very first draft, dropped for five consecutive turns:**

- Turn 26 draft (`transcript_excerpt_1.md:998`) opens: *"então nem precisamos de call — te adianto por aqui."*
- Turn 27's rewrite (`transcript_excerpt_1.md:1009`, reacting to Finding 1) drops it entirely: *"Oi Camila! Pra gente seguir com a integração da Magnatech eu preciso de um token novo [...]"* — no mention of skipping the call.
- The opener stays absent through turns 28, 29, 30, 31 (`transcript_excerpt_1.md:1020, 1035, 1048, 1059-1061`) — none of these turns asked for its removal; it was lost as a side effect of turn 27's full rewrite and never regenerated.
- Turn 32, the engineer flags the gap (`transcript_excerpt_1.md:1065`): *"Cadê a parte que vai falar Camila? Acho que a gente não precisa mais da reunião."*
- Turn 33 (`transcript_excerpt_1.md:1076`) names the defect directly and explicitly:
  > "Não, cara, não é para tirar uma coisa e colocar outra. **É para adicionar.** É o texto de antes, adicionando a mensagem de que não precisa mais da reunião. **Não é tirar uma coisa e adicionar outra, porra.**"
- Only at turn 33's response (`transcript_excerpt_1.md:1078-1082`) is the opener restored.

**Evidence — the same pattern recurs with the "team went to test integration" clause, this time in the other direction:**

- Turn 28, the engineer explicitly asks to reinstate the "team ran the test" framing (`transcript_excerpt_1.md:1015`); the agent complies (`transcript_excerpt_1.md:1020`).
- Turn 30's rewrite (`transcript_excerpt_1.md:1047-1049`, addressing the meta/relay problem in Finding 3) drops that clause again, with no request to remove it.
- It stays absent through turn 31's draft (`transcript_excerpt_1.md:1058-1062`, which is a near-verbatim copy of the engineer's own dictation at `transcript_excerpt_1.md:1056` — the engineer's own dictated text also does not carry the "team tested" clause at this specific point, so its absence here is jointly caused).
- Turn 34, the engineer flags the second disappearance (`transcript_excerpt_1.md:1085`): *"Cadê a parte que explica que, quando o time foi fazer o teste de integração, o token [expirou]?"*
- Turn 34's response restores it (`transcript_excerpt_1.md:1090`).

**Significance:** across turns 27→33 and 28→34, the pattern is identical — each correction round regenerated the whole message from the latest instruction rather than applying a targeted change on top of the previously-converged text, and content that had been accepted in an earlier round was silently lost when a later round rewrote for an unrelated reason. The engineer named this exact mechanism unprompted (turn 33), independent of this investigation.

### Finding 3: The agent collapsed a two-audience, two-truth-level message structure into a single ready-made forwardable script

The engineer's actual request (clarified progressively, turns 29-30, 35) was: a message from Paulo to Camila, explaining the situation to Camila and telling her what to convey to Bruna — not a verbatim script for Camila to copy-paste to Bruna.

**Evidence — turn 29's draft collapses the two audiences into one artifact, `transcript_excerpt_1.md:1034-1039`:**
> "Oi Camila! Já me situei aqui [...]
>
> Segue o que você pode passar pra ela:
>
> 'Oi Bruna! O time foi fazer o primeiro teste da integração e esbarrou num problema: [...] Consegue marcar um horário rápido com o Paulo pra fazer isso junto? É bem rápido.'"

The agent wrote a literal, quoted, ready-to-send script in Camila's voice, addressed to Bruna.

**Evidence — the engineer's turn-29 complaint identifying the actual ask, `transcript_excerpt_1.md:1026-1030`:**
> "Eu preciso mandar uma mensagem para Camila para ela falar com a Bruna. O que ela tem que explicar para a Bruna é o texto. **Esse texto que você mandou é o texto que ela vai mandar. Eu não quero o texto que ela vai mandar.** Eu quero que você gere o texto que eu vou mandar para ela, explicando que ela tem que falar para a Bruna."

**Evidence — turn 30 makes the constraint on the Bruna-facing part explicit, `transcript_excerpt_1.md:1045`:**
> "Você não pode falar o que ela vai falar, velho. [...] **Ela tem que escrever nas palavras dela.** Se eu mandar um texto, a menina vai saber que quem escreveu não foi a Camila. **O texto tem que ser escrito pela Camila.**"

Turn 30's response (`transcript_excerpt_1.md:1048`) correctly resolves this — it replaces the quoted Bruna script with an instruction for Camila to explain "com as suas palavras." This resolution held for the rest of the thread; the meta/relay structure itself was not re-broken after turn 30, though the engineer restates the same underlying constraint once more at turn 35 (`transcript_excerpt_1.md:1102`) as part of a broader re-framing that also touches Finding 1's issue again.

### Finding 4: The parent session's own self-critique (written before this spike was spawned) is not fully supported by the transcript on two of its three claims

Before spawning this investigation, the same session wrote a preliminary self-assessment (`transcript_excerpt_1.md:1131-1135`). It is useful as a hypothesis to check against the evidence, not as a settled finding — subagent output is evaluated on its own merits regardless of what the spawning turn already believed.

**Claim checked — "eu ter inventado um fato" (turn 26's hallucination):** partially supported. The FALSITY of the claim and its presence in outbound text are both real and citable (Finding 1). But "invented" overstates the mechanism — the content was drawn from the engineer's own draft-then-rejected example text, not generated independently. The more precise, and arguably more actionable, description is "failed to track a same-message self-revision, and failed to cross-check the result against its own already-established session facts."

**Claim checked — non-incremental editing / regression:** fully supported, and is the most cleanly evidenced finding in this spike (Finding 2), including the engineer's own naming of the defect (`transcript_excerpt_1.md:1076`).

**Claim checked — "somei ruído por cima (o 'ao vivo comigo', o 'tudo bem')":** not supported by direct evidence in this sub-thread.
- `"ao vivo comigo"` is grounded in fact established earlier in the same session (`transcript_excerpt_1.md:866`: *"é rápido, mas tem que ser na hora (o code expira em segundos)"*), was offered as optional/cuttable by the agent itself at `transcript_excerpt_1.md:1001` and `transcript_excerpt_1.md:1023` ("se achar que pesa, corta"), and the engineer never asked for it to be cut — it survives unchanged through the final turn-35 draft (`transcript_excerpt_1.md:1107`).
- `"tudo bem"` does not appear in any of the ten drafted message bodies in this sub-thread (`transcript_excerpt_1.md:998, 1009, 1020, 1034-1039, 1048, 1058-1062, 1067-1073, 1078-1082, 1087-1091, 1104-1110`, checked directly). The only occurrence of the phrase in the whole sub-thread is the engineer's own pre-emptive remark at `transcript_excerpt_1.md:1054` ("não precisa colocar tudo bem"), which reads as the engineer talking through his own phrasing rather than correcting agent output — there is nothing to correct.

**Significance:** a fix aimed at "stop adding unrequested pleasantries/hedges" would be solving a problem this transcript does not show happening. The two well-evidenced mechanisms are Finding 1 (comprehension of self-revising instructions + no fact cross-check) and Finding 2 (non-incremental rewriting).

### Finding 5: Turn-by-turn classification and quantification

The engineer's own count ("mais de 10 prompts") matches: turns 26 through 35 are ten user turns spent on the message itself (turn 36 pivots to requesting this investigation and is excluded).

| Turn | transcript_excerpt_1.md line | What the turn asked | Primary category | Agent-attributable? |
|---|---|---|---|---|
| 26 | 989-993 | Initial ask, with a self-revising example (state-then-reject) | Comprehension of self-revision (Finding 1) | Yes |
| 27 | 1003-1004 | "That's a lie, Camila would know" | Reacting to turn 26's error | Yes (turn 26 caused it) |
| 28 | 1014-1015 | Reinstate the "team tested" framing | Engineer reversal | No |
| 29 | 1025-1030 | "You wrote the script SHE sends, not the message I send her" | Meta/relay collapse (Finding 3) | Yes |
| 30 | 1044-1045 | "She has to write it in her own words" | Elaboration of Finding 3 | Partially (clarifying, not correcting a new error) |
| 31 | 1053-1056 | Tone/greeting, dictates near-exact wording | Style preference, engineer-driven | No |
| 32 | 1064-1065 | "Where's the 'no more meeting needed' part?" | Content regression (Finding 2) | Yes |
| 33 | 1075-1076 | "It's not remove-and-replace, it's ADD" — names the defect | Content regression (Finding 2) | Yes |
| 34 | 1084-1085 | "Where's the part about the team's test?" | Content regression (Finding 2) | Yes |
| 35 | 1093-1102 | Third reversal on the "team tested" framing + final structural clarification | Engineer reversal (again) + Finding 1 | Mixed |

**Quantification:** of the 10 correction turns, 5 (27, 29, 32, 33, 34) trace directly to an agent-caused defect independent of any new information from the engineer. 2 (28, 35) are the engineer reversing his own prior instruction on the same fact — a genuine, repeated self-contradiction (reject at 27, accept at 28, drop at 30, re-request at 34, reject again at 35 — three full reversals on one clause) that the agent never once surfaced back to the engineer as a contradiction requiring confirmation; it silently complied each time. 1 (31) is a style/tone preference dictated by the engineer with no clear prior agent error to react to. 1 (30) is a legitimate elaboration of an already-identified issue. Read plainly: roughly half of the ten turns are cleanly agent-caused, a smaller share is genuine (repeated) prompt self-contradiction, and even the self-contradiction turns were made costlier than necessary because the agent never asked a single clarifying question despite an identical clause being added, removed, and re-added three times across turns 27/28/30/34/35.

### Finding 6: The standing per-turn hook injections added measurable, task-irrelevant volume but show no direct causal link to the observed failures

**Evidence — exact injected content and size, read directly from the raw JSONL (not the distillation, which intentionally does not duplicate hook payloads):** every one of the 11 turns in this sub-thread (26 through 36) is preceded by exactly two `UserPromptSubmit` hook injections of fixed, identical size — `"=== OUTPUT POLICY REMINDER ==="` (6,051 characters) and `"=== CODE PATTERN DISCIPLINE (injected) ==="` (3,466 characters), confirmed via direct `jq` extraction of `.attachment.content[0] | length` for `hookName == "UserPromptSubmit"` across timestamps `2026-09-16T17:32:20` through `2026-09-16T17:51:28`. That is 9,517 characters (roughly 2,400-2,500 tokens) of injected context per turn, or approximately 104,700 characters (~26,000+ tokens) across this ten-turn sub-thread alone, on a task that involved zero code, zero file writes, and zero HTML rendering.

**No direct evidence of causal contribution was found.** Checking the actual assistant behavior in turns 26-36 against the four Output Policy triggers that could plausibly apply (HTML rendering for comparisons/decisions, the closing-summary requirement, the "Code Pattern Discipline: read siblings before writing code" instruction, the ">3 items, ask one-at-a-time" rule): none fired. Every response in this sub-thread was a plain-text chat reply with a single fenced code block; no `tool_use` calls occur anywhere between `transcript_excerpt_1.md:994` and `transcript_excerpt_1.md:1117` (confirmed by direct inspection — no `[TOOL_USE: ...]` marker appears in that range). The Code Pattern Discipline injection, which is explicitly scoped to "writing or editing production code," had no code to apply to and produced no visible effect.

**One weaker, non-causal but worth-naming correlation:** a `Stop` hook (`validate-decision-evidence.sh`) blocked the immediately preceding turn (`transcript_excerpt_1.md:952-976`, timestamp `17:29:07`, on an unrelated PLAN.md options-fork) for presenting a decision without a code excerpt. This is the only hook-driven `Stop` block in the entire session. It does not recur in the message-drafting sub-thread and there is no evidence it influenced turn 26 onward — turn 26's response was appropriately terse and conversational, not report-shaped.

**A second, plausible but unproven contributing signal:** every turn also carries a static `"output_style"` attachment (`transcript_excerpt_1.md` distillation strips this; confirmed directly in JSONL) reading *"Proactive output style is active. Execute autonomously, minimize interruptions, prefer action over planning."* This is consistent with — though not shown to cause — the pattern in Finding 5: the agent complied with every instruction, including three full reversals of the same fact, without ever pausing to ask one clarifying question ("you've asked me to add and remove this same claim three times — which is it?"). This is a plausible contributing disposition, not a proven one; no turn in the transcript shows the agent considering and rejecting the option to ask.

### Finding 7: No structural mechanism nudges incrementality for chat-delivered text, unlike file-delivered text

When drafted content lives in a file, the `Edit` tool structurally requires an `old_string`/`new_string` pair — the model is, by construction, working against a diff, not a blank page. When drafted content is delivered directly as chat text (as the Camila message was, throughout this entire sub-thread — no file, no `Write`, no `Edit` tool call), there is no equivalent structural pressure: the model regenerates the full fenced block from scratch on every turn, and nothing in the tool surface distinguishes "this is a targeted correction" from "this is a fresh draft." Finding 2's regression pattern is consistent with this asymmetry — every one of the ten drafts in this sub-thread was a from-scratch fenced code block, never an incremental diff notation of any kind.

CLAUDE.md's existing "Planning Documents Discipline" section ("restructure properly — never patch") governs the opposite direction for a different artifact class (files like PLAN.md/TASKS.md, where the instruction is to prefer full restructuring over patching). There is no existing rule, in either direction, for a short human-facing text artifact drafted and redrafted directly in the chat channel.

## Trade-offs surfaced

| Candidate fix | Targets | Pros | Cons | Evidence base |
|---|---|---|---|---|
| CLAUDE.md rule: "iterative text drafting = incremental diff, preserve prior content unless explicitly told to remove it" | Finding 2 (non-incremental rewriting) | Cleanest, most repeated, most explicitly-named-by-the-engineer failure; generalizes beyond this one message to any multi-turn chat-delivered text artifact (PR descriptions, emails, messages); doc-only rules of this shape already exist and work as reminders (e.g. Planning Documents Discipline, No Premature DRY) | Does not address Finding 1 (fact cross-check) or Finding 3 (audience/relay structure); "preserve prior content" is itself a judgment call a hook cannot verify (semantic diff of freeform prose) | Findings 2, 5, 7 |
| CLAUDE.md rule: "when drafting a message a human will send, use only the facts provided; never invent facts; ask for what's missing" | Framed at Finding 1, but mismatched to the actual mechanism | Addresses a real category of risk (unconfirmed claims in outbound human-facing text) | As phrased, "never invent" does not describe what happened (a cherry-picked clause from the engineer's own rejected example, not an invention) — a rule matching the wrong mechanism is easy to satisfy in letter while missing in spirit; would not obviously have caught "select the settled clause, not the offered-then-rejected one" or "cross-check against this session's own established facts" | Findings 1, 4 |
| Hook: Stop-boundary content-similarity check between consecutive chat-delivered drafts, gated on words like "adicionar"/"não é pra tirar" in the triggering prompt | Finding 2 | Mechanical, would catch the exact regression pattern seen here | High false-positive risk: a full rewrite is sometimes correct (turn 27 legitimately needed to remove the fabricated clause wholesale); no existing precedent in the hook catalog for diffing free-text chat output against prior turns; likely to be noisy given how often a message legitimately needs full rewording | Finding 7 (considered, not evidenced as built or tested) |
| Disposition change: make the agent ask a clarifying question when the engineer reverses a prior instruction on the same fact | Finding 5's "3 reversals, 0 questions" observation | Would have collapsed turns 28/34/35 into one exchange | Cuts directly against CLAUDE.md's own Decision Authority resolution ladder and its cited rationale (issue #31497, "asking had no cost so I kept asking instead of thinking") — recommending more asking as a general fix reintroduces the exact failure mode that rule was written to eliminate; the tension is a design trade-off already made deliberately elsewhere, not a naive oversight | Finding 5, 6 |
| No mechanical/doc change | — | Zero cost | Leaves the most-repeated, most-explicitly-named failure (Finding 2) unaddressed, with a clear engineer-visible recurrence pattern (turns 27→33, 28→34) | Findings 2, 5 |

## What remains uncertain

- Whether the turn-35 draft was ever actually accepted — the engineer pivoted directly to requesting this investigation (turn 36) without confirming satisfaction with the last draft.
- What turn 31's "cara"/"tudo bem" complaint (`transcript_excerpt_1.md:1054`) refers to — no prior draft in this sub-thread contains either, so it may be dictation noise, a reference to something outside this transcript's scope, or the engineer pre-empting a worry rather than correcting actual output. Not resolvable from the transcript alone.
- Whether the "Proactive" output style's "prefer action over planning" framing is a genuine contributing factor to the agent's zero-clarifying-questions pattern (Finding 6) or coincidental — no turn shows the model explicitly weighing and declining to ask.
- Whether the same non-incremental-rewrite pattern recurs in file-delivered (Edit-tool-mediated) text drafting, where the tool itself imposes some diff structure — out of scope for this transcript, which shows only chat-delivered drafting.
- The root cause of the engineer's three-way reversal on the "team ran the first test" framing (turns 27 reject → 28 accept → 30 drop → 34 re-request → 35 reject again) — whether this is genuine indecision, voice-dictation artifacts (turn 34's "o token não expirou" almost certainly inverts the intended meaning given every surrounding turn asserts the opposite), or a distinction the engineer was trying to draw between "what Paulo tells Camila" vs. "what Camila tells Bruna" that took several turns to articulate. Cannot be disambiguated from the text alone.

## Suggested options for main and the engineer

- **Option A** — add a CLAUDE.md rule scoped to iterative, chat-delivered (non-file) text drafting: apply corrections incrementally, preserving all previously-accepted content unless the latest instruction explicitly asks to remove it. Doc-only (no mechanical hook is feasible for semantic content preservation across freeform prose, per Finding 7's reasoning and the precedent of other judgment-only rules in CLAUDE.md, e.g. Timeless Documentation's carve-out). This is the option best supported by the evidence in Findings 2, 5, and 7 — it targets the single most repeated, most explicitly-named-by-the-engineer failure, and it generalizes to any similar future artifact (PR descriptions, draft emails, messages). Its trade-off, stated plainly: it would not have prevented Finding 1 (the false-claim/no-cross-check turn) or Finding 3 (the meta/relay collapse) — those two are addressed, if at all, by separate, narrower interventions.
- **Option B** — a narrower, additional rule about cross-checking a claim of fact against what the session has already established before it goes into outbound human-facing text — targets Finding 1's actual mechanism more precisely than a generic "don't invent facts" rule would, but is harder to phrase generally and has a thinner evidence base (one occurrence in this transcript).
- **Option C** — no change targeting Finding 3 (the meta/relay collapse) — it self-corrected within the sub-thread (turn 30) once named, and does not show the repeat pattern that Findings 1 and 2 show.
- **Option D** — explicitly decline to address Finding 5's "zero clarifying questions across three reversals" pattern via a disposition change, given its direct conflict with the already-documented Decision Authority rationale; if the engineer wants this addressed, it needs to be scoped narrowly enough not to reopen the excessive-asking failure mode CLAUDE.md already fought to close.

(No recommendation is made among these — the evidence and the trade-offs are laid out above for the engineer to decide, per the options each row supports.)
