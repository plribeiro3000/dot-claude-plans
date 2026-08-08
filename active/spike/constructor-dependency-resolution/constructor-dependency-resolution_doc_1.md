# Auxiliary — Verbatim excerpts from primary sources

Collected during research for `SPIKE.md` in this directory. Each excerpt below was
fetched directly from the cited URL and re-confirmed by a second fetch (self-check
per the citation-discipline rules). Quotes are reproduced exactly as returned by the
fetch tool; no paraphrasing.

## 1. Miško Hevery, "Constructor does Real Work" — full "new Keyword" section

Source: https://raw.githubusercontent.com/mhevery/guide-to-testable-code/master/flaw-constructor-does-work.md

Section heading: `Problem: "new" Keyword in the Constructor or at Field Declaration`

Full section text (verbatim, tables/code samples omitted for brevity — see original
for the `House`/`Kitchen`/`Bedroom` before/after example):

> This example mixes object graph creation with logic. In tests we often want to
> create a different object graph than in production. Usually it is a smaller graph
> with some objects replaced with test-doubles. By leaving the new operators inline
> we will never be able to create a graph of objects for testing.
>
> - Flaw: inline object instantiation where fields are declared has the same
>   problems that work in the constructor has.
> - Flaw: this may be easy to instantiate but if `Kitchen` represents something
>   expensive such as file/database access it is not very testable since we could
>   never replace the `Kitchen` or `Bedroom` with a test-double.
> - Flaw: Your design is more brittle, because you can never polymorphically
>   replace the behavior of the kitchen or bedroom in the `House`.
>
> If the `Kitchen` is a value object such as: Linked List, Map, User, Email
> Address, etc., then we can create them inline as long as the value objects do not
> reference service objects. Service objects are the type most likely that need to
> be replaced with test-doubles, so you never want to lock them in with direct
> instantiation or instantiation via static method calls.

Elsewhere in the same document (Warning Signs list, already cited in
`~/.claude/docs/NO-CONSTRUCTOR-WORK.md`):

> "Anything more than field assignment in constructors"
> "Control flow (conditional or looping logic) in a constructor"

And the testability-cost framing:

> "It all comes down to how hard or easy it is to construct the class in isolation
> or with test-double collaborators. If it's hard, you're doing too much work in
> the constructor!"

## 2. Miško Hevery, "Digging into Collaborators" — full constructor-relevant text

Source: https://raw.githubusercontent.com/mhevery/guide-to-testable-code/master/flaw-digging-into-colaborators.md

Warning Signs (verbatim):

> Objects are passed in but never used directly (only used to get access to other
> objects)
> Law of Demeter violation: method call chain walks an object graph with more than
> one dot (`.`)
> Suspicious names: context, environment, principal, container, or manager

Constructor-specific sentences (verbatim):

> "Instead of looking for things, simply ask for the objects you need in the
> constructor or method parameters."
>
> "Instead of asking other objects to get your collaborators, declare
> collaborators as dependencies in the parameters to the method or constructor."

Closing recommendation (verbatim):

> "The way to fix code using context objects is to replace them with the specific
> objects that are needed. This will expose true dependencies, and may help you
> discover how to decompose objects further to make an even better design."

Example of the flagged shape (verbatim code, egregious end of the spectrum):

```java
getUserManager().getUser(123).getProfile().isAdmin()
// this is egregiously bad
```

and a milder example from the same document:

```java
client.getAuthenticator().authenticate(cookie);
```

## 3. Framework Design Guidelines (Cwalina & Abrams) — full constructor rules relevant to this question

Source: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/constructor
(Microsoft's own note: "reprinted by permission... 2nd Edition... published in
2008... Some of the information on this page may be out-of-date.")

> "✔️ CONSIDER using a static factory method instead of a constructor if the
> semantics of the desired operation do not map directly to the construction of a
> new instance, or if following the constructor design guidelines feels unnatural."
>
> "✔️ DO minimal work in the constructor. Constructors should not do much work
> other than capture the constructor parameters. The cost of any other processing
> should be delayed until required."
>
> "✔️ DO throw exceptions from instance constructors, if appropriate."
>
> "❌ AVOID calling virtual members on an object inside its constructor. Calling a
> virtual member will cause the most derived override to be called, even if the
> constructor of the most derived type has not been fully run yet."

Note: this last guideline ("DO throw exceptions... if appropriate") is in direct
tension with 4Shark's own Strategy 2 in `NO-CONSTRUCTOR-WORK.md` ("validation is
not the constructor's job"). It is reported here for completeness — it does not by
itself answer the engineer's complexity-threshold question, but shows the source
4Shark already leans on is not uniformly aligned with 4Shark's hard line either.

## 4. Yegor Bugayenko, "Constructors Must Be Code-Free" — re-confirmed, no exception found

Source: https://www.yegor256.com/2015/05/07/ctors-must-be-code-free.html

> "Let me reiterate that the only allowed statement inside a constructor is an
> assignment."
>
> "My point is that having any computations done inside a constructor is a bad
> practice and must be avoided because they are side effects and are not requested
> by the object owner."

A second, independent fetch targeted specifically at finding an exception,
complexity threshold, or distinction between "assignment" and "resolution"
returned: no such text exists in the article. The article's own conclusion states
the rule as absolute, with no complexity carve-out of any kind.

## 5. Martin Fowler, "Inversion of Control Containers and the Dependency Injection pattern"

Source: https://www.martinfowler.com/articles/injection.html

> "With service locator the application class asks for it explicitly by a message
> to the locator. With injection there is no explicit request, the service appears
> in the application class - hence the inversion of control."
>
> "The key difference is that with a Service Locator every user of a service has a
> dependency to the locator."
>
> "My long running default with objects is as much as possible, to create valid
> objects at construction time."
>
> "My preference is to start with constructor injection, but be ready to switch to
> setter injection as soon as the problems I've outlined above start to become a
> problem."

## 6. Giorgio Sironi, "When to inject: the distinction between newables and injectables" (secondary source describing Hevery's terminology)

Source: https://www.giorgiosironi.com/2009/07/when-to-inject-distinction-between.html

> "Entities are newables, Services are injectable (this is Misko Hevery
> terminology)."
>
> "Entities should be create with new operator every time you need them, while
> Services should be created by a factory or a dependency injection container."
>
> "Services depends on entities, while the opposite should not happen."
>
> "Entities are stateful; their job is to maintain their state and to be saved
> (and not saving itself) in some place or in memory. Services are stateless: you
> can instance a MailService many times, but it is always the same service for the
> end-user."

**Caveat**: Hevery's own primary post ("To 'new' or not to 'new'...",
testing.googleblog.com, 2008-10-03) could not be fetched directly — the tool
returned only page chrome/comments, not the article body — and the Wayback Machine
is unreachable from this environment. The "newable/injectable" terminology is
therefore attributed to Hevery only through Sironi's account, which is itself a
verified, directly-quoted secondary source. Treat the Hevery attribution as
reported-by-Sironi, not independently confirmed against Hevery's primary text.

## 7. Ben Nadel, "Creating Service Objects And Value Objects In A Dependency Injection (DI) Framework"

Source: https://www.bennadel.com/blog/2377-creating-service-objects-and-value-objects-in-a-dependency-injection-di-framework.htm

> "A Service object can ask for other Service objects in its constructor."
>
> "A Service object can never ask for a Value object in its constructor. This is
> because the dependency injection (DI) framework will not know how to create the
> required Value object."
>
> "A Value object can ask for other Value objects in its constructor."
>
> "A Value object can never ask for a Service object in its constructor."

This is one blogger's stated convention for working with a specific DI framework
(the post is framework-specific, not a general textbook or widely-cited source) —
reported here as a data point, not as established community consensus on its own.

## 8. Law of Demeter — one-dot heuristic

Source: https://en.wikipedia.org/wiki/Law_of_Demeter

> "a method `m` of an object `a` may only invoke the methods of the following
> kinds of objects: `a` itself; `m`'s parameters; any objects instantiated within
> `m`; `a`'s attributes; global variables accessible by `a`"
>
> "the law can be stated simply as 'use only one dot'. That is, the code
> `a.m().n()` breaks the law where `a.m()` does not."

## 9 & 10. Service Locator anti-pattern debate (tangential — general DI discourse, not constructor-specific)

Source: https://blog.ploeh.dk/2010/02/03/ServiceLocatorisanAnti-Pattern/ (Mark Seemann)

> "the problem with Service Locator is that it hides a class' dependencies,
> causing run-time errors instead of compile-time errors"

Source: https://www.jimmybogard.com/service-locator-is-not-an-anti-pattern/ (Jimmy Bogard)

> "if you use ASP.NET Core, you've likely already ran into these scenarios, where
> you want to use a scoped service like `DbContext` inside a singleton (filters,
> hosted services, etc.). In these cases, you likely have no other option but to
> use service location."
>
> "usage a pattern in certain scenarios can be advantageous/required or it might
> not be, but it really depends on the scenario."
