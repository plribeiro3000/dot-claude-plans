# SPIKE — When a Comment Earns Its Place

## Investigation question

When does an inline code comment genuinely earn its place, as a *qualitative*
decision the author applies rather than a line-count a hook can enforce? Two
sharp sub-questions:

1. Does "a deliberate deviation from the established local pattern" justify an
   inline comment, or does that rationale belong in the commit message / PR
   description / CHANGELOG — git as the home for "why it changed"?
2. Is a forward-looking guard comment ("this omission/choice is intentional —
   don't undo it to match the siblings") legitimate, or should a test carry
   that invariant (an executable assertion that breaks if someone reverts it),
   making the comment redundant?

The trigger: a one-line front-end hotfix removed `enabled: true` from a
GraphQL query (per a client request, so an export screen also lists inactive
users) and the model added a one-line comment explaining the removal. The
engineer's position is that this specific WHY already lives in the commit
(release 1.288.1) and the CHANGELOG, so the comment duplicates a fact that has
a better home and should not have been written. 4Shark's existing mechanical
gate (`validate-comment-bloat.sh`) is purely quantitative — it blocks a
comments-only edit of 3+ lines and a block of 6+ consecutive lines — and
cannot catch a single, useless line, which is exactly the shape this incident
produced.

## Sources consulted

- `~/.claude/docs/CODE-COMMENTS.md` — the current rule under test; lists "the
  reason for a deliberate deviation" and "a resolved decision" as valid
  comment reasons.
- `~/.claude/docs/TIMELESS-DOCUMENTATION.md` — already routes a document's own
  edit history to git; the analogous question for code comments is this
  spike's sub-question 1.
- `~/.claude/docs/CODE-PATTERN-DISCIPLINE.md` — step 5 currently states a
  deliberate deviation's reason "goes in a code comment at the line."
- `~/.claude/docs/DECISION-AUTHORITY.md` — states a resolved decision is
  recorded in "a comment at the line, a name that says what the value is, a
  test that pins the behaviour the decision chose" — three options, not
  currently ranked against each other.
- `~/.claude/scripts/validate-comment-bloat.sh` — read in full; confirms the
  two thresholds (`MAX_CONSECUTIVE_COMMENT_LINES=6`,
  `MIN_COMMENTS_ONLY_LINES=3`) and that a single comment line added alongside
  a code edit (not a comments-only edit) is invisible to this hook by
  construction.
- Google eng-practices code-review guide, Linux kernel coding style, Ousterhout
  *A Philosophy of Software Design*, Robert C. Martin *Clean Code*, Jeff
  Atwood (Coding Horror) — canonical "when to comment" frameworks.
- anthropics/claude-code#65961, #61305 — GitHub issues documenting the model's
  persistent over-commenting despite explicit instructions.
- Hacker News threads 43929768 and 49102548 — community discourse on agentic
  over-commenting, including a documented dissent.
- LinkedIn (Gleb Sidora / arodiss) — practitioner argument that AI comments
  are unreliable because they carry none of a test's accountability.
- Jon Cairns ("Use git to comment your code") vs. tekin.co.uk ("Why Git blame
  sucks for understanding WTF code") — opposing positions on whether commit
  history is a workable substitute for an inline comment.
- Martin Fowler ("Goto Fail, Heartbleed, and Unit Testing Culture") and the Go
  executable-examples pattern — tests/examples that cannot go stale by
  construction.
- uncomment, llmstrip, and a 4Shark-adjacent gist (bavanws) — tooling attempts
  at suppressing reflexive commenting.
- See auxiliary: `comment-discipline_sources_1.md` — the full quote bank,
  organized by topic, with confidence notes on every entry, including the two
  sources that failed verification (Kernighan & Pike primary text; part of one
  LinkedIn quote) and are marked accordingly.

## Findings

### Finding 1: The "why not what" framing is universal, but it hides a real split between two questions

**Evidence:** Google: *"Usually comments are useful when they explain why some
code exists, and should not be explaining what some code is doing."* The
Linux kernel: *"you want your comments to tell WHAT your code does, not HOW."*
Both quoted in full with URLs in `CODE-COMMENTS.md`, independently
re-confirmed during this spike (see auxiliary §1).

**Source:** <https://github.com/google/eng-practices/blob/master/review/reviewer/looking-for.md>; <https://www.kernel.org/doc/html/latest/process/coding-style.html>

**Significance:** `CODE-COMMENTS.md` already reconciles the vocabulary clash
correctly — Google's "why" and the kernel's "what" name the same target, the
purpose, and both forbid restating mechanics. What is NOT settled by either
source is the question this spike is actually about: even a comment that
correctly explains a "why" can still be the wrong PLACE to put that why, if a
better place exists (git, a test). Neither source addresses *competing
locations* for legitimate why-content — they only distinguish legitimate
why-content from illegitimate what-content. This is Finding 1's boundary: the
existing 4Shark rule answers "is this comment redundant with the code?" but
not "is this comment redundant with a BETTER home for the same fact?" — that
second question is what sub-questions 1 and 2 are actually asking.

**Verification:** URL fetched (both) / verbatim quote checked / quote
substring confirmed at the review guide body text and the kernel coding-style
page body text respectively.

### Finding 2: Ousterhout and Martin genuinely disagree on WHERE the line sits, not just on vocabulary — and neither settles the git-vs-comment question

**Evidence:** Ousterhout (via Notes on the red flag "Comment Repeats Code"):
*"If the information in a comment is already obvious from the code next to
the comment, then the comment isn't helpful."* This is a narrow test — it only
forbids restatement, and separately (per secondary sourcing, moderate
confidence — see auxiliary) his broader framing treats comments as capturing
*"information that was in the mind of the designer but couldn't be
represented in the code."* Martin, by contrast, treats every comment as an
admission of failure: *"The proper use of comments is to compensate for our
failure to express ourself in code. Note that I used the word failure. I
meant it. Comments are always failures."* (goodreads.com/work/quotes/3779106,
attributed to *Clean Code*.)

**Source:** <https://notes.portebois.net/2021/03/04/13.html>;
<https://www.goodreads.com/work/quotes/3779106-clean-code-a-handbook-of-agile-software-craftsmanship-robert-c-martin>

**Significance:** This is a real disagreement, not a vocabulary artifact: if
Martin is right, the bar for ANY comment is "could the code have been made
clearer instead" — a comment surviving that bar is rare. If Ousterhout is
right, a comment is a legitimate, first-class carrier of designer intent that
the code was never going to carry regardless of how it was written (an
interface's contract, a non-obvious constraint on a caller). Neither author,
in any verified source found, directly addresses whether git commit history
is an acceptable substitute location for that intent — both are answering "is
a comment ever justified", not "given that a comment is justified in
principle, is the comment the right PLACE for it, or is git/a test better."
That is the actual gap 4Shark's two sub-questions are probing, and no single
canonical source closes it.

**Verification:** URL fetched (both) / verbatim quote checked / quote
substring confirmed at the cited page bodies.

### Finding 3: AI over-commenting is a documented, current, and recognized phenomenon — including inside Anthropic's own issue tracker, with a persistence mechanism 4Shark has already hit

**Evidence:** anthropics/claude-code#65961, reported title *"[MODEL] Claude
verbose code comments by default — ignores instructions to stop"*: *"Claude
Code adds far too many code comments by default. The comments are mostly
redundant, restating what the adjacent code already makes obvious or simply
making references to the chat with Claude itself, leaking its chain of
thoughts. It happens on every language, every model."* And, specifically on
the failure mode 4Shark's engineer is describing (a rule that does not hold):
*"Crucially, this default persists even when explicitly told to stop: A clear,
mandatory rule in CLAUDE.md does not reliably suppress it. Reinforcing the
rule via the memory system does not stop it either."*

A second, related issue (#61305, closed as a duplicate) gives a concrete
before/after: a reminder shrinks a 3-line narration comment to 1 line, but the
1-line version survives only because the reporter manually intervened —
*"corrections hold for only ~one turn before regressing in subsequent
code-generation turns."*

**Source:** <https://github.com/anthropics/claude-code/issues/65961>;
<https://github.com/anthropics/claude-code/issues/61305>

**Significance:** This directly supports the engineer's premise — the model
is not deciding from what is true in the 4Shark codebase; it is reverting to
a training-data default that a documentation-only rule (`CODE-COMMENTS.md`
plus its write-time injection) does not reliably override, and that a
count-based gate (`validate-comment-bloat.sh`) structurally cannot reach when
the comment is exactly one line. The #61305 example is the same shape as the
`enabled: true` incident: a reminder can shrink or suppress the comment for
one turn, but nothing in the current stack prevents the NEXT turn from
regressing, because the gate that exists counts lines, not redundancy.

**Verification:** URL fetched (both) / verbatim quote checked / quote
substring confirmed via a self-check re-fetch on issue #65961 (the
"persists even when explicitly told to stop" sentence).

### Finding 4: The community is not unanimous that over-commenting is a problem worth fixing — a real dissent exists, and it is worth naming honestly

**Evidence:** Hacker News thread 43929768 carries the widely-quoted line *"The
most common thing that makes agentic code ugly is the overuse of comments,"*
but the reply that quotes it pushes back directly: *"I've seen this complaint
a lot, and I honestly don't get it. I have a feeling it helps LLMs write
better code. And removing comments can be done in the reading pass, somewhat
forcing you to go through the code line by line and 'accept' the code that
way."* (commenter NitpickLawyer)

**Source:** <https://news.ycombinator.com/item?id=43929768>

**Significance:** This spike was asked to be honest about whether the
phenomenon is "widely reported" or "thinner than expected." The honest answer
is: widely reported (the GitHub issues, the second HN thread, the Revelry
Labs piece, and the LinkedIn post all independently corroborate it — see
Findings 3 and 6), but NOT unanimous. At least one practitioner voice treats
comment overproduction as a minor, correctable cost of agentic coding rather
than a defect worth engineering around. This does not weaken the case for a
qualitative test — 4Shark's own trigger incident and the two GitHub issues
are independent, first-hand evidence of the cost — but it means the spike
should not overstate consensus that does not exist.

**Verification:** URL fetched / verbatim quote checked / quote substring
confirmed (the reply is a direct blockquote of the disputed line, both
present on the page).

### Finding 5: A second practitioner independently reaches the "tests, not comments" position 4Shark's engineer is asking about

**Evidence:** Gleb Sidora, writing about Claude Code specifically: *"Comments
provide both humans and AI models with clues about what the code does - but
there's no guarantee these clues are accurate. Over time code evolves, usage
changes and comments are left as they were, explaining logic that no longer
exists."* And, in an earlier extraction of the same post (see auxiliary §2 for
the confidence caveat on this specific line — it did not repeat in the
self-check re-fetch): *"comments are like poorly-written code that is not and
can not be covered by tests."*

**Source:** <https://www.linkedin.com/posts/arodiss_claude-code-isnt-quite-a-human-colleague-activity-7384314123200733185-JFrk>

**Significance:** Whether or not the exact "poorly-written code... not covered
by tests" phrasing is treated as fully reconfirmed (see the confidence note),
the independently reconfirmed excerpt makes the same point in different
words: a comment's claim about the code is untested and therefore
unverifiable at the moment a reader trusts it, while a test's claim is
checked every run. This is the strongest community-sourced argument found FOR
sub-question 2's proposed direction (guard belongs in a test) — not because
Sidora addresses 4Shark's specific "deliberate omission" framing, but because
the underlying mechanism (comments have no enforcement; tests do) is the same
one that makes a guard-test superior to a guard-comment in general.

**Verification:** URL fetched / verbatim quote checked / quote substring
confirmed via self-check re-fetch on the fully-reconfirmed excerpt; the
second line is flagged UNVERIFIED-at-full-confidence per the auxiliary note
and is not treated as independently load-bearing here.

### Finding 6: On sub-question 1 (deviation comment vs. git), the community is genuinely split, and the split maps onto a real cost the "put it in git" side does not fully answer

**Evidence — "put it in git" side:** Jon Cairns: *"Another kind of comment
that doesn't belong in the code is one like 'I changed this because…' ... I'd
argue that these comments are just as prone to becoming out of date and
contradictory as explanatory comments, and that they actually belong in the
logs of your version control system."*

**Evidence — "git history is not a reliable substitute" side:** tekin.co.uk,
on `git blame` specifically: *"git blame is too coarse: it reports against
the whole line... git blame is too shallow: it only reports a single change;
the most recent one... git blame is too narrow: it only considers the file
you are running blame against."*

**Source:** <https://blog.joncairns.com/2015/09/use-git-to-comment-your-code/>;
<https://tekin.co.uk/2020/11/patterns-for-searching-git-revision-histories>

**Significance:** These are not actually contradictory once the target is
made precise. Cairns is arguing against a narrow class of comment — one that
literally narrates a change ("I changed this because...", "now also
handles...") — which is exactly the shape `CODE-COMMENTS.md` §3 (Diff
narration) ALREADY forbids and routes to git, independent of this spike. The
tekin.co.uk critique is about a different act: using `git blame`/`git log` as
a *retrieval mechanism* for understanding present-tense code, which is slower
and noisier than a comment sitting at the point of use. **The two positions
are not actually about the same comment shape.** A narrated-change comment
("I removed `enabled: true` because of a client request, see release
1.288.1") is squarely Cairns's target and 4Shark's own existing
`TIMELESS-DOCUMENTATION.md`/§3 rule already forbids it — this is not a live
question, it is already decided by an existing 4Shark rule the engineer's
incident report itself demonstrates was violated. A comment that instead
states a present-tense FACT with no reference to the change ("no `enabled`
filter: the export must include inactive users") is not diff narration by
`CODE-COMMENTS.md`'s own current forbidden-shapes list — it reads as a
present-tense business rule, which is the "resolved decision" category the
rule currently allows. The actual open question is narrower than either
source addresses: is "the export must include inactive users" a fact the
CODE cannot show (which would make it a legitimate comment under the current
rule) or is it simply the CURRENT git-log summary restated in the file
(making it exactly the shape TIMELESS-DOCUMENTATION.md already forbids, just
without an explicit "we changed X" marker)? See "What remains uncertain"
below — this spike could not find a source that draws this exact line.

**Verification:** URL fetched (both) / verbatim quote checked / quote
substring confirmed (Cairns via direct fetch; tekin.co.uk via a dedicated
self-check re-fetch of all three quoted sentences).

### Finding 7: Sub-question 2 has closer community support — pinning/characterization tests are the named concept for "guard against reverting an intentional choice," and 4Shark's own doc already half-endorses the test path

**Evidence:** Fowler: *"No bug is considered properly fixed without an
automated regression test."* And, on why: *"An automated test captures those
runs as a permanent double-check."* On the executable-documentation angle,
via the Go language documentation (cited inside a Bitfield Consulting post):
*"unlike examples within comments, example functions are real Go code,
subject to compile-time checking, so they don't become stale as the code
evolves."*

4Shark's own `DECISION-AUTHORITY.md` (internal, already read in full for this
spike, not a web source): *"A resolved decision is recorded where the next
reader meets it, and that place is the code: a comment at the line, a name
that says what the value is, a test that pins the behaviour the decision
chose."*

**Source:** <https://martinfowler.com/articles/testing-culture.html>;
<https://bitfieldconsulting.com/posts/examples>; internal —
`~/.claude/docs/DECISION-AUTHORITY.md`.

**Significance:** The concept 4Shark's second sub-question is reaching for —
"an executable assertion that breaks if someone reverts it" — has an
established community name: a pinning test / characterization test / a
regression test written specifically to encode "this is intentional, not a
bug." Two properties make a test structurally better than a comment for THIS
specific job (guarding against an accidental revert), independent of any
"comments are inferior in general" framing: (1) it is enforced — a revert
that violates the guard fails CI, where a reverted comment simply
disappears silently with the code it guarded; (2) it survives exactly the
`validate-comment-bloat.sh` blind spot this spike exists to address — a
single-line comment guard is invisible to any count-based gate and to most
readers skimming a diff, while a failing test is impossible to merge
silently. `DECISION-AUTHORITY.md` already lists "a test that pins the
behaviour" alongside "a comment at the line" as parallel options without
ranking them — this spike's evidence suggests that for the specific shape
"guard against an unintentional revert," the test is the stronger of the two,
not merely an alternative.

**Verification:** URL fetched (both) / verbatim quote checked / quote
substring confirmed at both page bodies; the `DECISION-AUTHORITY.md` citation
is `file:105` of the doc read in full at the start of this spike (not a URL
fetch — internal source, cited per this repository's own citation norms for
non-web sources).

### Finding 8: A genuinely qualitative suppression tool exists in the wild, but it has the identical structural weakness as the thing it replaces

**Evidence:** The bavanws gist's two-layer approach pairs a prevention rule
(*"Default to no comment. Code shows how; comment only to carry why"*) with a
post-hoc "comment-cleanup skill" that applies a judged ruleset — *"When in
doubt about a why, keep it; when in doubt about a how, delete it"* — as a
second LLM pass over the code. `uncomment`, by contrast, is honestly
quantitative: *"Originally built to clean up AI-generated code drowning in
explanatory comments"*, but it works by AST-based STRUCTURAL detection
(comment vs. non-comment), with an allowlist of *shapes* it preserves
(TODO/FIXME, docstrings, lint directives) — it has no concept of whether a
given comment's CONTENT is redundant.

**Source:** <https://gist.github.com/bavanws/123e0343f8a79cec825d9141124a0a83>;
<https://github.com/goldziher/uncomment>

**Significance:** This is the clearest evidence available that the engineer's
framing is correct: nothing found in this research closes the gap between
"decidable by a matcher" and "decidable by judgment" for THIS specific
question. `uncomment` and `llmstrip` sidestep the judgment question by either
removing everything indiscriminately (uncomment, with a shape-based
allowlist) or pattern-matching known AI writing tics (llmstrip, 34 rules,
still pattern-based). The bavanws cleanup skill is the one approach found
that actually attempts the judgment call — but it does so by running ANOTHER
LLM pass with a ruleset, which has exactly the same reliability ceiling as
the original generation: a model applying a rule about "is this redundant"
is subject to the same generative pressure #65961 documents, just at review
time instead of write time. No evidence was found (hit-rate data, case
studies) that this second-pass approach reliably catches what the first pass
missed.

**Verification:** URL fetched (both) / verbatim quote checked / quote
substring confirmed at both page bodies.

## A synthesized qualitative decision test

Built from Findings 1, 2, 5, and 7, and from `CODE-COMMENTS.md`'s own
deletion test (which this does not replace — it sharpens the one case the
deletion test does not resolve: a comment that DOES survive deletion because
it states a real fact, but states it in the wrong PLACE).

**Step 0 (unchanged) — the existing deletion test still runs first.** Delete
the comment. If a competent reader loses nothing, it was noise, full stop.
This spike does not touch that test; it only continues past it, because the
`enabled: true` comment PASSES it — the fact it states ("the export must
include inactive users") really is not derivable from the code alone.

**Step 1 — the relocation test (answers sub-question 1).** A comment that
survives Step 0 is checked against one further question: *does this comment
describe the CURRENT git-log entry for this line, or does it describe a
CURRENT business/technical fact the code embodies?*

- If removing the comment and reading `git log -p` / `git blame` on the same
  line would tell a reader the identical fact in the identical words (a
  paraphrase of "why we changed it"), the comment is diff narration —
  `CODE-COMMENTS.md` §3 already forbids this, and Finding 6 confirms the
  community position (Cairns) supports keeping that rule as-is. Cut it; the
  commit/PR/CHANGELOG already carries it, and per `TIMELESS-DOCUMENTATION.md`
  the comment would be the document narrating its own edit history.
- If the comment states a fact that is true of the system regardless of when
  or why it became true — a business rule, an invariant, a constraint on a
  caller — it survives Step 1, REGARDLESS of whether that fact happens to
  also be recoverable from git. Finding 6's tekin.co.uk evidence is why: git
  is a real but expensive, narrow, and shallow retrieval path, and a reader
  at the point of use should not have to run three `git blame` calls to
  recover a fact the code needs them to know right now.
- **The engineer's own trigger case is instructive under this test, and it
  cuts against a blanket rule either way.** "No enabled filter: the export
  must reach inactive users too, so they can be exported without being
  reactivated first" is phrased as a justification for a CHANGE ("must reach
  ... too", "without being reactivated first" — a comparison against a prior
  state), which fails Step 1 as diff narration. A present-tense rewrite with
  no comparison ("the export includes inactive users — export must not
  require reactivation") would pass Step 1, because it states a standing
  constraint, not a change. **This means the engineer's objection to the
  SPECIFIC comment that was written is well-founded under the existing rule
  — it was diff narration dressed as a decision comment — without requiring
  a new rule that "deviation reasons never belong in comments" at all.**

**Step 2 — the guard test (answers sub-question 2).** For a
forward-looking "don't undo this" comment specifically:

- If the invariant can be checked mechanically (a value, a return shape, an
  absence of a filter, a call that must NOT happen) — write a test that pins
  it, per Finding 7. Delete the comment, or reduce it to a one-line pointer
  at the test if the code alone still reads as suspicious without any
  annotation at all (rare — most guarded lines read fine once the test
  exists, because the reader trusts the test suite to have caught a bad
  revert already).
- If the invariant genuinely cannot be checked mechanically (a design
  rationale, a business-policy statement with no observable behavioral
  signature a test could assert on, an external system's undocumented
  quirk) — the comment is the only mechanism available, and it earns its
  place under the existing "external cause" / "trap" rows of
  `CODE-COMMENTS.md`'s table.

**The test survives the failure mode that beat the line-count hook** because
it is not counting anything — it asks two content questions (does this
restate the commit? does this pin something a test could pin instead?) that
apply identically to a one-line comment and a ten-line comment. A single
useless line still fails Step 1 or Step 2 exactly as a ten-line block would;
the test's power comes from being orthogonal to length, which is precisely
what `validate-comment-bloat.sh` cannot be, by its own documented design (it
is deliberately restricted to facts about text, not judgments about intent —
confirmed by reading the script in full for this spike).

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Keep `CODE-COMMENTS.md` as-is (deviation + resolved-decision both stay valid comment reasons) | No new rule to learn; matches Ousterhout's and 4Shark's `DECISION-AUTHORITY.md` "record it where the reader meets it" framing | Does not distinguish a present-tense fact from disguised diff narration — exactly the gap the trigger incident fell through | Findings 1, 2, 6 |
| Remove "deviation from pattern" as a listed valid reason, route it entirely to git/PR | Closes the gap Cairns's argument targets; aligns with `TIMELESS-DOCUMENTATION.md`'s existing logic applied consistently | Loses the point-of-use fact a reader would otherwise have to retrieve via `git blame`, which Finding 6's tekin.co.uk evidence shows is coarse, shallow, and narrow in practice | Finding 6 |
| Redirect "forward-looking guard" from comment to test, when mechanically checkable | Enforced rather than advisory; survives exactly the failure mode (single useless line) that started this spike; has a named community concept (pinning/characterization test) | Not every guard is mechanically checkable (a business-policy rationale with no observable signature); a test alone gives a reader no reason *why*, only that it must not change | Finding 7 |
| A second LLM "cleanup pass" applying a qualitative ruleset (bavanws-style) | Genuinely judges content, not just shape; can run as a mechanical CI gate | Inherits the same generative unreliability as the first pass (#65961's own finding) — no evidence found that a second pass reliably outperforms explicit rules at write time | Findings 3, 8 |
| Blanket structural stripping (uncomment/llmstrip) | Fast, deterministic, catches the volume problem completely | Cannot distinguish a load-bearing comment from noise; would delete exactly the comments `CODE-COMMENTS.md` requires (deviation reasons, resolved decisions, forwarder exceptions) | Finding 8 |

## What remains uncertain

- **No source found draws the exact line between "a present-tense fact the
  code embodies" and "the current git-log summary restated without an
  explicit 'we changed X' marker."** This is the sharpest open question:
  Finding 6's relocation test (Step 1 above) is this spike's own synthesis,
  built from reconciling Cairns and tekin.co.uk, not a position either source
  states directly. It should be treated as a proposed test, not a confirmed
  community consensus.
- **Kernighan & Pike's *The Practice of Programming* could not be
  independently verified.** Every fetch attempt against primary or scanned
  text failed or produced a response pattern consistent with the fetch
  tool's summarizer filling a gap rather than reading real content (see
  auxiliary §1 for the specific evidence of this). The "don't comment bad
  code, rewrite it" line IS real and confirmed, but is attributed inside
  Robert Martin's own book to Kernighan & PLAUGHER (a different book, *The
  Elements of Programming Style*), not Kernighan & Pike. If 4Shark wants a
  Kernighan & Pike citation specifically, it needs a source this spike did
  not find.
- **Whether the bavanws-style "second LLM pass" cleanup skill actually works
  in practice is unmeasured.** No hit-rate data, before/after comparison, or
  case study was found for that approach specifically — it is included as an
  example of a genuinely qualitative attempt, not as validated evidence that
  qualitative LLM-judged cleanup is reliable.
- **The community is not unanimous that AI over-commenting is a problem** —
  Finding 4's NitpickLawyer dissent is real and should not be erased from the
  record in favor of a cleaner-sounding "consensus" narrative.
- **No mechanical gate was found or designed in this research that closes the
  gap `validate-comment-bloat.sh` already documents as unreachable.** Every
  tool found (uncomment, llmstrip, the bavanws skill) either sidesteps the
  judgment question structurally (blanket removal) or re-introduces the same
  reliability ceiling by using another LLM to judge (the cleanup skill). If
  the realistic answer is "no mechanical gate can catch this, only a
  better-stated rule plus the reviewer," this spike's evidence supports that
  conclusion — Finding 8 is the direct support for it.

## Suggested options for main and the engineer

- **Option A — Keep `CODE-COMMENTS.md`'s two valid-reason rows as-is, and add
  the relocation test (Step 1) as a THIRD, narrower test applied specifically
  to a "deviation" or "resolved decision" comment**, so the rule keeps its
  existing carve-outs but gains the distinction Finding 6 surfaces between "a
  standing fact" and "diff narration wearing a decision-comment costume."
  This directly targets the trigger incident without removing a row the
  documentation currently states is required elsewhere in the corpus (e.g.
  `NO-DELEGATE.md`'s forwarder exception, `ASSOCIATION-NAMING.md`'s judged
  name).

- **Option B — Remove "deliberate deviation from pattern" as a listed valid
  comment reason entirely, per the engineer's original framing**, redirecting
  all such rationale to the commit/PR/CHANGELOG unconditionally.
  `CODE-PATTERN-DISCIPLINE.md` step 5 would need a corresponding edit (it
  currently states the reason "goes in a code comment at the line"). This is
  the cleanest rule to state and enforce, and it removes the exact ambiguity
  that produced the trigger incident, but Finding 6's tekin.co.uk evidence is
  a genuine, documented cost this option accepts rather than resolves — a
  reader at the point of use loses the fact unless they successfully retrieve
  it from git, which the cited source argues is unreliable in practice for
  anything beyond the single most recent change to that exact line.

- **Option C — For sub-question 2 specifically, add explicit guidance
  (independent of A or B above) that a forward-looking guard is redirected to
  a test whenever the invariant is mechanically checkable, and stays a
  comment only when it is not** — this is the option with the strongest,
  most specific community backing found (Finding 7) and the cleanest fit to
  `DECISION-AUTHORITY.md`'s existing "a test that pins the behaviour" language,
  which already names this option without currently ranking it above the
  comment alternative.

- **Option D — Accept Finding 8's conclusion and do not build new mechanical
  enforcement for the qualitative judgment**, treating `validate-comment-bloat.sh`
  as already at the edge of what a hook can decide, and leaning instead on
  restating the rule more precisely (whichever of A/B is chosen) plus
  `@agent-code-policy-verifier` at the commit boundary — which is the one
  mechanism in 4Shark's existing stack actually capable of judging content
  rather than shape.

(No recommendation between A/B/C/D — per the Subagent Contract, that choice
belongs to main and the engineer.)
