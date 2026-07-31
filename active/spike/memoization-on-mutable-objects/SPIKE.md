# SPIKE — Memoization on mutable objects, and the hidden method-local cache

**Status:** research done, doc not yet written
**Trigger:** review of `Incentive#referenced_identifiers` during item 4 of the Dentaku AST migration (`app`, branch `feature/variable-identification`, unmerged)
**Question:** what are the established names for (a) the shape we rejected, (b) the shape we chose, and (c) the rule that decides between them?

## The concrete case that started this

`Incentive#update_variables` needs the set of identifiers referenced by all of the incentive's rules, and consults it once per candidate variable — four branches, a loop each.

The first revision computed it once into a method-local:

```ruby
  def update_variables
    incentive_variables.delete_all
    identifiers = referenced_identifiers
    # ... four branches, each: if identifiers.include?(variable.key)
```

The engineer rejected the local with a specific argument: **within the method the rules do not change, so the local is memoization — just scoped to the method and with no stated rule.** Either the object memoizes and owns the invalidation question, or it does not memoize and the call is repeated at its real cost. Choosing per-snippet by whichever is cheapest there is what fails to become a pattern.

The revision that shipped drops the local and repeats `referenced_identifiers` in each branch.

## Finding 1 — Memoization is only sound for referentially transparent expressions

Memoization caches a result keyed by inputs. That substitution is valid exactly when the expression can be replaced by its value without changing program behaviour — the property called **referential transparency**, which follows from a function being **pure** (same inputs → same result, no side effects).

This is the rule that decides the case. `Formula#referenced_identifiers` is referentially transparent *for the life of the object* because a `Formula` is immutable: its `text` is assigned in the constructor and never changes, so tokenizing it always yields the same identifiers. `Incentive#referenced_identifiers` is not: it derives from `rules`, a mutable `has_many`, so the same receiver can legitimately answer differently at two moments in its life.

**Verification:** claim assembled from search-result summaries only; individual sources NOT fetched. Treat the *attribution* as UNVERIFIED and the *reasoning* as ours. The concept names (referential transparency, purity) are standard and not in dispute; what is unverified is which source phrases it this way.

## Finding 2 — Memoizing derived state IS caching, and inherits cache invalidation

thoughtbot's "Ruby Memoization and Alternatives" names the shape directly:

> "Saving derived state to an instance variable **is a form of caching** and comes with all the associated gotchas (cache invalidation!)."

and prices it:

> "Caching has some upfront costs you always pay: extra complexity and cache invalidation."

with the condition under which the price is worth paying:

> "For expensive operations that get called multiple times, the benefit of only doing the work once (or not doing it at all in a lazy method) may be worth the cost."

**Verification:** URL fetched — https://thoughtbot.com/blog/ruby-memoization-and-alternatives · Verbatim quotes checked · Substrings confirmed in the fetched page.

## Finding 3 — The same source argues *against* memoization as the default, on our exact grounds

Two lines land on the decision we made:

> "Usually it's OK to do the same cheap operation more than once!"

> "Most common uses of memoization in Ruby are premature optimization."

This is the published position matching the engineer's: repeating a cheap call is the honest default, and memoization is the exception that must earn itself.

**Verification:** URL fetched — https://thoughtbot.com/blog/ruby-memoization-and-alternatives · Verbatim quotes checked · Substrings confirmed in the fetched page.

## Finding 4 — Why repeating the call is genuinely cheap here (measured against the code, not assumed)

The repeated call does **not** re-tokenize. Two memoizations already sit on the path, both on immutable state:

```ruby
# app/models/rule.rb:32-36 — returns the same Formula while the source text is unchanged
  def formula
    return @formula if @formula.present? && @formula.text == value

    @formula = Formula.new(value)
  end

# app/models/formula.rb — memoizes the tokenizer result on an immutable object
  def referenced_identifiers
    @referenced_identifiers ||= Dentaku::Tokenizer.new.tokenize(text).select { |token| token.is?(:identifier) }.map(&:value).uniq
  end
```

So a repeated `incentive.referenced_identifiers` redoes only `flat_map` + `downcase` + `uniq` over arrays that already exist — no Dentaku, no database (the `rules` association is loaded by the time the `after_save` callback runs).

**Verification:** read from the working tree at `app/models/rule.rb` and `app/models/formula.rb`; quotes are the file contents.

## Finding 5 — `Rule#formula` is the guarded-memoization shape, and it is the third option

`Rule` is mutable (its `value` changes), so it cannot use a bare `||=`. It memoizes anyway, with an explicit invalidation predicate comparing the cached object's source against the current one. That is the shape any mutable object must adopt if it wants the cache — and its cost is visible: the guard must be written, and it must compare something cheap enough to be worth it.

For `Incentive` the guard would have to compare the collection of rule values, which is more code than the line the memoization would save. That asymmetry — not taste — is why the same class of object made opposite choices in the same codebase.

**Verification:** read from the working tree at `app/models/rule.rb:32-36`.

## What has NO confirmed name

I did not find, in this round, an established name for **"a method-local variable used as a scoped memoization"** — the specific shape the engineer objected to. The nearest neighbours are *common subexpression elimination* (a compiler optimization, not a hand-written design choice) and generic *caching*. **Do not assert a name for this in the doc.** Describe the shape instead, and state the rule it violates: the cache exists but no invalidation policy was ever stated, so the pattern cannot be applied consistently anywhere else.

## The rule these findings support

Memoize only where the memoized expression is referentially transparent for the receiver's whole life — in practice, on an **immutable object**. On a mutable object, either pay the call each time (the default, per Finding 3) or memoize with an **explicit invalidation guard** whose cost you accept (Finding 5). Never introduce a cache with no stated invalidation policy, including a method-local that exists only to avoid a repeat call, because it decides the trade-off invisibly and per-snippet rather than as a pattern.

## Open

- The name gap above — worth one more search round before the doc is written, targeting compiler/refactoring literature.
- Findings 1's attribution needs a fetched source, or the doc should state the concepts without attributing them.
- Whether the rule belongs in a new `MEMOIZATION.md` or as a section of `CODE-PATTERN-DISCIPLINE.md` — the engineer asked for new documentation, so a new file is the default, with a summary section added to `CLAUDE.md` per the Documentation Loading Model.
