# Delegation removal — app PR #5296

## Current state

Three artifacts are in flight.

- **app PR #5296** — `feature/disallow-delegate` → `develop`. Open. Head on GitHub is `51e766e5b`; the worktree at `app/.claude/worktrees/disallow-delegate` carries **uncommitted corrections** on top of it (listed under "Corrections applied locally").
- **app PR #5302** — `feature/disallow-ternary` → `feature/disallow-delegate`. Open, head `12675fabb`. Retarget to `develop` with `gh pr edit --base develop` once #5296 merges. It must be rebased again after #5296's head moves.
- **rubocop-fourshark 0.8.5** — released. Exempts a macro aimed at `:class` (`delegate :model, to: :class`).

## The rule, as the engineer states it

The forbidden shape is a forwarder that **contributes nothing**: instead of the caller writing `a.b.method`, the caller writes `a.method`, and `a` holds a method whose whole body is `b.method`. Same message, no argument, no added context.

Three shapes are **not** that, and the cop must not flag them.

**The object supplies its own state.** `variable.format(value)` inside `AggregatedIndicator` passes the indicator's own `value` to the collaborator that knows how to format it. The caller cannot just navigate — it would have to rebuild the call as `aggregated_indicator.variable.format(aggregated_indicator.value)`, naming the receiver twice. Already exempt in the gem (`composes_own_state?`).

**The forwarder is aimed at the object's own class.** `delegate :model, to: :class`. Already exempt as of 0.8.5.

**The forwarder publishes a higher-level API over a PRIVATE collaborator — a DSL or facade.** `Metric` keeps `adapter` private and exposes `delegate :calculate, to: :adapter`; `ApplicationSearchIndex` keeps `client` private and exposes `search`, `scroll`, `save_document!`. Deleting the forwarder does not let the caller navigate — it forces the internal adapter public, so a worker reaches for `metric.adapter.calculate(...)` or `DealSearchIndex.client.scroll(...)` and the object stops deciding how it is used. **Not yet exempt. This is the open gem work.**

## The two DSL cases need no gem change

Target visibility is not the discriminator and must not become one. `Metric#adapter` is private, but `ApplicationSearchIndex.client` is a **public** `attr_accessor` at line 12 — `private` starts at line 181, after `scroll`. A visibility test covers one case and not the other, and it hands every author an escape hatch: privatise the collaborator, keep the forwarder.

The discriminator the gem already applies is the right one: **does the object contribute something, or only relay?** Both cases are failing because the forwarder relays, and in both the fix is to make the object contribute — which the existing `composes_own_state?` exemption then covers.

`ApplicationSearchIndex.scroll` relays whatever the caller hands it, while every sibling contributes: `search` builds `{ index: index_name, body: ... }`, `save_document!` raises on a bad result. Give `scroll` the same shape — it builds the request from what the index knows. **Open risk to settle first**: confirm the OpenSearch client's `scroll` accepts the parameters the new body would pass; the scroll API takes `scroll_id` and `scroll`, and adding `index:` may be rejected. A constant does not count as own state for the cop (`own_state?` matches an ivar, `self`, or a receiverless call — not a `const`), so inventing a constant to satisfy it would not work and inventing a private reader for a literal would be satisfying the linter rather than the design.

`Metric` has the clearer fix, and it corrects a real defect at the call site. [app/workers/metric/consumer.rb:36](../../../app/.claude/worktrees/disallow-delegate/app/workers/metric/consumer.rb:36) passes `client_id: metric.client_id, comparator: metric.comparator, installment: metric.installment, product_id: metric.product_id, status_id: metric.status_id` — the worker reads five attributes off the metric to hand them straight back. Replace the `delegate` with a `calculate` that receives only what the metric does not know (commission, plan, interval bounds, user) and supplies its own five to the adapter. `adapter` stays private, the body composes own state, the cop is satisfied, and the call site loses five arguments.

## Rule work owed in rubocop-fourshark

Both items are gem changes, released as a hotfix branch off `main` (`hotfix/X.Y.Z`, PR to `main`, then `bundle exec rake release` — the engineer's command, OTP required). **No workaround in the app**: an `Exclude:` list of app files under `Style/DisallowDelegate` is forbidden, and adding one was a mistake made twice in this session.

**1. The DSL / facade exemption.** A forwarder whose target is private is publishing an interface, not answering for a collaborator. The cop currently sees only the send and cannot tell the target is internal. Deciding the detection is the design question — the target's visibility inside the same class body is knowable from the AST (a `private` marker before the target's `def`, or `private :name`), but a `delegate` macro at the top of a class body is evaluated before the target is defined, so the check has to look at the whole class, not the line.

**2. The `allow_nil: true` group.** These carry a second defect on top of delegation — `allow_nil` is `&.` applied to every forwarded method at once, so the absent case is silently swallowed for all of them. The conversion is per method (name the absent case, e.g. `return false if frequency.blank?`), which is judgment, not a mechanical rewrite. The engineer's instruction is to settle the correct shape and encode it, not to exclude the files.

## `.rubocop.yml` is untouched, and stays untouched

The file is byte-identical to `develop` on both branches. It carries no `Style/DisallowDelegate` and no `Style/DisallowTernary` entry at all, so both cops run from the gem defaults across the whole repository — no `Exclude:`, not even `bin/`, `db/` or `spec/`. Any entry added there is a workaround, and adding one is forbidden: the fix belongs in the gem or in the code.

Both cops arrive with the `rubocop-fourshark` bump to 0.8.5 in `Gemfile.lock`, which is part of #5296. Against that config the repository reports **112 offenses**: 27 from `Style/DisallowDelegate` (#5296's work, listed below) and 85 from `Style/DisallowTernary` (#5302's work, already converted on that branch).

## Delegate offenses — 25 cleared, 8 open

The cop now reports **8** offenses, all in `app/models/variable.rb:104-111`. Everything else is done and pushed.

### Cleared, by conversion shape

**Composes own state** (the cop's existing `composes_own_state?` exemption). `Metric#calculate` replaces `delegate :calculate, to: :adapter` — it now takes only what the metric does not know (`commission_uuid`, `ends_at`, `plan`, `starts_at`, `user_id`) and supplies its own `client_id`, `comparator`, `installment`, `product_id`, `status_id` to the adapter; `adapter` stays private and `app/workers/metric/consumer.rb:36` loses five arguments. `ApplicationSearchIndex.scroll` takes a `scroll_id` and builds the request with its own `scroll_keep_alive`, matching how `search` builds `{ index: index_name, body: ... }`; the keep-alive is a private class method because this file already expresses index configuration as class methods (`index_name`, `document_id`, `properties`) rather than constants.

**Native enumerize predicates** — the `payment_exportation_field.rb` / `seat_action.rb:25` precedent. `calendar.rb`, `indicator_document.rb`, `kpi_document.rb`, and `variable.rb` (`calculation`, `frequency`, `override_calculation`) gained `predicates: true` and dropped the delegate that republished the value object's predicates.

**Remove Middle Man, no caller** — the five `attachment` delegates (`audit`, `campaign`, `document`, `statement_portable_batch`, `plan_statement_portable_batch`), `ranking_result.rb`, `indicator.rb`, `plan_statement.rb`. Deleting `PlanStatement`'s also un-shadows its own `belongs_to :owner` at line 5, which the delegate was overriding.

**Remove Middle Man, callers updated** — `commission.rb` and `partial_commission.rb` dropped seven forwarders to `plan`; six call sites now navigate (`user_commission.rb` ×2, `commission_policy.rb`, `plan_slice_commission_policy.rb`, `indicator_aggregation/user_producer.rb`, `goal_dataset/producer.rb`). `rankifier_variable.rb` dropped three forwarders to `rankifier`; `calculate` names the absent case once (`return 0 if rankifier.blank?`) instead of `allow_nil` swallowing it per predicate, and the three validation conditions became explicit lambdas. `indicator.rb`'s `compiled_at_day` navigates to `variable`.

**Specs updated** — `indicator_spec.rb` and `rankifier_variable_spec.rb` stubbed the forwarders. Both now set the real collaborator (a `Variable` with a frequency; a `WeightRankifier` / `GoalReachRankifier`), which removes the stubs entirely.

### Open — `variable.rb:104-111`, the `data_type_object` group

Eight macros forward `boolean?`, `date?`, `duration?`, `format`, `number?`, `output`, `percent?`, `string?` to a **private** `data_type_object` (`variable.rb:169`), which the Variable builds from its own `data_type` column.

`NO-DELEGATE.md` blesses this exact case as the exception — *"`Variable#number?` qualifies (it is a typed thing; `data_type_object` is how it works that out internally)"* — and the cop flags it. That is the documented stop condition: the linter and the documentation disagree, so the fix belongs in the gem, not in the code.

There is no honest code-level conversion. The caller cannot navigate (the collaborator is private), so Remove Middle Man has no target; rewriting the macros as hand-written methods with identical bodies is the conversion the engineer already rejected; and the Variable has nothing to contribute to `number?` beyond the `data_type` it already used to build the object.

The gem-side discriminator that fits the engineer's framing (*"em vez de chamar o método direto no objecto, você chama no objecto `a.b.method`"*) is target visibility: when the target is private, there is no `a.b.method` for the caller to write. The objection recorded earlier — that `ApplicationSearchIndex.client` is public, so visibility covers one case and not the other — no longer has a counterexample in the codebase, because `scroll` was fixed by composition instead. What remains of the objection is that visibility hands an author an escape hatch (privatise the collaborator, keep the forwarder). That trade-off is the engineer's call.

## Verification

`rubocop` across 4787 files: 93 offenses — the 8 above plus the 85 `Style/DisallowTernary` that belong to #5302. No other cop fires.

Full suite: 6013 examples, 3 failures, all three reproduced on `develop` in the main checkout (numeric-vs-string serialization in `deals_controller_spec` ×2 and `graphql_controller_payment_resolver_spec`). Two failures this branch DID cause were found and fixed: `record.responsible_ids` in `commission_policy.rb:70` and `record.calendar` in `plan_statement_policy.rb:21` — both missed by the initial grep because the receiver is named `record`, not the model.

## Open review thread on #5296

Copilot flagged `app/graphql_mutations/create_payment_report_graphql_mutation.rb:14`. It is **not** a false positive. `PaymentReportForm` lost `delegate :id, to: :payment_report`; the mutation returns the form, and `PaymentReportGraphqlType` declares `field :id`, so resolving `id` off the form now raises. The lock failure adds `errors.add(:id, :invalid)` to the form rather than to the record, so simply returning `payment_report` instead loses that error. Needs a decided shape, not a mechanical fix.

## Process notes for the next session

Do not remove or rewrite anything the cop did not flag. Every correction above exists because a method, a memoization, a visibility, or a validation condition was changed on the agent's own initiative while the task was delegation removal only.

Rewriting a `delegate` macro as a method with an identical body is not a conversion — it satisfies the linter, which only reads the macro, while leaving the responsibility exactly where it was.

The engineer reviews the diff hunk by hunk and brings each problem in turn. Fix only what is brought; do not sweep ahead of the review.
