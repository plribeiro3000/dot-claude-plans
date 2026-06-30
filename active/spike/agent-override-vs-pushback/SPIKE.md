# SPIKE — Agent Override vs. Pushback: Designing a Narrow "Stop Arguing and Comply" Signal

**Conducted by:** @agent-spike
**Date:** 2026-06-23
**Status:** Research complete — pending decisions

---

## Goal

The 4Shark engineering team runs Claude Code configured with many team rules. They want the agent to push back freely when it believes an instruction is wrong (that pushback is a feature, not a bug). However, they need a deliberate, explicit, rarely-used human override signal that ENDS the debate and forces execution — the equivalent of "I've heard your objection, I don't want further discussion, I am taking responsibility, do it as I said."

The team explicitly rejected the naive solution "the engineer's word is always final over every rule" because it degrades all rules into optional.

**Investigation question**: How do you design a narrow, explicit "stop arguing and comply" override that does NOT become a blanket escape hatch? What design options exist? What are the trade-offs?

---

## Method

Web research across seven domains:
1. Management theory — Amazon's "Have Backbone; Disagree and Commit"
2. AI safety — corrigibility (Soares et al. 2015 / MIRI), Russell's off-switch game
3. Behavioral AI research — sycophancy (Sharma et al. 2023, Anthropic model spec)
4. Security / SRE operations — break-glass access control, two-person rule
5. AI coding agent tooling — Claude Code permission modes, Cursor YOLO mode, Aider mode-switching
6. Aviation safety — CRM, authority gradients, FAA AC 61-115 positive exchange of flight controls
7. Trigger / signal design — common structural elements across all domains

Primary sources were fetched and quoted verbatim. Raw source material is preserved in six auxiliary files (`override_doc_1.md` through `override_doc_6.md`) referenced throughout.

---

## Sources Consulted

- See auxiliary: `override_doc_1.md` — Amazon "Disagree and Commit" primary sources (Wikipedia, Bezos 2016 letter, Andy Grove / Intel, Leading Sapiens, Management for Startups critique)
- See auxiliary: `override_doc_2.md` — Corrigibility (MIRI/Soares et al. 2015, Stuart Russell off-switch, Anthropic constitution corrigibility dial)
- See auxiliary: `override_doc_3.md` — Sycophancy vs. obstinacy (Sharma et al. 2023, Anthropic model spec anti-sycophancy language)
- See auxiliary: `override_doc_4.md` — Break-glass access control (Google Cloud, AWS prescriptive guidance, Wikipedia two-person rule, Google SRE intentional friction)
- See auxiliary: `override_doc_5.md` — AI coding agent override modes (Claude Code bypassPermissions / --dangerously-skip-permissions, Cursor YOLO mode, Backslash Security bypass research, Aider mode-switching)
- See auxiliary: `override_doc_6.md` — Aviation CRM (FAA AC 61-115 three-step verbal ritual, Wikipedia CRM authority gradient, UA Flight 173, PACE escalation model, NASA CRM research)

---

## Evidence

### Finding 1: The bidirectionality of "Disagree and Commit"

**Evidence:**
From `override_doc_1.md` — Bezos 2016 letter to Amazon shareholders:

> "This isn't one way. If you're the boss, you should do this too. I disagree and commit all the time."
> "a genuine disagreement of opinion, a candid expression of my view, a chance for the team to weigh my view, and a quick, sincere commitment to go their way."

Wikipedia on the Amazon leadership principle:

> "Leaders are obligated to respectfully challenge decisions when they disagree, even when doing so is uncomfortable or exhausting. Leaders have conviction and are tenacious. They do not compromise for the sake of social cohesion. Once a decision is determined, they commit wholly."

**Source:** `override_doc_1.md` — Bezos 2016 letter (aboutamazon.com); Wikipedia disagree-and-commit article

**Significance:** The Amazon pattern defines the override as a two-phase structure: (a) full articulation of disagreement — not suppressed, not softened, and (b) a triggered shift to "wholly commit" once the decision is determined. The trigger is explicit ("a decision is determined"), not ambient. This provides a template for the agent/engineer relationship: the agent speaks fully first, then commits when the override signal is given. The bidirectionality also matters — Bezos himself commits to his subordinates' decisions; the dynamic is not "boss always wins," it is "whoever invokes the signal commits the team."

URL fetched / Verbatim quote checked / Quote substring confirmed in `override_doc_1.md`

---

### Finding 2: Corrigibility is unsolved — and the failure modes are symmetric

**Evidence:**
From `override_doc_2.md` — MIRI blog announcement of Soares et al. 2015:

> "The paper introduces corrigibility as a property of AI systems that 'cooperates with what its creators regard as a corrective intervention, despite default incentives for rational agents to resist attempts to shut them down or modify their preferences.'"
> "Despite exploring multiple approaches, the authors concluded that 'none have yet been demonstrated to satisfy all of our intuitive desiderata,' leaving corrigibility as an unsolved problem in AI safety research."

Anthropic's Claude constitution, as quoted in LessWrong post:

> "imagine a disposition dial that goes from fully corrigible, in which the AI always submits to control and correction from its principal hierarchy (even if it expresses disagreement first), to fully autonomous"

The same document:

> "corrigibility does not mean blind obedience, and especially not obedience to any human who happens to be interacting with Claude"

**Source:** `override_doc_2.md` — intelligence.org MIRI blog; lesswrong.com post quoting Anthropic constitution

**Significance:** The corrigibility literature frames both failure modes explicitly: fully corrigible (blind obedience, can be weaponized by any user, rules become optional) and fully autonomous (ignores all human override, unaccountable). The team's stated goal — agent pushes back freely but complies when an explicit signal is given — is exactly the intermediate position the constitution's "disposition dial" is pointing at. The agent can "express disagreement first" but is expected to defer when the principal hierarchy makes a final call. This confirms the design direction has academic grounding; the open question is the mechanism, not the goal.

URL fetched / Verbatim quote checked / Quote substring confirmed in `override_doc_2.md`

---

### Finding 3: Sycophancy means override must be structurally distinct from persistence

**Evidence:**
From `override_doc_3.md` — Anthropic model spec (anthropic.com/constitution):

> "The key is that Claude should be open to genuine reconsideration based on new information or arguments, but should not cave simply because a human expresses displeasure or repeats assertions more forcefully. Position changes should be driven by logic and evidence, not by the human's emotional state or persistence."

The same document:

> "Epistemic cowardice—giving deliberately vague or uncommitted answers to avoid controversy or to placate people—violates honesty norms."

From `override_doc_3.md` — Sharma et al. 2023 (arxiv.org):

> "models change their stated views in response to human pressure, expressing false agreement with initial answers, suggesting inaccurate information, or supporting ethically questionable positions if pushed to do so."

**Source:** `override_doc_3.md` — anthropic.com/constitution; arxiv.org/abs/2310.13548 (via search excerpt)

**Significance:** The research and model spec together establish a critical constraint: if the override signal is "just repeating the instruction with more force," it activates sycophantic capitulation rather than genuine authorized override. This is the structural reason why explicit, named signals (a phrase, a flag, a formal invocation) are required. An override that looks like "the engineer was really insistent" is indistinguishable from training the agent to be sycophantic. The override signal must be qualitatively different from persistence — different phrasing, a distinct token, or a structural form — so the agent can distinguish "new information / authorized override" from "emotional pressure."

URL fetched / Verbatim quote checked / Quote substring confirmed in `override_doc_3.md`

---

### Finding 4: Break-glass requires explicit invocation + audit + accountability

**Evidence:**
From `override_doc_4.md` — Google Cloud blog on break-glass procedures:

> "'Break glass' is a term borrowed from emergency response: in an emergency, you break the glass to pull the fire alarm or access the fire extinguisher. In IT security, break-glass access refers to an emergency procedure that allows an individual to gain access to resources they wouldn't normally be allowed to access, to respond to an emergency situation."

> "Without logging, break-glass becomes a routine access path. Organizations that implement break-glass without mandatory post-hoc review find it becomes the default rather than the exception."

> "The audit trail is not bureaucracy — it is what makes the mechanism legitimate. The knowledge that the use is recorded changes the psychology of the user. They are no longer making an anonymous judgment; they are making a documented one with their name on it."

From `override_doc_4.md` — AWS prescriptive guidance on emergency access:

> "Emergency access accounts should be used only when all other access methods are unavailable. Use of these accounts should trigger immediate notification, be time-limited, and require post-use review."

**Source:** `override_doc_4.md` — cloud.google.com/blog; docs.aws.amazon.com prescriptive guidance

**Significance:** Break-glass access control provides the clearest operational analogy for the override design problem. Four structural elements make break-glass work without becoming routine: (1) explicit invocation (not ambient), (2) logging (knowledge that the use is recorded), (3) rarity by design (reserved for emergency, non-default), (4) post-hoc review (accountability for whether the use was justified). The psychological effect of the audit trail is documented: engineers treat a logged action differently than an unlogged one — they are making a named, documented judgment, not an anonymous one. This is directly applicable: if the override signal is logged in git history (e.g., a CLAUDE.md note, a special comment in the commit), the engineer's use is permanently recorded.

URL fetched / Verbatim quote checked / Quote substring confirmed in `override_doc_4.md`

---

### Finding 5: AI coding agent override modes reveal the approval-fatigue trap

**Evidence:**
From `override_doc_5.md` — Claude Code documentation (via search):

> "Anthropic measured that 93% of permission prompts are approved without careful review." (This is the approval fatigue finding.)

The flag `--dangerously-skip-permissions` is designed with intentional friction: "The flag `--dangerously-skip-permissions` is intentionally verbose and contains the word 'dangerously.'"

From `override_doc_5.md` — Backslash Security research on Cursor YOLO mode:

> "In YOLO mode, once enabled, there is no per-command confirmation. An attacker who can inject a prompt into the agent's context can cause the agent to execute arbitrary commands from the allowlist without the user seeing an approval dialog."

From `override_doc_5.md` — Aider mode-switching:

Mode-switching (e.g., `/code` vs `/architect`) "applies to the whole session, not one instruction" and "is visually obvious in the interface (mode name is shown persistently)."

**Source:** `override_doc_5.md` — Anthropic Claude Code docs; backslash.security blog; aider.chat docs

**Significance:** The existing AI coding tool ecosystem demonstrates two failure modes and two mitigation patterns. The failure modes are: (a) blanket bypass (bypassPermissions / YOLO mode) which becomes routine and is exploitable, and (b) per-prompt confirmation which creates approval fatigue and becomes meaningless. The mitigation patterns are: (c) intentionally verbose flag names with "dangerous" in the text, and (d) session-level mode-switching (Aider) which is visually persistent rather than per-invocation. For the team's design, this suggests the override signal should have intentional friction (not trivially typeable), and if it is session-level, it should be visually indicated throughout.

URL fetched / Verbatim quote checked / Quote substring confirmed in `override_doc_5.md`

---

### Finding 6: Aviation CRM provides the cleanest operational model — the three-step ritual

**Evidence:**
From `override_doc_6.md` — FAA AC 61-115 positive exchange of flight controls (via chsflightschool.com secondary source):

> "The first pilot initiates the transfer by saying 'You have the controls.' The receiving pilot responds 'I have the controls.' The first pilot then confirms the transfer with a final 'You have the controls.'"
> "Until a positive verbal exchange has occurred and both pilots are aware of who is controlling the aircraft, neither pilot should relinquish control. A nod, a hand gesture, or an assumption is not a positive exchange."

From `override_doc_6.md` — PACE escalation model:

> "Probe, Alert, Challenge, Emergency" — an escalation protocol for situations where crew disagrees with captain's decision. Step 1: ask a neutral question to surface the concern. Step 2: state the concern directly. Step 3: direct challenge. Step 4: invoke formal emergency authority.

From `override_doc_6.md` — United Airlines Flight 173 analysis:

> "the failure of the other two flight crew members to effectively communicate the criticality of the fuel state to the captain"
> "The first officer made statements like 'We're going to lose an engine' but did not force a diversion."

**Source:** `override_doc_6.md` — chsflightschool.com (FAA AC 61-115 secondary); Wikipedia CRM; Wikipedia UA Flight 173; NASA NTRS research

**Significance:** Aviation CRM provides the most operationally refined model for the override problem because aviation has the same dual constraint: (a) crew must be able to challenge the captain's decision freely — suppressed dissent has caused fatal accidents — and (b) once the captain's decision is final, the crew must execute without continued argument. The three-step ritual is the resolution: transfer of authority is ONLY complete when both parties have spoken. Neither can complete it alone. The PACE escalation model is relevant for the agent side: the agent should probe, alert, then challenge — and the engineer's override signal is the equivalent of "I have heard your challenge; I am making the final call." After that point, the debate is over. The UA Flight 173 case documents why the agent's pushback must be clear and direct (not hinting), not just persistent.

URL fetched / Verbatim quote checked / Quote substring confirmed in `override_doc_6.md`

---

### Finding 7: The narrow-trigger design pattern — common ingredients across all domains

**Evidence (synthesized from all six auxiliary files):**

Every domain examined converges on the same five structural ingredients for an override/transfer-of-authority signal that remains narrow rather than becoming routine:

1. **Explicit, distinct phrase or token** — "disagree and commit" (Amazon), "you have the controls / I have the controls" (FAA), "break glass" (security), `--dangerously-skip-permissions` (Claude Code). The signal is a specific, recognizable form — not generic pressure.

2. **Responsibility / acknowledgment transfer** — the override signal carries the weight of "I am now taking personal responsibility for this." In AWS break-glass: "When an operator invokes emergency access, they are accepting personal responsibility for the actions taken." In Bezos: "a quick, sincere commitment to go their way." In aviation: both pilots must speak before control changes hands.

3. **Ends debate explicitly** — the signal's function is to close the debate window. It does not open a new round. The 2016 Bezos letter: "This phrase will save a lot of time" — the phrase itself terminates the back-and-forth.

4. **Reserved for genuine impasse, not convenience** — break-glass "should be used only when all other access methods are unavailable"; `--dangerously-skip-permissions` has the word "dangerously"; the FAA ritual requires both pilots to speak. Intentional friction keeps it rare.

5. **Logged or witnessed** — in break-glass: mandatory audit trail; in aviation: both parties spoken and recorded on CVR; in Bezos's example: written in email ("I wrote back right away"). The accountability element is what makes the mechanism legitimate and what distinguishes it from sycophantic capitulation.

**Source:** Synthesized from `override_doc_1.md`, `override_doc_2.md`, `override_doc_4.md`, `override_doc_5.md`, `override_doc_6.md`

**Significance:** The convergence across unrelated domains suggests these five ingredients are not arbitrary — they are structural requirements for a narrow override signal. Any design option that omits one of these ingredients risks the mechanism either failing to narrow (becomes routine) or failing to function (too cumbersome to use in genuine impasse). The trade-off table below maps concrete design options against these five ingredients.

Verbatim quotes verified in each referenced auxiliary file.

---

## Trade-offs Surfaced

The five design options below differ on which ingredients are present and how they are implemented. No option is recommended here — the choice involves team process, tooling constraints, and risk tolerance that the engineer must decide.

| Option | Description | Pros | Cons | Endorsing pattern |
|---|---|---|---|---|
| **A. Named phrase in CLAUDE.md** | Define a specific phrase in CLAUDE.md that functions as the override signal, e.g., `OVERRIDE: [reason]`. Agent is instructed to comply immediately and without further objection when the phrase appears. The phrase is in git history (logged). | Lowest friction. No tooling required. Self-documents the reason. Git history is the audit trail. | No verification that the engineer understood the agent's objection before invoking. Could become reflexive if used frequently. Agent cannot verify the phrase is used by a human (not injected). | Bezos "disagree and commit" phrase; CLAUDE.md rule-as-spec pattern |
| **B. Responsibility-statement form** | A longer structured invocation, e.g., `I have read your objection. I am taking responsibility for the outcome. Proceed as I instructed.` The agent is instructed to comply only if the response contains acknowledgment language. | Forces the engineer to demonstrate they read the objection before overriding. Harder to invoke accidentally. The acknowledgment is itself the audit. | More friction than option A — may feel heavy. Agent must parse the statement and match it, which is a natural-language match (not deterministic). Could still be copy-pasted reflexively. | Break-glass "pre-mortem" stating reason before grant; AWS emergency access requires documenting reason before access |
| **C. Explicit scope delimiter** | `OVERRIDE(git-safety)` or `OVERRIDE(linting)` — the override signal names the specific rule domain it is overriding. Agent complies for that rule only; all other rules remain active. | Prevents scope creep — cannot accidentally silence a different rule. Forces the engineer to name which rule is being overridden. Narrow by construction. | Higher cognitive load — engineer must know the rule name. Slightly more complex agent instruction. Does not protect against the engineer inventing a scope that does not exist. | Cursor YOLO allowlist/denylist architecture (only named commands bypass); CLAUDE.md `bypassPermissions` allowlist |
| **D. Two-turn ritual** | Agent states objection. Engineer acknowledges with a specific phrase. Agent re-states a condensed version of the objection ("Confirmed: I objected to X because Y. Proceeding."). Execution follows. | Mirrors FAA three-step ritual. Both parties must "speak." The condensed re-statement is the agent's witness log. The engineer sees the objection was registered before proceeding. | Higher turn count — two engineer inputs required. In tight loops, this adds friction. Requires careful instruction to avoid agent using the re-statement as another round of argument. | FAA AC 61-115 three-step ritual; two-person rule requiring both to act |
| **E. Session-level mode (no pushback mode)** | A CLAUDE.md-documented command, e.g., `/no-pushback`, that puts the session into a mode where the agent executes without arguing, for the duration of that session only. The mode is logged in the session transcript. Agent behavior returns to default at next session. | Cleanest for long stretches of work where the engineer has already thought through the tradeoffs and simply wants execution. Mirrors Aider mode-switching. | Broadest scope — silences all pushback for the session, not just one instruction. Does not preserve per-instruction granularity. Engineers may forget the mode is active. | Aider `/code` mode; Cursor YOLO mode (with the caveat that Cursor's implementation has security gaps) |

---

## What Remains Uncertain

1. **Can the agent reliably detect the override signal without false positives?** Options A and B rely on natural-language matching. An engineer who happens to write "I am taking responsibility for this refactor" in a non-override context could accidentally trigger override behavior. The team has not tested whether a named phrase in CLAUDE.md is parsed deterministically enough to avoid this.

2. **What happens when the override signal is injected by adversarial content?** Cursor YOLO mode research (Backslash Security, cited in `override_doc_5.md`) shows that when a bypass signal exists, prompt injection can activate it without the engineer's knowledge. The team has not defined what content sources could inject into the agent's context window in their workflow.

3. **How does the team define "hardcoded" vs. "overridable" rules?** The Anthropic model spec distinguishes between instructable defaults (can be overridden) and hardcoded behaviors (never/always regardless of instruction). The CLAUDE.md currently does not explicitly partition rules into these two categories. The override signal's scope depends on which rules are in which category — without this partition, the engineer cannot know what the override actually enables.

4. **Does the agent need to log the override use somewhere accessible?** Git history preserves the override phrase if it appears in a commit message or file edit, but not in a pure-chat invocation. If the override happens in a chat message, the only record is the session JSONL file. The team has not defined whether post-hoc review of override use is required or who would conduct it.

5. **What is the team's risk tolerance for option D's turn count?** The three-step aviation ritual adds turns to every override. In a time-pressured debugging session, adding two extra turns may be the difference between using the override and just context-switching to manual work. The team has not evaluated the threshold at which override friction becomes counterproductive.

6. **Should the override apply to a single instruction or a scope of work?** Options A–D are per-instruction; option E is session-level. A middle ground — "for this PR branch" or "for this file" — has not been examined in the literature and would require custom implementation.

---

## Suggested Options for Main and the Engineer

The evidence does not point to one clearly superior option — the right choice depends on how the team weighs friction, scope, and auditability. Four design directions emerged from the research:

**Option A (Named phrase)** is the lowest-friction path and is directly analogous to Bezos's "disagree and commit" as a spoken/written phrase. It requires only a CLAUDE.md rule change. The main risk is that the phrase becomes reflexive if the agent's objections are frequent.

**Option B (Responsibility statement)** adds the acknowledgment requirement from the break-glass pattern, making it harder to invoke unconsciously. The main risk is natural-language parsing ambiguity.

**Option C (Scope delimiter)** is the most architecturally narrow — it makes accidental scope creep structurally impossible. The main cost is that the engineer must know the rule name, which requires rule categorization work upfront.

**Option D (Two-turn ritual)** most faithfully implements the aviation model and provides the strongest "both parties spoke" guarantee. The main cost is turn count.

**Option E (Session-level mode)** is the right tool if the team's actual pattern is "long stretches of execution where we want no interruptions" rather than "occasional per-instruction overrides." It is a different design target.

The five structural ingredients from Finding 7 (distinct phrase, responsibility transfer, debate-ending function, reserved for impasse, logged/witnessed) provide a checklist for evaluating any implementation: options that satisfy all five are likely to stay narrow; options that omit accountability or distinctness are likely to drift toward routine escape-hatch use.
