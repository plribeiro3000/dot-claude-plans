# SPIKE — Credential Leakage in AI Agent Chat Output: Community Framing and the Advisory-vs-Mechanical Question

## Investigation question

How does the security community/industry frame the problem of secrets/credential VALUES leaking into an AI coding agent's **chat output** (as distinct from secrets leaking into prompts, training data, or via prompt-injection exfiltration)? Where does the community agree and where does it split on the mechanism — prompt-level/instruction-level guardrails vs deterministic/mechanical output-side enforcement? What concrete tools exist for output-side redaction, and what do OWASP/NIST say authoritatively? Finally: does the community corroborate 4Shark's current **advisory-only** Layer 0 rule (`~/.claude/CLAUDE.md` § Output Policy → Layer 0 — Never emit a credential value) as a legitimate defense-in-depth layer even without mechanical enforcement, or does the evidence point toward it being close to useless without a backstop?

This spike does not re-litigate the Claude-Code-specific mechanics (hooks, `MessageDisplay`, JSONL transcripts) — that ground was already covered in depth by the prior spike `~/.claude/plans/completed/spike/agent-secret-output-leakage/SPIKE.md`, whose engineer decision (2026-06-26) was "DO NOTHING MECHANICAL" for the reasons documented there. This spike instead asks: **what does the broader industry say about the class of problem**, so the engineer can decide how (and how strongly) to word the rule, informed by whether the community treats prompt-only defenses as legitimate or as theater.

**Scope — source-agnostic.** The concern is any credential VALUE reaching the Claude Code session's chat output, regardless of where the value came from: a file read, a command's output, a config or env var, a tool result (an email fetch is one such source, not the defining one), or text the engineer pasted. Earlier drafts of this spike over-indexed on the email vector; that was a narrowing of the briefing, not of the problem. Wherever an example names email below, read it as one instance of the general case — the rule under consideration guards the output side against a credential value from ANY in-session source.

## Relationship to the prior spike (read first)

`~/.claude/plans/completed/spike/agent-secret-output-leakage/SPIKE.md` already established, specific to Claude Code:
- No hook intercepts the model's generated response text before display; `MessageDisplay` only masks the on-screen render, "the transcript and what Claude sees keep the original" (official Claude Code docs, quoted in that spike).
- CLAUDE.md instructions are "advisory... they don't change what Claude Code allows" (Claude Code permissions docs, quoted there).
- The engineer's explicit, final decision was to accept an advisory-only Layer 0 rule with no mechanical backstop, because every mechanical option available inside Claude Code either fails to cover the free-form-credential-in-context case or destroys a legitimate capability worth keeping (reading/summarizing content that legitimately references a credential — a fetched document, a command's output, a config). The prior spike illustrated this with the email-fetch case; the reasoning is not specific to email.

This spike does not repeat that mechanical investigation. It complements it with the **industry-wide** view of the same trade-off, using non-Claude-Code sources (OWASP, NIST, guardrail vendors, independent security researchers), to test whether 4Shark's specific choice is aligned with, or diverges from, what the field considers reasonable.

## Sources consulted

- [OWASP GenAI Security Project — LLM02:2025 Sensitive Information Disclosure](https://genai.owasp.org/llmrisk/llm022025-sensitive-information-disclosure/) — canonical risk description + mitigation list, including the caveat on system-prompt restrictions
- [OWASP GenAI Security Project — LLM07:2025 System Prompt Leakage](https://genai.owasp.org/llmrisk/llm072025-system-prompt-leakage/) — "the system prompt should not be considered a secret, nor should it be used as a security control"
- [DeepInspect — OWASP LLM06/LLM02 output-side controls](https://www.deepinspect.ai/blog/owasp-llm06-sensitive-information-disclosure) — disclosure-path taxonomy ("in-context leakage") and gateway output controls
- [Simon Willison — The lethal trifecta for AI agents](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) — "how confident can you be that your protection will work every time?"
- [protectai/llm-guard — Secrets scanner (input-side) docs](https://github.com/protectai/llm-guard/blob/main/docs/input_scanners/secrets.md)
- [protectai/llm-guard — Sensitive scanner (output-side) docs](https://protectai.github.io/llm-guard/output_scanners/sensitive/)
- [Microsoft Presidio](https://presidio.dataprivacystack.org/) — general PII de-identification, not secrets-specific, not LLM-output-specific by its own description
- [Lakera — Data Leakage Prevention docs](https://docs.lakera.ai/docs/data-leakage-prevention) — input+output PII/system-prompt screening
- See auxiliary: `credential-leakage-in-agent-output_sources_1.txt` — full verbatim quote log for every source above, plus the additional lower-confidence sources (NeMo Guardrails, Guardrails AI, TruffleHog, NIST AI RMF, generic guardrail-vendor defense-in-depth framing) that are marked UNVERIFIED or search-synthesis-only where a direct page fetch was not obtained, per Citation Discipline

## Findings

### Finding 1: The vocabulary — "in-context leakage" is the precise term for 4Shark's scenario; it sits inside the broader "Sensitive Information Disclosure" risk category

**Evidence:** OWASP's GenAI Security Project names the overall risk category "Sensitive Information Disclosure" (currently numbered LLM02:2025; the same risk was LLM06 in the earlier ordering, so both numbers appear across the ecosystem depending on which revision a given source cites). A third-party synthesis of that OWASP category (DeepInspect) splits disclosure into three distinct paths:

> "Training-data leakage: The model emits content it memorized during training... In-context leakage: The model emits content that was supplied to it during the current session through retrieval, tool output, or system prompt content... Cross-tenant leakage: The model or the retrieval layer or the cache layer confuses one tenant's data with another's."

**Source:** [deepinspect.ai](https://www.deepinspect.ai/blog/owasp-llm06-sensitive-information-disclosure) — attribution is to DeepInspect's synthesis, not to OWASP verbatim (OWASP's own page does not use this exact three-way taxonomy in these words).

**Significance:** 4Shark's incident (a credential value enters the session context through some source — a file read, a command's output, a config/env var, a tool result such as an email fetch, or text the engineer pasted — and the agent then echoes it into the chat output while summarizing or explaining) is precisely "in-context leakage," not training-data memorization and not cross-tenant confusion. The OWASP/DeepInspect definition is itself source-agnostic — "supplied to it during the current session through retrieval, tool output, or system prompt content" — which is exactly why it fits the general case rather than the email vector specifically. This term usefully distinguishes the case from the adjacent, better-known problem of prompt injection causing exfiltration (Finding 4) and from training-data memorization (a different, unrelated failure mode). Community vocabulary for the mechanism side includes "output filtering," "output guardrails," "DLP" (data loss prevention), "redaction," "masking," and "secrets scanner" — all appear across the tool docs cited in Finding 3.

Verification block: URL fetched (deepinspect.ai) / verbatim quote confirmed present in fetched content at the location described / not re-fetched a second time (single-fetch verification only for this finding; the OWASP category-numbering claim is corroborated independently by both OWASP page fetches in Findings 2 and 5, which is the cross-check).

---

### Finding 2: OWASP explicitly denies system-prompt-level text the status of a "security control" — for a related but distinct risk (system prompt leakage)

**Evidence:**

> "It's important to understand that the system prompt should not be considered a secret, nor should it be used as a security control. Accordingly, sensitive data such as credentials, connection strings, etc. should not be contained within the system prompt language."

**Source:** [OWASP GenAI Security Project — LLM07:2025 System Prompt Leakage](https://genai.owasp.org/llmrisk/llm072025-system-prompt-leakage/), re-fetched and confirmed verbatim.

**Significance:** This OWASP item concerns a different failure mode than 4Shark's — it is about the model's *own* system prompt/instructions being extracted by an attacker, not about a user-supplied document containing a secret that the model echoes. It is cited here only for the general principle OWASP states about the *status* of prompt-level text: it is not to be relied upon as a security boundary. That principle is stated about system prompts specifically, but the underlying reasoning (prompt-level text shapes behavior probabilistically, it is not enforced) is the same reasoning that applies to any instruction-level rule, including a CLAUDE.md behavioral rule. This is presented as an analogous, transferable principle — not as OWASP addressing 4Shark's exact scenario.

Verification block: URL fetched twice (initial + re-verification) / verbatim quote "the system prompt should not be considered a secret, nor should it be used as a security control" confirmed present both times, together with the following sentence naming credentials and connection strings explicitly.

---

### Finding 3: OWASP's OWN mitigation list for Sensitive Information Disclosure includes system-prompt restrictions — but immediately caveats them as unreliable, and lists them as one item among several, not a standalone control

**Evidence:**

> "Adding restrictions within the system prompt about data types that the LLM should return can provide mitigation against sensitive information disclosure. However, such restrictions may not always be honored and could be bypassed via prompt injection or other methods."

This sentence sits in the same paragraph as other mitigations: data sanitization to prevent user data from entering training, and (elsewhere in the same document, per the earlier fetch summarized in the auxiliary file) tokenization/redaction via pattern matching and robust input validation.

**Source:** [OWASP GenAI Security Project — LLM02:2025 Sensitive Information Disclosure](https://genai.owasp.org/llmrisk/llm022025-sensitive-information-disclosure/), re-fetched and confirmed verbatim, full paragraph.

**Significance:** This is the single most directly relevant piece of authoritative guidance to the "is a prompt rule worth it" question. OWASP's position is neither "prompt rules are useless" nor "prompt rules are sufficient" — it is "prompt rules are A mitigation, listed alongside others, with an explicit unreliability caveat in the same sentence." OWASP does not say to skip the prompt-level mitigation; it says not to rely on it alone.

Verification block: URL fetched twice / verbatim quote confirmed present both times in the same paragraph, including the exact caveat sentence.

---

### Finding 4: A distinct, adjacent, more famous framing (Simon Willison's "lethal trifecta") independently arrives at the same unreliability conclusion for prompt-level defenses — for a different threat model

**Evidence:**

> "There are ways to reduce the likelihood that the LLM will obey these instructions: you can try telling it not to in your own prompt, but how confident can you be that your protection will work every time? Especially given the infinite number of different ways that malicious instructions could be phrased."

His recommended alternative: avoid combining the three trifecta elements (access to private data, exposure to untrusted content, ability to communicate externally) rather than trying to prompt the agent out of misbehaving once all three are present.

**Source:** [Simon Willison — The lethal trifecta for AI agents](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/), re-fetched and confirmed verbatim.

**Significance:** Willison's trifecta is about an *adversarial* scenario — an attacker's untrusted content instructing the agent to exfiltrate data it should not touch. 4Shark's case has no adversary and no injected instruction; it is a credential value benignly present in the session (from any source — a fetched document, a command's output, pasted text) that the agent over-summarizes into its output. The threat models differ. What transfers is narrower and more specific than the trifecta itself: Willison's stated reason for distrusting "tell it not to" — that LLM behavior is non-deterministic and "the infinite number of different ways instructions could be phrased" makes blanket coverage unreliable — is a mechanism-level argument that applies regardless of whether the source of the risky content is adversarial or benign. It corroborates Finding 3's caveat from an independent, non-OWASP source.

Verification block: URL fetched twice / verbatim quote confirmed present both times, including the immediately surrounding sentences.

---

### Finding 5: The output-redaction tool landscape treats "PII" and "secrets" as two different problems, and mature tooling for OUTPUT-side *secrets* detection specifically is thinner than for output-side PII

**Evidence:** In protectai's LLM Guard, the "Secrets" scanner — the one built on the detect-secrets engine (Yelp) capable of recognizing API tokens, private keys, and high-entropy strings — is documented as an **input**-side scanner only:

> "This scanner diligently examines user inputs, ensuring that they don't carry any secrets before they are processed by the language model."

The separate "Sensitive" scanner, which IS documented as operating on the model's **output**, is described in PII terms:

> "serves as your digital vanguard, ensuring that the language model's output is purged of Personally Identifiable Information (PII) and other sensitive data"

with example entity types given as "PERSON" and "EMAIL," extensible via regex — not shipped with credential-shaped detectors out of the box. Microsoft Presidio's own documentation lists detected entities as "credit card numbers, names, locations, social security numbers, bitcoin wallets, US phone numbers, financial data" — no secrets/credentials category, and no claim of being positioned for LLM/agent output use specifically.

**Source:** [protectai/llm-guard Secrets scanner docs](https://github.com/protectai/llm-guard/blob/main/docs/input_scanners/secrets.md), [protectai/llm-guard Sensitive scanner docs](https://protectai.github.io/llm-guard/output_scanners/sensitive/), [Microsoft Presidio](https://presidio.dataprivacystack.org/) — all fetched directly and quoted verbatim (see auxiliary for full text).

**Significance:** This is a factual gap in the tool landscape relevant to 4Shark's exact case. Off-the-shelf output-redaction tooling is built and marketed primarily around PII (names, emails, SSNs, card numbers) — a fundamentally regex/NER-friendly, format-recognizable category. A credential appearing in free-form text in the session ("the password is Xy9#mK2vL") — whether it arrived via a fetched document, a command's output, a config, or pasted text — does not have a fixed shape the way a card number or SSN does; it is exactly the kind of free-form secret that the *input*-side Secrets scanner (built for structured file content and command output) targets, but that documented output-side scanners do not clearly claim to catch. This does not mean no combination of tools could be assembled to cover it (a custom regex/entropy rule could be added to an output scanner) — it means no examined tool ships that coverage by default for arbitrary-text credential values in a fetched document. NeMo Guardrails' documentation (per search synthesis, not independently re-verified by direct fetch — see auxiliary) claims its output rails cover "secrets" alongside PII, which would be the one exception found, but this specific claim was not independently confirmed against the primary docs page within this spike's time-box.

Verification block: both protectai URLs and the Presidio URL fetched directly / verbatim quotes confirmed present as shown / NeMo Guardrails "secrets" claim explicitly flagged UNVERIFIED in the auxiliary file and not treated as a confirmed Finding here.

---

### Finding 6: The industry pattern for combining prompt-level and mechanical controls is "defense-in-depth" — prompt rules are consistently framed as one necessary-but-insufficient layer, never as a sufecient standalone answer, and never as literally worthless either

**Evidence:** This is reported as a pattern observed across multiple guardrail-vendor sources located via search (Datadog, Wiz, and generic "LLM guardrails" guides), not as a single verbatim quote from one named source — per Citation Discipline Rule 2 (no composite attribution), this is stated as an industry pattern rather than a Finding with one citation:

- "No single guardrail technique is sufficient. Combining input validation, output filtering, and system-level controls in a defense-in-depth approach is necessary."
- "Guardrails significantly reduce risk but cannot guarantee complete safety."
- "Prompt guardrails are a critical component of a full defense-in-depth strategy for LLM security... No single guardrail can stop every attack on its own."

**Source:** search-synthesis composite across multiple guardrail-vendor blog posts found via WebSearch on 2026-07-04 — NOT independently fetched and quoted from one named page; treated as a pattern, not a verified single-source Finding, per Citation Discipline.

**Significance:** Even in this lower-confidence, non-single-source form, the pattern is consistent with the higher-confidence Findings 3 and 4: nowhere in the material gathered does any source claim a prompt-level instruction alone constitutes a sufficient control, and nowhere does any source claim a prompt-level instruction contributes literally zero value. The consistent framing is "necessary layer, insufficient alone" — which is a middle position between "worth having" and "security theater."

Verification block: this Finding is explicitly NOT sustained by a single verified quote — it is reported as an unverified pattern observation and is excluded from the load-bearing chain in the Verdict below, per Citation Discipline Rule 7 (derivations from verified Findings only).

---

## Consensus vs. Division map

| | Prompt-level / instruction-level rule | Deterministic / mechanical output enforcement |
|---|---|---|
| **What it is** | A CLAUDE.md rule, a system prompt instruction: "never print a credential value" | Regex/entropy output scanner, DLP gateway, guardrail library post-processing generated text before it reaches the user |
| **Where the consensus sits** | **Agreement across every authoritative source gathered**: not a security control by itself. OWASP states this explicitly for system prompts (Finding 2); OWASP's own mitigation list caveats it in the same breath it recommends it (Finding 3); Willison's independent, non-OWASP framing reaches the same unreliability conclusion via a different threat model (Finding 4) | **Agreement that this is the layer that actually enforces**, when it exists: OWASP's broader mitigation list, past the system-prompt line, moves to "tokenization and redaction," "pattern matching," and "robust input validation" as the items expected to do the real work (Finding 3, auxiliary) |
| **Where division appears** | Division is NOT over whether prompt rules work reliably (no source claims they do) — it is over whether they are **worth having at all** given they don't. No source gathered argues they are worthless; the consistent framing (Finding 6, lower-confidence) is "necessary-but-insufficient layer" | Division appears in **tool coverage**, not in the principle: PII-shaped data (names, SSNs, cards) has mature, purpose-built output scanners (LLM Guard Sensitive scanner, Presidio-backed NeMo rails, Guardrails AI PII validator); free-form credential VALUES embedded in arbitrary prose (4Shark's exact case) do not have the same off-the-shelf output-side coverage — the purpose-built Secrets scanner examined (LLM Guard) is documented as input-side only (Finding 5) |
| **What nobody disputes** | Prompt-level text can be bypassed, ignored under ambiguous phrasing, or simply not followed reliably — this is stated by OWASP for a related risk and independently by Willison for an adjacent threat model; the reasoning (non-deterministic model behavior, infinite phrasings) is general, not scenario-specific | A mechanical layer, where it exists and is well-built, changes the outcome from "the model chooses not to" to "the text physically cannot pass through" — the entire reason OWASP lists redaction/DLP/pattern-matching as separate, additional line items rather than restating the system-prompt line |

**The genuine open question the sources do NOT resolve for 4Shark specifically:** every source addresses the case where a mechanical layer exists ALONGSIDE the prompt rule, as one of several layers. None of the gathered sources directly addresses the case 4Shark is actually in — a prompt rule as the ONLY layer, with mechanical enforcement deliberately rejected (per the prior spike's engineer decision) because the only mechanical options available inside Claude Code either fail to cover the free-form-credential-in-context case or destroy a capability worth keeping (reading/summarizing content that legitimately references a credential, from any source). This is a genuine gap between the general guidance and 4Shark's specific constraint set; see "What remains uncertain."

## Tool landscape (factual summary — see Finding 5 and auxiliary for verbatim detail)

| Tool | What it is | Operates on output specifically? | Covers secrets/credentials on output? |
|---|---|---|---|
| protectai/llm-guard — Secrets scanner | detect-secrets (Yelp)-based scanner for API tokens, private keys, high-entropy strings | No — documented as input-side only | N/A (input-side) |
| protectai/llm-guard — Sensitive scanner | PII/sensitive-data scanner, regex + Anonymize-scanner mechanisms | Yes | Not by default; PII-focused, extensible via custom regex |
| Microsoft Presidio | General PII de-identification library (cards, names, SSNs, locations, financial data) | Not specifically positioned for LLM output; general text/image tool | No — no secrets/credentials category in its own docs |
| NVIDIA NeMo Guardrails | Output rails framework; sensitive-data rail backed by Presidio/Private AI | Yes | Claimed in search synthesis ("secrets" alongside PII) — **not independently verified by direct fetch**, flagged UNVERIFIED |
| Lakera Guard | Commercial input+output DLP/PII/system-prompt screening | Yes (confirmed for PII and system-prompt content) | Secrets-on-output claim found only in search-result summaries, not in the directly fetched docs page — flagged UNVERIFIED for that specific claim |
| Guardrails AI | Open-source output validator library (Apache 2.0) | Yes | PII validator confirmed via search synthesis; secrets-specific validator not confirmed |
| TruffleHog | Git-repo/CI secret scanner (regex + entropy + live verification) | No — not an LLM-output tool at all | N/A — cited only as the origin of the entropy+regex detection technique other tools reuse |

## Authoritative guidance quotes (OWASP / NIST)

- OWASP LLM02:2025 (Sensitive Information Disclosure): *"Adding restrictions within the system prompt about data types that the LLM should return can provide mitigation against sensitive information disclosure. However, such restrictions may not always be honored and could be bypassed via prompt injection or other methods."* — [genai.owasp.org](https://genai.owasp.org/llmrisk/llm022025-sensitive-information-disclosure/)
- OWASP LLM07:2025 (System Prompt Leakage): *"the system prompt should not be considered a secret, nor should it be used as a security control. Accordingly, sensitive data such as credentials, connection strings, etc. should not be contained within the system prompt language."* — [genai.owasp.org](https://genai.owasp.org/llmrisk/llm072025-system-prompt-leakage/)
- NIST AI RMF Generative AI Profile (NIST AI 600-1): reported (not independently re-verified against the primary PDF within this spike's time-box — see auxiliary) to name "inference-time privacy controls (input filtering, output redaction)" as a mitigation-practice category, corroborating that "output redaction" is treated by NIST as a distinct, named control class alongside input filtering. This is flagged UNVERIFIED for exact wording and is not used to sustain the Verdict below.

## What remains uncertain

- Whether any examined output-redaction tool ships default, out-of-the-box detection for free-form credential values embedded in natural-language prose (as opposed to structured files/env vars) — the tools examined lean on PII entity recognition (names, SSNs, emails) or input-side secrets scanning, and none was confirmed, via direct fetch, to combine both on the output side by default.
- The NeMo Guardrails "secrets" output-rail claim, the Lakera "secrets on output" claim, and the exact NIST AI RMF wording — all flagged UNVERIFIED in the auxiliary file; a follow-up spike could re-fetch these primary sources directly if the tool landscape becomes decision-relevant (e.g., if 4Shark reconsiders mechanical enforcement).
- No source gathered addresses 4Shark's specific configuration — prompt rule as the SOLE layer, with mechanical enforcement deliberately and permanently rejected for functional reasons (not for lack of will to build it). All sources assume a prompt rule sits alongside some mechanical layer; none argues for or against a prompt-only regime as its own coherent stance. (This gap is independent of source: it holds for a credential arriving via any in-session channel, not just an email fetch.)
- Whether the "in-context leakage" terminology (Finding 1) is OWASP's own vocabulary or solely a third-party synthesis — the exact three-way taxonomy quoted was found on a vendor page (DeepInspect), not on the OWASP page itself; OWASP's own page was not observed to use this precise three-way split in these words.

## Verdict — is 4Shark's advisory-only Layer 0 rule corroborated by the community, or is it "security theater"?

Grounded strictly in Findings 2, 3, and 4 (Finding 6 and the tool-landscape claims are explicitly excluded from this chain per Citation Discipline, being either lower-confidence pattern observations or UNVERIFIED claims):

**The evidence does not support calling a prompt-level rule "worthless" or "theater."** No source gathered — OWASP across two separate risk items, or Simon Willison from an entirely independent angle — makes that claim. OWASP's own canonical mitigation list for this exact risk category *includes* the system-prompt restriction as a legitimate mitigation (Finding 3), which is direct evidence against the "theater" framing: OWASP does not omit it, and does not tell practitioners to skip it.

**The evidence equally does not support treating a prompt-level rule as a "control" in the security-engineering sense of the word.** OWASP is explicit, twice, in two different but related risk items, that prompt-level text is not to be relied upon as a security boundary (Finding 2) and that restrictions phrased in a prompt "may not always be honored and could be bypassed" (Finding 3). Willison's independent framing — "how confident can you be that your protection will work every time?" — reaches the same place from a different threat model (Finding 4).

**Put together, the consistent, corroborated position across every authoritative source examined is: a prompt-level rule is a legitimate, real, non-zero layer — but it is explicitly NOT a guarantee, and every source that discusses it discusses it as one item in a list that also includes deterministic mechanisms.** This directly matches the language 4Shark's own Layer 0 section already uses — *"This rule is the intent signal, not a guarantee"* — which is the same posture OWASP and Willison independently arrive at for the closest analogous cases in the literature.

**What the sources do NOT corroborate, because none of them was asked to consider it, is the specific configuration 4Shark is in: a prompt rule as the ONLY layer, by deliberate, permanent choice, with mechanical enforcement ruled out for reasons specific to Claude Code's architecture and 4Shark's functional requirement (keep intact the ability to read and summarize in-session content — files, command output, fetched documents — that may legitimately reference a credential) — not for lack of trying.** Every source assumes a prompt rule as ONE layer among several. None argues either that a prompt-only regime is acceptable or that it is unacceptable; the question of "is it fine to have only the intent-signal layer, permanently, when the mechanical layer is architecturally foreclosed" is outside the scope of anything found. This is the genuine, unresolved gap — not a contradiction of 4Shark's stance, but a boundary the industry guidance does not reach. The engineer's own prior-spike decision already reasoned through this specific trade-off directly (rejecting the mechanical options on their merits, not from unawareness of the risk) — this spike's finding is that the general literature is consistent with, but does not independently validate, that specific final call.

## Suggested options for main and the engineer

- **Option A**: Keep Layer 0 exactly as worded, treating this spike as confirmation that the "advisory, not a guarantee" framing already matches how OWASP and independent researchers describe prompt-level rules for closely analogous risks — no wording change needed.
- **Option B**: Strengthen the wording of Layer 0 to explicitly name the OWASP framing ("not to be considered a security control") so future readers of CLAUDE.md understand the rule is deliberately calibrated as an intent-signal, not an enforced boundary — reducing the risk that a future engineer mistakes the rule for more protection than it provides.
- **Option C**: Revisit the "no mechanical enforcement" decision from the prior spike specifically for the narrower case of output-side redaction tooling (Finding 5's gap: free-form credential values in prose) — e.g., evaluate whether a `MessageDisplay`-hook regex approach (already investigated mechanically in the prior spike, verdict "partially achievable") is worth adopting now that the industry framing confirms deterministic layers are what OWASP expects to do the actual enforcement work, even though this spike's sources don't mandate it.

(NO recommendation — options surfaced; engineer and main decide)

## Resolution — decided and implemented (2026-07-04)

**Decision: Option B (strengthen the wording with the OWASP framing), realized as a new top-priority Critical Rule** rather than an in-place edit of Layer 0. A short rule — "Never Emit a Credential Value in the Session" — was added as the FIRST subsection under `## Critical Rules` at the top of `CLAUDE.md`, above every other rule, so it is present in every session and survives context compaction (the engineer's ask for a "small, highest-priority doc"). It is written in the declarative register Layer 0 already uses (not imperative), names OWASP LLM02:2025 with the verbatim "may not always be honored and could be bypassed" caveat, carries the "intent signal, not a guarantee" framing, and points to Layer 0 for the full handling. Layer 0 itself was left unchanged.

**Source-agnostic correction:** the rule (and this spike's framing) was corrected to be source-agnostic — it guards the session output against a credential value from ANY in-session source (file read, command output, config/env, tool result, pasted text), with the email fetch demoted to one example. The earlier email-vector emphasis was a narrowing of the briefing, not of the problem.

**Not adopted / deferred:**
- **Option A (keep Layer 0 exactly as-is)** — rejected; the elevation + OWASP grounding was judged worth the small change.
- **Option C (revisit mechanical enforcement for the free-form-credential gap)** — deferred as a possible future spike, NOT built. There is no mechanical way to redact the model's OWN output text inside Claude Code (a hook cannot edit the assistant's response; `MessageDisplay` only masks the on-screen render). Any mechanical layer could therefore only act upstream on the tool-result/input side (scrubbing a value before it enters context), which is a separate, heavier build with its own feasibility spike — and it is explicitly not the next step.

**Delivered:** PR #340 — `docs(guardrails): add credential-value session-output guard-rail` — merged into `develop` on 2026-07-04.
