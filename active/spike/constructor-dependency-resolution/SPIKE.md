# SPIKE — Constructor Dependency Resolution: Grounding a Complexity-Based Middle Tier

## Investigation question

4Shark's `NO-CONSTRUCTOR-WORK.md` currently takes the hardest available line —
Bugayenko's "the only allowed statement inside a constructor is an assignment." The
engineer proposes relaxing this along a specific axis, stated verbatim (Portuguese,
preserved literally as an engineer quote):

> "O que não pode ter no constructor é lógica. [...] ele só pode ter a construção
> daquilo que ele precisa para trabalhar, com exceção daquilo que é muito complexo.
> Eu preciso ter um objeto tal, mas nesse objeto eu preciso chamar outro cara que
> tem, não sei o que. Às vezes é um negócio muito complexo e não recebe um
> inicializador por algum motivo que não tem como, cara. Aí ele não vai no
> constructor. Então, a regra é: inicialmente, é só quem chegou nos parâmetros,
> mas, se precisar de algo extra, que dá para pegar de forma simples dos dados que
> chegam ou de algum outro lugar. Pode ficar no constructor, mas se for muito
> complexo, não pode."

Restated in English as a three-tier rule: (1) assigning the received parameters is
always allowed; (2) resolving something extra the object needs, when it is *simple*
to reach from the arrived data or from somewhere else, is allowed in the
constructor; (3) when reaching it is *complex*, it must not be in the constructor.

The concrete case that motivated it: `Rule::Options#initialize(rule)` doing
`@company = rule.incentive.company`, after which every public method uses
`company`.

The question for this research: **does the software-engineering community name and
ground a complexity/cost-based middle tier of this shape** — and if not fully, which
parts of the engineer's three-tier rule are grounded by an existing source, which are
4Shark's own framing, and does any existing source actively argue against the
relaxation (specifically against the motivating example)?

## Sources consulted

- https://raw.githubusercontent.com/mhevery/guide-to-testable-code/master/flaw-constructor-does-work.md — Hevery's "Constructor does Real Work" flaw; contains an explicit Value Object exception not currently reflected in `NO-CONSTRUCTOR-WORK.md`. See auxiliary excerpt 1.
- https://raw.githubusercontent.com/mhevery/guide-to-testable-code/master/flaw-digging-into-colaborators.md — Hevery's "Digging into Collaborators" flaw; names the engineer's motivating shape directly and recommends the opposite fix. See auxiliary excerpt 2.
- https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/constructor — Framework Design Guidelines; "DO minimal work" cost framing, factory-method alternative, and (in tension with 4Shark's own Strategy 2) explicit endorsement of throwing from constructors. See auxiliary excerpt 3.
- https://www.yegor256.com/2015/05/07/ctors-must-be-code-free.html — Bugayenko; re-fetched specifically hunting for an exception or threshold — none found. See auxiliary excerpt 4.
- https://www.martinfowler.com/articles/injection.html — Fowler on Service Locator vs. Dependency Injection, and a stated preference for resolving objects fully at construction time. See auxiliary excerpt 5.
- https://www.giorgiosironi.com/2009/07/when-to-inject-distinction-between.html — secondary source attributing "newable"/"injectable" terminology to Hevery; Hevery's own primary post could not be independently fetched (see auxiliary excerpt 6 caveat).
- https://www.bennadel.com/blog/2377-creating-service-objects-and-value-objects-in-a-dependency-injection-di-framework.htm — one blogger's Service/Value object constructor convention for a specific DI framework. See auxiliary excerpt 7.
- https://en.wikipedia.org/wiki/Law_of_Demeter — formal LoD statement and the "one dot" heuristic, relevant to evaluating the two-hop `rule.incentive.company` chain in the motivating example. See auxiliary excerpt 8.
- https://blog.ploeh.dk/2010/02/03/ServiceLocatorisanAnti-Pattern/ and https://www.jimmybogard.com/service-locator-is-not-an-anti-pattern/ — tangential community disagreement on resolving a dependency at the point of use rather than receiving it; not constructor-specific. See auxiliary excerpts 9–10.
- See auxiliary: `constructor-dependency-resolution_doc_1.md` — full verbatim excerpts backing every Finding below, with second-fetch confirmation per the citation-discipline self-check rule.

Two URLs were attempted and could not be used to sustain any claim:
`https://testing.googleblog.com/2008/10/to-new-or-not-to-new.html` (Hevery's
primary "newable/injectable" post — the fetch returned only page chrome and reader
comments, not the article body) and `https://web.archive.org/...` (tool reports
this host is unreachable from this environment). Both are marked UNVERIFIED and are
not used to sustain any Finding on their own.

## Findings

### Finding 1: Hevery's own "Constructor does Real Work" doc contains an explicit exception — but it is TYPE-based (value object vs. service object), not complexity-based

**Evidence:**

```
If the `Kitchen` is a value object such as: Linked List, Map, User, Email
Address, etc., then we can create them inline as long as the value objects do not
reference service objects. Service objects are the type most likely that need to
be replaced with test-doubles, so you never want to lock them in with direct
instantiation or instantiation via static method calls.
```

**Source:** https://raw.githubusercontent.com/mhevery/guide-to-testable-code/master/flaw-constructor-does-work.md, section "Problem: `new` Keyword in the Constructor or at Field Declaration"

**Significance:** 4Shark's `NO-CONSTRUCTOR-WORK.md` cites this same document as
Source 1 ("Constructor does Real Work") and quotes its Warning Signs list, but does
not carry this exception forward — the 4Shark doc's stated position ("4Shark takes
the hard line... assignment only") is stricter than Hevery's own text. The
exception's axis is **what kind of object is being created** (a value object: no
identity concerns, no reference to service objects, trivial to construct) — not
**how hard it is to reach**. This means the exception, as Hevery states it, would
not automatically validate the engineer's "simple to reach" framing; it validates a
different, narrower thing: constructing (with `new`) an object of a low-behavior,
data-holding type.

**Verification:** URL fetched / Verbatim quote checked (re-fetched a second time
requesting the full section verbatim, confirmed byte-for-byte identical wording) /
Quote substring confirmed at the section titled `Problem: "new" Keyword in the
Constructor or at Field Declaration`, final paragraph.

### Finding 2: Hevery's "Digging into Collaborators" flaw names the engineer's exact motivating shape — and prescribes the opposite fix

**Evidence:**

```
Warning Signs:
Objects are passed in but never used directly (only used to get access to other
objects)
Law of Demeter violation: method call chain walks an object graph with more than
one dot (.)
```

```
Instead of looking for things, simply ask for the objects you need in the
constructor or method parameters.
```

```
The way to fix code using context objects is to replace them with the specific
objects that are needed. This will expose true dependencies, and may help you
discover how to decompose objects further to make an even better design.
```

**Source:** https://raw.githubusercontent.com/mhevery/guide-to-testable-code/master/flaw-digging-into-colaborators.md

**Significance:** `Rule::Options#initialize(rule)` deriving `@company =
rule.incentive.company` is structurally the pattern this flaw names: `rule` is
"passed in but never used directly" (only `rule.incentive.company` is used
downstream), and the chain has two dots, crossing this source's own "more than one
dot" line. Per this source, the prescribed fix is not "leave the resolution in the
constructor because it's simple" — it is to have the constructor **receive
`company` directly**, moving the navigation to whatever assembles the `Rule::Options`
instance (a factory, or the caller). This is a source directly on-point for the
concrete motivating example, and it argues against leaving the resolution in the
constructor at all, regardless of how "simple" the chain looks.

**Verification:** URL fetched / Verbatim quote checked (re-fetched specifically for
constructor-mentioning sentences, then again for the full Warning Signs and closing
recommendation) / Quote substrings confirmed in the Warning Signs list and the
closing "Instead of looking for things..." / "The way to fix..." paragraphs.

### Finding 3: Bugayenko's source draws no exception of any kind — confirmed on a second, targeted fetch

**Evidence:**

```
Let me reiterate that the only allowed statement inside a constructor is an
assignment.
```

```
My point is that having any computations done inside a constructor is a bad
practice and must be avoided because they are side effects and are not requested
by the object owner.
```

**Source:** https://www.yegor256.com/2015/05/07/ctors-must-be-code-free.html

**Significance:** This is the source 4Shark's current hard line is built on. A
targeted second fetch, asking specifically for any exception, complexity threshold,
or distinction between "assignment" and "resolution," returned nothing — the
article states its position as absolute with no carve-out. If 4Shark keeps this
source as the primary authority for the rule (as `NO-CONSTRUCTOR-WORK.md` currently
does — "4Shark takes the hard line... for Bugayenko's reason"), the engineer's
middle tier is a deviation from that authority's stated position, not an extension
of it.

**Verification:** URL fetched twice / Verbatim quote checked both times / Quote
substring confirmed in the article body, and the second fetch's negative result
(no exception text found anywhere in the document) is itself the evidence for this
Finding's second half.

### Finding 4: Framework Design Guidelines frames "minimal work" as a COST to defer, not a size threshold to permit

**Evidence:**

```
DO minimal work in the constructor. Constructors should not do much work other
than capture the constructor parameters. The cost of any other processing should
be delayed until required.
```

```
CONSIDER using a static factory method instead of a constructor if the semantics
of the desired operation do not map directly to the construction of a new
instance, or if following the constructor design guidelines feels unnatural.
```

**Source:** https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/constructor (Microsoft's own note: this page is a reprint of the 2008 2nd edition, flagged as possibly out of date)

**Significance:** "The cost of any other processing should be delayed" reads as a
deferral instruction (move it to a method, or a factory), not as "small costs are
fine, only large ones must move." This source does not state a complexity
threshold either — it is closer to Bugayenko's position than to the engineer's
three-tier framing, though softer in tone ("minimal", not "code-free"). The same
source's factory-method alternative is already 4Shark's Strategy 4 for the case
where construction genuinely needs computed input — which is one candidate answer
to the engineer's Tier 3 case (`não recebe um inicializador por algum motivo`):
move the resolution to a named factory class method, not leave it either in the
constructor or undone.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed
in the bulleted guideline list under "There are two kinds of constructors..."

### Finding 5: "Newable vs. Injectable" is a candidate TYPE-based (not complexity-based) vocabulary for the same underlying question — attribution to Hevery is secondary-sourced only

**Evidence:**

```
Entities are newables, Services are injectable (this is Misko Hevery
terminology).
```

```
Entities should be create with new operator every time you need them, while
Services should be created by a factory or a dependency injection container.
```

**Source:** https://www.giorgiosironi.com/2009/07/when-to-inject-distinction-between.html

**Significance:** If this terminology is accurately attributed (see caveat below),
it offers an established name for the same axis Finding 1 surfaces from Hevery's
own doc: some things (newables — entities, value objects) may be constructed
directly wherever needed, including inside a constructor; other things
(injectables — services) must always be passed in. Like Finding 1, this is a
type-based line, not a complexity-based one — "is `Company` a stateful
data-holding thing, or does it carry behavior/side effects the caller might want
to swap out (a service)?" is a different question from "is `rule.incentive.company`
easy or hard to reach?" A domain entity with persistence and business methods (the
likely shape of `Company` in 4Shark's codebase) sits ambiguously between Hevery's
own examples of "newable" (his list includes `User` alongside `LinkedList`,
`Map`, `EmailAddress`) and a behavior-bearing service.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed
in Sironi's post, attributed there to "Misko Hevery terminology." **Caveat**:
Hevery's own primary post (testing.googleblog.com, 2008-10-03, titled "To 'new' or
not to 'new'...") could not be independently fetched — the tool returned page
chrome and reader comments only, not the article body — and the Wayback Machine is
unreachable from this environment. This Finding rests on Sironi's secondary account
of Hevery's terminology, not on Hevery's primary text directly.

### Finding 6: Law of Demeter's "one dot" heuristic gives a mechanical (not complexity-judgment-based) line the motivating example crosses

**Evidence:**

```
a method m of an object a may only invoke the methods of the following kinds of
objects: a itself; m's parameters; any objects instantiated within m; a's
attributes; global variables accessible by a
```

```
the law can be stated simply as "use only one dot". That is, the code a.m().n()
breaks the law where a.m() does not.
```

**Source:** https://en.wikipedia.org/wiki/Law_of_Demeter

**Significance:** `rule.incentive.company` is a two-hop chain (`rule` →
`incentive` → `company`), which crosses the "one dot" heuristic this source states.
This is a different, more mechanical axis than "is it simple" — a chain can be
subjectively "simple to read" while still being two dots, and this heuristic would
flag it regardless. It corroborates Finding 2's classification of the motivating
example as a "Digging into Collaborators" case rather than a borderline-acceptable
simple lookup.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed
in the "Formal definition" and general-discussion sections of the article.

### Finding 7: The Service Locator anti-pattern debate is genuine community disagreement, but is not about constructors specifically

**Evidence:**

```
the problem with Service Locator is that it hides a class' dependencies, causing
run-time errors instead of compile-time errors
```
— Mark Seemann

```
if you use ASP.NET Core, you've likely already ran into these scenarios, where
you want to use a scoped service like DbContext inside a singleton (filters,
hosted services, etc.). In these cases, you likely have no other option but to
use service location.
```
— Jimmy Bogard

**Source:** https://blog.ploeh.dk/2010/02/03/ServiceLocatorisanAnti-Pattern/ and https://www.jimmybogard.com/service-locator-is-not-an-anti-pattern/

**Significance:** This shows the broader community is split on whether resolving a
dependency at the point of use (rather than always receiving it) is defensible —
but the debate is about DI-container service location (`container.Resolve<T>()`),
not about a constructor navigating an already-injected object graph
(`rule.incentive.company`). It is included as background trade-off material, not as
direct grounding for either side of the engineer's specific proposal.

**Verification:** URL fetched (both) / Verbatim quote checked (both) / Quote
substrings confirmed in each post's body text.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Keep the current hard line (assignment only, no exception) | Matches Bugayenko's stated position exactly, which is the reason 4Shark cites for taking the hard line; no judgment call needed at review time about what counts as "simple" | Diverges from Hevery's own stated Value Object exception, even though Hevery is cited as a source; every "simple" derivation (e.g. `@total = amount + tax`) still requires a full Strategy-1 method extraction | Findings 3, 1 |
| Add a type-based exception mirroring Hevery's Value Object carve-out (a value-shaped, non-service object may be assigned/derived inline) | Grounded directly in a source 4Shark already cites; narrower and more mechanically checkable than a subjective "is it simple" test (the object's type answers it) | Does not resolve the motivating example cleanly — Hevery's own "Digging into Collaborators" flaw would flag `rule.incentive.company` regardless of whether `Company` counts as a "value object", because the chain itself (not the target's type) is what's flagged; requires 4Shark to define what counts as a "value object" in a codebase whose domain objects are ActiveRecord-backed entities, not immutable DDD value objects | Findings 1, 2, 5 |
| Adopt the engineer's complexity/cost framing as 4Shark's own extension (not attributed to any cited source) | Matches the engineer's stated intuition and the motivating example's felt cost; keeps the rule's spirit (no meaningful business logic in a constructor) while permitting cheap derivations | No source in this research states a complexity threshold for constructor work — every source that comes close (Hevery's testability framing, FDG's "cost... should be delayed") treats cost as a reason to MOVE work out, not a reason to permit it in; "simple to reach" is not mechanically checkable the way a type-based rule is, and would need judgment at every code review | Findings 3, 4 |
| Route the motivating case through Strategy 4 (a named factory class method) already in `NO-CONSTRUCTOR-WORK.md` | Already documented, requires no new rule at all; directly matches FDG's own factory-method alternative and Hevery's "ask for the objects you need... move the responsibility of object finding to the factory" recommendation | Does not by itself validate ANY constructor-side resolution, however simple — it moves the decision entirely outside the constructor, which may be more machinery than the engineer intends for genuinely trivial cases | Findings 2, 4 |

## What remains uncertain

- No source found in this research states a complexity or cost *threshold* for
  constructor work — every source that discusses cost treats it as a signal to
  defer/extract, not as a boundary marking where inline work becomes acceptable.
  "The community does not name a complexity-based middle tier" is the most accurate
  summary this research can support; it is a valid conclusion, not a gap in the
  search.
- Whether `Company` (or an equivalent ActiveRecord-backed domain entity in
  4Shark's codebase) counts as a Hevery-style "value object" (Finding 1) or a
  "newable" (Finding 5) was not settled — Hevery's own value-object examples
  include `User`, a data-bearing object with identity, which blurs the line
  between his usage and the stricter DDD Value Object (no identity, immutable).
  This research did not read 4Shark's actual `Rule`, `Incentive`, or `Company`
  model code, so it cannot say whether `Company` in this codebase carries
  behavior that would classify it as a "service" under either framework.
- Whether the "newable/injectable" terminology (Finding 5) is accurately
  attributed to Hevery could not be independently confirmed — his primary source
  post was unreachable in this environment (see Finding 5's verification caveat).
- No established name was found for the engineer's exact three-tier shape
  (mandatory assignment / conditionally-allowed simple resolution / forbidden
  complex resolution) as a single, named concept. The two closest matches found
  are type-based (Findings 1 and 5), not complexity-based, and neither maps
  cleanly onto "simple to reach from the data that arrived."

## Suggested options for main and the engineer

- **Option A — Keep the current hard line**, unchanged, and route every "I need
  something extra" case through Strategy 4 (a named factory class method). This
  matches Bugayenko (the source 4Shark cites for taking the hard line) and Hevery's
  "Digging into Collaborators" recommendation exactly, at the cost of needing a
  factory method even for felt-trivial derivations.
- **Option B — Add a type-based exception** modeled on Hevery's own Value Object
  carve-out (Finding 1): a constructor may assign a value derived inline ONLY when
  the derived value is itself a value-object-shaped result (trivial to construct,
  state-focused, does not reference a service object) — leaving the complexity
  question aside and deciding instead by the TYPE of what is being produced. This
  would need 4Shark to define, in its own terms, what counts as a "value object" in
  an ActiveRecord-heavy codebase, since the motivating example's `Company` is
  likely not one under a strict DDD reading.
- **Option C — Adopt the engineer's complexity framing explicitly as a 4Shark
  extension**, documented as such (not attributed to Hevery, Bugayenko, or FDG,
  since none of them state this criterion) — accepting that "simple to reach" is a
  judgment call at review time rather than a mechanically checkable rule, the same
  way several other 4Shark rules already carry a documented judgment residue (e.g.
  § No Delegate's "would a reader of this class's interface expect it to answer
  this?" test).
- **Option D — Narrow the exception to navigation depth only**, using the Law of
  Demeter "one dot" heuristic (Finding 6) as the mechanical test instead of a
  subjective complexity judgment: a single-hop derivation (`@x = argument.y`) may
  stay in the constructor; anything crossing more than one dot (like the
  motivating `rule.incentive.company`) must not. This is mechanically checkable
  (unlike Option C) but is a narrower exception than the engineer described, and
  it would still flag the exact motivating example as disallowed — meaning
  `Rule::Options#initialize(rule)` would need to receive `company` directly rather
  than deriving it, per Finding 2's prescribed fix.

(No recommendation — the four options above surface the grounding each has and
each lacks; main and the engineer choose.)

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce
> uncertainty. Surfaces findings + options — does NOT recommend or pick; main and
> the engineer choose. Every claim cites its source (`file:line` + quote, or URL +
> quote); an uncitable claim is written as "Not found: <…>" instead. Large or
> structured evidence goes to auxiliary files
> (`constructor-dependency-resolution_{kind}_{n}.{ext}`) in the same directory,
> each referenced from this document by relative link. The `output-verifier` runs
> the seven structural checks after the write — including citation integrity and
> auxiliary-file integrity — and the `policy-verifier` checks convention
> conformance.
