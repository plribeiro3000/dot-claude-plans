# Delegation removal — app

## Outcome

Delivered by **app PR #5296** (`feature/disallow-delegate` → `develop`, merged). The `develop` branch reports **zero offenses** for both `Style/DisallowDelegate` and `Style/DisallowTernary` across 4807 files, and `.rubocop.yml` carries no entry for either cop — the clean result comes from converted code, not from an exclusion list.

**app PR #5302** (`feature/disallow-ternary`) was closed as superseded. It never had a scope of its own once #5296 shipped: #5296 is the PR that bumped `rubocop-fourshark` to 0.8.6, and that bump enabled `Style/DisallowTernary` alongside `Style/DisallowDelegate`, so #5296 had to convert every ternary for its own CI to pass. The 86 ternary lines #5302 would have removed are already gone from `develop`.

## The rule

The forbidden shape is a forwarder that **contributes nothing**: instead of the caller writing `a.b.method`, the caller writes `a.method`, and `a` holds a method whose whole body is `b.method`. Same message, no argument, no added context.

Three shapes are not that, and the cop does not flag them.

**The object supplies its own state.** `variable.format(value)` inside `AggregatedIndicator` passes the indicator's own `value` to the collaborator that knows how to format it. The caller cannot just navigate — it would have to rebuild the call as `aggregated_indicator.variable.format(aggregated_indicator.value)`, naming the receiver twice. Exempt in the gem via `composes_own_state?`.

**The forwarder is aimed at the object's own class.** `delegate :model, to: :class`. Exempt as of gem 0.8.5.

**The object publishes a higher-level API over a private collaborator.** This looked like it needed a third gem exemption. It did not — see below.

## How each group was resolved

**Composes own state.** `Metric#calculate` replaces `delegate :calculate, to: :adapter`; it takes only what the metric does not know (`commission_uuid`, `ends_at`, `plan`, `starts_at`, `user_id`) and supplies its own `client_id`, `comparator`, `installment`, `product_id`, `status_id`. `adapter` stays private and the call site in `app/workers/metric/consumer.rb` loses five arguments. `ApplicationSearchIndex.scroll` takes a `scroll_id` and builds the request with its own keep-alive, matching how `search` builds `{ index: index_name, body: ... }`.

**Native enumerize predicates.** `calendar.rb`, `indicator_document.rb`, `kpi_document.rb`, `payment_exportation_field.rb` and `rankifier_variable.rb` dropped delegates that republished a value object's predicates. Each gained explicit guard-then-navigate methods (`return false if frequency.blank?` then `frequency.daily?`) rather than `predicates: true` — `Enumerize::Value` resolves any `<value>?` through `Predicatable#method_missing`, so the option was never required for navigation-style calls.

**Remove Middle Man, no caller.** The five `attachment` delegates (`audit`, `campaign`, `document`, `statement_portable_batch`, `plan_statement_portable_batch`), plus `ranking_result.rb`, `indicator.rb` and `plan_statement.rb`. Deleting `PlanStatement`'s also un-shadows its own `belongs_to :owner`, which the delegate was overriding.

**Remove Middle Man, callers updated.** `commission.rb` and `partial_commission.rb` dropped seven forwarders to `plan`; six call sites navigate instead. `rankifier_variable.rb` dropped three forwarders and names the absent case once (`return 0 if rankifier.blank?`) instead of letting `allow_nil` swallow it per predicate.

**The `variable.rb` `data_type_object` group.** Eight macros forwarded `boolean?`, `date?`, `duration?`, `format`, `number?`, `output`, `percent?` and `string?` to a private collaborator, and this was the group with no honest code-level conversion — the caller cannot navigate to a private target, so Remove Middle Man had no destination. The resolution was a design change rather than a gem exemption: a new `app/types/data_type.rb` registers a Rails Attributes API type, so `attribute :data_type, DataType.new` makes `data_type` itself return an `ApplicationDataType` instance and the forwarders become methods that answer from the Variable's own attribute. A consequence to know when reading those models: `data_type` reads as an object, so `validates ... inclusion: { in: DEAL_TYPES }` against a list of class-name strings no longer matches, and `deal_variable.rb`, `indicator_variable.rb` and `easy_variable.rb` each carry a custom `validate :data_type_inclusion` with a one-line comment saying why.

## Gem state

`rubocop-fourshark` is at **0.8.6**, released and consumed by `develop`. No gem work is owed by this effort — both items that looked like gem changes (a DSL/facade exemption, and the `allow_nil` group) were closed by app-side design instead, which is the better outcome: an exemption keyed on target visibility would have handed every author an escape hatch (privatise the collaborator, keep the forwarder).

The gem's `main` carries commits past the 0.8.6 tag, including an `EmptyLineBeforeGuardClause` cop. Reaching the app needs a release cut, which is separate work.

## The unrelated gems the bump carried

#5296 bumped `rubocop-fourshark` without constraining resolution, so Bundler carried seven other gems forward. Six are the rubocop subtree and stay in development/test. `concurrent-ruby 1.3.7 → 1.3.8` is the exception: a transitive runtime dependency of `activesupport`, so it ships to production in a PR that was not about it.

That gem was audited and cleared. Version 1.3.8 was published 2026-07-19, so it is well past the 7-day quarantine — the age gate the quarantine enforces was never at risk here, only the review. Upstream, the release carries three commits and seven files; the library change is `NULL = ::Object.new.freeze` (making the sentinel Ractor-shareable) and a switch to `caller_locations` for exception backtraces on Ruby 3.4+. Locally, a recursive diff of the installed 1.3.7 against 1.3.8 shows five files differing and none added or removed, with the Ruby files matching the upstream change exactly. The `IO.popen` calls in `processor_counter.rb` predate this version — that file is byte-identical between the two.

One item cannot be verified from source: `concurrent_ruby.jar` differs between releases and is not tracked in the repository, so it is produced at packaging time and there is no source to compare it against. It loads only under `Concurrent.on_jruby?` (`utility/native_extension_loader.rb`), and the application runs MRI, so it is never required.

A bump made this way should be `bundle update --conservative <gem>`, which moves the named gem and only what it strictly requires.

## Changelog

Both refactors are recorded under `## [Unreleased]` as `Delegation style` and `Conditional expression style` (app PR #5344). The second entry exists because #5296 delivered the ternary conversion as well — the PR that was going to record it closed without merging.

## Process notes

Do not remove or rewrite anything the cop did not flag. Several corrections during this effort existed only because a method, a memoization, a visibility or a validation condition was changed on the agent's own initiative while the task was delegation removal.

Rewriting a `delegate` macro as a method with an identical body is not a conversion — it satisfies the linter, which only reads the macro, while leaving the responsibility exactly where it was.

An `Exclude:` list under `Style/DisallowDelegate` or `Style/DisallowTernary` is not an option. When the linter and the documentation disagree, the fix belongs in the gem or in the design.
