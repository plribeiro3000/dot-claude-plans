# SPIKE — Reusing one incentive's calculated result inside another incentive's rule

**Status**: research complete, no implementation
**Date**: 2026-07-29 (v2 — v1 framed the problem wrongly; see §0)
**Trigger**: Atento Colombia asked for incentive rules whose result depends on the *calculated result* of another incentive. Santiago Velasquez prepared a proposal (Slack DM, 2026-07-07 and 2026-07-17) naming the concept **"variáveis calculadas"**.
**Goal**: settle the shape of the solution at a level presentable to the client, without committing to implementation.

**Language classification**: internal engineering document → English (`LANGUAGE-POLICY.md`, category 1).

---

## 0. What v1 of this spike got wrong

v1 answered "where does the value come from". That is not the problem. Two corrections, both from the engineer:

1. **"Sum the previous stages" is not the request.** What exists today is the *accumulated* result of the previous step — the user's total and the group's total. What was asked is the value of **one single rule, one faixa**, stored and reusable anywhere later. Those are different capabilities, and v1 conflated them.

2. **The plan-save validation is not a solution to the coupling — it IS the coupling.** v1 recommended "publish into a variable, and validate at plan save that a publisher exists in an earlier stage", presenting the validation as the thing that made the option safe. Requiring the plan to contain the publisher, in the right stage, is precisely what binds one incentive to another. v1 sold the coupling as its own fix.

The real problem, in the engineer's words: *"O problema é a gente gerar dependência de um incentivo limitador para um incentivo indicador. É esse o problema! Se a gente cria isso, fica ruim!"*

---

## 1. The invariant that breaks

Today an incentive is a **self-contained, plan-independent artifact**. Its rules reference:

- company-level variables fed by the integration (`app/services/commission/indicator_options_processor.rb:41-46`)
- values the platform always supplies — `premio`/`premium`, `meta`/`goal`, `orcamento`/`budget`, `premio_grupo`/`group_premium` (`app/services/commission/limiter_options_processor.rb:44-55`)

None of that depends on which *other* incentives are in the plan. That is why the same incentive is reused across many plans through `incentivations` without further thought.

The moment a limiter's formula says "the result of incentive ABC", that limiter is no longer self-contained: it is only correct inside a plan that also contains ABC, in an earlier stage. It stops being a piece that fits anywhere and becomes a piece that only fits alongside another one.

**This holds regardless of the syntax used.** A custom Dentaku function naming the incentive and a variable published by that incentive create the same coupling; only the spelling differs.

So the design question is not "how to write the reference". It is: **what can a formula name that exists independently of which incentives are in the plan?**

---

## 2. Facts

### 2.1 The per-faixa value is already stored, uniquely addressable, and needs no new table

`db/schema.rb:446-464`:

```ruby
create_table "commissionings", id: :serial, force: :cascade do |t|
  t.integer  "deal_id"
  t.integer  "rule_id"
  t.integer  "user_commission_id"
  t.decimal  "value", precision: 28, scale: 6, default: "0.0"
  t.index ["rule_id", "user_commission_id"],
          name: "commissionings_unique_period_index",
          unique: true, where: "(deal_id IS NULL)"
  t.index ["user_commission_id", "rule_id", "deal_id"],
          name: "commissionings_unique_deal_index",
          unique: true, where: "(deal_id IS NOT NULL)"
end
```

For indicator, ranking, limiter and redemption incentives there is **exactly one row per (rule, user)** carrying that faixa's value. "How much did this person earn on this faixa" is a query, not a storage feature. This fully answers Santiago's concern about data volume: there is no new data to store.

Only the deal (transactional) stage is finer — one row per deal — so "the faixa's value" there is a sum over deals.

The per-incentive breakdown the engineer wants to be able to state — *"ganhou R$ 300 nesse incentivo, R$ 200 nesse e perdeu R$ 100 nesse outro, resultado R$ 400"* — follows directly by grouping those rows on `rules.incentive_id` (`Commissioning belongs_to :rule` at `app/models/commissioning.rb:8`, `Rule belongs_to :incentive` at `app/models/rule.rb:9`).

### 2.2 A faixa that yielded zero has no row

`app/workers/indicator_incentive/consumer.rb:41` and `app/workers/limiter_incentive/consumer.rb:40` both persist only under `if value.present? && value.nonzero?`. So the absence of a row means "evaluated to zero", not "was not calculated". Irrelevant for display; decisive for a formula — reading a faixa that did not fire must yield zero, never an error.

### 2.3 Rules of the same incentive also run in parallel

`app/workers/indicator_incentive/producer.rb:22`:

```ruby
combinations = user_commission_ids.product(rule_ids)
```

`rule_ids` covers every rule of every indicator incentive of the plan, in one flat fan-out. So putting all indicators inside a single incentive does **not** let one faixa see another's result. What that workaround does achieve is different: it removes indicator→indicator dependency altogether, because downstream stages then read a single number — the incentive's total. Worth confirming with the engineer that this is what was meant, since it is the difference between "solves it for the client" and "does not".

### 2.4 A second, already-aggregated breakdown exists: per payment type

`db/schema.rb:2381-2399` — `user_payment_type_commissions` is unique per `(user_commission, payment_type)` and already carries the per-stage split: `deal_money`, `modifier_money` (indicator stage), `ranking_money`, `limiter_money`, `redemption_money`, plus the points mirrors.

This matters because **payment type is the only thing both sides already name without knowing about each other.** It is a calendar-level entity, and every `Incentivation` must bind its incentive to one of the calendar's payment types (`app/models/incentivation.rb:24-29`).

### 2.5 A dangling reference does not raise — it silently returns zero

`app/models/rule.rb:47-51` rescues `Dentaku::Error`, `NameError`, `NoMethodError`, `ArgumentError` and returns `0`; every consumer calls `calculate`, never `calculate!`. Relevant to any option that relies on naming: without validation the failure mode is a wrong payroll, not an exception.

---

## 3. Options, on the coupling axis

Each option differs in three things: **what the formula names**, **what happens when that thing is absent from the plan**, and **whether the incentive stays reusable on its own**.

There is no option that delivers formula-level reuse with zero coupling. The choice is which kind of dependency to accept, and whether the system enforces it or merely reflects it in the data.

| Option | Formula names | If absent from the plan | Incentive reusable alone? | Coupling |
|---|---|---|---|---|
| A — function by incentive | the incentive | plan rejected, or silent zero | no | hard |
| B — published variable + validation | the variable | plan will not save | no | hard |
| C — published variable, no validation | the variable | falls back to the variable's `default` | yes | data-level |
| D — by payment type | the payment type | zero (empty bucket) | yes | none |
| E — statement only, no formula reuse | nothing | — | yes | none |

**A — Dentaku function by incentive reference.** Literally the request; `Incentive#reference` already exists and is unique per company (`app/models/incentive.rb:13,48,82-99`). Rejected: it is exactly the dependency the engineer refused; `reference` is company-scoped while the value is plan-scoped; and validating it requires walking the Dentaku AST of every rule at plan save.

**B — published variable with plan-save validation.** What v1 recommended. Rejected per §0: the validation is the coupling, and it breaks cross-plan reuse of the incentive.

**C — published variable, no validation.** Same publication mechanism, but nothing is enforced. `Variable` already requires a `default` (`app/models/variable.rb:35`), and `IndicatorOptionsProcessor#aggregated_indicator_value` already falls back to `variable.format_default` when no value exists for the user. So a reader without a publisher reads the default and the plan still runs. The incentive stays self-contained; the dependency is data-level, not structural. Cost: a client who forgets the publisher gets a silently defaulted number — mitigable with a warning at plan finalization and by showing the value per user in the statement, never with a hard validation.

**D — by payment type.** The formula names a payment bucket ("the amount accumulated in Bônus Qualidade"), not an incentive. The only option where the named thing exists independently of the plan's incentive composition, and the aggregate is already stored (§2.4). Cost: granularity is the bucket — two incentives sharing a payment type are indistinguishable — and it pushes the client to create payment types purely to separate calculation, which pollutes the payment file since payment types drive exportation.

**E — split transparency from reuse.** Ship the per-incentive / per-faixa breakdown in the statement first: pure read of §2.1, no new data, no naming inside any formula, no coupling. It delivers exactly the sentence the engineer wants to be able to say, and settles the legal-traceability requirement (Paulo, Slack `1783436330.220589`: *"para ter validade legal e juridica tambem"*) before any architectural decision is taken.

---

## 4. Chosen direction — the auxiliary variable (engineer's call, 2026-07-29)

Option C, with two refinements that resolve the objection to v1's option B:

**The output binding lives on the `Rule` — the faixa — declared when the incentive is created.** Revised from an earlier draft that put it on the `Incentivation`. The client's actual request is the value of *one specific faixa*, and the faixa is the `Rule`; binding at incentive or incentivation level cannot express it. Each rule optionally declares the auxiliary variable its value is written to, so the user can bind one faixa, several, or all of them to the same variable.

This does not reintroduce coupling on the writer side: declaring "I write into X" is an output declaration, and the writing incentive remains self-contained. The reader-side dependency is unchanged and is still validated at plan composition (§4.4 below).

**Accepted trade-off of binding on the `Rule`:** the declaration travels with the incentive, so the same incentive always writes to the same variable in every plan it enters. Binding on the `Incentivation` would have allowed per-plan retargeting. The variable name is semantic, so stability is the desired behaviour, and the gain is that plan composition has nothing to fill in — the names arrive already declared.

**A new variable type — auxiliary/support — sitting alongside the existing three.** `Variable::TYPES` is currently `%w[DealVariable IndicatorVariable EasyVariable]` (`app/models/variable.rb:4`); this adds a fourth. It is not fed by the integration: the commission pipeline computes it. Values land in `AggregatedIndicator` (`aggregated_modifiers`), already unique per `(user_commission, variable)` and already the source the options processors read.

Name collision is handled by an index that already exists — `index_variables_on_company_id_and_key`, unique (`db/schema.rb:2539`), plus the unique `(company_id, name)` index on the line below. No new namespace.

**Accumulation is a sum**, so the binding granularity is free-form and covers every scenario the client can pose: all rules of an incentive into one variable (the incentive's total), one rule into its own variable (that faixa's exact value), or two different incentives into the same variable (summed across incentives).

**The forward-only rule is validated at plan save.** An incentive reading an auxiliary variable declares a hard dependency on some incentive writing it in a *strictly earlier stage*. Same stage is not allowed — §2.3. Unlike v1, this validation does not bind the incentive to another incentive; it validates a plan's composition, which is where the dependency actually lives.

### 4.1 The variable snapshot is built before any incentive runs — the auxiliary path cannot reuse it

The values of all plan variables are computed **once** by `Commission::IndicatorOptionsProcessor` and frozen onto `user_commission.modifier_options` (`app/workers/user_commission/indicator_options_consumer.rb:16-17`). Every consumer afterwards reads that frozen hash: indicator (`indicator_incentive/consumer.rb:29`), limiter (`limiter_incentive/consumer.rb:35`), redemption (`redemption_incentive/consumer.rb:32`).

And it is built **before even the deal stage**: `AggregatedIndicator::Calculator::Producer` → `UserCommission::IndicatorOptionsProducer` → its consumer → `DealIncentive::Producer` (`aggregated_indicator/calculator/producer.rb:28`, `user_commission/indicator_options_consumer.rb:22`).

So writing a row into `aggregated_modifiers` during the indicator stage changes nothing for the limiter — its hash was assembled long before. **"Just another variable type in the aggregated indicators" does not deliver the value to the reader.** The auxiliary values need their own read path, assembled at the moment of use, exactly as `Commission::LimiterOptionsProcessor` already is (invoked inside the consumer with fresh state) and as `premio` already is (`user_commission.money`, read live at `indicator_incentive/consumer.rb:32`).

### 4.2 Accumulation must not happen at write time — the rules run in parallel

Binding several faixas (or two incentives) to one variable means several jobs writing the same row: every `(user_commission, rule)` pair is an independent job (`indicator_incentive/producer.rb:22`). Read-modify-write on a shared row loses updates, silently and non-reproducibly.

The write-side race disappears entirely by materialising the auxiliary values in a step **after the stage's finalizer**, reading from `commissionings` — already the per-rule source of truth with a unique index on `(rule_id, user_commission_id)`. The sum falls out of a `group by`, and all three binding scenarios are covered with no extra mechanism.

### 4.2b Accumulating with `+=` is not idempotent, and the pipeline is at-least-once

Writing the auxiliary value at commissioning-creation time is a reasonable shape, but the operation must be **recompute the sum**, never **add to the sum**.

Sidekiq delivers at least once. The commissioning write survives a retry because it was deliberately made idempotent — `IndicatorCommissioning.find_or_initialize_by(user_commission_id:, rule_id:)` (`indicator_incentive/consumer.rb:52-55`) backed by the unique index on `(rule_id, user_commission_id)` (`db/schema.rb:457`). A retried job rewrites the same commissioning row. An increment does not survive the same retry: the job runs twice, the counter advances twice, and the commissioning row still says one. The result is a silently doubled payroll value with no trace.

`value = SUM(commissionings feeding this variable for this user)` is idempotent by construction and still leaves the value closed at every moment, which is what the increment was for. Recomputing on every commissioning save is N times the work of recomputing once at the stage boundary for an identical result — and since same-stage reads are forbidden (§2.3), the stage boundary is already early enough for every legitimate reader.

### 4.2c Reprocessing already resets the rows, but nothing recreates them

`AggregatedIndicator::Purge::Consumer` destroys **every** aggregated indicator of the user commission, unscoped by variable type (`aggregated_indicator/purge/consumer.rb:17-21`), and it runs before any incentive stage. So auxiliary rows living in the same table are wiped on reprocess for free.

The counterpart is that `AggregatedIndicator::Producer` recreates rows only for `plan.variables.easy` and `plan.variables.indicators` (`aggregated_indicator/producer.rb:23-25`), both positively type-scoped. Auxiliary rows will therefore not be recreated there and need their own creation path — `find_or_create` at write time, or a dedicated step.

### 4.3 A faixa that evaluates to zero writes no row

Per §2.2, zero-valued results are not persisted. An auxiliary variable fed only by a faixa that did not fire would fall back to `Variable#default`, which is a required, free-form field (`app/models/variable.rb:35`). Either the auxiliary type forces `default` to zero, or materialisation writes an explicit zero.

### 4.4 The "someone writes this" validation belongs to the plan, not the incentive

An incentive is a company-level entity and does not know which plan it will enter; the same incentive can go into ten plans, with the publisher present in some and absent in others. At incentive save, only the local facts are checkable: the variable exists and is of the auxiliary type. The rule "someone writes it, in an earlier stage" is meaningful only at **plan composition**, so it runs there. That is not the coupling rejected in §0 — it validates a plan's composition rather than binding one incentive to another.

Filtering the plan's incentive picker to those compatible with the auxiliary variables already present is the preventive form of the same rule and is worth having, but it is UX, not the guarantee: plans are also written through `/api/v3/`, which is the integrator's path.

### 4.5 Implementation surface (not scoped, just named)

**The exclusion work is far smaller than expected, because the existing scopes are positive.** `Incentive#update_variables` (`incentive.rb:153,159,163,171`), the `Rule` syntax validators (`rule.rb:173,193,199,207`), `AggregatedIndicator::Producer` (`aggregated_indicator/producer.rb:23,25`), `IndicatorDataset::Producer` (`indicator_dataset/producer.rb:20,22`) and `DealIncentive::Consumer` (`deal_incentive/consumer.rb:33`) all read through `variables.deals` / `variables.indicators` / `variables.easy`, i.e. `where(type: X)`. A fourth type is excluded by construction — no code change.

What does need attention is the handful of reads with **no type scope**, which would pick auxiliaries up silently: `Commission::IndicatorOptionsProcessor` (`indicator_options_processor.rb:41`, `plan.variables`), `CalendarAudit::Producer` (`calendar_audit/producer.rb:19`), `GoalDataset::Migration::Producer` (`goal_dataset/migration/producer.rb:16`), and `Commission::MoneySanitizerProcessor` (`money_sanitizer_processor.rb:48`, `commission.variables`).

The first of those is not a place to exclude but the place that already helps: because `plan.variables` is unscoped there, auxiliary keys land in the `modifier_options` snapshot on their own — carrying their default. Each consumer then only has to overwrite them with fresh values via one extra `.merge(auxiliary_options)`, which is exactly the shape the limiter and redemption consumers already use for `limiter_options` / `redemption_options` (`limiter_incentive/consumer.rb:37`, `redemption_incentive/consumer.rb:34`). The read side is a merge per consumer, not a new pipeline stage.

### 4.6 The authoring → registration → plan flow, checked against the schema

**One collection with a role, not two.** `incentive_variables` is a bare join table — `incentive_id`, `variable_id`, no unique index on the pair (`db/schema.rb:950-955`). Adding a `role` column (input / output) carries both meanings in the same collection, which is what the plan roll-up already consumes. Deriving the role instead of storing it is unsafe: an incentive can legitimately read a variable and write it, so the role belongs to the join row, not to the variable. Since `Incentive#update_variables` rebuilds the collection with `delete_all` + recreate (`incentive.rb:150`), duplicates are prevented by the rebuild, but a unique index on `(incentive_id, variable_id, role)` is worth adding while the column is.

**The third collection is not needed.** "Variables the calculation *requires*" is a derived set: input rows whose variable is of the auxiliary type. Storing it would be a third representation of a fact the other two already carry.

**Plan validation must include stage order, not only existence.** The rule is not "some incentive in this plan exports the variable" but "some incentive in a *strictly earlier stage* exports it". Existence alone lets two limiters in the same plan pass validation and then race, since a stage's incentives all run in parallel (§2.3).

**What genuinely changes in today's behaviour.** Auxiliary variables reaching `plan_variables` is what makes the read path work, but `plan_variables` carries `goal_type` (`db/schema.rb:1617-1624`) and is consumed by goal binding, so an auxiliary variable would surface in the goal-binding UI as something a meta can be attached to. Together with the unscoped reads named in §4.5 (`calendar_audit/producer.rb:19`, `goal_dataset/migration/producer.rb:16`, `money_sanitizer_processor.rb:48`), these are the existing flows that need the exclusion. Everything else is additive: an incentive with no output variables and a plan with no auxiliary variables follow exactly the path they follow today.

### Open points

- **Publish-only vs publish-and-pay.** Does an incentive that publishes a value also add it to the premium? It changes whether a `Commissioning` row exists at all, which changes every existing sum including `premio_grupo` (`limiter_options_processor.rb:19-42`). Getting it wrong changes payroll totals silently.
- **Which stages may write.** If the deal stage can write an auxiliary variable, its value is born after the snapshot and before the indicator stage — readable through the dedicated processor, but every writing stage then needs its own materialisation step. Restricting writes to the indicator stage onward makes the machinery substantially smaller and still covers the Colombia case (indicator → limiter/redemption). Decide this before sizing anything.
- **Whether the binding is mandatory or optional per rule.** The engineer's phrasing was "obrigado a colocar qual variável"; making it mandatory on every rule forces a variable to exist even where nothing reads it.
- **Statement display.** The transparency half (option E) is not superseded — the per-incentive breakdown in the statement is what makes the stored value auditable, and it is the piece that satisfies the legal requirement.

---

## 6. Sources

**Code** (`~/Projects/4Shark/app`, `develop`): `db/schema.rb`, `app/models/{incentive,incentivation,commissioning,rule,plan,variable,aggregated_indicator}.rb`, `app/services/commission/{indicator,limiter}_options_processor.rb`, `app/workers/{indicator_incentive,limiter_incentive}/{producer,consumer,finalizer}.rb`, `app/workers/user_commission/{indicator,limiter}_options_consumer.rb`, `app/workers/{deal_incentive,ranking_incentive}/finalizer.rb`, `Gemfile.lock` (`dentaku 3.5.7`).

**Slack**: DM `D07UVJP36GZ` (Paulo Ribeiro / Santiago Velasquez), 2026-07-07 and 2026-07-17.

**Not consulted**: the two proposal decks — `Propuesta de Interfaz Variables Calculadas - 4Shark.pptx` (`F0BJ3RTK8RF`) and `proposta_variaveis_calculadas_4shark_pt.pptx` (`F0BFN5ANRT8`). `slack_read_file` fails on binary content and neither file is on this machine, so the UI proposal has not been reviewed. Everything here about the interface is inference.
