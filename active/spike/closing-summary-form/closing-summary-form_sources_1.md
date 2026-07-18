# Sources consulted — closing-summary-form spike

Fetch status legend: VERIFIED = quote confirmed by direct WebFetch/Read of the primary
page or document. UNVERIFIED = only a WebSearch summary was obtained, no direct fetch
confirmed the substring; not used to sustain any Finding or Option in SPIKE.md.

## Used to sustain Findings (VERIFIED)

1. NN/G — "7 Tips for Presenting Bulleted Lists in Digital Content"
   https://www.nngroup.com/articles/presenting-bulleted-lists/
   Fetched twice (initial + self-check re-fetch, both 2026-07-17). Sustains F1, F2.

2. NN/G — "Website Reading: It (Sometimes) Does Happen"
   https://www.nngroup.com/articles/website-reading/
   Fetched 2026-07-17. Sustains F3.

3. NN/G — "Concise, SCANNABLE, and Objective: How to Write for the Web"
   https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/
   Fetched 2026-07-17. Sustains F4, F5.

4. NN/G — "Progressive Disclosure"
   https://www.nngroup.com/articles/progressive-disclosure/
   Fetched 2026-07-17. Sustains F13.

5. Microsoft Style Guide — "Lists"
   https://learn.microsoft.com/en-us/style-guide/scannable-content/lists
   Fetched 2026-07-17 (full page returned). Sustains F6.

6. GOV.UK — "A to Z style guide" (bullets/steps entry)
   https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/style-guides/a-to-z-style-guide/
   Fetched 2026-07-17. Sustains F7.

7. Wikipedia — "Nut graph"
   https://en.wikipedia.org/wiki/Nut_graph
   Fetched 2026-07-17. Sustains F9.

8. AJE (American Journal Experts) — "Overcoming the Curse of Knowledge: Communicating
   at the proper level of detail"
   https://www.aje.com/arc/how-to-overcome-the-curse-of-knowledge
   Fetched 2026-07-17. Sustains F10.

9. George Mason University Writing Center — "Improving Cohesion: The Known/New Contract"
   https://writingcenter.gmu.edu/writing-resources/grammar-style/improving-cohesion-the-known-new-contract
   Fetched 2026-07-17. Sustains F11.

10. Wikipedia — "BLUF (communication)"
    https://en.wikipedia.org/wiki/BLUF_(communication)
    Fetched 2026-07-17. Sustains F12.

11. National Library of Medicine — "Structured Abstracts"
    https://www.nlm.nih.gov/bsd/policy/structured_abstracts.html
    Fetched 2026-07-17. Sustains F14.

12. Google SRE Book — "Example Postmortem"
    https://sre.google/sre-book/example-postmortem/
    Fetched 2026-07-17. Sustains F15 (length observation).

13. Google SRE Book — "Postmortem Culture"
    https://sre.google/sre-book/postmortem-culture/
    Fetched 2026-07-17 (second, targeted fetch to confirm absence of a length rule,
    and to confirm the blameless-framing quote). Sustains F15 (blameless framing) and
    the "not found" statement about summary length in SRE guidance.

14. Kangas, B. D. (2012). "Not Waving but Drowning: A Review of Tufte's The Cognitive
    Style of PowerPoint." International Journal of Teaching and Learning in Higher
    Education, 24(3), 421-423.
    https://files.eric.ed.gov/fulltext/EJ1000695.pdf
    Read in full via the Read tool (PDF, 3 pages) 2026-07-17 — see
    closing-summary-form_excerpt_1.txt for the preserved full text. Sustains F8 (the
    crux finding on bullets and logical-relationship limits).

15. SimplyPsychology — "What? So What? Now What? Critical Reflection Model"
    https://www.simplypsychology.org/what-so-what-now-what.html
    Fetched 2026-07-17. Sustains F17 (Borton attribution treated with the hedge noted
    in the Finding — the page presented the attribution inside a summarizing block,
    not unambiguously as the page's own verbatim prose).

## Consulted but NOT used to sustain any Finding (UNVERIFIED or contradicted on fetch)

- digital.gov "Plain language guide series" (https://digital.gov/guides/plain-language)
  — fetched directly; the fetched page did NOT contain the lists-vs-paragraphs
  guidance that an initial WebSearch summary attributed to plainlanguage.gov. The
  Federal Plain Language Guidelines PDF (plainlanguage.gov/howto/guidelines/...) also
  redirected to this same page and could not be fetched directly. The "paragraphs for
  complex/highly technical content" claim from the WebSearch summary is therefore
  DROPPED from SPIKE.md — no fetched source confirms it verbatim.

- emphasis.co.uk "Why bullets won't make your case" — HTTP 403 on fetch. UNVERIFIED,
  not used. (rightattitudes.com, fetched as a substitute for Tufte-quote hunting,
  explicitly told us it could only paraphrase, not quote Tufte directly — this is why
  the Kangas academic review was used as the verified proxy instead.)

- ixdf.org "Progressive Disclosure" — fetched, but did not corroborate the Nielsen
  attribution a WebSearch summary claimed; superseded by the direct NN/G fetch (source
  4 above), which does carry NN/G's own framing.

- onlinetoolbase.com blog post on "bullet points fragment reasoning" — low-authority
  blog, never fetched directly; superseded entirely by the Kangas/Tufte academic
  source (source 14).

- writing-skills.com / emphasis.co.uk claim that bullets strip "linking words" —
  same as above, superseded by Kangas/Tufte.

- "Postmortem summary should be two to three sentences" — this specific numeric claim
  appeared only in a WebSearch results summary, not in either fetched SRE book page.
  DROPPED as unverified; SPIKE.md instead reports the one confirmed example (1
  sentence) as an observation, not a rule.

- Chat-UI "sticky bottom" auto-scroll research specific to SUMMARY PLACEMENT in
  streamed output — WebSearch surfaced general chat-UI engineering discussion
  (scroll-to-bottom-button patterns, streaming UX blog posts) but no study speaking
  directly to where a closing summary should sit in a streamed reply. Treated in
  SPIKE.md as "not found" per the spike brief's instruction (§4).
