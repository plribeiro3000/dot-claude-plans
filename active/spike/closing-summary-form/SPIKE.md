# SPIKE — Closing Summary Form (Layer 5 Output Policy)

## Investigation question

4Shark's Output Policy (`CLAUDE.md` § Output Policy, Layer 5) mandates that every
substantive agent reply end with a horizontal rule followed by **one short paragraph**
summarizing what happened and what (if anything) needs the engineer. The engineer
reports the resulting summaries read badly: content that is inherently list-shaped
gets crammed into a single running paragraph, producing a run-on sentence instead of
something scannable. The engineer wants the summary to be **didactic** — comprehensible
to a reader who lacks context and is catching up after stepping away from a long
technical session — not merely short or decorative.

This spike asks: what does the evidence actually say about (1) prose paragraphs vs.
bulleted lists for comprehension, (2) what makes a summary didactic rather than merely
short, (3) structural conventions built for exactly this job, (4) whether the
placement of the summary (last, not first) is contradicted by any evidence specific to
streamed chat output, and (5) whether any length target for this kind of summary is
defensible or folklore. Is 4Shark's current one-paragraph mandate defensible, and what
should the rule say?

## Sources consulted

Fifteen sources were fetched directly and used to sustain findings; a fuller
fetch-status ledger — including sources consulted but dropped as unverified — lives in
the auxiliary file `closing-summary-form_sources_1.md`. The full text of the one
non-web (PDF) primary source is preserved in `closing-summary-form_excerpt_1.txt`.

- [nngroup.com/articles/presenting-bulleted-lists](https://www.nngroup.com/articles/presenting-bulleted-lists/) — bullets as attention shortcuts, and a caution against over-bulleting short content
- [nngroup.com/articles/website-reading](https://www.nngroup.com/articles/website-reading/) — scanning is the default mode, reading happens under specific conditions
- [nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web](https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/) — one-idea-per-paragraph and inverted-pyramid preference
- [nngroup.com/articles/progressive-disclosure](https://www.nngroup.com/articles/progressive-disclosure/) — deferring detail to reduce cognitive load
- [learn.microsoft.com/en-us/style-guide/scannable-content/lists](https://learn.microsoft.com/en-us/style-guide/scannable-content/lists) — list sizing and structural-consistency rules
- [guidance.publishing.service.gov.uk .../a-to-z-style-guide](https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/style-guides/a-to-z-style-guide/) — GOV.UK's bullet rules and the "very long list → paragraph" exception
- [en.wikipedia.org/wiki/Nut_graph](https://en.wikipedia.org/wiki/Nut_graph) — the journalism "nutshell paragraph" convention
- [aje.com/arc/how-to-overcome-the-curse-of-knowledge](https://www.aje.com/arc/how-to-overcome-the-curse-of-knowledge) — curse of knowledge, definition and mitigation
- [writingcenter.gmu.edu .../improving-cohesion-the-known-new-contract](https://writingcenter.gmu.edu/writing-resources/grammar-style/improving-cohesion-the-known-new-contract) — the known/given-new contract
- [en.wikipedia.org/wiki/BLUF_(communication)](https://en.wikipedia.org/wiki/BLUF_(communication)) — BLUF definition, AR 25-50 origin, documented scope
- [nlm.nih.gov/bsd/policy/structured_abstracts.html](https://www.nlm.nih.gov/bsd/policy/structured_abstracts.html) — structured-abstract convention
- [sre.google/sre-book/example-postmortem](https://sre.google/sre-book/example-postmortem/) — a real postmortem Summary section
- [sre.google/sre-book/postmortem-culture](https://sre.google/sre-book/postmortem-culture/) — blameless framing, absence of a length rule
- See auxiliary `closing-summary-form_excerpt_1.txt` — Kangas (2012), the peer-reviewed review of Tufte's "The Cognitive Style of PowerPoint," preserved in full because the underlying source is a purchased pamphlet and the direct PDF mirror exceeded the fetch tool's size limit. This is the load-bearing source for Finding 8.
- [simplypsychology.org/what-so-what-now-what.html](https://www.simplypsychology.org/what-so-what-now-what.html) — the What?/So What?/Now What? reflection model
- See auxiliary `closing-summary-form_sources_1.md` — full fetch-status ledger, including six sources consulted and explicitly dropped as unverified (digital.gov, emphasis.co.uk, ixdf.org, onlinetoolbase.com, a "2-3 sentence" postmortem-length claim, and chat-UI placement research)

## Findings

### Finding 1: Bullets function as visual attention shortcuts

**Evidence:** "Readers perceive the bullets as shortcuts to succinct, high-priority
content."

**Source:** [NN/G — Presenting Bulleted Lists](https://www.nngroup.com/articles/presenting-bulleted-lists/)

**Significance:** This is the strongest pro-bullet evidence found: bullets are a visual
cue that draws attention independent of content quality. This supports converting
already-discrete items (a list of files touched, a list of open questions) into visible
list items rather than folding them into prose.

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substring confirmed present in the fetched article text (self-check re-fetch performed
on this same URL, quote reconfirmed present).

---

### Finding 2: NN/G itself warns against over-bulleting short content

**Evidence:** "Shorter lists are generally overkill and generally work better embedded
in a sentence."

**Source:** [NN/G — Presenting Bulleted Lists](https://www.nngroup.com/articles/presenting-bulleted-lists/)

**Significance:** The same source that documents bullets' attention advantage also
documents a boundary condition: a short list (implicitly, one whose items are brief and
few) is better folded into a sentence than exploded into bullets. This cuts against an
unconditional "always bullet the list-shaped parts" reading — NN/G's own guidance is
conditional on list length/complexity, not a blanket preference for bullets.

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substring re-confirmed present via an explicit self-check re-fetch of the same URL,
2026-07-17.

---

### Finding 3: Readers scan by default; they read fully only under specific conditions

**Evidence:** "users typically scan it" and "When web content helps users focus on
sections of interest, users switch from scanning to actually reading the copy."

**Source:** [NN/G — Website Reading: It (Sometimes) Does Happen](https://www.nngroup.com/articles/website-reading/)

**Significance:** Scanning is the reading default, but NN/G documents that focused,
well-organized content converts scanning into full reading. This is relevant to
"didactic" framing: a summary that names its subject and states consequence up front
(so the reader immediately knows this section is relevant to them) is more likely to be
read in full than a generic block of text.

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substring confirmed present in the fetched article text.

---

### Finding 4: "One idea per paragraph" is the operative rule for prose on screen, not "avoid paragraphs"

**Evidence:** "topic sentences are important, as is the 'one idea per paragraph' rule"

**Source:** [NN/G — Concise, Scannable, and Objective](https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/)

**Significance:** NN/G's guidance for web prose is not "replace paragraphs with
bullets" but "keep each paragraph to one idea." A closing summary that tries to state
both "what happened" and "what needs the engineer" and "the list of files touched" in
one paragraph violates this rule regardless of whether it is bulleted — it is carrying
more than one idea.

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substring confirmed present in the fetched article text.

---

### Finding 5: Users prefer conclusion-first (inverted pyramid) structure

**Evidence:** "I was able to find the main point quickly, from the first line. I like
that." (a study participant's own words, reported by NN/G)

**Source:** [NN/G — Concise, Scannable, and Objective](https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/)

**Significance:** This is about *internal* structure of a block of text (conclusion
first within the block), not about where the block sits in the overall document. It is
consistent with — not in tension with — 4Shark's "summary goes last in the reply, but
states the outcome first within itself" framing, since the summary paragraph itself can
still open with the bottom line.

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substring confirmed present in the fetched article text.

---

### Finding 6: Microsoft's list-eligibility rule is size- and structure-conditioned, not content-blind

**Evidence:** "A list should have at least two items but (if possible) no more than
seven items." And, separately: "Make all the items in a list consistent in structure.
For example, each item should be a noun or a phrase that starts with a verb."

**Source:** [Microsoft Style Guide — Lists](https://learn.microsoft.com/en-us/style-guide/scannable-content/lists)

**Significance:** Microsoft's own decision rule for choosing a list over prose is
conditional: enough items (≥2, ideally ≤7) AND the items must be structurally
parallel. A single-item list is not a list by this rule, and a set of items that are
not parallel (e.g., one is a fact, one is a question, one is a recommendation) is not a
good list candidate either — the mixed content should likely stay prose, or be split
into a list of only the truly parallel items.

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substring confirmed present in the fetched page (the fetch returned the full page
source, including front-matter, so the quote's presence is unambiguous).

---

### Finding 7: Even GOV.UK, a bullet-forward style guide, keeps prose for a long enumerable set when prose reads better

**Evidence:** "Very long lists can be written as a paragraph with a lead-in sentence if
it looks better."

**Source:** [GOV.UK — A to Z style guide, "bullets and steps"](https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/style-guides/a-to-z-style-guide/)

**Significance:** GOV.UK is one of the most bullet-forward public style guides
(explicit rules for lead-in lines, lowercase bullet starts, no trailing punctuation) —
and even it treats "list vs. paragraph" as reader-judged ("if it looks better"), not an
absolute. This weakens any reading of the evidence as "always bullet list-shaped
content."

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substring confirmed present in the fetched page.

---

### Finding 8: Bulleted lists can only express three logical relationships — sequence, priority, and category membership — and most reasoning does not fit any of them

**Evidence:** "bulleted lists can only communicate three logical relationships – a
sequence from first to last in time, priority from least to most important or vice
versa, and simple membership in a category. Most information teachers attempt to
convey in the classroom, however, does not fit neatly within one of those
relationships. The correlation/causation example, like many advanced ideas, requires a
nuanced discussion of necessity and sufficiency to accurately and effectively relate
the criteria to the concept."

**Source:** Kangas, B. D. (2012), "Not Waving but Drowning: A Review of Tufte's The
Cognitive Style of PowerPoint," *International Journal of Teaching and Learning in
Higher Education*, 24(3), 421-423 — a peer-reviewed journal article reviewing Edward
Tufte's monograph, itself citing Shaw, Brown & Bromiley (1998, *Harvard Business
Review*) as the origin of the three-relationships claim. Full text preserved in
auxiliary `closing-summary-form_excerpt_1.txt`.

**Significance:** This is the single strongest piece of evidence found for the
engineer's core complaint. It is not merely an opinion that bullets "feel" wrong for
argument — it is a peer-reviewed, cited claim that bullet-list format is
*structurally* incapable of representing anything beyond sequence, priority ranking,
or category membership. A causal chain ("A caused B, so C") or a necessity/sufficiency
argument (exactly the shape of "what happened and why it matters") is outside what a
bulleted list can express without losing the relationship. This directly answers
question 1 of the spike brief: prose is required, not merely preferred, for content
that is an argument rather than an enumeration.

**Verification block:** PDF fetched via WebFetch (which persisted the binary and
redirected to a Read of the saved file, 2026-07-17) / Read directly with the Read tool,
full 3-page document / Verbatim quote checked against the Read tool's returned text /
Quote substring confirmed present on page 1-2 of the document, reproduced in full in
`closing-summary-form_excerpt_1.txt`.

---

### Finding 9: The journalism "nut graf" convention is a named, citable structure for exactly the "didactic summary for a reader with no context" problem

**Evidence:** A nut graf is "a paragraph following the lede... that proceeds to explain
the context of the news or other story 'in a nutshell.'" It "tells audiences why the
story is important and timely," explaining "where the story is coming from, where it is
going, and what is at stake."

**Source:** [Wikipedia — Nut graph](https://en.wikipedia.org/wiki/Nut_graph)

**Significance:** The nut graf is structurally close to what the engineer is asking
for: a short paragraph, placed after the reader has already seen the raw material (the
lede, or in 4Shark's case the tool trace), whose job is specifically to answer "why
does this matter and what does it mean" for a reader who has not been following along
closely. It is a *paragraph* form (prose), not a list form — journalism's own answer to
the didactic-summary problem is prose, not bullets.

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substrings confirmed present in the fetched Wikipedia article text.

---

### Finding 10: "Curse of knowledge" names the exact failure mode the engineer is describing and its documented mitigation is prose technique, not formatting

**CORRECTED 2026-07-17 by main after `output-verifier` FAILED this Finding's citation
integrity.** As originally written, this Finding presented two fragments in quotation
marks that do not exist in the cited source: `"necessary background context"` and
`"include clear transitions connecting concepts"`. Both were paraphrase presented as
verbatim quotation — a Citation Discipline rule 1 (quote-or-drop) violation. They are
removed below and replaced with the source's actual text, re-confirmed by the verifier's
direct re-fetch. The Finding's conclusion survives on the real text; the Trade-offs table
row that cites F10 is unaffected in substance.

**Evidence:** "The curse of knowledge is the result of the personalized thinking that
leads to the inability to remember a time before knowledge was acquired, and the
overestimation of the level of information acquired in the past." Recommended mitigations
include: "not presume readers have learned or know much about the subject" and favouring
"simple plain language" over jargon. On background: "Failure to provide background
information that explains the study rationale" is named as a failure mode. On connecting
ideas: "Transitional phrases tie concepts together and provide contextual clues about the
value of the research."

**Source:** [AJE — Overcoming the Curse of Knowledge](https://www.aje.com/arc/how-to-overcome-the-curse-of-knowledge)

**Significance:** This names the cognitive bias behind a summary that reads fine to the
agent (which has full context from the tool trace) but is opaque to an engineer
returning cold. The source's own prescriptions — supplying background rather than
omitting it, plain language over jargon, and transitional phrases that "tie concepts
together" — are prose techniques (a transition is a prose-only device; a bulleted list
has no transition, only adjacency). This is independent corroboration of Finding 8's
conclusion: didactic writing for a context-poor reader needs connective prose, not just
enumeration.

**Verification block:** URL fetched (2026-07-17) / Verbatim quotes checked / Two
originally-quoted fragments were found ABSENT from the source by `output-verifier`'s
direct re-fetch and have been removed; the four fragments quoted above are confirmed
present in the fetched article text.

---

### Finding 11: The known/given-new contract is a named mechanism for how to write TO a reader who lacks context, independent of list-vs-prose

**Evidence:** "At the beginning of a sentence, put 'known' information: ideas that you
have already mentioned or concepts you can reasonably assume your reader is already
familiar with. At the end of a sentence, put the newest, most unfamiliar information."

**Source:** [GMU Writing Center — Improving Cohesion: The Known/New Contract](https://writingcenter.gmu.edu/writing-resources/grammar-style/improving-cohesion-the-known-new-contract)

**Significance:** This is a sentence-ordering technique, not a list-vs-prose choice. It
answers part of the "what makes a summary didactic" question directly: name the
already-known subject first (e.g., "the migration script" — something the reader
already has context for from the reply), then state the new information (what changed,
what broke). A summary that opens with unfamiliar detail before naming its subject
violates this contract regardless of formatting.

**Verification block:** URL fetched (2026-07-17) / Verbatim quote checked / Quote
substring confirmed present in the fetched page text.

---

### Finding 12: BLUF is documented as applicable broadly, but no fetched source documents its scope as including — or excluding — real-time streamed output specifically

**Evidence:** "Bottom Line Up Front, or BLUF, is the practice of beginning a message
with its key information (the 'bottom line')." Origin: Army Regulation 25-50 states
"Army writing will be concise, organized, and to the point...putting the main point at
the beginning of the correspondence (bottom line up front)." Documented scope: "The
BLUF concept is not exclusive to writing since it can also be used in conversations and
interviews."

**Source:** [Wikipedia — BLUF (communication)](https://en.wikipedia.org/wiki/BLUF_(communication))

**Significance:** BLUF's documented origin (AR 25-50) and documented scope
(correspondence, conversations, interviews) are all **static or turn-complete**
communication forms — a memo is read after it is finished; a conversation turn is
heard after it is spoken. Nothing in the fetched text speaks to a message being
*revealed incrementally to a reader who is already watching it render* (the streamed-chat
case). This is a genuine gap, not an inference either way — see "What remains
uncertain" below. It does NOT contradict 4Shark's placement rule, but it also does not
positively confirm it; the fetched source is simply silent on the streaming case.

**Verification block:** URL fetched (2026-07-17) / Verbatim quotes checked / Quote
substrings confirmed present in the fetched Wikipedia article text.

---

### Finding 13: Progressive disclosure — deferring detail — is a named UX technique for reducing cognitive load, but it operates on WHAT is shown, not on prose-vs-list form

**Evidence:** "Initially, show users only a few of the most important options." /
"Offer a larger set of specialized options upon request." / "By hiding the advanced
settings, progressive disclosure helps novice users avoid mistakes."

**Source:** [NN/G — Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/)

**Significance:** Progressive disclosure is the principle already embodied in 4Shark's
Layer 5 narration rule (bounded narration, full detail available in the tool trace on
demand, only the load-bearing moment surfaced) and in the "chat carries the summary,
the file carries every item" split. It supports the existing architecture (summary =
disclosed layer, tool trace/HTML report = detail layer) but says nothing about the
internal form (prose vs. list) of the disclosed layer itself.

**Verification block:** URL fetched (2026-07-17) / Verbatim quotes checked / Quote
substrings confirmed present in the fetched article text.

---

### Finding 14: The structured abstract is a named convention for splitting a summary into labeled parts, with no universal length rule

**Evidence:** "A structured abstract is an abstract with distinct, labeled sections
(e.g., Introduction, Methods, Results, Discussion) for rapid comprehension." And: "the
format required for structured abstracts differs from journal to journal and that some
journals use more than one structure."

**Source:** [National Library of Medicine — Structured Abstracts](https://www.nlm.nih.gov/bsd/policy/structured_abstracts.html)

**Significance:** The structured abstract offers a middle path between "one running
paragraph" and "bulleted list": labeled mini-sections (each itself a short prose block).
This is a plausible model for a summary that has genuinely distinct components (what
happened / what changed / what needs you) without collapsing into either a single
paragraph or a flat bullet list. Directly relevant to spike question 3. No universal
length was found on this page — the source explicitly disclaims one.

**Verification block:** URL fetched (2026-07-17) / Verbatim quotes checked / Quote
substrings confirmed present in the fetched page text.

---

### Finding 15: Google SRE's own example postmortem Summary is exactly one sentence; no length rule is documented anywhere in the SRE book pages fetched

**Evidence:** The complete Summary section of Google's example postmortem reads:
"Shakespeare Search down for 66 minutes during period of very high interest in
Shakespeare due to discovery of a new sonnet." Separately, on blameless framing: "For a
postmortem to be truly blameless, it must focus on identifying the contributing causes
of the incident without indicting any individual or team for bad or inappropriate
behavior."

**Source:** [Google SRE Book — Example Postmortem](https://sre.google/sre-book/example-postmortem/) and [Google SRE Book — Postmortem Culture](https://sre.google/sre-book/postmortem-culture/)

**Significance:** This is a real-world, authoritative example of a didactic
"what/so what" summary (what broke, for how long, and why it was noticed) compressed
into a single prose sentence — evidence that a compact summary CAN carry causal
information ("down... due to discovery of a new sonnet" is itself a causal claim) in
one sentence, when the content genuinely is that simple. But this is one observed
example, not a documented length rule — a direct, targeted fetch of the SRE book's
"Postmortem Culture" page found no stated length guidance anywhere on it. A claim
circulating in secondary sources that SRE prescribes "two to three sentences" for a
summary was checked directly against both fetched SRE pages and is NOT present in
either — it is dropped as unverified (see `closing-summary-form_sources_1.md`).

**Verification block:** Both URLs fetched (2026-07-17) / Verbatim quotes checked /
Quote substrings confirmed present in each fetched page; the ABSENCE of a length rule
was itself confirmed by a direct, targeted re-fetch of the postmortem-culture page
asking specifically for any length guidance, which returned none.

---

### Finding 16: 4Shark's own citations for chat-UI auto-scroll are about scroll mechanics, not about where a summary should sit — no source was found addressing summary placement specifically in streamed output

**Evidence:** No verbatim quote is offered here — this is a negative finding.
General web search on chat-UI streaming scroll behavior surfaced only engineering
discussion of scroll-to-bottom mechanics ("detect whether the user has scrolled away
from the bottom... if the user is at the bottom or very close, scroll down to reveal
new content, otherwise do nothing" — paraphrased from search results, not verified by
direct fetch, and therefore not cited as a Finding).

**Source:** Not found. Per the spike brief's explicit instruction (§4), this is
reported honestly rather than manufactured.

**Significance:** The spike brief asked to re-litigate the LAST-placement rule only if
evidence contradicts it, and to say explicitly if nothing is found on the streaming
case. Nothing was found, either supporting or contradicting streaming-specific
placement research. 4Shark's own CLAUDE.md justification cites two GitHub issues
(#37627, #53382) about sticky-bottom scroll *behavior* as a UI mechanic (confirmed by
this spike's own general search results, which independently corroborate that
sticky-bottom auto-scroll is "the standard pattern in Claude, ChatGPT, and every other
streaming chat UI" per one search-result synthesis — but that synthesis was not
independently fetched and verified, so it is reported here as context, not as a
verified Finding). No source, verified or otherwise, was found that studies READER
COMPREHENSION of a summary's placement specifically under streaming/auto-scroll
conditions, as opposed to scroll-mechanics engineering. The placement question (spike
§4) is therefore unresolved by external evidence in either direction.

**Verification block:** Not applicable — this Finding is a documented absence, not a
sourced claim. No quote is offered because none was found; per Citation Discipline
rule 1 (quote-or-drop), no attribution is made.

---

### Finding 17: The "What? So What? Now What?" reflection model offers a third structural option — three short prose beats rather than one paragraph or a bullet list

**Evidence:** The model's three stages: "'What?'" (objective description, facts
without interpretation), "'So What?'" (analysis — implications, connections to prior
knowledge), and "'Now What?'" (concrete next steps / action). Attribution, as presented
on the fetched page: "originating from Terry Borton and further developed by Rolfe et
al. for healthcare practice."

**Source:** [SimplyPsychology — What? So What? Now What?](https://www.simplypsychology.org/what-so-what-now-what.html)

**Significance:** This maps almost exactly onto 4Shark's own summary requirement ("what
happened, and what needs them" is a two-beat compression of What?/So What?/Now What?).
It is evidence that a three-beat prose structure is an established, named reflective
convention — not evidence that it must be three separate paragraphs or bullets; the
model is silent on formatting and is typically applied as continuous reflective prose
in its source disciplines (education, healthcare debriefing).

**Verification block:** URL fetched (2026-07-17) / Quote checked / Quote substrings
confirmed present in the fetched page text. Note: the attribution to Borton is
presented on the source page inside a summarizing block rather than unambiguously as
the original author's own sentence — treated with appropriate hedging in Significance,
per Citation Discipline rule 3 (no invented term/attribution beyond what the fetched
text actually supports).

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Single running prose paragraph (current rule) | Preserves causal/argumentative connective tissue (F8); matches nut-graf (F9) and postmortem-summary (F15) precedent for compact didactic prose; matches known-new contract's sentence-to-sentence flow (F11) | Forces genuinely enumerable content (file lists, item counts) into sentence form, which NN/G's own list-length rule (F6) and GOV.UK's own list rules (F7) suggest is a poor fit past ~2 parallel items; can become a run-on when it tries to carry more than "one idea" (F4) | F4, F6, F7, F8, F9, F11, F15 |
| Free-form bullets for everything list-shaped | Bullets are a proven attention shortcut (F1); matches Microsoft/GOV.UK's default preference for scannable content | Structurally cannot express causal/argumentative relationships beyond sequence, priority, or membership (F8); strips the "why" that curse-of-knowledge mitigation requires (F10); NN/G's own guidance says short lists work worse as bullets, not better (F2) | F1, F2, F8, F10 |
| Structured/labeled mini-sections (structured-abstract style) | Matches a real academic convention for exactly this problem — compact, multi-part, didactic summary (F14); can isolate "what happened" from "what needs you" without losing prose connectivity within each part | No length rule to anchor it (F14); heavier machinery than a one-off chat reply may warrant; not designed for a reader scanning quickly (designed for deliberate reading) | F14 |
| Mixed: prose for the argument, bullets only for genuinely enumerable, parallel items | Follows GOV.UK's own "if it looks better" judgment call (F7) and Microsoft's parallel-structure gate (F6) rather than an absolute; keeps causal reasoning in prose per F8 while giving enumerable content (file lists, item counts) its visual shortcut per F1 | Requires per-reply judgment ("is this content actually list-shaped and parallel, or is it an argument?") rather than a single mechanical rule; harder to enforce via a Stop-hook block, which currently checks only for presence of the paragraph, not its internal shape | F1, F6, F7, F8 |

## What remains uncertain

- **Placement (last vs. first) under streaming conditions specifically**: no source,
  verified or unverified, was found studying reader comprehension of summary placement
  under auto-scrolling/streamed output, as distinct from general BLUF/nut-graf research
  on static documents (Finding 16). The spike brief instructed not to re-litigate
  placement absent direct evidence — none was found either way, so this remains
  genuinely unresolved by research, not settled by it.
- **Length target**: no authoritative source gave a numeric length rule for this kind
  of compact didactic summary. The one real-world example found (Google SRE, Finding
  15) is a single sentence, but the source itself states no rule — this is an
  observation, not a norm. A "two to three sentences" claim circulating in secondary
  sources was checked directly and could not be confirmed in either SRE book page
  fetched. Any numeric length target for 4Shark's rule would be the engineer's design
  choice, not an evidence-derived number.
- **Whether a Stop-hook can mechanically distinguish "this content is genuinely
  list-shaped" from "this content is an argument"**: this spike did not investigate the
  hook implementation (`validate-closing-summary.sh`) or whether format-shape detection
  is feasible there; that is a separate, implementation-level question outside this
  spike's scope.

## Suggested options for main and the engineer

- **Option A — Keep the single-paragraph rule as-is.** Sustained by F8 (bullets cannot
  express causal/argumentative relationships), F9 (nut graf precedent is prose), F11
  (known-new contract is a sentence-flow technique), F15 (SRE's own compact summary is
  prose). Risk: does not address the engineer's concrete complaint about genuinely
  enumerable content being forced into run-on sentences.

- **Option B — Allow a short list INSIDE the closing block when the content is
  genuinely enumerable and parallel, prose for everything else.** Sustained by F1
  (bullets as attention shortcut), F2 and F6 (both sources gate list-use on
  size/parallelism, not blanket preference), F7 (GOV.UK's own "if it looks better"
  judgment), F8 (prose stays mandatory for the causal/argumentative part). This is the
  "mixed" option from the trade-off table — evidence sustains it more directly than
  either pure extreme, since multiple sources (F2, F6, F7) independently converge on a
  conditional, not absolute, list-vs-prose rule.

- **Option C — Adopt a structured/labeled mini-section shape** (e.g., a fixed micro-template
  inside the closing block: one prose sentence for what happened, one prose sentence
  for what needs the engineer, optionally one bullet run for enumerable items). Sustained
  by F14 (structured-abstract precedent) and F17 (What?/So What?/Now What? as a named
  three-beat reflective structure). Risk: heavier machinery than F4's "one idea per
  paragraph" rule requires, and no source specifies a length or exact split for a chat
  reply specifically (this is genuinely novel synthesis, not directly precedented).

- **Option D — Leave placement (last) and the didactic-content requirements (name the
  subject, state consequence, avoid undefined jargon) untouched**, since no evidence
  contradicts placement (Finding 16, "not found" rather than "settled") and F10/F11
  already ground didactic content requirements independent of the prose-vs-list
  question.

No option is recommended here — main and the engineer choose. Options B and D are not
mutually exclusive with each other or with A/C; the underlying prose-vs-list question
(A vs. B vs. C) and the placement/content question (D) are separable decisions.
