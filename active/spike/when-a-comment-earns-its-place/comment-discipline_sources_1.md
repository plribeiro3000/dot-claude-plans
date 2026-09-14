# Source bank — when-a-comment-earns-its-place

Raw verified quotes collected for this spike, organized by topic, kept so a
revision of `SPIKE.md` can re-weight or drop a source without re-fetching
everything. Every entry was fetched during this spike and self-checked
(re-fetched, substring confirmed) unless marked UNVERIFIED.

---

## 1. Canonical "when to comment" frameworks

### Google eng-practices (already in 4Shark's CODE-COMMENTS.md, re-confirmed)

URL: <https://github.com/google/eng-practices/blob/master/review/reviewer/looking-for.md>

> "Are all of the comments actually necessary? Usually comments are useful when they explain why some code exists, and should not be explaining what some code is doing. If the code isn't clear enough to explain itself, then the code should be made simpler."

> "mostly comments are for information that the code itself can't possibly contain, like the reasoning behind a decision."

### Linux kernel coding style (already in CODE-COMMENTS.md, re-confirmed)

URL: <https://www.kernel.org/doc/html/latest/process/coding-style.html>

> "Comments are good, but there is also a danger of over-commenting."

> "Also, try to avoid putting comments inside a function body: if the function is so complex that you need to separately comment parts of it, you should probably go back to chapter 6 for a while."

### Ousterhout, *A Philosophy of Software Design* (via secondary sources — WebFetch could not extract text from the primary PDF)

Source: <https://notes.portebois.net/2021/03/04/13.html> (already in CODE-COMMENTS.md, re-confirmed)

> "If the information in a comment is already obvious from the code next to the comment, then the comment isn't helpful."
> "One example of this is when the comment uses the same words that make up the name of the thing it is describing."

Source (WebSearch synthesis of goodreads.com/work/quotes/61938796, individually fetched and each line present verbatim on the goodreads quotes page — see §1a note below):

> "The overall idea behind comments is to capture information that was in the mind of the designer but couldn't be represented in the code."

> "Some people believe that if code is written well, it is so obvious that no comments are needed. This is a delicious myth...Unfortunately, it's simply not true."

> "Comments should describe things that are not obvious from the code."

**§1a note on verification depth**: the goodreads quotes-page fetch was accepted at WebSearch-summary confidence, not re-fetched individually against the live page for this bank (time-boxed). Treat these three as MODERATE confidence, not the same tier as the Google/kernel/Ousterhout-red-flag quotes above, which were fetched, quoted, and separately self-checked. Do not use the moderate-confidence lines as the sole support for a hard claim in SPIKE.md.

**Table of contents confirms** "Explanation of Intent" (p.56) is a *Robert Martin* subsection heading (Clean Code), NOT an Ousterhout heading — corrected after initially conflating the two. Read directly via `Read` on the downloaded Clean Code sample-pages PDF (`Contents`, page ix of that PDF), which is real, OCR'd book content:

```
Chapter 4: Comments .......................................................53
  Comments Do Not Make Up for Bad Code..................................55
  Explain Yourself in Code ...............................................55
  Good Comments ...........................................................55
    Legal Comments...........................................................55
    Informative Comments...................................................56
    Explanation of Intent..................................................56
    Clarification .............................................................57
    Warning of Consequences.............................................58
    TODO Comments........................................................58
    Amplification .............................................................59
    Javadocs in Public APIs...............................................59
  Bad Comments ............................................................59
    Mumbling ..................................................................59
    Redundant Comments .................................................60
    ...
```

(The sample-pages PDF is a 67-page preview containing only front matter + full index — chapter 4's body text itself was NOT retrievable this way; verbatim body quotes below came from goodreads / third-party fetches instead.)

### Robert C. Martin, *Clean Code* ch. 4

Via <https://www.goodreads.com/work/quotes/3779106-clean-code-a-handbook-of-agile-software-craftsmanship-robert-c-martin> (fetched, quotes present on page):

> "Redundant comments are just places to collect lies and misinformation."

> "The proper use of comments is to compensate for our failure to express ourself in code. Note that I used the word failure. I meant it. Comments are always failures."

> "Truth can only be found in one place: the code."

> "Clean code is simple and direct. Clean code reads like well-written prose. Clean code never obscures the designer's intent but rather is full of crisp abstractions and straightforward lines of control."

> "A long descriptive name is better than a short enigmatic name. A long descriptive name is better than a long descriptive comment."

Via <https://www.goodreads.com/quotes/909630-redundant-comments-are-just-places-to-collect-lies-and-misinformation> (individually confirmed, attribution: Robert C. Martin, *Clean Code: A Handbook of Agile Software Craftsmanship*):

> "Redundant comments are just places to collect lies and misinformation."

Via <https://www.goodreads.com/author/quotes/45372.Robert_C_Martin> (WebSearch synthesis, "necessary evil" framing — MODERATE confidence, not individually re-fetched line-by-line):

> "comments are, at best, a necessary evil."
> "Every time you write a comment, you should grimace and feel the failure of your ability of expression."

**"Explanation of Intent" example** (Martin's own worked example, via secondary blog — <https://bpoplauschi.github.io/2021/01/20/Clean-Code-Comments-by-Uncle-Bob-part-2.html>, fetched):
A `compareTo` method whose comment reads, in the blog's rendering of the book's example: *"we are greater because we are the right type."* — explaining a WHY that the comparison logic alone does not carry. Second example: a threading test with comment *"This is our best attempt to get a race condition by creating large number of threads."*

### Kernighan & Pike, *The Practice of Programming* — NOT independently verified

Every attempt to fetch primary or scanned text of *The Practice of Programming* itself failed (PDF binary/image-encoded, no readable extraction) or produced a suspiciously identical 5-bullet paraphrase across unrelated URLs (signal of the fetch tool's summarizer filling a gap rather than reading real content — this response repeated verbatim across three different fetch targets, which is not how a real page's content should behave). **UNVERIFIED — do not cite Kernighan & Pike with any specific wording in the main SPIKE.** The "don't comment bad code, rewrite it" line IS independently confirmed, but attributed inside Robert Martin's own book to *Kernighan & Plaugher* (Brian W. Kernighan and P. J. Plaugher, authors of *The Elements of Programming Style* — a DIFFERENT book from *The Practice of Programming*, which Kernighan co-wrote with Rob Pike):

Via <https://www.goodreads.com/quotes/9720041-don-t-comment-bad-code-rewrite-it-brian-w-kernighan-and-p> (confirmed):

> "Don't comment bad code—rewrite it." —Brian W. Kernighan and P. J. Plaugher, quoted inside *The Robert C. Martin Clean Code Collection*.

### Jeff Atwood, Coding Horror

"Coding Without Comments" — <https://blog.codinghorror.com/coding-without-comments/> (fetched, self-checked, substring confirmed):

> "the code already tells us how it works; we need the comments to tell us why it works."

> "You should always write your code as if comments didn't exist."

> "if your feel your code is too complex to understand without comments, your code is probably just bad."

> "to write good comments you have to be a good writer"

"Code Tells You How, Comments Tell You Why" — <https://blog.codinghorror.com/code-tells-you-how-comments-tell-you-why/> (fetched):

> "Code can only tell you how the program works; comments can tell you why it works."

> "Code can't explain why the program is being written, and the rationale for choosing this or that method." (Atwood quoting Jef Raskin inside the post)

---

## 2. AI-over-commenting as a recognized, current phenomenon

### anthropics/claude-code#65961 — "[MODEL] Claude verbose code comments by default — ignores instructions to stop"

URL: <https://github.com/anthropics/claude-code/issues/65961> (fetched, self-check re-fetch confirmed the persistence sentence)

> "Claude Code adds far too many code comments by default. The comments are mostly redundant, restating what the adjacent code already makes obvious or simply making references to the chat with Claude itself, leaking its chain of thoughts. It happens on every language, every model."

> "Crucially, this default persists even when explicitly told to stop:
> - A clear, mandatory rule in `CLAUDE.md` does not reliably suppress it.
> - Reinforcing the rule via the memory system does not stop it either."

> "I suppose the core problem is that verbose commenting is the out-of-the-box default, and that default is strong enough to override explicit user instructions."

Reporter: bhuvarloka. (This is the exact issue already cited by 4Shark's own `validate-comment-bloat.sh` and `CODE-PATTERN-DISCIPLINE.md`/`DECISION-AUTHORITY.md` corpus — independently re-confirmed here, not merely trusted.)

### anthropics/claude-code#61305 — "[BUG] Generated code ignores repeated zero-comment instructions" (closed as duplicate of #65961)

URL: <https://github.com/anthropics/claude-code/issues/61305> (fetched)

> "Across many sessions over several months, Claude adds explanatory 'what' comments to generated code even when both the project CLAUDE.md and persistent memory explicitly instruct zero comments / why-only comments. It often self-corrects when reminded mid-session, then regresses on the next code-writing turn."

CLAUDE.md rule quoted inside the issue: *"Default to writing zero comments... if the code needs a comment to explain what it does, the names are wrong."*

Before/after example given by the reporter:

```javascript
// BEFORE (ignored the zero-comment rule):
// Load Lottie vegetables animation (cache JSON across imports).
// lottie-web is imported dynamically so its weight stays out of the
// main bundle – it loads only while a recipe import is in progress.
import(/* webpackChunkName: "lottie" */ 'lottie-web/...')

// AFTER one manual reminder (still one line, but load-bearing):
// Dynamic import keeps lottie-web out of the main bundle.
import(/* webpackChunkName: "lottie" */ 'lottie-web/...')
```

Reporter's summary of the failure shape: *"The instruction system appears 'non-load-bearing' for this behavior—corrections hold for only ~one turn before regressing in subsequent code-generation turns."*

### Hacker News thread (item 43929768) — already cited in CODE-COMMENTS.md, independently re-confirmed + counter-argument found

URL: <https://news.ycombinator.com/item?id=43929768>

Quoted-and-replied-to line (appears inside a `>` blockquote in commenter NitpickLawyer's reply, confirmed present verbatim on the page):

> "The most common thing that makes agentic code ugly is the overuse of comments."

**Counter-argument found in the same thread**, commenter NitpickLawyer (fetched, confirmed):

> "I've seen this complaint a lot, and I honestly don't get it. I have a feeling it helps LLMs write better code. And removing comments can be done in the reading pass, somewhat forcing you to go through the code line by line and 'accept' the code that way. In the grand scheme of things, if this were the only downside to using LLM-based coding agents, I think we've come a long way."

This is a genuine dissent worth carrying into the spike: at least one practitioner voice argues over-commenting is a minor, correctable cost and may even help generation quality — not universal consensus that it is a problem.

Second HN thread found, item 49102548 (fetched, confirmed), commenter Sivart13:

> "If anything Claude writes too many comments. Instead of clean code it dumps walls of text describing a given 'if' as a 'user-grained access-gated control-correcting flow-valve'."

### LinkedIn — Gleb Sidora (arodiss)

URL: <https://www.linkedin.com/posts/arodiss_claude-code-isnt-quite-a-human-colleague-activity-7384314123200733185-JFrk> (fetched, self-check re-fetch confirmed the exact substring)

> "Comments provide both humans and AI models with clues about what the code does - but there's no guarantee these clues are accurate. Over time code evolves, usage changes and comments are left as they were, explaining logic that no longer exists. So in no time you find that they actually harm code readability. I hope Anthropic and other AI companies will tone down commenting tendency in future releases. As a side note, the same curse applies to README.md / CLAUDE.md files that are now so easy to generate, but are as difficult as ever to keep up-to-date."

And, per WebFetch's earlier extraction pass on this same post (not independently re-quoted verbatim in the second fetch, so treat as MODERATE confidence — it did not appear in the confirmed excerpt above):

> "comments are like poorly-written code that is not and can not be covered by tests."
> "Only comment if something weird goes on. However if something weird goes on, you should probably refactor it"

**Confidence note**: the first fetch of this post returned these two lines distinctly; the self-check re-fetch, asked to confirm the exact substring, returned a *different* excerpt of the same post that did not repeat them, then appended them as an apparent recollection ("Actually, let me locate the precise sentence: ...") without quoting surrounding context. This is a weaker self-check than the others in this bank. Use the CONFIRMED long excerpt above as the primary citation; treat "comments are like poorly-written code..." as reported-but-not-independently-reconfirmed.

### Revelry Labs — "The Code Comment Debate Is Over (AI Won)"

URL: <https://revelry.co/insights/code-comment-debate-ai/> (fetched)

> "AI generated code, which is famous for commenting every line already"

This piece argues the opposite direction from 4Shark's instinct — that AI's ability to keep comments synchronized with code in real time makes heavy commenting newly *viable* rather than newly *dangerous*. Included as a genuine dissenting position, not cherry-picked support.

---

## 3. Deviation-comment vs. git; guard-comment vs. test

### Jon Cairns, "Use git to comment your code (and stop writing rubbish commit messages, please)"

URL: <https://blog.joncairns.com/2015/09/use-git-to-comment-your-code/> (fetched)

> "Another kind of comment that doesn't belong in the code is one like 'I changed this because…' ... I'd argue that these comments are just as prone to becoming out of date and contradictory as explanatory comments, and that they actually belong in the logs of your version control system."

> "If your commit messages are written with this in mind then they become more like documentation for the history of your code."

### Counter-argument: tekin.co.uk, "Why Git blame sucks for understanding WTF code (and what to use instead)"

URL: <https://tekin.co.uk/2020/11/patterns-for-searching-git-revision-histories> (fetched, self-check re-fetch confirmed all three quotes)

> "git blame is too coarse: it reports against the whole line. If the most recent change isn't related to the part of the line you're interested, you're out of luck."

> "git blame is too shallow: it only reports a single change; the most recent one. The story of the particular piece of code you're interested in may have evolved over several commits."

> "git blame is too narrow: it only considers the file you are running blame against. The code you are interested in may also appear in other files, but to get the relevant commits on those you'll need to run blame several times."

This is the sharpest documented objection to "put it in git, not the comment": git history is real but expensive and unreliable to navigate at the point of reading, which is exactly the point-of-use 4Shark's own CODE-COMMENTS.md test ("does a competent reader lose something?") is testing.

### Martin Fowler, "Goto Fail, Heartbleed, and Unit Testing Culture"

URL: <https://martinfowler.com/articles/testing-culture.html> (fetched)

> "No bug is considered properly fixed without an automated regression test."

> "Well-written unit tests can provide two types of documentation: the test names act as a sort of specification of the code's behavior; and the tests themselves act as code samples for each behavior case."

> "An automated test captures those runs as a permanent double-check."

### Executable-example / doc-test sources (comments-can't-go-stale vs. tests-can't-go-stale)

Bitfield Consulting, "Go's best-kept secret: executable examples" — <https://bitfieldconsulting.com/posts/examples> (fetched, attributed inside the post to Donovan & Kernighan, *The Go Programming Language*):

> "unlike examples within comments, example functions are real Go code, subject to compile-time checking, so they don't become stale as the code evolves."

### Michael Feathers, characterization / pinning tests (via WebSearch synthesis of multiple secondary sources — MODERATE confidence, not fetched from the primary book)

> "a characterization test does not check whether the code is correct. It pins what the code actually does right now."

This is the community concept closest to 4Shark's "forward-looking guard ('this omission/choice is intentional — don't undo it to match the siblings')" question: a pinning/characterization test is explicitly designed to make an intentional-and-possibly-surprising current behavior break loudly if someone reverts it, which is exactly the guard-comment's stated job.

### "Code never lies, comments sometimes do" — attributed to Ron Jeffries

Via <https://www.azquotes.com/quote/878654> and <https://quotefancy.com/quote/1652498/Ron-Jeffries-Code-never-lies-comments-sometimes-do> (WebSearch synthesis; quote-aggregator attribution, MODERATE-LOW confidence — no primary source page located and quote-aggregator sites are known to occasionally misattribute short aphorisms). Cite as "widely attributed to Ron Jeffries" with this caveat, never as a firmly sourced Jeffries quote.

### 4Shark's own DECISION-AUTHORITY.md (internal, already read in full — not a web source)

> "A resolved decision is recorded where the next reader meets it, and that place is the code: a comment at the line, a name that says what the value is, a test that pins the behaviour the decision chose."

Note this ALREADY names "a test that pins the behaviour" as one of three legitimate recording mechanisms, alongside a comment — it does not currently pick between them for the guard-comment case. This is the exact ambiguity sub-question 2 asks to resolve.

---

## 4. What works to suppress reflexive commenting

### uncomment (Goldziher)

URL: <https://github.com/goldziher/uncomment> (fetched)

> "Blazingly fast CLI to remove comments from code using tree-sitter grammers"

> "Originally built to clean up AI-generated code drowning in explanatory comments, it now works on anything with a tree-sitter grammar."

> "Regex-based comment strippers guess. They delete a `//` inside a string literal, mangle a URL in a docstring, or leave a linting directive your CI depends on. uncomment doesn't guess."

Preserves TODO/FIXME, doc comments, and linting directives by default. Quantitative/structural (AST-based comment detection), not qualitative — it cannot tell a load-bearing comment from a redundant one; it is a blanket removal tool with an allowlist of *shapes* (TODO, docstring, lint directive), not of *content quality*.

### llmstrip (HugoLopes45)

URL: <https://github.com/HugoLopes45/llmstrip> (fetched)

> "Strip AI patterns from text and code. Prompt + linter."

Ships as a CLI, a Claude Code skill (`/llmstrip` invoked manually mid-session), a Cursor rule, and a git-hook/CI-gate mode (`llmstrip --report --fail`). Also quantitative/pattern-based (34 rules), not a judge of whether an individual surviving comment earns its place.

### 4Shark's own gist-documented pattern (bavanws), "Reducing code-comment verbosity with Claude Code"

URL: <https://gist.github.com/bavanws/123e0343f8a79cec825d9141124a0a83> (fetched)

Two-layer approach — a CLAUDE.md prevention rule plus a "comment-cleanup skill" invoked after the fact:

> "Default to no comment. Code shows how; comment only to carry why"

> "When in doubt about a why, keep it; when in doubt about a how, delete it."

Cleanup-skill six-step ruleset includes an explicit "moving targets" step — delete a comment pointing at something transient ("spec section 3", "design doc") — and a "bloated rationale" step: *"a five-line block almost never survives intact; suspect it on sight."*

**This is qualitative in intent** (a judgment ruleset an LLM applies per-comment after the fact) but has the same structural weakness as 4Shark's own commit-boundary verifier: it depends on a model (the cleanup skill IS a prompted LLM pass) correctly judging redundancy, which is the same judgment call this spike's whole question is about. It is evidence of a genuinely qualitative APPROACH (as opposed to a count-based hook), not evidence that the approach reliably works — no data on its hit rate was found.

### Linter-as-constraint framing (dev.to, general community sentiment, WebSearch synthesis — MODERATE confidence)

> "AI can choose to ignore documentation, but it cannot ignore linting errors in your CI pipeline"

Directionally consistent with why 4Shark already treats `validate-comment-bloat.sh` (a mechanical CI-adjacent gate) as necessary ballast alongside the documentation-only rule, even though the doc itself states the gate cannot reach the qualitative judgment.
