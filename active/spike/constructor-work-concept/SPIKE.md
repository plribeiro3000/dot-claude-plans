# SPIKE — The established concept for "a constructor must only construct"

## Investigation question

The engineer's position: a class constructor exists to construct the class. It receives only what is needed, stores it where it belongs, and stops. Business logic — and above all anything that *defines the class's output* — belongs in other methods, never in the constructor. Does the community name this practice, and under what name(s), so 4Shark can write the rule against an established concept instead of inventing one?

Trigger: a review diff where `initialize(reported_reason, reported_meta)` assigned `@reason` from an `if REPORTABLE_REASONS.include?(...)` and `@details` from a five-branch `case reported_reason` — i.e. the constructor computed the object's output.

## Sources consulted

- https://raw.githubusercontent.com/mhevery/guide-to-testable-code/master/flaw-constructor-does-work.md — names the flaw and lists mechanically checkable warning signs
- https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/constructor — the guideline in imperative form, from a vendor framework-design standard
- https://www.yegor256.com/2015/05/07/ctors-must-be-code-free.html — the strictest formulation (assignment only) and the argument about *when* computation should happen

Note on a fourth source: `http://misko.hevery.com/code-reviewers-guide/flaw-constructor-does-real-work/` is the original home of Finding 1 and is **DEAD** (`getaddrinfo ENOTFOUND misko.hevery.com`). The quotes below come from the author's own GitHub mirror, not from the dead domain — cite the mirror.

## Findings

### Finding 1: the flaw has a canonical name — "Constructor does Real Work"

**Evidence:** the document's title is *"Constructor does Real Work"*, and its Warning Signs list includes, verbatim:

- *"Anything more than field assignment in constructors"*
- *"Control flow (conditional or looping logic) in a constructor"*
- *"Object not fully initialized after the constructor finishes (watch out for `initialize` methods)"*
- *"`new` keyword in a constructor or at field declaration"*
- *"Static method calls in a constructor or at field declaration"*

On why it is a problem: *"Testing such constructors is difficult. To instantiate an object, the constructor must execute. And if that constructor does lots of work, you are forced to do that work when creating the object in tests."* And: *"When collaborator construction is mixed with initialization, it suggests that there is only one way to configure the class, which closes off reuse opportunities."*

**Source:** Miško Hevery, *Guide to Writing Testable Code* (originally Google), flaw #2 — https://raw.githubusercontent.com/mhevery/guide-to-testable-code/master/flaw-constructor-does-work.md

**Significance:** two of the warning signs match the trigger diff exactly and are *mechanically* checkable: control flow in a constructor, and anything beyond field assignment. This is the concept name to cite. Note the emphasis is **testability** — the argument is that construction forces the work to run — which is adjacent to, not identical to, the engineer's argument (that the constructor is the wrong *place* for logic regardless of tests).

**Verification:** URL fetched / Verbatim quote checked / Quote substrings confirmed in the fetched document body (flaw title, Warning Signs list, "Core Problems" section).

### Finding 2: the same rule exists as a vendor design guideline — "DO minimal work in the constructor"

**Evidence:** verbatim: *"✔️ DO minimal work in the constructor."* followed by *"Constructors should not do much work other than capture the constructor parameters. The cost of any other processing should be delayed until required."*

The same page also carries the escape hatch, verbatim: *"✔️ CONSIDER using a static factory method instead of a constructor if the semantics of the desired operation do not map directly to the construction of a new instance, or if following the constructor design guidelines feels unnatural."*

**Source:** *Framework Design Guidelines* (Cwalina & Abrams, Addison-Wesley), reprinted at https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/constructor

**Significance:** gives the rule an imperative, quotable form independent of testability, plus a named alternative for the case where construction genuinely needs computation (a factory method). Caveat for citation honesty: the page carries a Microsoft note that this content is reprinted from the **2nd edition (2008)** and *"Some of the information on this page may be out-of-date."*

**Verification:** URL fetched / Verbatim quote checked / Quote substrings confirmed in the page's guideline list ("DO minimal work in the constructor", "CONSIDER using a static factory method").

### Finding 3: the strictest formulation — "the only allowed statement inside a constructor is an assignment"

**Evidence:** verbatim: *"Let me reiterate that the only allowed statement inside a constructor is an assignment."* And on computation specifically: *"My point is that having **any** computations done inside a constructor is a bad practice and must be avoided because they are side effects and are not requested by the object owner."*

On *when* computation should happen: *"In imperative programming, we do all calculations right now and return fully ready results. In declarative programming, we are instead trying to delay calculations for as long as possible."* On the cost: *"It prevents composition of objects and makes them un-extensible."*

**Source:** Yegor Bugayenko, *Constructors Must Be Code-Free* — https://www.yegor256.com/2015/05/07/ctors-must-be-code-free.html

**Significance:** this is the finding that covers the engineer's specific complaint. Hevery and Microsoft argue from testability and cost-deferral; this one argues that a computation at construction time is a **side effect the caller did not request** — which is precisely what a constructor deriving the object's output does. It is also the only source that states the boundary as a hard line ("assignment only") rather than a soft "minimal".

**Verification:** URL fetched / Verbatim quote checked / Quote substrings confirmed in the article body.

## Trade-offs surfaced

| Naming choice for the 4Shark rule | Pros | Cons | Source |
|---|---|---|---|
| Cite it as **"Constructor does Real Work"** (Hevery's flaw) | An actual named flaw with a checkable warning-sign list; two signs match the trigger diff verbatim | Framed around testability and dependency injection, so the "logic belongs elsewhere" part is implied rather than stated | Finding 1 |
| Cite it as **"DO minimal work in the constructor"** (Framework Design Guidelines) | Imperative, quotable, vendor-standard; carries the factory-method alternative | "Minimal" is soft — it does not draw the line the engineer draws; the source is flagged as possibly out-of-date | Finding 2 |
| Cite it as **"code-free constructors"** (Bugayenko) | The hard line ("assignment only") and the exact argument about unrequested computation | A single practitioner's blog, not a standard or a canonical catalog | Finding 3 |
| Use all three, layered | The flaw NAME, the imperative RULE, and the hard LINE each come from the source that states them best | Longer "Why" section | Findings 1–3 |

## What remains uncertain

- **The derived-output variant has no distinct name that this spike could verify.** "The constructor computed the object's output eagerly" is covered by Finding 3's delay-calculations argument, but no source was found that names *that* specific shape (as distinct from constructor work in general). Per Citation Discipline, "the community does not name this practice" is the honest conclusion — do not invent one.
- **Whether the exception is a factory method or a plain second method** is not settled by the sources: Finding 2 names the static factory method; Findings 1 and 3 do not weigh in on the Ruby-idiomatic alternative.
- **Not researched**: LMAX's *"Why I Don't Do Work in Constructors"* appeared in search results and was NOT fetched, so it is not cited. Four verified findings were not needed once three converged.

## Suggested options for main and the engineer

- Option A: write the rule citing all three sources layered (flaw name from Hevery, imperative rule from Microsoft, hard line from Bugayenko).
- Option B: write the rule citing only Hevery's flaw name, and keep the "Why" short.
- Option C: state the hard line as 4Shark's own ("assignment only") and cite the three sources as corroboration rather than as the rule's origin.

(No recommendation — surfaced for the decision.)

---

> Written in the main session (not via `@agent-spike`) at the engineer's request to spike this before writing the rule. Every claim carries its source and a verbatim quote; the one place no source was found is recorded as uncertain rather than filled in.
