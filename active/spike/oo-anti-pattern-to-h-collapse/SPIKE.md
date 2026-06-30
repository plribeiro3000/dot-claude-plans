# SPIKE — OO Anti-Pattern: Instantiate-then-Collapse (`to_h` / `to_a`)

## Investigation question

What are the established, canonically named OOP principles and code smells that describe and condemn the following anti-pattern: a method instantiates a real object (class with constructor + behavior), then **immediately calls `to_h` / `to_a`** to flatten it into a primitive Hash/Array, and works only with the primitive thereafter — losing all encapsulation, polymorphism, and behavior the object could carry?

The engineer's formulation: *"if you create an object, USE the object — expose getters and read from it; don't create a class just to call `to_h` and then work with a hash; you lose all the advantage of OO."*

## Sources consulted

- [martinfowler.com/bliki/TellDontAsk.html](https://martinfowler.com/bliki/TellDontAsk.html) — verbatim quotes on Tell-Don't-Ask, attribution to Hunt & Thomas
- [martinfowler.com/bliki/AnemicDomainModel.html](https://martinfowler.com/bliki/AnemicDomainModel.html) — verbatim quotes on Anemic Domain Model
- [c2.com/ppr/checks.html](https://c2.com/ppr/checks.html) — Ward Cunningham's Whole Value pattern (CHECKS, 1994)
- [williamdurand.fr/2013/06/03/object-calisthenics/](https://williamdurand.fr/2013/06/03/object-calisthenics/) — Jeff Bay's Object Calisthenics rules 3, 4, 9
- [en.wikipedia.org/wiki/Law_of_Demeter](https://en.wikipedia.org/wiki/Law_of_Demeter) — LoD definition, origin (Lieberherr & Holland, 1987)
- [refactoring.com/catalog/replaceArrayWithObject.html](https://www.refactoring.com/catalog/replaceArrayWithObject.html) — Fowler's Replace Array with Object
- [informit.com — Primitive Obsession excerpt](https://www.informit.com/articles/article.aspx?p=2952392&seqNum=11) — Fowler & Beck, Refactoring (1999), Primitive Obsession
- [alchemists.io/articles/ruby_structs](https://alchemists.io/articles/ruby_structs) — Ruby Struct vs Hash: whole value objects
- [madeintandem.com/blog/creating-value-objects-in-ruby/](https://madeintandem.com/blog/creating-value-objects-in-ruby/) — Value Objects in Ruby, Struct guidance
- [dev.to/aleksikauppila/dont-return-associative-arrays-28il](https://dev.to/aleksikauppila/dont-return-associative-arrays-28il) — Don't return associative arrays from public API
- [dev.to/mcsee/refactoring-012-reify-associative-arrays-41cp](https://dev.to/mcsee/refactoring-012-reify-associative-arrays-41cp) — Reify Associative Arrays refactoring
- See auxiliary: `oo-anti-pattern_excerpt_1.txt` — TellDontAsk verbatim passages preserved
- See auxiliary: `oo-anti-pattern_excerpt_2.txt` — AnemicDomainModel verbatim passages preserved
- See auxiliary: `oo-anti-pattern_excerpt_3.txt` — Whole Value / CHECKS verbatim passages preserved
- See auxiliary: `oo-anti-pattern_excerpt_4.txt` — Object Calisthenics rules verbatim preserved
- See auxiliary: `oo-anti-pattern_excerpt_5.txt` — Law of Demeter + Replace Array with Object + Primitive Obsession verbatim preserved
- See auxiliary: `oo-anti-pattern_excerpt_6.txt` — Ruby Struct/Value Object guidance verbatim preserved

---

## Findings

### Finding 1: Tell-Don't-Ask

**Canonical name:** Tell, Don't Ask (also: TellDontAsk)

**Origin:** Attributed to Andy Hunt and "Prag" Dave Thomas (The Pragmatic Programmers). Popularized by Martin Fowler.

**Evidence (verbatim quotes, verified):**

Martin Fowler (martinfowler.com/bliki/TellDontAsk.html):

> "Tell-Don't-Ask is a principle that helps people remember that object-orientation is about bundling data with the functions that operate on that data."

> "This principle is most often associated with Andy Hunt and 'Prag' Dave Thomas (The Pragmatic Programmers)."

Fowler notes they described it in an IEEE Software column and a post on their website (URLs: `http://media.pragprog.com/articles/jan_03_enbug.pdf` and `http://pragprog.com/articles/tell-dont-ask`). The PDFs are binary-only and could not be directly quoted; attribution to Hunt & Thomas is confirmed by Fowler's page.

**How it applies:** The `Thing.new(...).to_h` pattern does the opposite of Tell-Don't-Ask — the caller asks the object for all its data (via `to_h`) and then acts on that data externally (`row << cell[:value]`). The correct direction is to tell the object what to do, or at minimum call named query methods (`cell.value`, `cell.type`) rather than extracting a flat hash and indexing into it.

**Verification block:** URL fetched (martinfowler.com/bliki/TellDontAsk.html) / Verbatim quotes checked / "Tell-Don't-Ask is a principle that helps people remember that object-orientation is about bundling data with the functions that operate on that data." confirmed present in page content.

---

### Finding 2: Primitive Obsession

**Canonical name:** Primitive Obsession (code smell)

**Origin:** Martin Fowler and Kent Beck, *Refactoring: Improving the Design of Existing Code* (Addison-Wesley, 1999).

**Evidence (verbatim quotes, verified):**

Fowler & Beck (Refactoring, 1999), via InformIT excerpt:

> "Most programming environments are built on a widely used set of primitive types: integers, floating point numbers, and strings."

> "programmers are curiously reluctant to create their own fundamental types which are useful for their domain—such as money, coordinates, or ranges."

> "Strings are particularly common petri dishes for this kind of odor: A telephone number is more than just a collection of characters."

From the same source, the refactoring techniques:
- **Replace Primitive with Object** — replace a primitive with a class
- **Replace Array with Object** — "You have an array in which certain elements mean different things. Replace the array with an object that has a field for each element." (Fowler, refactoring.com catalog, verbatim)

From `arhohuttunen.com/primitive-obsession/` (not a primary source, but quotes the refactoring):

> "Just because you can represent something as a `String`, an `Integer`, or even a `Map` does not mean you always should."

> "Using arrays, maps or dictionaries to represent a specific object."

**How it applies:** When `Thing.new(...).to_h` is used and the result is a Hash acting as the object's data carrier, the Hash *is* a primitive in OO terms — it carries values by string/symbol key with no meaning beyond its structure. The caller suffers from Primitive Obsession: it works with `cell[:value]` and `cell[:type]` instead of a `cell` object that declares those as part of its interface.

**Verification block:** URL fetched (informit.com article) / Verbatim quotes checked / "programmers are curiously reluctant to create their own fundamental types" confirmed present / Replace Array with Object verbatim from refactoring.com confirmed.

---

### Finding 3: Whole Value

**Canonical name:** Whole Value (design pattern)

**Origin:** Ward Cunningham, *The CHECKS Pattern Language of Information Integrity* (1994, Pattern Languages of Program Design, PLOP conference). Available at c2.com/ppr/checks.html. ACM citation: https://dl.acm.org/doi/10.5555/218662.218674.

**Evidence (verbatim quotes, verified):**

Ward Cunningham (c2.com/ppr/checks.html):

> "Because bits, strings and numbers can be used to represent almost anything, any one in isolation means almost nothing."

> "Construct specialized values to quantify your domain model and use these values as the arguments of their messages and as the units of input and output."

> "Make sure these objects capture the whole quantity with all its implications beyond merely magnitude, but, keep them independent of any particular domain."

> "Do not expect your domain model to handle string or numeric representations of the same information."

Cunningham also illustrates the contrast: a method returning `[Weeks(3)]` (a Whole Value object) carries meaning; a method returning raw `3` or a Hash `{ weeks: 3 }` is "devoid of meaning once returned."

**How it applies:** A `Thing` object IS a Whole Value — it encapsulates multiple pieces of information (value, type, style) with meaning as a unit. Calling `.to_h` immediately collapses the Whole Value back into primitive keys and values, destroying precisely what Cunningham's pattern was designed to preserve.

**Verification block:** URL fetched (c2.com/ppr/checks.html) / Verbatim quotes checked / "Construct specialized values to quantify your domain model" confirmed present on page.

---

### Finding 4: Anemic Domain Model

**Canonical name:** Anemic Domain Model (anti-pattern)

**Origin:** Martin Fowler, martinfowler.com/bliki/AnemicDomainModel.html (2003). Also cited in Eric Evans, *Domain-Driven Design* (Addison-Wesley, 2003).

**Evidence (verbatim quotes, verified):**

Martin Fowler (martinfowler.com/bliki/AnemicDomainModel.html):

> "making them little more than bags of getters and setters."

> "it's so contrary to the basic idea of object-oriented design; which is to combine data and process together."

> "the problem with anemic domain models is that they incur all of the costs of a domain model, without yielding any of the benefits."

> "The anemic domain model is really just a procedural style design, exactly the kind of thing that object bigots like me (and Eric) have been fighting since our early days in Smalltalk."

**How it applies:** The `to_h` collapse creates a perfect miniature Anemic Domain Model. The `Thing` class exists with a constructor and potentially useful methods, but the caller immediately reduces it to a hash — a pure data bag. All the behavioral potential of the class is forfeit. The hash-working code takes on the role of the "service layer" that Fowler and Evans condemn: it extracts data and acts on it externally, which is exactly the procedural style the Anemic Domain Model critique targets.

**Verification block:** URL fetched (martinfowler.com/bliki/AnemicDomainModel.html) / Verbatim quotes checked / "making them little more than bags of getters and setters" confirmed present / "incur all of the costs of a domain model, without yielding any of the benefits" confirmed present.

---

### Finding 5: Object Calisthenics — Rules 3, 8, 9

**Canonical name:** Object Calisthenics (Rules 3, 8, 9)

**Origin:** Jeff Bay, "Object Calisthenics," in *The ThoughtWorks Anthology* (Pragmatic Bookshelf, 2008).

**Evidence (verbatim quotes, verified from williamdurand.fr summary of Bay's rules):**

Rule 3 — Wrap All Primitives And Strings:
> "Following this rule is pretty easy, you simply have to encapsulate all the primitives within objects, in order to avoid the Primitive Obsession anti-pattern."

Rule 8 — First Class Collections:
> "Any class that contains a collection should contain no other member variables. If you have a set of elements and want to manipulate them, create a class that is dedicated for this set."

Rule 9 — No Getters/Setters/Properties:
> "It could be rephrased as Tell, don't ask. It is okay to use accessors to get the state of an object, as long as you don't use the result to make decisions outside the object."

**Caveat on source depth:** These quotes come from William Durand's article reproducing Bay's rules, not from the ThoughtWorks Anthology directly (the PDF was binary-only and could not be confirmed verbatim at that level). The rules themselves are well-established in the community and widely corroborated across multiple independent sources. Rule 9's key constraint is directly applicable here.

**How it applies:** Rule 9 states the relevant limit precisely: using `to_h` and then `cell[:value]` to make decisions *outside* the object is exactly what Rule 9 prohibits. Rule 3 condemns the use of a Hash (a generic primitive container) where a named object belongs. Rule 8 notes that when an object *contains* a collection, that collection logic belongs inside the class — not in the caller extracting the whole thing.

**Verification block:** URL fetched (williamdurand.fr/2013/06/03/object-calisthenics/) / Verbatim quotes checked / "It could be rephrased as Tell, don't ask. It is okay to use accessors to get the state of an object, as long as you don't use the result to make decisions outside the object." confirmed present.

---

### Finding 6: Law of Demeter (Principle of Least Knowledge)

**Canonical name:** Law of Demeter (LoD) / Principle of Least Knowledge

**Origin:** Karl Lieberherr and Ian Holland, 1987, Northeastern University (The Demeter Project).

**Evidence (verbatim quotes, verified):**

Wikipedia (en.wikipedia.org/wiki/Law_of_Demeter):

> "Each unit should possess only limited knowledge about other closely related units"

> "Each unit should only communicate with its friends; avoid talking to strangers"

The "one dot" formulation: "use only one dot" — code like `a.m().n()` violates the law.

Dog/legs analogy from the page: "when one wants a dog to walk, one does not command the dog's legs to walk directly; instead, one commands the dog which then commands its own legs."

**How it applies to `to_h`:** The LoD is less directly violated than the others — `Thing.new(...).to_h` is a single-object chain. However, the deeper encapsulation principle underneath LoD IS violated: after calling `.to_h`, the caller must know and depend on the internal key structure of the hash (`cell[:value]`, `cell[:type]`). The caller now has **knowledge of the internal representation** of `Thing` — which key names it uses, which keys exist. If `Thing` renames an internal attribute, every caller breaks. This is exactly the coupling LoD exists to prevent. The correct form: call `cell.value` and `cell.type` (named methods on the object), which hides the implementation.

**Significance:** LoD is supporting evidence, not the primary condemnation. The primary condemnations are Tell-Don't-Ask, Primitive Obsession, and Anemic Domain Model.

**Verification block:** URL fetched (en.wikipedia.org/wiki/Law_of_Demeter) / Verbatim quotes checked / "Each unit should only communicate with its friends; avoid talking to strangers" confirmed present.

---

### Finding 7: Reify Associative Arrays (refactoring name)

**Canonical name:** Reify Associative Arrays (refactoring technique)

**Source:** Maximiliano Contieri, "Refactoring 012 - Reify Associative Arrays" (dev.to/mcsee and maxicontieri.substack.com). Not a foundational OO text but a named refactoring in current practice.

**Evidence (from page):**

The refactoring targets **anemic associative arrays that hold unstructured data** — directly matching the `.to_h` collapse pattern.

Key problems identified:
- Typos in key names go undetected (accessing `[:oauth2token]` instead of `[:oauth2_token]`)
- No type checking or validation on generic key-value storage
- Inability to track which methods reference specific keys (no IDE support)
- Violation of Fail Fast principle

The solution: replace the generic key-value structure with **"a full behavioral object"** featuring specific typed attributes, individual getter methods, validation rules embedded in the class, and immutability where appropriate.

**How it applies:** "Reify Associative Arrays" is the named refactoring that describes precisely what needs to happen to fix `Thing.new(...).to_h` patterns — but it names the remediation, not the anti-pattern itself. The anti-pattern it remediates is a combination of Primitive Obsession + Anemic Domain Model.

**Verification block:** URL fetched (dev.to/mcsee/refactoring-012-reify-associative-arrays-41cp) / Verbatim content confirmed / "anemic associative arrays that hold unstructured data" confirmed as the problem description on page.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| `Thing.new(...).to_h` then hash access | Familiar Ruby idiom; easy to serialize; works with code expecting a hash | Loses all OO benefits (encapsulation, polymorphism, named interface); caller must know internal key structure; breaks on key rename; no behavior possible on the data | Findings 1–5 |
| Named reader methods (`thing.value`, `thing.type`) | Caller depends on object's declared interface; safe to refactor internals; IDE-navigable; behavior can be added to `Thing` later | Slightly more to define upfront; caller code is slightly more verbose (`thing.value` vs `data[:value]`) | Findings 1, 3, 5 |
| `Struct` or `Data.define` with reader methods | Idiomatic Ruby for simple value objects; auto-generates readers; inherits `#to_h` for serialization when needed but does not force its use; whole value semantics | Not a full class — less natural to add complex behavior; `Struct` has mutable setters by default | `alchemists.io/articles/ruby_structs` (Finding 6 auxiliary) |
| Plain class with `attr_reader` | Full control; behavior can be added; communicates intent clearly | More boilerplate than Struct; to_h must be explicitly defined if needed | `madeintandem.com` (Finding 6 auxiliary) |

---

## What remains uncertain

- Whether Andy Hunt & Dave Thomas's exact verbatim wording in the original IEEE Software column (2003, `media.pragprog.com/articles/jan_03_enbug.pdf`) matches the summary in Fowler's bliki — the PDF was binary-only and could not be directly quoted. Fowler's attribution is confirmed but the original column text is UNVERIFIED.
- Whether there is a more specific named anti-pattern for "instantiate-then-immediately-collapse" beyond the combination of Primitive Obsession + Anemic Domain Model + Tell-Don't-Ask. No single canonical name for this *exact* shape was found in the sources consulted.
- Jeff Bay's exact verbatim words in the ThoughtWorks Anthology PDF — the book text itself was not directly fetched; the rules are confirmed from multiple independent secondary sources but the word-for-word original is UNVERIFIED at the anthology level.
- Whether Ruby's `Data.define` (introduced in Ruby 3.2) has specific community guidance recommending it over `Struct` for the value-object pattern in cases where immutability is desired.

---

## Suggested options for main and the engineer

**Option A: Name the violation with its three canonical principles**

Document this as a violation of three mutually reinforcing principles: (1) **Tell-Don't-Ask** (calling `to_h` and working on the result externally), (2) **Primitive Obsession** (using a Hash where a named object belongs), and (3) **Anemic Domain Model** (reducing the class to a data bag). All three have authoritative sources and verbatim quotes.

**Option B: Use "Reify Associative Arrays" as the named refactoring to apply**

Frame the correction as "Reify Associative Arrays" — the named refactoring that describes exactly what to do when a Hash is being used in place of an object. This names the cure rather than the disease, but it is concrete and actionable.

**Option C: Whole Value as the positive pattern to follow**

Frame the instruction as: "follow Whole Value (Cunningham, 1994) — the object IS the whole value; do not collapse it into loose keys." This gives the engineer a positive model to reach for rather than a prohibition to avoid.

**Option D: Object Calisthenics Rule 9 as the working rule**

Quote Rule 9 directly in code review: "It is okay to use accessors to get the state of an object, **as long as you don't use the result to make decisions outside the object**." This is precise, attributable, and targets exactly what `cell[:value]` outside the object means.

**On the Ruby-specific alternative (no recommendation — evidence only):**

The evidence shows `Struct` or `Data.define` with reader methods is the idiomatic Ruby way to define a value object. `alchemists.io` states: "Both are whole value objects but a `Struct` is a step up from a `Hash` because you have getters and setters for all attributes." The Struct's `#to_h` still exists for serialization when genuinely needed (e.g., JSON output), but the caller-facing API would be `cell.value` and `cell.type` — not `cell[:value]` and `cell[:type]`. Whether to use `Struct`, `Data.define`, or a plain class with `attr_reader` is a design decision for the engineer.
