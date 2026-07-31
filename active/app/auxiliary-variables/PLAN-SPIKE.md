# PLAN-SPIKE — Auxiliary (output) variables in `app`

**Status**: research complete, draft for engineer review. No implementation, no design revision.
**Date**: 2026-07-30
**Repository**: `~/Projects/4Shark/app`, branch `develop`
**Authoritative input**: `~/Projects/4Shark/dot-claude-plans/active/spike/incentive-calculated-variables/SPIKE.md` (read in full; §4 is the approved direction)
**Language classification**: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).

> This document plans the execution of the design already chosen in SPIKE §4. It does not revisit
> options A/B/D/E and proposes no alternative design. Where a genuine execution fork exists, both
> sides are stated with their trade-off and left for the engineer.

**Auxiliary files** (every claim below that says "inventory" or "chain" resolves to one of these):

- `auxiliary-variables_call-sites_1.md` — the complete variable-read call-site inventory, verified against `develop`.
- `auxiliary-variables_pipeline_2.md` — the commission worker chain, verified enqueue by enqueue, plus the `Computation` protocol, the retry-idempotency asymmetry, and the sign inversion.
- `auxiliary-variables_rollout_3.md` — rollout evidence: the queue / HireFire / Terraform wiring, the migration-vs-deploy window, the `Computation` counter mechanics with its TTL, the GraphQL contract as the frontend actually sends it, and the permission-creation path.

---

## Objective

Add a fourth `Variable` type — auxiliary — that the integration never feeds and the commission
pipeline computes. Each `Rule` may optionally declare one auxiliary variable as its output; that
rule's computed value for a user is written into that variable for that user, and several rules
targeting the same variable sum. Saving an incentive registers its output variables in
`incentive_variables` alongside its inputs, distinguished by a new `role`. At plan save, an
incentive whose formula reads an auxiliary variable requires another incentive in the same plan, in
a strictly earlier calculation stage, to export it. At calculation time the value is materialized
per `(user_commission, variable)` and injected into each consuming rule's Dentaku options hash.

## Scope

### In scope

- The `Variable` fourth type and its STI subclass.
- The `role` column on `incentive_variables` and the output binding on `rules`.
- Materialization of the per-`(user_commission, variable)` value and its accumulation semantics.
- The read path that delivers auxiliary values to consuming rules.
- Plan-level validation including stage order.
- Exclusion of auxiliary variables from existing unscoped flows.
- GraphQL surface and the `app-webclient` authoring surface.
- Test strategy, data migration, rollout sequence, execution order.

### Out of scope (open question)

- The statement / per-incentive breakdown display (SPIKE §5 "Statement display" — the transparency
  half of option E). It is named in the spike as not superseded, but it is a separate deliverable
  with no dependency on this one in either direction.
- Whether an auxiliary variable can carry a goal (`plan_variables.goal_type`) — see Decision 7.
- Whether the deal stage may write an auxiliary variable (SPIKE §5 "Which stages may write") — see
  Decision 3.

---

## Blocker found during research — not named in the spike

**A rule that references an auxiliary variable key fails validation today, and the failure is
silent.** This is not an exclusion problem; it is the read side of the feature not existing.

`Rule` validates every formula by evaluating it against a synthetic options hash built from
positively-scoped variable queries. `app/models/rule.rb:208-214`:

```ruby
  def indicator_variables_options
    incentive.company.variables.indicators.enabled.each_with_object({}) do |variable, options|
      options["#{variable.key}_goal"] = rand(5000..10_000) # english variable
      options["meta_#{variable.key}"] = rand(5000..10_000) # portuguese variable
      options[variable.key] = rand(1..5_000)
    end
  end
```

That hash reaches `validate_syntax`, which calls the bang evaluator (`app/models/rule.rb:172-180`):

```ruby
  def validate_syntax(options = {})
    formula_error = formula.error

    return errors.add(:value, formula_error.reason, **formula_error.details) if formula_error.present?

    calculate!(options)
  rescue *PARSE_EXCEPTIONS => _e
    errors.add(:value, :invalid)
  end
```

`calculate!` is `Dentaku!(value, cast_values(options)).to_f` (`app/models/rule.rb:59-61`), and
`Dentaku!` is `Dentaku.evaluate!` (`dentaku-3.5.7/lib/dentaku.rb:67-69`):

```ruby
def Dentaku!(expression, data = {})
  Dentaku.evaluate!(expression, data)
end
```

An unbound identifier raises `Dentaku::UnboundVariableError`, which is a subclass of
`Dentaku::Error` (`dentaku-3.5.7/lib/dentaku/exceptions.rb:6`):

```ruby
  class UnboundVariableError < Error
```

and `Dentaku::Error` is the first entry of `Rule::PARSE_EXCEPTIONS` (`app/models/rule.rb:4-5`):

```ruby
  PARSE_EXCEPTIONS =
    [Dentaku::Error, Dentaku::ZeroDivisionError, Dentaku::ArgumentError, NoMethodError, ArgumentError, NameError].freeze
```

So today the incentive simply refuses to save with `errors.add(:value, :invalid)` on the rule, with
no indication that the cause is an unknown variable key. **Extending the syntax validators to
include auxiliary keys is a prerequisite for the read side, not an optional polish.** Which
validators need it depends on Decision 3 (which stages may read).

The same rescue at runtime is SPIKE §2.5 — `calculate` returns `0`
(`app/models/rule.rb:53-57`) — so a missing auxiliary value at calculation time yields zero, never
an error.

---

## 1. Schema

`Variable` STI needs **no migration**: `variables.type` is a plain string column
(`db/schema.rb:2565`, `t.string "type", limit: 8000`) and the constraint is application-side
(`app/models/variable.rb:41`, `validates :type, presence: true, inclusion: { in: TYPES }`). What
changes is `Variable::TYPES` (`app/models/variable.rb:4`) plus a new STI subclass file mirroring
the three existing ones — each is five lines, e.g. `app/models/easy_variable.rb` in full:

```ruby
class EasyVariable < Variable
  rescue_unique_constraint index: :index_variables_on_company_id_and_key, field: :key
  rescue_unique_constraint index: :index_variables_on_company_id_and_name, field: :name

  validates :data_type, inclusion: { in: ApplicationDataType::EASY_TYPES }
end
```

The data-type allow-list is per subclass (`app/data_types/application_data_type.rb:4-6`):

```ruby
  DEAL_TYPES = %w[NumberDataType StringDataType BooleanDataType PercentDataType DurationDataType DateDataType].freeze
  INDICATOR_TYPES = %w[NumberDataType StringDataType BooleanDataType PercentDataType DurationDataType].freeze
  EASY_TYPES = %w[NumberDataType PercentDataType].freeze
```

Uniqueness of key and name is already enforced per company (`db/schema.rb:2568-2569`), so no new
namespace is needed — confirming SPIKE §4.

Four migrations are needed. All follow `~/.claude/docs/RAILS-MIGRATIONS.md`: generated with
`bin/rails generate migration`, one action each, `t.references` with inline `index:` /
`foreign_key:`, explicit `null:`, and a `self.statement_timeout` reading a per-migration ENV key —
the shape every recent migration uses, e.g.
`db/migrate/20260722215726_add_plan_id_to_plan_statement_portable_batches.rb` in full:

```ruby
class AddPlanIdToPlanStatementPortableBatches < ActiveRecord::Migration[8.1]
  def change
    safety_assured { add_reference :plan_statement_portable_batches, :plan, foreign_key: true, index: true, null: true }
  end

  def self.statement_timeout
    ENV.fetch('MIGRATION_20260722215726', 250)
  end
end
```

| # | Migration | Additive? | Reversible? | Backfill? |
|---|---|---|---|---|
| M1 | `role` on `incentive_variables` | yes | yes | yes — see §7 |
| M2 | output-variable reference on `rules` | yes | yes | no — null means "no output" |
| M3 | unique index on `incentive_variables (incentive_id, variable_id, role)` | yes | yes | must follow M1's backfill |
| M4 | the `Action` row for the new permission | yes | yes | n/a — creates one row |

**M1 — `incentive_variables.role`.** The table today (`db/schema.rb:950-955`) is a bare join with no
timestamps and no unique index on the pair:

```ruby
  create_table "incentive_variables", force: :cascade do |t|
    t.bigint "incentive_id"
    t.bigint "variable_id"
    t.index ["incentive_id"], name: "index_incentive_variables_on_incentive_id"
    t.index ["variable_id"], name: "index_incentive_variables_on_variable_id"
  end
```

Whether `role` is an integer with `enumerize` (the pattern `Variable#calculation`,
`VariableTrackCollection#calculation` and `Plan#status` all use) or a string is Decision 1.

**M2 — the output binding on `rules`.** `rules` already carries a variable-bearing FK
(`db/schema.rb:1959-1961`):

```ruby
    t.bigint "variable_track_id"
    t.index ["incentive_id"], name: "index_rules_on_incentive_id"
    t.index ["variable_track_id"], name: "index_rules_on_variable_track_id", unique: true, where: "(variable_track_id IS NOT NULL)"
```

so the shape has precedent in the same table. The association name is Decision 2 — note that
`belongs_to :output_variable` would need `class_name: 'Variable'`, and that plain
`belongs_to :variable` on `Rule` reads at the call site as `rule.variable`, which does not say
which direction the variable flows.

The model-side declaration follows the house rule (`~/.claude/CLAUDE.md` § Optional belongs_to):
`optional: true` on the `belongs_to`, and presence validated manually only if the binding is
mandatory — which it is not by default (Decision 4).

**M3 — the unique index.** SPIKE §4.6 recommends `(incentive_id, variable_id, role)`. Because
`Incentive#update_variables` rebuilds the whole collection with `delete_all` on every save
(`app/models/incentive.rb:150`), duplicates cannot arise through the normal path; the index is a
guarantee rather than a fix. It follows the concurrent-index shape of
`db/migrate/20260729113429_add_unique_index_to_user_update_document_enrollments.rb`, with
`disable_ddl_transaction!` and `algorithm: :concurrently` — mandatory together, and mechanically
enforced by `validate-concurrent-index-migration.sh`.

**M4 — the permission `Action` row.** A new permission is created by a data migration; the
established pattern is `db/migrate/20260729113439_user_update_document_actions.rb`:

```ruby
  def up
    Action.create!(key: 'user_update_document_listing', level: 'module', resource: 'user_update_document')
```

See §12.9 for why this one is load-bearing on the rollout sequence.

**Where the materialized value lives** is Decision 5, and it is the only schema question that is
not additive-by-inspection. Both candidates are described in §2.

---

## 2. Materialization: where the value is written, and how it accumulates

The spike settles the arithmetic and leaves the placement open. Two facts from the spike were
verified and hold:

- Every `(user_commission, rule)` pair is an independent job
  (`app/workers/indicator_incentive/producer.rb:22`): `combinations = user_commission_ids.product(rule_ids)`
  — so a read-modify-write on a shared row loses updates.
- Sidekiq is at-least-once, so `+=` is not idempotent, while `value = SUM(feeding commissionings)`
  is idempotent by construction (SPIKE §4.2b).

Research added three facts the spike does not carry, all detailed in the pipeline auxiliary file:

1. **Retry idempotency is not uniform.** The indicator stage uses
   `IndicatorCommissioning.find_or_initialize_by(user_commission_id:, rule_id:)`
   (`app/workers/indicator_incentive/consumer.rb:54`), which survives a retry. The limiter, ranking
   and redemption stages construct a fresh record — `limiter_commissioning = LimiterCommissioning.new`
   (`app/workers/limiter_incentive/consumer.rb:41`) — so a retry hits the unique index at
   `db/schema.rb:457` and raises on `save!`. Redemption compensates by destroying its prior rows in
   its producer (`app/workers/redemption_incentive/producer.rb:30`); limiter and ranking do not. A
   materialization that recomputes from `commissionings` inherits whatever consistency those rows
   have.
2. **`LimiterCommissioning` inverts its sign.** `value * -1` in both `#money` and `#points`
   (`app/models/limiter_commissioning.rb`), while the base `Commissioning#money` returns `value`
   unchanged (`app/models/commissioning.rb:60-64`). Summing `value` and summing `#money` disagree in
   sign for any limiter rule bound to an auxiliary variable.
3. **A commissioning row cannot exist without a payment type.** `validates :payment_type_id, presence: true`
   and `validates :user_payment_type_commission_id, presence: true`
   (`app/models/commissioning.rb:13,17`), both resolved from the plan's `Incentivation`. This is the
   hard edge behind the publish-only question (Decision 6).

### Option 2A — a dedicated stage after each writing stage's finalizer

A `Producer` fanning out over `(user_commission, auxiliary_variable)` and a `Consumer` recomputing
`value = SUM(commissionings of the rules bound to this variable, for this user commission)`,
inserted between a stage's cache-finalizer and the next stage's producer.

For the indicator stage that means inserting between `IndicatorIncentive::Finalizer`
(`app/workers/indicator_incentive/finalizer.rb:22`, which today enqueues `Ranking::Producer`) and
`Ranking::Producer`.

**Pros.** One recompute per `(user, variable)` per stage instead of one per commissioning save. The
write race disappears entirely because the stage runs after the fan-out has settled. It matches the
existing `Producer`/`Consumer` topology exactly, so the naming and the `Computation` accounting have
a template in every neighbouring worker.

**Cons.** One new producer/consumer pair per writing stage. Each pair must participate in the
`Computation` protocol correctly or the chain stalls (see below). It edits the enqueue graph, which
is where the stage order is currently encoded (§4), so the diff touches the finalizers — and that is
the one in-flight-visible change in the whole feature (§12.5).

**Cost.** Two worker classes per writing stage, plus one edit to the enqueuing finalizer per stage.

**Risk.** A `Computation` accounting mistake stalls the chain rather than producing a wrong number —
loud, not silent.

### Option 2B — recompute inside the existing consumer, at commissioning-save time

After the consumer saves its commissioning, recompute the auxiliary sum for that
`(user_commission, variable)` in the same job.

**Pros.** No new stage, no new `Computation` participation, no edit to the enqueue graph — so the
in-flight question of §12.5 does not arise at all. The value is closed at every moment rather than
only at stage boundaries.

**Cons.** N times the work for an identical result — SPIKE §4.2b states this directly: *"Recomputing
on every commissioning save is N times the work of recomputing once at the stage boundary for an
identical result"*. Two consumers writing to the same variable for the same user still race on the
recompute, so the write needs the unique index plus an upsert to be safe, and the last writer must
observe both commissionings — which is only guaranteed if the recompute reads at that moment,
inside its own transaction.

**Cost.** An edit inside each writing consumer plus the upsert helper.

**Risk.** The race is on the read-then-write of the aggregate, not on the commissioning itself. It
resolves to a correct value only if the query is genuinely re-read per job; a stale read produces a
silently low number, which is the failure class the payroll cannot tolerate.

### Where the row is written (Decision 5) — independent of 2A/2B

**Reuse `aggregated_modifiers`.** Already unique on `(user_commission_id, variable_id)`
(`db/schema.rb:86`), already purged on reprocess without a type scope
(`app/workers/aggregated_indicator/purge/consumer.rb:17-21`), already the source
`IndicatorOptionsProcessor` reads. Cost: `AggregatedIndicator::Calculator::Producer` fans out over
*every* row for the commission with no type scope
(`app/workers/aggregated_indicator/calculator/producer.rb:20-21`) and its consumer calls
`calculate!`, which falls back to `variable.format_default` when there are no
`indicator_aggregations` — so any path that re-enters the Calculator after auxiliary rows exist
overwrites them with the default. Within one run the ordering makes this unreachable (Calculator
completes before any incentive stage begins — see the chain in the pipeline auxiliary file); the
exposure is re-entry, and closing it means adding a type scope there.

**A dedicated table.** Costs a `create_table` migration and its own purge step (the free purge in
`aggregated_modifiers` is lost), and gains complete independence from the aggregated-indicator
machinery, including the Calculator hazard above.

### Worker naming

Per `~/.claude/docs/DATA-PROCESSING.md` and the mechanical block in
`validate-worker-topology-naming.sh`, a fan-out pair is `Producer`/`Consumer` and a single bounded
unit is `Processor`; `Executor`/`Runner`/`Handler` are blocked. Option 2A is Producer/Consumer.

### The `Computation` contract a new stage must honour

A producer raises when the previous stage has not settled, then increments `queue` by the exact
fan-out size before pushing (`app/workers/indicator_incentive/producer.rb:15,23`):

```ruby
      raise RaceConditionException unless commission.computation.done?
```

```ruby
        commission.computation.increment_queue(by: combinations.count)
```

A consumer increments `executions` once and enqueues the next stage only when it observes `done?`
(`app/workers/indicator_incentive/consumer.rb:63-67`):

```ruby
      commission.computation.increment_executions

      return unless commission.computation.done?

      UserPaymentTypeCommission::IndicatorCacheProducer.with_company_id(commission.company_id).dynamic_perform_async(commission_id, partial)
```

Note the empty-set branch: every producer enqueues the *next* stage directly when there is nothing
to fan out (`app/workers/indicator_incentive/producer.rb:26-28`). A new stage must do the same, or a
plan with no auxiliary variables stalls.

Every worker in the chain also takes `partial = false` and branches on it to load either
`Commission` or `PartialCommission` — a new worker must carry the same signature or partial
commissions break.

---

## 3. The read path

The plan variable snapshot is written once, before any incentive stage
(`app/workers/user_commission/indicator_options_consumer.rb:16-17`):

```ruby
      indicator_options = Commission::IndicatorOptionsProcessor.call(user_commission: user_commission, commission: commission)
      UserCommission.with_uncached_connection { user_commission.update(modifier_options: indicator_options) }
```

and that consumer enqueues `DealIncentive::Producer` (line 22), which is the first incentive stage.
So the snapshot predates every writing stage — SPIKE §4.1 confirmed. It is also *helpful*: because
`IndicatorOptionsProcessor` reads `plan.variables` unscoped
(`app/services/commission/indicator_options_processor.rb:41`), auxiliary keys land in the snapshot on
their own, carrying their default, so a consuming formula never hits the unbound-variable path at
runtime — it reads a default until the fresh merge overwrites it.

The fresh merge follows one of two named precedents, described with quotes in the pipeline auxiliary
file § 5: `RedemptionOptionsProcessor` computes inside the consumer, `LimiterOptionsProcessor`
computes in a dedicated preceding stage and persists onto the user commission. Both merge last,
after `modifier_options`.

**Consumers that must merge the auxiliary options**, with the exact line the merge would join:

| Consumer | Line | Current |
|---|---|---|
| `app/workers/indicator_incentive/consumer.rb` | 29 | `options = deal_options.merge(user_commission.modifier_options)` |
| `app/workers/ranking_incentive/consumer.rb` | 44 | `options = deal_options.merge(modifier_options).merge(ranking_options)` |
| `app/workers/limiter_incentive/consumer.rb` | 37 | `options = deal_options.merge(modifier_options).merge(limiter_options)` |
| `app/workers/redemption_incentive/consumer.rb` | 34 | `options = deal_options.merge(modifier_options).merge(redemption_options)` |

**The deal stage is different and needs its own decision.** It does not merge the snapshot wholesale;
it filters it down to metric keys (`app/workers/deal_incentive/consumer.rb:30-32`):

```ruby
      variables_keys = Metric.with_uncached_connection { plan.metrics.joins(:variable).pluck(:key) }
      metric_options = user_commission.modifier_options.select { |key| variables_keys.include?(key) }
      options = deal_options.merge(metric_options)
```

The same shape is in `app/workers/deal_incentive/period_processor.rb:20`. An auxiliary key would be
filtered out by that `select`, so deal-stage *reading* requires an explicit addition. Whether the
deal stage reads at all is part of Decision 3.

The new processor is a `Commission::<name>OptionsProcessor` class alongside the four existing ones in
`app/services/commission/`. It obeys `~/.claude/docs/DATA-ACCESS.md`: `with_uncached_connection`
around each access, IDs not loaded objects, associations navigated per record rather than joined.

---

## 4. Plan-level validation, including stage order

`Plan` already carries four custom validations (`app/models/plan.rb:58-61`):

```ruby
  validate :metric_rules
  validate :shared_conditions
  validate :redemption_incentive_requirements
  validate :responsibility
```

`redemption_incentive_requirements` is the closest structural sibling — it reasons over the plan's
incentive set and adds to `:incentivations` (`app/models/plan.rb:389-398`):

```ruby
  def redemption_incentive_requirements
    return unless incentivations.any?

    incentive_ids = incentivations.map(&:incentive_id)

    return unless Incentive.where(id: incentive_ids).redemptions.any?
    return if Incentive.where(id: incentive_ids).points.any?

    errors.add(:incentivations, :points_incentive)
  end
```

A new `auxiliary_variable_requirements` validation in the same place, reading the plan's incentives
through `incentivations`, matches that pattern exactly. Note it must read `incentive_ids`
(`app/models/plan.rb:421-425`), which excludes incentivations marked for destruction — the existing
sibling uses `incentivations.map(&:incentive_id)` and does not.

**The stage order has no representation in code today.** It exists only in the enqueue graph — 41
call sites, mapped in the pipeline auxiliary file. `Incentive::TYPES` is declared in a different
order and carries no ordering semantics (`app/models/incentive.rb:15`):

```ruby
  TYPES = %w[DealIncentive LimiterIncentive IndicatorIncentive RankingIncentive RedemptionIncentive].freeze
```

The actual execution order, read off the chain, is Deal → Indicator → Ranking → Limiter →
Redemption. Expressing it once is Decision 8:

- **An ordered constant on `Incentive`** (e.g. a frozen array or a hash of type to index) with a
  `stage_order` reader. Cheap, single place, and the validation reads it directly. It is a second
  representation of an order that lives in the enqueue graph, so the two can drift — nothing
  mechanically keeps them in sync.
- **A method per STI subclass** returning the subclass's own position, which puts the fact next to
  the class it describes and follows the `deal?`/`limiter?`/`indicator?` predicate style already on
  `Incentive` (lines 107-125). Same drift exposure, spread over five files.

Either way this is the first time the order becomes a named fact, and it is worth stating in the
plan that the enqueue graph remains the source of truth for execution while the constant becomes the
source of truth for validation.

**Validation is not the only gate, and the picker is not a substitute.** SPIKE §4.4 notes the plan
picker filtered to compatible incentives is the preventive form. Research adds that plans are also
created in bulk from a spreadsheet through `PlanDocument::Consumer`
(`app/workers/plan_document/consumer.rb:158`, `plan.incentivations.build(...)`, and `:209`,
`PlanDocument.with_uncached_connection { plan.save }`). That path reports plan-level errors and skips
only attributes starting with `incentivations.` (`app/workers/plan_document/consumer.rb:212`):

```ruby
        next if attribute.to_s.start_with?('incentivations.')
```

An error added to `:incentivations` (no dot) is therefore reported by the document import, exactly
like the existing `redemption_incentive_requirements`. That is the behaviour to preserve.

---

## 5. Exclusions in existing flows — the spike's inventory verified and extended

The full inventory with verbatim quotes is `auxiliary-variables_call-sites_1.md`. Summary:

**SPIKE §4.5's claim that positively-scoped reads are free is correct.** Fifteen call sites read
through `variables.deals` / `variables.indicators` / `variables.easy` and exclude a fourth type by
construction with no code change.

**All four unscoped reads the spike names are confirmed**: `indicator_options_processor.rb:41`,
`calendar_audit/producer.rb:19`, `goal_dataset/migration/producer.rb:16`,
`money_sanitizer_processor.rb:48`. Two of them fan out multiplicatively — `calendar_audit/producer.rb:20`
computes `period_ids.product(user_ids, variable_ids)`, so each auxiliary variable adds
`periods × users` audit jobs per plan.

**Seven unscoped reads the spike does not name** were found:

| File:line | What it is | Needs a decision? |
|---|---|---|
| `app/work_books/commission_work_book/indicator_work_sheet.rb:29` | commission report indicator sheet builds its lookup unscoped, though line 12 gates on `variables.indicators` | yes |
| `app/work_books/plan_slice_commission_work_book/indicator_work_sheet.rb:36` | same shape | yes |
| `app/work_books/variable_audit_work_book/variables_work_sheet.rb:28` | variable audit enumerates every enabled company variable | yes |
| `app/models/calendar_audit.rb:30` | `PlanVariable.where(plan_id: plan_ids).count` — the audit's expected row count | yes |
| `app/workers/company/inactivator.rb:107` | disables every company variable | no — covering all types is its purpose |
| `app/workers/company/activator.rb:110` | enables every company variable | no — same |
| `app/workers/company/cleansing/variable_producer.rb:13` | cleanses every company variable | no — same |

**The goal-binding surface is confirmed as the spike states.** `plan_variables` carries `goal_type`
(`db/schema.rb:1618`) and `Plan#create_variables` (`app/models/plan.rb:434-436`) populates it from
every `incentive_variables.variable_id`, so an auxiliary variable reaching `plan_variables` surfaces
in the goal-binding UI. Five consumers of `plan_variables` were inventoried; two are already filtered
by `goal_type` and three are not. `PlanVariableInputGraphqlType` requires `goal_type`
(`app/graphql_types/plan_variable_input_graphql_type.rb:5-6`), which is what makes the plan-finish
screen offer a goal for each row. Decision 7 settles whether auxiliary rows reach `plan_variables` at
all — and note that the read path in §3 depends on them reaching it, because
`IndicatorOptionsProcessor` reads `plan.variables`.

---

## 6. Backwards compatibility

The engineer's explicit concern. Each row names the code path and why it is or is not affected.

| Case | Path | Assessment |
|---|---|---|
| An incentive with no output binding | `Rule` output column null; `Incentive#update_variables` (`app/models/incentive.rb:149-175`) creates only input rows | Unaffected. `update_variables` iterates the same positively-scoped collections it does today; a null output binding adds nothing. |
| A plan with no auxiliary variable | `Plan#create_variables` (`app/models/plan.rb:434-436`) | Unaffected, **provided** the new stage's empty-set branch enqueues the next stage directly, as every existing producer does (`app/workers/indicator_incentive/producer.rb:26-28`). Without that branch the chain stalls for every plan. |
| Existing commissions being reprocessed | `Commission::Producer` resets both counters (`app/workers/commission/producer.rb:17-18`) and `AggregatedIndicator::Purge::Consumer` destroys every aggregated indicator unscoped (`app/workers/aggregated_indicator/purge/consumer.rb:17-21`) | Unaffected if the value lives in `aggregated_modifiers` — the purge is free. A dedicated table needs its own purge step or stale values survive a reprocess. |
| Partial commissions | Every worker in the chain branches on `partial` to load `PartialCommission` instead of `Commission` — e.g. `app/workers/indicator_incentive/consumer.rb:8-13` | Unaffected only if the new worker carries the identical `(commission_id, ..., partial = false)` signature and branch. `AggregatedIndicator#indicator` has a partial-specific `nil` return (`app/models/aggregated_indicator.rb:115-116`), so the materialization's zero-versus-absent semantics need checking against partials specifically. |
| `/api/v3/` (the integrator write path) | `app/controllers/api/v3/` holds `clients`, `deals`, `goals`, `groups`, `indicators`, `products`, `roles`, `subsidiaries`, `users` — and nothing else | **Not an authoring path for incentives, rules, or plans.** `grep -rn "incentive" config/routes.rb` returns nothing. The integrator feeds `indicators`, which feed `IndicatorVariable` values — auxiliary variables are never fed by it, which is the design's premise. The brief's concern does not apply to this feature; recorded so the plan does not carry a phantom risk. |
| Incentive bulk import | `IncentiveDocument::Processor` (`app/workers/incentive_document/processor.rb`) builds incentives and rules from positional CSV columns — the rule build at lines 81-86 uses `row[0]` (value) and `row[1]` (description) only | **Affected if the output binding must be importable.** A new rule attribute means a new CSV column and a positional-index change, which is a file-format change for every customer using the template. Whether the import supports the binding at all is Decision 9. |
| Plan bulk import | `PlanDocument::Consumer` (`app/workers/plan_document/consumer.rb:158,209`) | Affected only by the new plan validation, which it reports correctly — see §4. |
| Plan-slice auto-generation | `PlanSlice::Processor` (`app/workers/plan_slice/processor.rb:81,131`) creates `FormulaRule` and `IndicatorRule` records programmatically from variable tracks | Unaffected — generated rules carry a null output binding. |
| Incentive cloning | There is **no backend clone mutation.** `clone` is a permission and a UI action only: `IncentivePolicy#clone?` (`app/policies/incentive_policy.rb:28-33`), the permission string `incentive_clone` (`app/workers/company/admin/processor.rb:31`), and `actions << 'clone' if policy.clone?` (`app/graphql_types/incentive_graphql_type.rb:49`). The front has a clone component per incentive type (e.g. `app-webclient/src/app/indicator-incentives/clone/`) that prefills the create form | The clone goes through `CreateIncentiveGraphqlMutation`, whose rule allow-list is explicit (`app/graphql_mutations/create_incentive_graphql_mutation.rb:43-47`: `description`, `type`, `value`). **A cloned incentive silently loses its output bindings** unless both the mutation allow-list and the front clone form builder are extended. This is the sharpest backwards-compatibility risk in the table, because it fails silently and produces a plan that validates but computes a different number. |
| Plan cloning | No plan clone policy or component was found | Not applicable. |
| **An incentive already used by any plan** | `IncentivePolicy#update?` (`app/policies/incentive_policy.rb:12-19`) — `return false if record.plans.any?` | **This bounds the whole compatibility surface.** An incentive attached to any plan is not updatable through the mutation, so no existing productive incentive can acquire an output binding, and no existing plan's arithmetic can change without a new incentive being authored and added to a plan. Every risk in this table is therefore scoped to newly-authored incentives. |

---

## 7. Data migration

**Required: one backfill, for `incentive_variables.role`.** Every existing row is an input by
definition — `Incentive#update_variables` only ever creates input rows today
(`app/models/incentive.rb:149-175`). The backfill sets them all to the input role. Two shapes:

- A **default on the column** set to the input role, which makes the existing rows correct with no
  data pass. `incentive_variables` has no timestamps, so there is no created-at ordering to reason
  about. **This is also what makes M1 safe against the old code still serving** — see §12.4.
- An **explicit backfill** in a separate migration, per the one-action-per-migration rule.

There is a third possibility that removes the question: because `update_variables` rebuilds the
collection on every incentive save, the rows are ephemeral. A backfill is still needed for
incentives that are never re-saved, which is most of them.

**Not required:**

- `rules` — a null output binding is the correct value for every existing row.
- `aggregated_modifiers` — existing rows are indicator/easy aggregates and are untouched by a new
  type. Confirmed by inspection of the table (`db/schema.rb:80-89`), which carries no type column;
  the type is carried by the joined `variables` row.
- `plan_variables` — existing rows all reference non-auxiliary variables.
- `variables` — no column change, so nothing to backfill.

If Decision 5 lands on a dedicated table, that table starts empty and needs no backfill either.

---

## 8. API and front-end surface

### GraphQL — what exists today

| File | Relevant line | Current |
|---|---|---|
| `app/graphql_types/rule_graphql_type.rb` | 3-14 | Fields: `commissionings`, `created_at`, `description`, `document_line`, `id`, `incentive`, `incentive_id`, `type`, `updated_at`, `value`. No variable field. |
| `app/graphql_types/rule_input_graphql_type.rb` | 4-8 | Arguments: `_destroy`, `description`, `id`, `type`, `value` — **every one `required: false`**. |
| `app/graphql_types/incentive_variable_graphql_type.rb` | 4-7 | `id`, `incentive`, `incentive_id`, `variable`, `variable_id`. No role. |
| `app/graphql_types/variable_graphql_type.rb` | 33 | `field :type, String, null: false` — already exposes the STI type, so a fourth value needs no field change. |
| `app/graphql_resolvers/variable_graphql_resolver.rb` | 21 | `option(:type, type: String) { \|scope, type\| scope.for_type(type) }` — the front can already filter by type, backed by `Variable.for_type` (`app/models/variable.rb:55`). |
| `app/graphql_mutations/create_incentive_graphql_mutation.rb` | 43-47 | `rules: %i[ description type value ]` |
| `app/graphql_mutations/update_incentive_graphql_mutation.rb` | 43-49 | `rules: %i[ _destroy description id type value ]` |
| `app/graphql_mutations/create_variable_graphql_mutation.rb` | 4-11, 30-40 | Arguments and `permit` both list `type`, so creating an auxiliary variable needs no mutation change. |
| `app/graphql_types/plan_graphql_type.rb` | 39 | `field :plan_variables, [PlanVariableGraphqlType], null: true` |
| `app/graphql_mutations/finish_plan_graphql_mutation.rb` | 5, 23 | `plan_variables_attributes` — the goal-binding screen |

**Minimum GraphQL change set**, given the design: an output-variable field on `RuleGraphqlType`, the
matching argument on `RuleInputGraphqlType`, both incentive mutations' rule allow-lists extended
(these are explicit `%i[...]` arrays — an unlisted argument is silently dropped, which is the clone
failure in §6), and a `role` field on `IncentiveVariableGraphqlType` for the plan-side picker to
distinguish inputs from outputs. §12.7 grades each of these for contract compatibility.

### `app-webclient`

The rule form is a single shared module reused by every incentive type:
`app-webclient/src/app/rule/` holds `rule.model.ts`, `rule-create-form-builder.service.ts`,
`rule-update-form-builder.service.ts`, `rule.service.ts`, `rule.module.ts`. The create builder is the
whole surface for a rule's fields:

```ts
  build(model: Rule): UntypedFormGroup {
    return this.formBuilder.group({
      value: this.value(model.value),
      description: this.description(model.description),
    });
  }
```

and `Rule` in `rule.model.ts` carries `_destroy`, `description`, `expanded`, `id`, `value`, `type`.

Each incentive type composes it — `IndicatorIncentiveCreateFormBuilder` injects
`RuleCreateFormBuilder` and calls `rules: this.ruleFormBuilder.buildArray()`
(`app-webclient/src/app/indicator-incentives/create/indicator-incentive-create-form-builder.service.ts:25`).
The modules that reuse it are `deal-incentive`, `indicator-incentives`, `limiter-incentives`,
`redemption-incentives`, `rankifier-incentives`, each with `create/`, `update/` and `clone/`
sub-folders.

**So the front change is one control added in the shared `rule/` module, plus wiring in the five
incentive modules × three flows.** The clone flow is the one that must not be missed (§6).

**The two authoring behaviours the engineer named:**

- *Set the output variable on one rule and replicate to all.* This is a form-level action on the
  rules `FormArray` — the array lives in each incentive builder (`rules: this.ruleFormBuilder.buildArray()`),
  so the replicate control sits at the incentive form level, not inside the shared rule module.
- *A plan-side picker offering only incentives compatible with the auxiliary variables already
  present.* The plan create form builds `incentivationsAttributes` via
  `IncentivationCreateFormBuilderService`
  (`app-webclient/src/app/plan/create/plan-create-form-builder.service.ts:23`). The picker needs each
  candidate incentive's auxiliary inputs and outputs, which is why `IncentiveVariableGraphqlType`
  needs `role`. Per SPIKE §4.4 this is UX, not the guarantee — the plan validation is.

The variable creation screen (`app-webclient/src/app/variable/create/variable-create-form-builder.service.ts`)
already has a `type` control with a required validator, so offering the fourth type is a list change
rather than a form change. Note the builder's `variableCalculation`, `variableFrequency` and
`variableOverrideCalculation` helpers are conditionally required — matching the model, where those
three are validated only `if: :indicator?` (`app/models/variable.rb:32,36,39`). An auxiliary variable
follows the deal/easy shape and requires none of them, but it does require `default`
(`app/models/variable.rb:35`, `validates :default, presence: true`) — which is what SPIKE §4.3 turns
into a decision (Decision 11).

---

## 9. Test strategy

Per `~/.claude/docs/TESTING-PHILOSOPHY.md` (test the domain and the code that breaks silently, skip
Rails-Way trivia) and `~/.claude/docs/RSPEC-CONVENTIONS.md` (read siblings first; `let`/`before`/`it`;
no `subject`, no `let!`).

### Genuinely needs coverage

1. **The plan validation, including stage order.** It is new domain logic with a payroll consequence
   and several branches: reader with no exporter, reader with an exporter in the same stage, reader
   with an exporter in a later stage, reader with an exporter in an earlier stage, two exporters. The
   sibling to copy is the existing plan validation coverage; `Plan#redemption_incentive_requirements`
   is the structural twin.
2. **The materialization arithmetic.** Several rules into one variable; two incentives into one
   variable; a rule that evaluated to zero and therefore wrote no commissioning row
   (`app/workers/indicator_incentive/consumer.rb:41`); and — if a limiter rule may export — the sign
   question from `LimiterCommissioning#money`.
3. **Idempotency under retry.** Run the materialization twice and assert the value is unchanged.
   This is the property SPIKE §4.2b exists to protect and it is invisible in a single-run test.
4. **The exclusions.** One example per unscoped read that gets a scope, asserting an auxiliary
   variable does not appear. These are cheap and they are the regression net for §5.
5. **The rule syntax validators.** That a rule referencing an auxiliary key now saves — the Blocker
   above, which currently fails with a bare `errors.add(:value, :invalid)`.
6. **`Incentive#update_variables` role assignment.** That inputs and outputs both land, with the
   right role, and that the `delete_all` rebuild does not drop outputs.
7. **The empty-set branch of the new stage** (Option 2A only). That a plan with no auxiliary
   variables still advances to the next stage. This is the case every existing plan takes on the
   first deploy, so it is the one §12 depends on.

### Does not need dedicated coverage

- The STI subclass itself and its `data_type` inclusion — the three existing subclass specs
  (`spec/models/easy_variable_spec.rb`, `indicator_variable_spec.rb`, `deal_variable_spec.rb`) are the
  pattern, and one matching spec is the whole cost.
- Association and presence validations on the new columns — shoulda-matchers one-liners, following
  `spec/models/incentive_variable_spec.rb` which is ten lines in total.
- The chained workers themselves — team policy skips chained-worker tests.

### One existing spec breaks by construction

`spec/models/variable_spec.rb:35` asserts the type list literally:

```ruby
  it { is_expected.to validate_inclusion_of(:type).in_array(%w[DealVariable EasyVariable IndicatorVariable]) }
```

Adding a fourth type fails this. It is a required edit, not a regression.

### Factories

`spec/factories/variables.rb` has `:indicator` and `:deal` traits but no `:easy` trait, and
`spec/factories/rules.rb` has `:formula`, `:indicator`, `:ranking`, `:limiter` but no `:redemption`.
Adding an auxiliary trait follows the same shape. `spec/factories/incentive_variables.rb` is
currently a bare `factory :incentive_variable` with no attributes.

---

## 10. Execution phases

Ordered so each phase leaves the system working and is independently shippable. What blocks what is
stated per phase. §12 maps these phases onto deploys.

**Phase 1 — schema and model, inert.** M1 + M2 + M3, `Variable::TYPES` extended, the STI subclass,
`IncentiveVariable` role validation, the `Rule` association. Nothing reads or writes the new columns
yet. *Blocks everything.* *Blocked by* Decisions 1, 2, 5.

**Phase 2 — exclusions.** Add the type scope to the four unscoped reads the spike names, plus the
four additional ones §5 flags for a decision. Independently shippable and independently valuable —
it is the phase that makes an auxiliary variable harmless if one appears. *Blocked by* Phase 1
(the type must exist) and Decision 7.

**Phase 3 — registration.** `Incentive#update_variables` writes output rows with the output role and
input rows with the input role. `Plan#create_variables` roll-up behaviour confirmed or scoped per
Decision 7. Still no calculation. *Blocked by* Phase 1.

**Phase 4 — rule syntax validators.** Extend the sample options hash so a rule referencing an
auxiliary key validates. This is the Blocker; until it ships, no incentive carrying such a rule can
be saved through any path. *Blocked by* Phase 3 (the validator needs to know which auxiliary
variables the company has) and Decision 3.

**Phase 5 — plan validation.** The stage-order fact expressed once, the plan validation added, the
document-import error path confirmed. *Blocked by* Phases 3 and 4 and Decision 8.

**Phase 6 — materialization.** The new worker(s) per Decision 5, the `Computation` participation, the
empty-set branch, the partial-commission branch. *Blocked by* Phase 3. Independent of Phases 4-5,
so it can run in parallel with them.

**Phase 7 — read path.** The options processor and the merge in each consuming stage. *Blocked by*
Phase 6 (nothing to read otherwise) and Phase 4 (no rule can name the variable otherwise).

**Phase 8 — GraphQL + permission.** Fields, arguments, both mutation allow-lists, the M4 `Action`
row and the `MODULE_KEYS` entry. *Blocked by* Phase 1; practically sequenced after Phase 5 so the
front never offers a binding the backend rejects.

**Phase 9 — `app-webclient`.** The shared rule control, the five modules × three flows, the
replicate action, the plan picker. *Blocked by* Phase 8. The clone flows are the part §6 flags as
silently lossy if skipped.

**Phase 10 — bulk import.** Per Decision 9; if the CSV formats are not extended, this phase does not
exist and the limitation is documented instead.

---

## 11. Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| A cloned incentive silently loses its output bindings (§6) | A plan validates and computes a different number than the operator authored | Extend both mutation allow-lists and all five front clone builders in the same change; cover with a test that clones and asserts the binding |
| The new fan-out stage miscounts `Computation` | The chain stalls; no commission finishes for that plan | The stall is loud (no completion) rather than silent. The empty-set branch is the specific case to test, since it is the one every existing plan takes |
| The Calculator overwrites auxiliary rows with the variable default (§2) | A silently zeroed auxiliary value | Unreachable within a single run by the chain's ordering; add a type scope at `aggregated_indicator/calculator/producer.rb:20-21` if the value lives in `aggregated_modifiers` |
| `calendar_audit/producer.rb:20` fan-out multiplies by `periods × users` per auxiliary variable | Audit job volume grows per plan | Scope the read (§5, Decision 12) |
| Limiter/ranking commissioning writes are not retry-idempotent (§2) | A retried job raises on the unique index; a commissionings-based sum inherits whatever those rows hold | Pre-existing, not introduced here. It bounds how much the materialization can rely on those rows being rewritable |
| The stage order becomes a second representation of the enqueue graph (§4) | Drift between validation and execution | Nothing mechanical keeps them in sync; a test asserting the constant matches the observed chain is the only lever found |
| Sign disagreement for limiter exports (§2) | A wrong-signed payroll contribution | Settle it as part of Decision 3 — if limiters may not export, the question does not arise |
| A new queue name added to the sidekiq YAML but not to HireFire (§12.6) | The queue is polled but invisible to autoscaling — depth grows with no capacity added | Reusing an existing `base_queue_name` avoids the question entirely; otherwise both files change together. The drift already exists for four queues today |
| A new frontend selecting a field an old backend lacks (§12.7) | `errorPolicy: 'none'` discards the whole result — the screen breaks, not just the field | This is the constraint that decides whether the engineer's frontend-first sequence is achievable; see §12.7 and §12.10 |

---

## 12. Rollout — zero-downtime across the two applications

The engineer's stated requirement is expand/contract across the two applications: **(1)** release the
frontend carrying the new code, **(2)** that release tolerates both the old and the new backend
contract, **(3)** deploy the backend that makes the new contract available, **(4)** release the
frontend again removing the old branch. Everything below is measured against that sequence.

All evidence for this section — the queue and Terraform wiring, the migration-vs-deploy window, the
`Computation` counter mechanics, the GraphQL contract as the frontend actually sends it, and the
permission path — is in `auxiliary-variables_rollout_3.md`, quoted at `file:line`.

### 12.1 Which applications are affected

**Verified, not assumed.** A grep for `IncentiveVariable`, `PlanVariable`, `aggregated_modifier`,
`Commissioning` and `incentive_variables` across `onboarding`, `setup`, `integrator` and `lambda`
returned **no matches**. None of those four repositories references the models this feature touches.

So the affected set is **`app` and `app-webclient`** — but the second is not one deploy.
`ls app-webclient/src/environments` returns 40 entries: two shared environment files and **38
per-client environment folders**, and `DEPLOY-REFERENCE.md:138` states the model verbatim:

> **Netlify** — build+deploy combined at Netlify (publishes `dist/browser`), one Netlify site **per client** (whitelabel). NOT GitHub Actions.

"Release the frontend" therefore means **N Netlify site builds**, and `netlify.toml` carries no
`[context.*]` branch blocks, so which branch each site tracks lives in that site's own Netlify
settings rather than in the repository. **Not researched**: whether all 38 sites track the same
branch, and therefore whether a merge releases all clients simultaneously or per-site. That fact
changes the shape of steps (1) and (4) materially and should be confirmed before sizing them.

**Not researched**: `app-sdk-advpl` and `app-sdk-dotnet` were excluded from the grep and not opened;
`app-mobileclient` has no CI/CD in the repo (`DEPLOY-REFERENCE.md:140`).

### 12.2 The deploy sequence

Written as the engineer's four steps, with each backend phase from §10 mapped onto it. Steps 3a-3d
are the backend half and are separately deployable — whether they are separate deploys is §12.10.

| # | What is deployed | Precondition | Verify before moving on |
|---|---|---|---|
| 0 | Nothing — the permission `Action` row (M4) and the `MODULE_KEYS` entry ship with the first backend deploy | — | — |
| 1 | **Frontend**, new code present but inert (§12.7 decides what "inert" means mechanically) | The tolerance mechanism from Decision 13 is chosen and built | Every existing screen still loads against the current backend; no query selects a field the backend lacks |
| 2 | *(not a deploy — the property step 1 must have)* | — | — |
| 3a | **Backend, Phases 1-3**: schema (M1-M3), the STI type, registration with roles | Migrations pass the §12.4 old-code test | `Incentive` save still produces the same `incentive_variables` rows; no plan changes behaviour |
| 3b | **Backend, Phases 4-5**: rule syntax validators, plan validation | 3a live | A rule naming an auxiliary key saves; a plan missing an exporter is rejected; the document import reports the error |
| 3c | **Backend, Phase 6-7**: materialization + read path | 3b live | A commission with no auxiliary variables completes end to end (the empty-set branch); one with an auxiliary variable produces the expected value |
| 3d | **Backend, Phase 8**: GraphQL fields/arguments + M4 permission `Action` | 3c live | The new fields resolve; the permission exists and is granted to nobody |
| 4 | **Frontend**, the old branch removed | 3d live in the target environment | The authoring screens work; the tolerance branch is gone and nothing regressed |
| 5 | Permission granted per account (§12.9) | 4 live | The feature is reachable for that account only |

**The ordering constraint that is not negotiable**: 3d must not precede the frontend's ability to
send the new argument, and the frontend must not *require* the new field before 3d. That is the whole
content of the engineer's step (2), and §12.7 is where it is settled.

### 12.3 Environment progression

`app` has one deploy workflow per environment, each `workflow_dispatch` with no inputs, each
deploying that environment's current `:latest` (`DEPLOY-REFERENCE.md:80-88`):

| Environment | Build branch | Command | Productive? |
|---|---|---|---|
| `beta-001` | `develop` | `gh workflow run deploy-beta-001.yaml -R 4shark/app` | no |
| `demo-001` | `master` | `gh workflow run deploy-demo-001.yaml -R 4shark/app` | no |
| `shared-001` | `master` | `gh workflow run deploy-shared-001.yaml -R 4shark/app` | **yes** |
| `atento-001` | `master` | `gh workflow run deploy-atento-001.yaml -R 4shark/app` | **yes** |

`beta-001` builds from `develop`, so it is where every backend step is validated first, before the
change reaches `master` and therefore the other three. Validation of the full sequence — a real
incentive with an output binding, a real plan, a real commission run — belongs on `beta-001`, and
`demo-001` is the second non-productive gate.

**The two productive environments are gated.** `DEPLOY-REFERENCE.md:98` is explicit that this is
enforced rather than advisory:

> **This is enforced, not trusted:** `validate-productive-deploy.sh` (PreToolUse) blocks a `deploy-shared-001` / `deploy-atento-001` command unless a GO from the check is on record for that stack within the last 5 minutes

so each productive step is `bash ~/.claude/scripts/sidekiq-queue-check.sh --stack <stack>` followed
immediately by the deploy, as one motion. `beta-001` and `demo-001` are never gated.

**Every backend step in §12.2 runs in all four environments** — the sequence is per-environment, not
global. Two consequences worth stating in the plan: the productive gate multiplies by the number of
backend steps (a four-step backend rollout is eight gated commands across the two productive
stacks), and `atento-001` additionally deploys a payroll worker on `sa-east-1` Fargate
(`DEPLOY-REFERENCE.md:87`), which this feature does not touch but which shares the deploy.

### 12.4 The migrations, relative to the deploys — the expand/contract test

**The test is concrete, not abstract.** The migration runs on the *new* image while every serving
container is still the *old* image. In `app/.github/workflows/deploy-shared-001.yaml` the
`prepare-and-migrate` job (`:371`) builds and pushes the image (`:384`, `image-tag: latest` at
`:396`) and then runs `bin/rails db:migrate` (`:403`, `:458`), while the job that activates the new
code depends on it and runs later (`:616` `# DEPLOY WEB`, `:621` `needs: [sidekiq-quiet-mode, prepare-and-migrate]`).
So between those two points the schema is new and the code is old.

`strong_migrations` is active with default checks — `Gemfile:78`, and the initializer is two lines
(`StrongMigrations.auto_analyze = true`), with no `start_after` and nothing disabled.

| Migration | Safe against the OLD code still serving? | Reasoning | What `strong_migrations` requires |
|---|---|---|---|
| **M1** `role` on `incentive_variables` | **Only with a default.** | Old code runs `incentive_variables.create(variable_id: variable.id)` (`app/models/incentive.rb:156,160,164,168`) with no `role`. A `NOT NULL` column with no default makes every incentive save fail for the whole window. A column with a default (or nullable) is transparent. | Adding a column with a default is safe on modern Postgres; the check to expect is on backfilling, which is why the default is the cheaper shape (§7) |
| **M2** output reference on `rules` | **Yes.** | Nullable, unread by old code. | `add_reference` is flagged — the repo's own pattern wraps it: `safety_assured { add_reference :plan_statement_portable_batches, :plan, foreign_key: true, index: true, null: true }` (`db/migrate/20260722215726_...rb:5`) |
| **M3** unique index on `(incentive_id, variable_id, role)` | **Yes, if M1's default is in place first.** | Old code creates rows that all carry the default role, and `update_variables` rebuilds with `delete_all` first, so no duplicate arises. **One interaction to check**: the ranking branch uses `incentive_variables.find_or_create_by(variable_id: variable.id)` (`app/models/incentive.rb:172`) with no role scope — once roles exist, that could find an output row and skip creating the input row. That is a code concern for Phase 3, not a migration one, but it is where the index would surface it. | `disable_ddl_transaction!` + `algorithm: :concurrently`, per `db/migrate/20260729113429_...rb:2-11` and mechanically enforced by `validate-concurrent-index-migration.sh` |
| **M4** the `Action` row | **Yes.** | Inserting a row into `actions` changes no old-code behaviour; nothing reads the key until Phase 8 code is live. | Not a schema change. **But it is not idempotent** — `Action.create!` raises on a re-run, so it must not be re-applied |

**Nothing here needs splitting**, provided M1 carries a default. That single choice is what makes the
whole schema half backward-compatible with the running code — which is the expand half of
expand/contract, and there is no contract half in this feature (nothing is dropped or rewritten).

### 12.5 The `Computation` counter with a commission in flight

This was flagged as the sharpest risk. Working it out from the code changes the answer.

**The key does not change.** `Plan#computation` is `Computation.new("plan_#{id}")`
(`app/models/plan.rb:166-168`) and the Redis keys are `queue:plan_<id>` / `executions:plan_<id>`
(`app/models/computation.rb:48-54`). Nothing in this feature touches the derivation, so the first
and most dangerous phasing trigger in `DEPLOYMENT-STRATEGY.md:145` — *"The `Computation` key
derivation changes ... the old counters are orphaned and the chain stalls"* — **does not fire**.

**The enqueued job's argument shape does not change either.** The new stage is a new class with its
own signature; the existing `(commission_id, user_commission_id, rule_id, partial)` tuples are
untouched. So the second trigger does not fire.

**Whether a non-idempotent step is introduced is exactly Decision 5.** Option 2A's
recompute-from-commissionings is idempotent by construction; Option 2B is idempotent only if the
recompute genuinely re-reads. So the third trigger is *decided by the engineer*, not by the rollout.

**What actually happens to an in-flight commission**, step by step:

The successor of each stage is resolved at execution time, not carried in the payload — every
enqueue names the next class inline (`app/workers/indicator_incentive/finalizer.rb:22`:
`Ranking::Producer.with_company_id(...).dynamic_perform_async(commission_id, partial)`), and the
pushed payload carries only class, args and queue (`app/workers/tenant_worker.rb:51-58`). So a job
sitting in Redis when the new image starts serving runs the **new** body of its own class and
enqueues the **new** successor. Under Option 2A, a chain that was between the indicator stage and
ranking when the deploy landed picks up the auxiliary producer on its next hop instead of
`Ranking::Producer`. The auxiliary producer increments `queue` by its fan-out and its consumers
increment `executions` by the same amount, so the counters stay balanced and the chain continues.
**It does not orphan and it does not stall.**

**Two caveats, both stated as such.**

First — **this is inference from the code, not an executed test.** The reasoning rests on three read
facts (key derivation unchanged, argument shapes unchanged, successor resolved at execution time),
each cited above. It has not been exercised against a live in-flight commission, and the honest
verification is to run one on `beta-001`: start a commission, deploy mid-chain, confirm it completes.

Second — **the counters carry a 12-hour TTL.** `Counter::DEFAULT_EXPIRATION_TIME = 12.hours.to_i`
(`app/models/counter.rb:4`), refreshed on every increment, and `Counter#value` reads
`connection.get(@key).to_i` (`:48-52`) — so once both keys expire, `done?` evaluates `0 == 0` and
returns **true** even though the work never finished. A deploy window is minutes, so this is not
reachable during a deploy; it matters because a chain that *does* stall for more than 12 hours cannot
simply be resumed — the counters are gone and `done?` lies. Any manual recovery must reprocess, not
resume.

**Do in-flight commissions have to be drained first?** On this evidence, no — nothing forces it. What
does exist is the productive queue gate (§12.3), which is about Redis memory pressure during the
TSTP quiet window rather than about counter correctness. If the engineer wants the stronger
guarantee anyway, the observation is the same one the gate uses:
`bash ~/.claude/scripts/sidekiq-queue-check.sh --stack <stack>` returns GO only when nothing was
executing across the sampling window.

### 12.6 Terraform — verified, not assumed

**No Terraform change is required if the new workers reuse an existing `base_queue_name`. If they
declare a new one, the change is still zero Terraform — but two app-side config files, five times
each.**

The evidence is that Terraform declares a worker service by its **config file path**, never by a
queue list (`terraform/app-shared-001/terraform.tfvars:110`):

```hcl
    command                      = ["bundle", "exec", "sidekiq", "-C", "config/sidekiq_commission_without_deal_indexation.yml"]
```

`grep -rn "sidekiq_commission" terraform` returns twelve hits, all of this shape, across the four app
stacks. **No Terraform file anywhere enumerates a Sidekiq queue name.**

Autoscaling is per **process**, not per queue — the Lambda receives
`PROCESS_NAME = "worker_${replace(key, "-", "_")}"` and a `METRICS_ENDPOINT` pointing at the app's own
HireFire endpoint (`terraform/app-shared-001/lambda.tf:48-58`), where the keys are `commission`,
`user`, `system` plus per-variant entries (`:16-20`, `:29-31`).

So a new queue inside the existing commission process needs:

1. **`config/sidekiq_commission*.yml` — five files.** The queue must be listed or the fleet never
   polls it. The base file lists 24 queues (`config/sidekiq_commission.yml:5-28`); each variant
   repeats them with a suffix (`config/sidekiq_commission_tiger_shark.yml:5-28`).
2. **`config/initializers/hire_fire.rb` — five dyno blocks.** `:worker_commission` (36),
   `:worker_commission_white_shark` (61), `:worker_commission_tiger_shark` (86),
   `:worker_commission_without_deal_indexation` (111), `:worker_payroll_tiger_shark` (139).

**A queue in the YAML but not in HireFire is polled but invisible to autoscaling** — depth grows and
no capacity is added, silently. That is not hypothetical: `sidekiq_commission.yml` lists
`user_payment_type_ranking_caching` (19), `commission_ranking_caching` (20),
`user_payment_type_redemption_caching` (26) and `commission_redemption_caching` (27), and the
`:worker_commission` HireFire block lists none of the four. The drift exists today.

**The ordering, if a new queue is taken**: both config files are part of the application image, so
they ship with the backend deploy that introduces the workers — there is no separate infrastructure
step and nothing to apply beforehand. The premise in the brief that a Terraform apply would have to
precede the backend deploy does not hold here, because the queue is not declared in Terraform.

**Not researched**: the autoscaling Lambda's own source (the `worker-commission-autoscaling`
package) was not read — only the environment Terraform supplies it. Whether it does anything
per-queue beyond consuming the HireFire endpoint is unverified.

### 12.7 GraphQL contract compatibility — field by field

Two directions must be graded separately, and only one of them is the usual "additive is safe" case.

**Direction A — old frontend against new backend.** Additive and safe, for every item:

| Change | Breaking for an un-updated client? | Why |
|---|---|---|
| New nullable field on `RuleGraphqlType` | No | The old client's mutation selects only `{ id }` (`indicator-incentive-create.component.ts:188-190`); an unselected field is never returned |
| New **optional** argument on `RuleInputGraphqlType` | No | The old client builds the rule input field by field (`:153-165`) and simply omits it |
| New nullable `role` field on `IncentiveVariableGraphqlType` | No | Same — unselected |
| Fourth value in `variables.type` | No | `field :type, String, null: false` (`variable_graphql_type.rb:33`) is a `String`, not an enum, so a new value is just another string. **This is why the type is not a breaking change** — had it been a GraphQL enum, adding a value would be a client-visible schema change |
| Extending the mutations' `%i[...]` rule allow-lists | No | Widening what is permitted never rejects an existing payload |

**The one shape that WOULD break it**: a `required: true` argument on `RuleInputGraphqlType`. Every
argument there is `required: false` today (`rule_input_graphql_type.rb:4-8`), and the old client's
mutation declares the input type by name (`$rules: [RuleInputGraphql!]`), so a newly-required
argument fails validation on every existing frontend. **The type name must also not change**, for the
same reason.

**Direction B — new frontend against old backend. This is the hard one, and it is what the
engineer's step (2) is about.** A GraphQL query that selects a field the server does not define is
rejected at validation, and the frontend's Apollo clients are configured with `errorPolicy: 'none'`
(`indicator-incentive-create.service.ts:15-28`, and the identical block in
`indicator-incentive-permissions.service.ts:16-29`) — so a partial result is discarded and the whole
operation fails. **A new frontend that simply adds `outputVariableId` to its rule query breaks the
entire incentive screen against an old backend, not just that field.**

So "the frontend tolerates both" is not automatic; it has to be built. Three mechanisms, none chosen
here (Decision 13):

- **Inert release.** The new frontend ships the code but never sends or selects the new fields —
  the query text is unchanged until step 4. Cheapest and safest, and it makes step 1 a genuinely
  no-op release. The cost is that step 1 delivers nothing observable, which raises the question in
  §12.10 of whether it earns its place.
- **Branch on the permission the front already fetches.** `IndicatorIncentivePermissionsService`
  already queries `incentivePermissions { userId permissions }`
  (`indicator-incentive-permissions.service.ts:41-48`), and the new permission (§12.9) does not exist
  until the backend deploy. So the front can hold two query strings and pick by whether the
  permission is present. This makes step (2) literally true — one build tolerating both backends —
  and it reuses machinery that is already there. The cost is two query strings per affected screen
  for the duration, and the correctness depends on the permission being a faithful proxy for "the
  backend has the field", which it is only if M4 ships in the same deploy as the fields.
- **Schema introspection at boot.** Ask the server what it supports. The most general, and the one
  with no existing precedent in this repository — nothing found in `app-webclient` does this.

### 12.8 Rollback, per step, and the point of no return

| Step | Rollback | Reversible? |
|---|---|---|
| 1 — frontend, inert | Netlify redeploy of the previous build, per site | Yes, fully |
| 3a — schema + registration | Redeploy the previous image. The columns stay (rolling back a migration is not part of the deploy flow), which is harmless because the old code never reads them. M1's default is what keeps the old code writing valid rows | Yes — code reverts, schema stays and is inert |
| 3b — validators + plan validation | Redeploy the previous image. Plans that were rejected by the new validation were never saved, so nothing to undo | Yes |
| 3c — materialization + read path | Redeploy the previous image. Auxiliary rows already written become unread; if they live in `aggregated_modifiers` the next reprocess purges them (`aggregated_indicator/purge/consumer.rb:17-21`) | Yes, with the caveat that any commission calculated *with* auxiliary values keeps those values until reprocessed |
| 3d — GraphQL + permission | Redeploy the previous image. The `Action` row stays; it is inert while nobody holds the permission | Yes |
| 4 — frontend, old branch removed | Netlify redeploy of the step-1 build | Yes |
| 5 — permission granted | Revoke the permission | Yes |

**Is there a point of no return?** On this evidence, **no** — nothing in the feature drops a column,
rewrites data, or changes an existing cross-service contract. Two things are worth naming as the
closest candidates:

- **A commission already calculated with auxiliary values.** Reverting the code does not restore the
  previous numbers; it stops producing new ones. The stored `commissionings` are unchanged either
  way (the auxiliary value is derived from them, not the reverse), so a reprocess under the old code
  reproduces the old result. That is a recovery path, not an irreversibility — but it is a
  *reprocess*, which on a productive stack is not free.
- **M4's `Action.create!` is not idempotent.** Re-applying it raises. That is a re-run hazard, not a
  rollback hazard.

**Where old frontend and new backend cannot coexist**: nowhere, per §12.7 Direction A. The
asymmetric direction is new frontend against old backend, and that is the one step 1 must be built
to survive.

### 12.9 Feature flag / release toggle

`DEPLOYMENT-STRATEGY.md:163` states the mechanism:

> **The permission system IS 4Shark's release toggle.** ... there is no client-facing screen to manage permissions, so 4Shark controls it manually and, by default, grants the permission to no one until the feature is proven.

The mechanics, read from the code:

A permission is an `Action` row plus a `Permission` join to a role. New actions are created **by a
data migration** — `db/migrate/20260729113439_user_update_document_actions.rb:5`:

```ruby
    Action.create!(key: 'user_update_document_listing', level: 'module', resource: 'user_update_document')
```

and the key is added to the hardcoded `MODULE_KEYS` list in
`app/workers/company/admin/processor.rb:16-52` (where `incentive_clone` sits at line 31), which the
processor iterates to grant to the Admin role (`:77-83`). The lookup is `Action.get(key: action_key)`,
which resolves through `ApplicationRecord.get_id` (`app/models/application_record.rb:134-140`) ending
in `find_by!` — **so a key listed in `MODULE_KEYS` with no `Action` row raises `RecordNotFound` and
the processor dies.** M4 must therefore land in the same deploy as the `MODULE_KEYS` entry, never
after it.

The gate itself follows the shape of every sibling in `IncentivePolicy`
(`app/policies/incentive_policy.rb:8-10`):

```ruby
  def create?
    role.permission?('incentive_creation') || user.permission?('incentive_creation')
  end
```

**Does the flag change the sequencing above?** It does one thing: it makes steps 3a-3d safe to ship
with nobody able to reach the feature, which is what lets them be separate deploys without any
intermediate state being user-visible. It does **not** remove the §12.7 Direction-B problem — a
frontend selecting a field the backend lacks fails at GraphQL validation, before any permission is
consulted. The permission gates *reachability*, not *schema compatibility*.

One boundary worth recording: because `IncentivePolicy#update?` returns false when
`record.plans.any?` (§6), granting the permission cannot retroactively change any incentive already
in a plan. The blast radius of enabling the flag for an account is limited to incentives authored
after it.

### 12.10 The deploy shape — the engineer's sequence versus the shorter one

Per `~/.claude/docs/DEPLOYMENT-STRATEGY.md:174`, a deploy is the engineer's decision and this
document does not pick. Both paths, with the condition that decides.

**Path A — the engineer's four-step sequence, with the backend split into 3a-3d.**

Pros: every step is independently revertible; the empty-set branch of the new stage runs in
production before any auxiliary variable exists; each backend phase is validated on `beta-001` before
the next is written. Cons: four backend deploys × four environments, with the productive gate on two
of them; two frontend releases across N Netlify sites; and step 1 delivers nothing observable if
Decision 13 lands on "inert release". Risk: low per step, and the intermediate states are all no-ops
by construction.

**Path B — the shorter sequence the evidence supports: one backend deploy, then one frontend
release.**

The evidence that permits it: none of the three phasing triggers in `DEPLOYMENT-STRATEGY.md:143-147`
fires (§12.5 — the `Computation` key is unchanged, argument shapes are unchanged, and idempotency is
Decision 5's to preserve); every schema change is additive and backward-compatible with the running
old code provided M1 carries a default (§12.4); the permission keeps the whole feature unreachable
until it is granted (§12.9); and old-frontend-against-new-backend is safe in every direction graded
in §12.7. Under Path B the frontend goes **second**, which also dissolves the Direction-B problem
entirely — there is never a new frontend facing an old backend, so the tolerance mechanism of
Decision 13 is not needed at all.

Pros: one gated productive command per stack instead of four; no dual-query-string period; no
Decision 13. Cons: a larger diff arriving at once, so a defect is isolated by bisecting the phases
rather than observed per deploy; and the empty-set branch of the new stage meets production traffic
in the same deploy as everything else.

**The condition that decides between them.** Path B is available *because* the permission gate makes
the backend inert and *because* the frontend goes last. It stops being available if either premise
breaks: if the frontend must ship first for a reason outside this feature (a shared release train
across the 38 sites, for instance — see the unresearched branch question in §12.1), then Direction B
of §12.7 is live and Path A with Decision 13 is the only sequence that satisfies it. Equally, if
Decision 5 lands on a materialization that is not idempotent under retry, the third phasing trigger
fires and the change must be phased regardless of everything else.

**Not researched**: whether the 38 Netlify sites can be released independently. If they cannot, the
cost of the two frontend releases in Path A is 38 builds each rather than one, and that changes the
comparison materially.

---

## Decisions

Resolved under the ladder in `DECISION-AUTHORITY.md` — the engineer's instruction, then 4Shark's documented conventions and the surrounding code, then community practice. Each row records what was decided and the source that decided it. None of these were escalated; every one is visible and correctable at PR review.

| # | Decision | Resolved as | Decided by |
|---|---|---|---|
| 1 | `incentive_variables.role` storage | Integer column with `enumerize`, default `input` | House pattern — `Variable#calculation` (`variable.rb:66`) and `Plan#status` (`plan.rb:98`) both use `enumerize`. The default is what makes M1 transparent to old code during the migration window (§12.4) |
| 2 | The `Rule` output association name | `belongs_to :output_variable, class_name: 'Variable', optional: true` | § Association Naming — `output` distinguishes direction rather than restating the owner, so the stutter test keeps it. `optional: true` plus manual validation is the house rule |
| 3 | Which stages write and which read | Writes from the indicator stage onward; reads in ranking, limiter and redemption. The deal stage neither writes nor reads | § Scope Discipline (the minimum that satisfies the request) plus SPIKE §5, which records that this *"makes the machinery substantially smaller and still covers the Colombia case"*. Avoids the metric-key `select` bypass at `deal_incentive/consumer.rb:31` |
| 4 | Is the binding mandatory per rule | Optional | The engineer's own description — *"ele pode salvar só uma faixa ou ele pode salvar todas"* is impossible if every rule must bind |
| 5 | Materialization placement and storage | Recompute the sum (never `+=`) at commissioning save, stored in `aggregated_modifiers` | The engineer specified the write moment (*"toda vez que criar um commissioning"*); recompute rather than increment is forced by Sidekiq at-least-once (SPIKE §4.2b). `aggregated_modifiers` is already the per-`(user_commission, variable)` store, already purged on reprocess, already on the read path — § No Premature DRY rejects a new table with no benefit yet. **Cost recorded**: N recomputes per user per stage rather than one at the stage boundary |
| 6 | Publish-only vs publish-and-pay | Publish-and-pay only. The rule creates its commissioning exactly as today; publishing is purely additive | § Scope Discipline. Nothing is excluded from any existing sum, `premio_grupo` is untouched, and the payment-type constraint at `commissioning.rb:13,17` is satisfied because the row exists anyway. No per-rule flag until someone asks for one |
| 7 | Do auxiliary variables reach `plan_variables` | Yes, with goal binding suppressed for the type | The only combination that works — the read path in §3 requires them there, and leaving goal binding on would surface them in the goal UI (§5) |
| 8 | Where the stage order lives | Ordered constant `CALCULATION_ORDER` on `Incentive`, plus a spec asserting it matches the enqueue graph | The spec is the sync mechanism the "nothing keeps them in sync" objection asked for. A single ordered constant is the standard shape; the alternative spreads the order across five STI subclasses |
| 9 | Does the incentive CSV import support the binding | No — documented limitation | § Scope Discipline. Not requested, and it changes a customer-facing template (`incentive_document/processor.rb:81-86`) |
| 10 | Deploy shape | Path B — one backend deploy, then one frontend release | `DEPLOYMENT-STRATEGY.md` phases **only** if a trigger fires. The `Computation` key derivation is unchanged (`plan_#{id}`, `plan.rb:166-168`), job argument shapes are unchanged, and decision 5 makes the step idempotent — no trigger fires, so a single backend deploy is legitimate by the framework's own rule. **The act of deploying remains the engineer's** — that is the residue, not the shape |
| 11 | Zero handling | The auxiliary type constrains `default` to zero | Materializing explicit zero rows would write one row per non-firing rule per user for no read benefit (SPIKE §4.3) |
| 12 | The four unscoped reads | Both commission indicator worksheets get `.indicators` on the lookup; `CalendarAudit`'s expected-count query excludes auxiliaries; the variable audit workbook keeps them | Per site, from each site's own purpose. The worksheets already gate on `variables.indicators.exists?` at their line 12 — scoping line 29/36 restores the file's own declared subject. An auxiliary has no integration source, so counting it as "expected" produces a permanent false gap. The audit workbook is a configuration catalog with a type column and already renders blank frequency for deal and easy variables (`variables_work_sheet.rb:15-38`) |
| 13 | How the frontend tolerates both backends | Not applicable — removed | Decision 10 puts the frontend last, so it never faces an old backend and the `errorPolicy: 'none'` problem does not arise |
| 14 | Materialization queue | Reuse the existing commission queue of the stage it hangs off | Zero cost (§12.6), and it avoids the live autoscaling-drift hazard confirmed between `sidekiq_commission.yml:19-27` and `hire_fire.rb` |

### The Netlify question — researched, not a decision

The 38 client sites do **not** version independently. Every one runs the same entry point against the same repository — `build.js` is called by Netlify as `yarn build <project> [overrideSelector]` (`app-webclient/build.js:13-18`), where `project` selects an Angular project carrying that front's colors and assets and the optional second argument layers translation overrides. So a frontend release is **one merge that fans out into 38 builds**, not 38 coordinated releases.

That removes the concern raised against Path A's two frontend releases, and it makes Path B strictly cheaper for the same reason: one merge, one fan-out. Which branch each site tracks still lives in Netlify settings rather than the repository (`netlify.toml` carries no `[context.*]` block), but under Path B that affects only timing, never correctness, because the frontend ships last and never faces an old backend.

### The one thing that is not decided here

Running the deploy. `DECISION-AUTHORITY.md` names an action outside version control as irreducible residue — a PR diff neither shows it nor reverts it. The *shape* is decided above by the documented framework; the *execution* is the engineer's, on their timing, against the productive queue-depth gate.

---

## The `Incentivation` question — resolved, not assumed

The brief flags the engineer's statement *"a gente vai ter que alterar o modelo de incentivation"*
and asks whether the recorded design genuinely requires it.

**Under the design as recorded in SPIKE §4, `Incentivation` needs no change.** The reasoning, with
each fact cited:

- `Incentivation` carries exactly three foreign keys and one validation concern — the payment type
  must belong to the plan's calendar (`app/models/incentivation.rb:4-10, 24-29`). The table is
  `incentive_id`, `payment_type_id`, `plan_id`, timestamps (`db/schema.rb:937-948`).
- The output binding lives on `Rule` (SPIKE §4), so nothing about which variable an incentive writes
  passes through `Incentivation`.
- The registration lives on `incentive_variables` with a `role` (SPIKE §4.6), which hangs off
  `Incentive`, not `Incentivation`.
- The plan validation needs, per plan: each incentive's auxiliary inputs and outputs, and each
  incentive's stage. The first comes from `incentive_variables`; the second from `Incentive#type`.
  The link from plan to incentive is `incentivations.incentive_id`, which already exists and is
  already what `Plan#redemption_incentive_requirements` uses (`app/models/plan.rb:392`,
  `incentive_ids = incentivations.map(&:incentive_id)`).
- The plan roll-up into `plan_variables` reads `incentive_variables` through a join that does not
  touch `Incentivation` (`app/models/plan.rb:440-444`).

**Where the sentence most likely comes from.** SPIKE §4 records that the binding was moved:
*"Revised from an earlier draft that put it on the `Incentivation`"* (line 124). Under that earlier
draft `Incentivation` would have gained the output-variable column, which is exactly the change the
sentence describes. The spike's stated reason for moving it is that *"The client's actual request is
the value of one specific faixa, and the faixa is the `Rule`; binding at incentive or incentivation
level cannot express it"*.

**The one thread that could still reach `Incentivation`, if Decision 6 goes a particular way.**
`Incentivation` is where the payment type binds, and a commissioning row cannot exist without one
(`app/models/commissioning.rb:13,17`). If publish-only rules must produce a commissioning row that
does not pay, the payment type for that row still resolves through `Incentivation`
(`app/workers/limiter_incentive/consumer.rb:18-23`), and marking such a row as non-paying is a
`Commissioning` concern rather than an `Incentivation` one. No change to `Incentivation` follows even
then — but the engineer should confirm the sentence referred to the superseded draft rather than to
something the spike does not capture.

**Not researched**: whether the two proposal decks named in SPIKE §6 ("Not consulted") describe an
incentivation-level binding. Neither file is on this machine, so the interface proposal remains
unreviewed — as the spike itself states.

---

## Open questions for the engineer

1. Every row of the decision table above, but especially Decisions 3, 5 and 6 — each one changes the
   size of the work, not just its shape. Decision 5 additionally decides whether the third phasing
   trigger fires, so it feeds Decision 10.
2. The Blocker (rule syntax validators) is a prerequisite the spike does not name. Confirm it belongs
   in this scope rather than as a separate change.
3. Does the sentence about altering `Incentivation` refer to the superseded draft, or to something
   the spike does not capture?
4. `/api/v3/` does not expose incentives, rules or plans. Confirm the integrator is genuinely not an
   authoring path for these, so the plan does not carry a phantom compatibility risk.
5. Is the statement / per-incentive breakdown (SPIKE §5) in this scope or a separate deliverable?
   It is the piece the spike ties to the legal-traceability requirement.
6. The two proposal decks remain unreviewed (SPIKE §6). If the UI proposal constrains the authoring
   surface in §8, it should be read before Phase 9 is sized.
7. **Can the 38 `app-webclient` Netlify sites be released independently, and do they all track the
   same branch?** (§12.1.) This is unresearched and it changes the cost of the two frontend releases
   in Path A by a factor of 38. It also decides whether Path B's "frontend last" is even available.
8. Should the in-flight-commission reasoning in §12.5 be confirmed by an actual `beta-001` test
   (start a commission, deploy mid-chain, confirm completion) before the first productive deploy?
   The reasoning is inference from three read facts, not an executed result.

---

## Sources

**Codebase** (`~/Projects/4Shark/app`, `develop`) — every file below was opened and the cited lines
read:

- Models: `variable.rb`, `rule.rb`, `incentive.rb`, `incentivation.rb`, `incentive_variable.rb`,
  `plan.rb`, `plan_variable.rb`, `commissioning.rb`, `limiter_commissioning.rb`,
  `indicator_commissioning.rb`, `aggregated_indicator.rb`, `computation.rb`, `counter.rb`,
  `application_record.rb`, `easy_variable.rb`, `indicator_variable.rb`, `deal_variable.rb`,
  `variable_track.rb`, `variable_track_collection.rb`, `tenant_worker/queue.rb`
- Services: `commission/indicator_options_processor.rb`, `commission/limiter_options_processor.rb`,
  `commission/redemption_options_processor.rb`
- Workers: the full commission chain (41 enqueue sites, tabulated in
  `auxiliary-variables_pipeline_2.md`), plus `tenant_worker.rb`, `incentive_document/processor.rb`,
  `plan_document/consumer.rb`, `plan_slice/processor.rb`, `calendar_audit/producer.rb`,
  `goal_dataset/migration/producer.rb`, `indicator_dataset/producer.rb`,
  `commission_goal/producer.rb`, `company/admin/processor.rb`
- Policies: `incentive_policy.rb`
- GraphQL: `variable_graphql_type.rb`, `rule_graphql_type.rb`, `rule_input_graphql_type.rb`,
  `incentive_graphql_type.rb`, `incentive_variable_graphql_type.rb`,
  `plan_variable_input_graphql_type.rb`, `variable_graphql_resolver.rb`,
  `create_incentive_graphql_mutation.rb`, `update_incentive_graphql_mutation.rb`,
  `create_variable_graphql_mutation.rb`, `finish_plan_graphql_mutation.rb`
- Config: `Gemfile`, `config/initializers/strong_migrations.rb`, `config/initializers/hire_fire.rb`,
  `config/sidekiq_commission.yml`, `config/sidekiq_commission_tiger_shark.yml`
- Workflow: `.github/workflows/deploy-shared-001.yaml` (job order and migration step)
- Schema: `db/schema.rb` lines 80-89, 446-464, 937-955, 1617-1624, 1951-1962, 2551-2575
- Migrations (as pattern references): `20260729113420_create_user_update_document_enrollments.rb`,
  `20260722215726_add_plan_id_to_plan_statement_portable_batches.rb`,
  `20260729113429_add_unique_index_to_user_update_document_enrollments.rb`,
  `20260729113439_user_update_document_actions.rb`
- Specs and factories: `spec/models/variable_spec.rb`, `incentive_variable_spec.rb`,
  `plan_variable_spec.rb`; `spec/factories/variables.rb`, `rules.rb`, `incentive_variables.rb`

**`app-webclient`**: `netlify.toml`, `src/environments/` (40 entries), `src/app/rule/` (model +
create/update builders), `src/app/indicator-incentives/create/` (form builder, service, component —
the inline GraphQL mutation and the Apollo `errorPolicy` block),
`src/app/indicator-incentives/indicator-incentive-permissions.service.ts`,
`src/app/variable/create/variable-create-form-builder.service.ts`,
`src/app/plan/create/plan-create-form-builder.service.ts`, and the per-incentive-type module listings

**`terraform`**: `app-shared-001/terraform.tfvars` (worker service definitions),
`app-shared-001/lambda.tf` (autoscaling lambdas, env vars, ASG map),
`app-shared-001/config.yml` (commission-balancing service map)

**Gem**: `dentaku 3.5.7` (`Gemfile.lock:180`) — `lib/dentaku.rb:63-69`, `lib/dentaku/exceptions.rb:6`

**4Shark documentation**: `~/.claude/CLAUDE.md` (§ Optional belongs_to, § Association Naming,
§ Rails Migrations, § Data Processing, § Testing Policy, § Decision Authority, § Deployment
Strategy), `~/.claude/docs/RAILS-MIGRATIONS.md`, `~/.claude/docs/DATA-PROCESSING.md`,
`~/.claude/docs/DATA-ACCESS.md`, `~/.claude/docs/DEPLOYMENT-STRATEGY.md` (read in full),
`~/.claude/docs/DEPLOY-REFERENCE.md` (read in full), `~/.claude/docs/TESTING-PHILOSOPHY.md`,
`~/.claude/docs/RSPEC-CONVENTIONS.md`, `~/Projects/4Shark/app/CLAUDE.md`

**Auxiliary files**: `auxiliary-variables_call-sites_1.md`, `auxiliary-variables_pipeline_2.md`,
`auxiliary-variables_rollout_3.md`

**Not researched / could not be verified**:

- The two proposal decks named in SPIKE §6 — neither is on this machine.
- Statement/display behaviour — out of scope per § Scope.
- `app-sdk-advpl`, `app-sdk-dotnet`, `app-mobileclient` — not opened (§12.1).
- The autoscaling Lambda's own source package (§12.6).
- Whether the 38 Netlify sites release independently (§12.1, open question 7).
- **`app/docs/architecture/PARALLEL_PROCESSING.md` does not exist.** `DEPLOYMENT-STRATEGY.md` cites
  it four times with line numbers (`:39-42`, `:76-79`, `:88-89`) and `app/CLAUDE.md` links the
  `dot-claude` `DATA-PROCESSING.md` in its place; `ls docs/architecture` returns eight files and that
  is not among them. Those citations could not be verified, so every `Computation` fact in §12.5 was
  read from `app/models/computation.rb` and `app/models/counter.rb` directly instead.
