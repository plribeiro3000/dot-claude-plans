# SPIKE — Post-Mortem Best Practices in Software Engineering

**Conducted by:** spike agent
**Date:** 2026-05-27
**Status:** Research complete — pending decisions

---

## Goal

Answer: what does the industry actually prescribe and practice for post-mortems in software engineering? Specifically:

1. What sections appear in virtually every template (convergent structure)?
2. Where do sources diverge (Five Whys vs. systemic analysis, templates vs. narrative)?
3. What does the Claude Code ecosystem already have?
4. Enough grounding for Paulo to decide: skill, template, or reference material only.

Paulo's context: first startup career, no formal post-mortem experience. This spike surveys externally before any internal decision.

---

## Method

- Web fetches of canonical sources (Google SRE Book chapter, PagerDuty docs, Atlassian template, real published incident reports from GitLab, Cloudflare, AWS)
- Web searches for thought leadership (Allspaw, Cook, Fowler, Uncle Bob, Charity Majors/Honeycomb, LFI community)
- GitHub searches for Claude Code skills and community implementations
- Mirror fetch for Allspaw's original article (Etsy URL returned HTTP 403)
- Direct curl fetch of thananon SKILL.md raw URL to `/tmp/thananon_skill_raw.txt`; verbatim substrings verified via grep

---

## Evidence

> Raw data and detailed findings are documented below. Summaries appear in Conclusions.

### Sources Consulted

- [https://sre.google/sre-book/postmortem-culture/](https://sre.google/sre-book/postmortem-culture/) — Google SRE Book chapter, the canonical modern template reference
- [https://jaytaylor.com/notes/node/1498058768000.html](https://jaytaylor.com/notes/node/1498058768000.html) — Mirror of Allspaw's "Blameless PostMortems and a Just Culture" (original at etsy.com returned 403)
- [https://response.pagerduty.com/after/post_mortem_template/](https://response.pagerduty.com/after/post_mortem_template/) — PagerDuty post-mortem template (10 sections, verbatim)
- [https://postmortems.pagerduty.com/culture/blameless/](https://postmortems.pagerduty.com/culture/blameless/) — PagerDuty blameless culture guide
- [https://slab.com/library/templates/atlassian-postmortem-template/](https://slab.com/library/templates/atlassian-postmortem-template/) — Atlassian post-mortem template (14 sections via Slab library)
- [https://about.gitlab.com/blog/2017/02/01/gitlab-dot-com-database-incident/](https://about.gitlab.com/blog/2017/02/01/gitlab-dot-com-database-incident/) — GitLab 2017 database incident report
- [https://blog.cloudflare.com/details-of-the-cloudflare-outage-on-july-2-2019/](https://blog.cloudflare.com/details-of-the-cloudflare-outage-on-july-2-2019/) — Cloudflare July 2019 outage post-mortem
- [https://blog.cloudflare.com/cloudflare-incident-on-june-20-2024/](https://blog.cloudflare.com/cloudflare-incident-on-june-20-2024/) — Cloudflare June 2024 incident report
- [https://aws.amazon.com/message/41926/](https://aws.amazon.com/message/41926/) — AWS S3 outage post-event summary, February 2017
- [https://how.complexsystems.fail/](https://how.complexsystems.fail/) — Richard Cook, "How Complex Systems Fail" (18 principles, verbatim)
- [https://blog.pragmaticengineer.com/postmortem-best-practices/](https://blog.pragmaticengineer.com/postmortem-best-practices/) — Pragmatic Engineer survey of post-mortem best practices across companies
- [https://www.honeycomb.io/blog/negotiating-priorities-incident-investigations](https://www.honeycomb.io/blog/negotiating-priorities-incident-investigations) — Honeycomb on learning-focused incident investigations (Fred Hebert)
- [https://github.com/wilsto/claude-code-starter-kit/blob/main/.claude/skills/incident-response/SKILL.md](https://github.com/wilsto/claude-code-starter-kit/blob/main/.claude/skills/incident-response/SKILL.md) — Claude Code incident-response skill (5-phase workflow)
- [https://github.com/thananon/9arm-skills/blob/main/skills/engineering/post-mortem/SKILL.md](https://github.com/thananon/9arm-skills/blob/main/skills/engineering/post-mortem/SKILL.md) — Claude Code bug post-mortem skill
- [https://github.com/alirezarezvani/claude-skills/blob/main/c-level-advisor/executive-mentor/skills/postmortem/SKILL.md](https://github.com/alirezarezvani/claude-skills/blob/main/c-level-advisor/executive-mentor/skills/postmortem/SKILL.md) — Claude Code executive postmortem skill
- See auxiliary: `sources/google_sre_postmortem_chapter.txt` — full verbatim extracts from the SRE Book chapter
- See auxiliary: `sources/allspaw_blameless_postmortem.txt` — key passages from Allspaw's foundational article
- See auxiliary: `sources/pagerduty_template.txt` — PagerDuty template sections verbatim
- See auxiliary: `sources/atlassian_template.txt` — Atlassian template sections verbatim
- See auxiliary: `sources/real_postmortems_structure.txt` — cross-source structural analysis of four published incident reports
- See auxiliary: `sources/cook_complex_systems_fail.txt` — all 18 principles verbatim plus key extended explanations
- See auxiliary: `sources/claude_code_ecosystem.txt` — survey of three Claude Code skill implementations

---

### Finding 1: Google SRE Book defines the canonical post-mortem as a written record with five required elements

**Evidence:**
> "A postmortem is a written record of an incident, its impact, the actions taken to mitigate or resolve it, the root cause(s), and the follow-up actions to prevent the incident from recurring."

The page also states the three primary goals: "ensuring the incident is documented, that all contributing root cause(s) are well understood, and, especially, that effective preventive actions are put in place."

**Source:** https://sre.google/sre-book/postmortem-culture/ — opening definition paragraph of the chapter

**Significance:** The Google SRE Book is the most-cited modern reference for post-mortem practice. Its definition establishes five content elements (record, impact, actions taken, root cause, follow-up actions) that appear in virtually every template surveyed. The three goals are repeated almost verbatim in PagerDuty, Atlassian, and the Claude Code skills found in the ecosystem.

**Verification:**
- URL fetched: https://sre.google/sre-book/postmortem-culture/ — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes
- Quote substring confirmed at: opening definition paragraph of the chapter

---

### Finding 2: Google SRE Book prescribes specific triggers for when a post-mortem is required

**Evidence:**
> "User-visible downtime or degradation beyond a certain threshold"
> "Data loss of any kind"
> "On-call engineer intervention (release rollback, rerouting of traffic, etc.)"
> "A resolution time above some threshold"
> "A monitoring failure (which usually implies manual incident discovery)"

And additionally: "any stakeholder may request a postmortem for an event."

**Source:** https://sre.google/sre-book/postmortem-culture/ — bullet list in the "Google's Postmortem Philosophy" section discussing when a post-mortem should be written

**Significance:** The trigger criteria are important for 4Shark's context: a `/post-mortem` skill needs a policy about *when* it fires, not just *how* to write the document. The Google triggers are severity-based and quantitative (thresholds), not event-type-based.

**Verification:**
- URL fetched: https://sre.google/sre-book/postmortem-culture/ — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes
- Quote substring confirmed at: bullet list in the "Google's Postmortem Philosophy" section

---

### Finding 3: The cultural foundation of blameless post-mortems originates with John Allspaw at Etsy (2012)

**Evidence:**
> "an engineer who thinks they're going to be reprimanded are _disincentivized_ to give the details necessary."

The article describes punishment as creating a self-reinforcing cycle leading to "Cover-Your-Ass engineering" — where engineers withhold information to avoid blame, which guarantees repeated failures. The "Second Story" concept from human factors research is invoked: effective post-mortems seek to understand why actions "made sense to them at the time."

**Source:** https://jaytaylor.com/notes/node/1498058768000.html (mirror of Allspaw's original Etsy codeascraft article, published May 2012; original at etsy.com/codeascraft/blameless-postmortems returned HTTP 403)

**Significance:** Allspaw's 2012 article is the origin point for the term "blameless post-mortem" in software engineering. Google SRE, PagerDuty, Atlassian, and the LFI community all cite it or its ideas. Understanding the origin helps distinguish the cultural practice (which is primary) from the template (which is secondary).

**Verification:**
- URL fetched: https://jaytaylor.com/notes/node/1498058768000.html — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes
- Quote substring confirmed at: paragraph describing engineer disincentivization in the blame cycle section

---

### Finding 4: The SRE Book's blameless principle rests on a specific epistemic claim about intent

**Evidence:**
> "A blamelessly written postmortem assumes that everyone involved in an incident had good intentions and did the right thing with the information they had."

And:
> "If a culture of finger pointing and shaming individuals or teams for doing the 'wrong' thing prevails, people will not bring issues to light for fear of punishment."

**Source:** https://sre.google/sre-book/postmortem-culture/ — blameless postmortems discussion in the chapter body

**Significance:** The epistemic claim (everyone did what made sense given the information they had) is not a courtesy — it is a methodological stance. It shifts the investigation question from "who failed?" to "what information was unavailable or misleading?" This directly shapes how questions are framed during a post-mortem review.

**Verification:**
- URL fetched: https://sre.google/sre-book/postmortem-culture/ — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes
- Quote substrings confirmed at: blameless postmortems discussion in the chapter body (both quotes present)

---

### Finding 5: PagerDuty prescribes a 10-section template with explicit guidance on quantified impact

**Evidence:**
The PagerDuty post-mortem template contains these 10 sections:
1. Overview — "Include a short sentence or two summarizing the contributing factors, timeline summary, and the impact."
2. What Happened
3. Contributing Factors — "Include a description of any conditions that contributed to the issue."
4. Resolution — "Include a description of what solved the problem. If there was a temporary fix in place, describe that along with the long-term solution."
5. Impact — "Be very specific here and include exact numbers." (tracks: time in SEV-1/SEV-2, notifications out of SLA, accounts and users affected, support requests)
6. Responders (Incident Commander, scribe, participants)
7. Timeline — "(1) time the contributing factor began, (2) time of the page, (3) time that the status page was updated, (4) time of any significant actions, (5) time the SEV-2/1 ended, (6) links to tools/logs"
8. How'd We Do? (What Went Well? / What Didn't Go So Well?)
9. Action Items — "Each action item should be in the form of a JIRA ticket"
10. Messaging (Internal Email / External Message)

**Source:** https://response.pagerduty.com/after/post_mortem_template/ — template page, all sections

**Significance:** PagerDuty's template is notable for two divergences from other templates: (a) it includes a Messaging section for internal/external communication, which no other template surveyed includes; (b) the quantified Impact section is more prescriptive than any other template, specifying exact metrics to track by name.

**Verification:**
- URL fetched: https://response.pagerduty.com/after/post_mortem_template/ — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes
- Quote substrings confirmed at: each section's guidance paragraph on the template page

---

### Finding 6: Atlassian's template uses Five Whys for root cause analysis — a method other practitioners explicitly critique

**Evidence:**
The Atlassian template employs the Five Whys technique: "Begin with a description of the impact and ask why it occurred" — iteratively questioning until reaching underlying causes rather than symptoms.

Atlassian's 14 sections (as listed on the page): Incident summary, Leadup, Fault, Impact, Detection, Response, Recovery, Timeline, Root cause identification: The Five Whys, Root cause, Backlog check, Recurrence, Lessons learned, Corrective actions.

**Source:** https://slab.com/library/templates/atlassian-postmortem-template/ — Root Cause Analysis section of the template

**Significance:** Five Whys appears in Atlassian's template as the prescribed root cause method. The Pragmatic Engineer article quotes Andrew Hatch (LinkedIn) critiquing Five Whys: "The danger of the Five Whys is how, by following it, we might miss out on other root causes of the incident. (...) We're not broadening our understanding. We're just trying to narrow down on one thing, fix it, and hope that this will make the incident not happen again." (Source: https://blog.pragmaticengineer.com/postmortem-best-practices/, attributed to Andrew Hatch's USENIX SREcon21 talk) This is a material divergence between templates — not a formatting choice.

**Verification:**
- URL fetched: https://slab.com/library/templates/atlassian-postmortem-template/ — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes
- Quote substring confirmed at: Root Cause Analysis section of the template
- Pragmatic Engineer fetch confirms: the "danger of the Five Whys" quote is attributed to Andrew Hatch (LinkedIn) presenting at USENIX SREcon21, not to John Allspaw

---

### Finding 7: Real published post-mortems from GitLab, Cloudflare, and AWS converge on five structural elements — and diverge from templates on others

**Evidence:**
Four published incident reports were analyzed (GitLab 2017, Cloudflare 2019, Cloudflare 2024, AWS S3 2017). Sections present in **all four**:
- Summary / what happened (brief)
- Timeline with timestamps
- Root cause / what went wrong
- Impact (quantified)
- Remediation / what changed

Sections **absent from published reports but present in prescribed templates**:
- Explicit "What Went Well" section (absent from all four real examples)
- Action Items table (absent from GitLab and AWS; present in Cloudflare 2024)
- Messaging / communications section (absent from all real examples)
- Backlog Check / Recurrence (Atlassian-specific; absent from all real examples)

GitLab 2017 verbatim: "We lost six hours of database data (issues, merge requests, users, comments, snippets, etc.) for GitLab.com."
AWS 2017 verbatim: "one of the inputs to the command was entered incorrectly and a larger set of servers was removed than intended"
Cloudflare 2024 verbatim: "On Thursday, June 20, 2024, two independent events caused an increase in latency and error rates for Internet properties and Cloudflare services that lasted 114 minutes."

**Source:** See auxiliary `sources/real_postmortems_structure.txt` for full structural analysis. Individual sources: https://about.gitlab.com/blog/2017/02/01/gitlab-dot-com-database-incident/, https://blog.cloudflare.com/details-of-the-cloudflare-outage-on-july-2-2019/, https://blog.cloudflare.com/cloudflare-incident-on-june-20-2024/, https://aws.amazon.com/message/41926/

**Significance:** The gap between prescribed templates and actual practice is significant. Companies that publish post-mortems regularly (Cloudflare, AWS, GitLab) consistently include: summary, timeline, root cause, impact, and remediation. They consistently omit: "What Went Well," messaging templates, and backlog checks. This suggests those sections may serve internal process purposes rather than the explanatory purpose of a published post-mortem.

**Verification:**
- URLs fetched: all four above — WebFetch confirmed 2026-05-27
- Verbatim quotes checked: yes
- Quote substrings confirmed at: GitLab — opening paragraph and meta description; AWS — root cause section; Cloudflare 2024 — opening paragraph

---

### Finding 8: Richard Cook's "How Complex Systems Fail" argues that single root cause attribution is fundamentally wrong

**Evidence:**
Principle 7 (verbatim header): "Post-accident attribution to a 'root cause' is fundamentally wrong."

Extended explanation from the same source: "Because overt failure requires multiple faults, there is no isolated 'cause' of an accident."

Principle 8 (verbatim header): "Hindsight biases post-accident assessments of human performance."

Principle 15 (verbatim header): "Views of 'cause' limit the effectiveness of defenses against future events."

**Source:** https://how.complexsystems.fail/ — principle headers 7, 8, and 15

**Significance:** Cook's paper is the academic foundation for the "contributing factors" framing that appears in PagerDuty's template (they use "Contributing Factors" not "Root Cause" as the section name). The distinction matters: "root cause" implies a single chain ending in one culprit; "contributing factors" implies a system of conditions that together made failure possible. Templates differ on which framing they use — this is a substantive choice, not a naming preference.

**Verification:**
- URL fetched: https://how.complexsystems.fail/ — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes
- Quote substrings confirmed at: principle headers 7, 8, and 15 on the page; extended explanation in the body text of principle 7

---

### Finding 9: PagerDuty's blameless guide distinguishes "what/how" questions from "who/why" questions as a concrete facilitation technique

**Evidence:**
> "A blameless postmortem stays focused on how a mistake was made instead of who made it."

> "Ask 'what' and 'how' questions rather than 'who' or 'why.'"

Avoid "why" questions because they "force people to justify their actions, attributing blame."

When defensiveness emerges: "Restore mutual purpose by reiterating that the goal of the postmortem is to understand what systemic factors lead to the incident and collaboratively identify actions that can reduce failure moving forward."

Framing technique: "When inquiring about a human action, abstract to an inspecific responder. Anyone could have made the same mistake."

**Source:** https://postmortems.pagerduty.com/culture/blameless/ — "The Blameless Postmortem" main content area and "Key Takeaways" and "How to Cultivate a Blameless (or Blame-Aware) Culture" sections

**Significance:** This is the most operationally specific guidance found for facilitating a post-mortem meeting. The "what/how vs. who/why" rule is actionable and teachable. A `/post-mortem` skill that includes meeting facilitation guidance would benefit from this framing — it is concrete enough to be scripted.

**Verification:**
- URL fetched: https://postmortems.pagerduty.com/culture/blameless/ — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes
- Quote substrings confirmed at: first quote in "The Blameless Postmortem" section; second and third in "Key Takeaways"; fourth in "How to Cultivate a Blameless (or Blame-Aware) Culture" section

---

### Finding 10: Honeycomb moved away from mandatory templates and action-item tracking — favoring selective, learning-focused reviews

**Evidence:**
From Honeycomb's incident investigation article (author: Fred Hebert):
> "The approach I personally favor is always the one that centers on learning (Epistemological), with the belief that when you have good explanations, you can surface preventative approaches as well."

> "we prefer to have a few in-depth reviews than surface coverage of all incidents"

> "Choose incidents where folks are surprised, or even say out loud 'I want to review this' or 'this is a really weird one.' They're strong signals that these incidents are good learning opportunities."

The Pragmatic Engineer article also quotes Honeycomb engineer Paul Osman:
> "For us, the review is more about 'who knew what when and how did they know it?' and 'how did our systems surprise us?' instead of 'what action items can we extract from this?'"

**Source:** https://www.honeycomb.io/blog/negotiating-priorities-incident-investigations (Fred Hebert, Honeycomb); Paul Osman quote via https://blog.pragmaticengineer.com/postmortem-best-practices/

**Significance:** Honeycomb's approach represents the far end of the maturity spectrum: abandoning mandatory templates in favor of curiosity-driven, selective reviews. This is corroborated by the Pragmatic Engineer's survey of teams. It is not the starting point for a team writing its first post-mortem — but it is the direction the most sophisticated practitioners are moving.

**Verification:**
- URL fetched: https://www.honeycomb.io/blog/negotiating-priorities-incident-investigations — WebFetch confirmed 2026-05-27; author confirmed as Fred Hebert
- Verbatim quotes checked: yes (all three Fred Hebert quotes confirmed by WebFetch)
- Quote substrings confirmed at: article body (author: Fred Hebert, published 2024-08-28)

---

### Finding 11: The Pragmatic Engineer survey identifies "fixing fast vs. learning" as the central tension in post-mortem culture

**Evidence:**
From the Pragmatic Engineer article quoting John Allspaw:
> "We often confuse fixing things fast with learning."

> "Most incidents are written to be filed, not to be read or learned from."

The article also quotes Allspaw on attention dynamics during incidents:
> "Incidents create attention energy around them. When something goes wrong, people pay far more attention to everything around the event than when it's business as usual."

And a direct critique of Five Whys from Andrew Hatch (LinkedIn, USENIX SREcon21):
> "The danger of the Five Whys is how, by following it, we might miss out on other root causes of the incident. (...) We're not broadening our understanding. We're just trying to narrow down on one thing, fix it, and hope that this will make the incident not happen again."

**Source:** https://blog.pragmaticengineer.com/postmortem-best-practices/ — survey article; all four quotes attributed by the article as noted (Allspaw ×3, Hatch ×1)

**Significance:** The Pragmatic Engineer survey is the most recent broad-coverage survey found. The central tension it names — writing to file vs. writing to learn — is the most practical framing for a team starting out: the template should serve learning, not compliance. The Five Whys critique from Allspaw and Hatch appears here alongside Atlassian's endorsement of Five Whys (Finding 6), making this the sharpest divergence in the literature.

**Verification:**
- URL fetched: https://blog.pragmaticengineer.com/postmortem-best-practices/ — WebFetch confirmed 2026-05-27
- Verbatim quote checked: yes (all four quotes confirmed by WebFetch)
- Quote substrings confirmed at: sections on learning vs. speed (Allspaw quotes) and the Five Whys critique (Hatch quote)

---

### Finding 12: Three Claude Code skill implementations exist in the community — covering different scopes

**Evidence:**
Three distinct Claude Code skill implementations for post-mortems were found:

1. **wilsto/claude-code-starter-kit** — `incident-response` skill: end-to-end 5-phase workflow (triage → investigation → resolution → communication → postmortem). Template uses: Summary, Timeline, Root Cause, Impact, What Went Well, What Went Wrong, Action Items table with owner/due date/priority. Behavioral rule verbatim: "Execute phases in order — never skip a phase."

2. **thananon/9arm-skills** — `post-mortem` skill: scoped to engineer-to-engineer bug RCA after a fix is confirmed. Requires all four inputs before drafting: repro exists, root cause identified, fix pointer, fix validated. The Tone section of the skill uses six distinct directives. Verbatim excerpts from that section (raw fetch confirmed — see below):
   - On code identifiers: "Code identifiers are first-class. `tadaLaunchPrepare`, `tada/prim.h::syncWaitPeer`, `scratchBuf`, commit SHAs, line numbers — keep them. The whole point is that future engineers can grep their way back to the change."
   - On hedging: "No hedging. 'We believe' / 'appears to' / 'may have' — drop. State it or don't write it."
   - On blamelessness: "Blameless. Describe the bug, the gap, and the fix. Never 'X should have caught this.' The CI gap is the failure mode, not the person."
   - On advocacy: "No advocacy. A post-mortem records what happened and what's next. If you want to argue for a refactor, that's a separate proposal — link to it from the action items."

3. **alirezarezvani/claude-skills** — executive `postmortem` skill: organizational failure analysis using 5 Whys + Change Register. Key distinction verbatim: "Blame is cheap. Understanding is hard."

No MCP server specifically for post-mortems was found in registry searches. No LFI community tool for Claude Code was found.

**Source:** https://github.com/wilsto/claude-code-starter-kit/blob/main/.claude/skills/incident-response/SKILL.md, https://github.com/thananon/9arm-skills/blob/main/skills/engineering/post-mortem/SKILL.md, https://github.com/alirezarezvani/claude-skills/blob/main/c-level-advisor/executive-mentor/skills/postmortem/SKILL.md — See auxiliary `sources/claude_code_ecosystem.txt`

**Significance:** The community has already built three shapes of post-mortem tooling for Claude Code: full incident lifecycle, code-level RCA, and executive analysis. Paulo would need to decide which of these overlaps with 4Shark's actual need — or whether 4Shark's version should cover all three phases in a single skill with branching behavior, or separately per scope.

**Verification:**
- wilsto and alirezarezvani: URLs fetched via GitHub web view
- thananon: raw URL fetched via `curl -sL https://raw.githubusercontent.com/thananon/9arm-skills/main/skills/engineering/post-mortem/SKILL.md -o /tmp/thananon_skill_raw.txt` (2026-05-27); all four verbatim excerpts above verified by substring grep against `/tmp/thananon_skill_raw.txt`
  - "Code identifiers are first-class. `tadaLaunchPrepare`…" — confirmed at line 99 of raw file
  - "No hedging." — confirmed at line 102 of raw file
  - "Blameless. Describe the bug, the gap, and the fix." — confirmed at line 103 of raw file
  - "No advocacy." — confirmed at line 104 of raw file
- "Execute phases in order — never skip a phase." — confirmed in wilsto SKILL.md behavioral rule block
- "Blame is cheap. Understanding is hard." — confirmed in alirezarezvani SKILL.md

---

### Finding 13: Martin Fowler and Uncle Bob have minimal direct post-mortem writing; the field is owned by SRE/operations practitioners

**Evidence:**
No dedicated Martin Fowler article on post-mortems was found on martinfowler.com. A web search across martinfowler.com returned only tangential references: a Fragments entry (April 2026) that links to an external post-mortem without Fowler's own commentary on the practice, and a brief definitional mention in Patrick Kua's "An Appropriate Use of Metrics" article (not authored by Fowler).

A 2013 tweet attributed to @martinfowler (https://x.com/martinfowler/status/385766726970781696) reportedly endorsed Allspaw's article. That URL returns **HTTP 402 Payment Required** — the content is behind a paywall/auth wall and cannot be fetched or verified.

No substantive writing from Robert C. Martin (Uncle Bob) on post-mortems or incident response was found. His published work focuses on code-level practice (SOLID principles, Clean Code, Clean Architecture).

**Source:** Web search for "Martin Fowler post-mortem retrospective blameless incident culture site:martinfowler.com" returned no martinfowler.com article on the topic. Twitter/X URL https://x.com/martinfowler/status/385766726970781696 — UNVERIFIED (HTTP 402).

**Significance:** The absence is meaningful: post-mortem methodology is not a code-quality topic. It belongs to SRE/operations/safety-engineering literature. The canonical voices are Allspaw (former Etsy CTO), Richard Cook (medical systems), Sidney Dekker (aviation safety), and the Google SRE team. Paulo should not expect Fowler or Martin to have depth here — the right references are the ones surveyed above.

**Verification: UNVERIFIED — X.com returns HTTP 402 (paywall/auth required); tweet content cannot be confirmed.** No alternative fetchable Fowler URL on post-mortems was found. The finding's main claim (absence of dedicated Fowler writing on the topic) is supported by the negative result of the martinfowler.com search, which did return results but none on post-mortem methodology specifically. This finding sustains no option in the Next Steps section.

---

## Conclusions

**Convergent structure (what companies actually publish):** Five sections appear in every real published post-mortem surveyed (GitLab 2017, Cloudflare 2019, Cloudflare 2024, AWS 2017): Summary, Timeline, Root Cause / Contributing Factors, Impact (quantified), Remediation. These five are the minimum viable structure (Finding 7).

**Template inflation vs. practice:** Prescribed templates (PagerDuty: 10 sections; Atlassian: 14 sections) add sections absent from real examples — "What Went Well," Messaging, Backlog Check. These sections appear to serve internal process goals rather than external explanatory ones (Finding 7).

**Root cause framing is a substantive choice, not a naming preference:** Five Whys (Atlassian) produces a single linear chain and is critiqued by Cook (Finding 8) and Allspaw/Hatch (Finding 11) as too narrow. "Contributing Factors" (PagerDuty, Cook) is theoretically grounded but harder to facilitate for first-timers. The team must choose one (Findings 6, 8, 11).

**Cultural foundation precedes template:** Blameless framing (Allspaw 2012 via Finding 3; SRE Book via Finding 4; PagerDuty facilitation via Finding 9) is more important than section order. Without blameless norms, any template produces compliance documents, not learning documents (Finding 11: "Most incidents are written to be filed, not to be read or learned from").

**Maturity trajectory:** Simple mandatory templates → selective learning-focused reviews (Honeycomb, Finding 10). The starting point and the destination are different; a first-time team should not skip to the Honeycomb approach.

**Claude Code ecosystem:** Three shapes of skill already exist (Finding 12). The thananon skill is the closest to engineer-level code RCA. The wilsto skill covers the full incident lifecycle. The alirezarezvani skill covers executive-level analysis. None is specific to 4Shark conventions.

**Fowler/Uncle Bob:** Not relevant to this domain. Post-mortem literature is owned by SRE/operations practitioners (Finding 13, UNVERIFIED footnote — does not alter this conclusion, which is sustained by the absence of fetchable Fowler content).

---

## Next Steps

Three options for Paulo and the engineer — no recommendation, Paulo and the engineer decide:

**Option A: Build a `/post-mortem` Claude Code skill**
Scope: guide the engineer through writing a post-mortem after an incident, producing a Markdown document. Input: incident description, timeline, what changed. Output: a completed post-mortem file. Anchored in the convergent 5-section structure (Finding 7) plus blameless framing (Findings 3, 4, 9). Would cover the same ground as the thananon skill but with 4Shark's conventions. The wilsto skill covers the full incident lifecycle — more ambitious build. Sustained by Findings 3, 4, 5, 7, 9, 12.

**Option B: Build a post-mortem Markdown template only**
A `POST-MORTEM.template.md` living in `~/.claude/templates/` (or per-project) with the convergent 5 sections plus optional sections for "What Went Well" and "Action Items." Engineer fills it manually. Lower build effort, zero skill maintenance overhead. Fits the pattern of existing templates in the configuration. Sustained by Findings 5, 6, 7, 12.

**Option C: Adopt the convergent 5-section structure as documented knowledge only**
No skill, no template file. Keep this SPIKE.md as the canonical reference. Paulo pulls up the SPIKE when needed. Appropriate if incidents are rare enough that the setup cost outweighs the benefit. Sustained by Finding 7.

The three options are not mutually exclusive: Option B (template) is a natural intermediate step before or alongside Option A (skill). Option C can serve while A or B is being built.

Open questions before deciding:
- Whether 4Shark has recurring incidents that justify a skill vs. occasional incidents that justify a template
- Whether the target audience is engineering-level (code RCA) or management-level (organizational failure analysis), or both
- Whether 4Shark wants to publish post-mortems externally (client-facing) or keep them internal — this changes the Messaging section's relevance
- Whether the Five Whys critique matters in practice at 4Shark's scale (most relevant for complex distributed systems; for smaller teams, Five Whys may be sufficient)
- What format post-mortems should live in at 4Shark: JIRA ticket, Google Doc, GitHub issue, Markdown file in repo, or a dedicated directory
- Whether the Learning From Incidents (LFI) community's facilitation guides (Jeli Howie Guide, Etsy Debriefing Guide) are worth integrating — the search found references but did not fully fetch the facilitation content

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
