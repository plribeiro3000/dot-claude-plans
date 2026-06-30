# Source Excerpts: Literature on Domain vs Implementation Naming

## Source 1 — Steve McConnell, Code Complete 2 (via Nikola Brežnjak blog summary)

URL: https://nikola-breznjak.com/blog/books/programming/code-complete-2-steve-mcconnell-power-variable-names/

Verbatim quote confirmed on page:

> "The name must fully and accurately describe the entity that the variable represents."

Source note: This is a direct quote from Code Complete Chapter 11 ("The Power of Variable Names"),
reproduced verbatim in the blog post. The blog post is a chapter-by-chapter notes series from the book.

Additional passage on constants (same page, verbatim):

> "When naming constants, name the abstract entity the constant represents rather than the number the constant refers to."

---

## Source 2 — Robert C. Martin, Clean Code Chapter 2 (via dev.to teamradhq summary)

URL: https://dev.to/teamradhq/clean-code-chapter-2-41ph

Paraphrase quote confirmed verbatim on page (covers both sections):

> "Use solution domain names because other engineers will be able to infer their meaning. Use problem domain names as non-technical stakeholders will be able to infer their meaning."

**UNVERIFIED — original book wording.** The exact original sentences from Clean Code (e.g. "Remember that
the people who read your code will be programmers. So go ahead and use computer science (CS) terms..." and
the "programmer-eese" sentence) were NOT found verbatim on this page or on any reachable secondary source.
Re-fetched 2026-06-19: dev.to contains only the paraphrase above. thecoderoad.blog and fabrizioduroni.it
also paraphrase ("Math names, algorithm names, pattern names are all good choices" / "If no 'programmer
oriented name' exists, go with names taken from the problem domain"). The literal book text requires the
original Clean Code (p. 27).

Section titles confirmed across multiple independent sources: "Use Solution Domain Names" and
"Use Problem Domain Names" appear in Clean Code Chapter 2. Cross-confirmed by:
- https://thecoderoad.blog/2020/03/29/clean-code-naming-conventions/
- https://www.fabrizioduroni.it/2017/09/11/clean-code-meaningful-names/

Note: The section "Use Intention-Revealing Names" is named in the book but no verbatim text from that
section was obtainable from publicly available secondary sources — only paraphrases. The concept's
existence and section title are confirmed. Direct text requires the original book.

---

## Source 3 — Joel Spolsky, "Making Wrong Code Look Wrong" (2005)

URL: https://www.joelonsoftware.com/2005/05/11/making-wrong-code-look-wrong/

Verbatim quotes confirmed on page:

> "Apps Hungarian had very useful, meaningful prefixes like 'ix' to mean an index into an array, 'c'
> to mean a count, 'd' to mean the difference between two numbers (for example 'dx' meant 'width'),
> and so forth."

> "Systems Hungarian had far less useful prefixes like 'l' for long and 'ul' for 'unsigned long' and
> 'dw' for double word, which is, actually, uh, an unsigned long."

> "Somebody, somewhere, read Simonyi's paper, where he used the word 'type,' and thought he meant
> type, like class, like in a type system, like the type checking that the compiler does. He did not."

---

## Source 4 — Martin Fowler / Eric Evans, "Ubiquitous Language" (2006)

URL: https://martinfowler.com/bliki/UbiquitousLanguage.html

Verbatim quote confirmed on page (attributed to Evans, DDD):

> "By using the model-based language pervasively and not being satisfied until it flows, we approach a
> model that is complete and comprehensible, made up of simple elements that combine to express complex
> ideas... Domain experts should object to terms or structures that are awkward or inadequate to convey
> domain understanding; developers should watch for ambiguity or inconsistency that will trip up design."

Additional quote from Evans (via Khalil Stemmler article, URL: https://khalilstemmler.com/articles/typescript-domain-driven-design/intention-revealing-interfaces/):

> "If a developer must consider the implementation of a component in order to use it, the value of
> encapsulation is lost." — Evans, DDD

---

## Source 5 — GitHub Issue anthropics/claude-code #42796

URL: https://github.com/anthropics/claude-code/issues/42796

Title: "[MODEL] Claude Code is unusable for complex engineering tasks with the Feb updates"

Verbatim quote confirmed on page:

> "After thinking was reduced, convention adherence degraded measurably:
>
> * Abbreviated variable names (buf, len, cnt) reappeared despite explicit rules against them
> * Cleanup patterns (if-chain instead of goto) were violated
> * Comments about removed code were left in place
> * Temporal references ('Phase 2', 'will be completed later') appeared in code despite being
>   explicitly banned"

> "These violations are not the model being unaware of the conventions — the conventions are in its
> context window. They are the model not having the thinking budget to check each edit against the
> conventions before producing it."

---

## Source 6 — GitHub Issue anthropics/claude-code #4954

URL: https://github.com/anthropics/claude-code/issues/4954

Title: "Claude defaults to training data patterns instead of following CLAUDE.md project guidelines"

Issue documents: Claude generated Sass-style BEM syntax when CLAUDE.md required modern CSS nesting.
Root cause identified in issue: "Claude pattern-matched to Sass/SCSS examples (more prevalent in training
data) instead of following the documented modern CSS nesting requirements."

Status: Closed as duplicate of #2901.

---

## Source 7 — GitHub Issue anthropics/claude-code #21119

URL: https://github.com/anthropics/claude-code/issues/21119

Title: "Bug: Claude repeatedly ignores CLAUDE.md instructions in favor of training data patterns"

Key hypothesis from issue:

> "training bias is somewhat addressable by manipulating context. The correct context can prune
> undesirable paths to undesirable patterns."

CLAUDE.md-weight quote — re-fetched and confirmed verbatim 2026-06-19 (corrected from an earlier
paraphrase that had been mislabeled as verbatim):

> "The CLAUDE.md instructions ARE in my context, but they don't seem to have sufficient weight to
> override trained patterns. Reading "ALWAYS use git-commit-manager" doesn't prevent me from typing
> `git commit` when that's the pattern I've seen thousands of times in training."
