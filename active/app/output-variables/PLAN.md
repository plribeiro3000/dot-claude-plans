# PLAN — Output (output) variables in `app`

> Reference: derived from `PLAN-SPIKE.md` (engineer-approved) and its auxiliary files
> `output-variables_call-sites_1.md`, `output-variables_pipeline_2.md`,
> `output-variables_rollout_3.md`. Background design record:
> `~/Projects/4Shark/dot-claude-plans/active/spike/incentive-calculated-variables/SPIKE.md` §4.
> Repository: `~/Projects/4Shark/app` (backend) and `~/Projects/4Shark/app-webclient` (frontend),
> branch `develop`.
> Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).

## Objective

Add a fourth `Variable` type — output — that the integration never feeds and the commission pipeline computes. Each `Rule` may optionally declare one output variable as its output; that rule's computed value for a user is written into that variable for that user, and several rules targeting the same variable sum. **Every incentive stage may export an output variable this way, the deal (transactional) stage included; reading one as a formula input is open to every stage except the deal stage.** Saving an incentive registers its output variables in `incentive_output_variables`, its own entity; `incentive_variables` keeps its exact current meaning — the variables an incentive reads. At plan save, an incentive whose formula reads an output variable requires another incentive in the same plan, in a strictly earlier calculation stage, to export it — so every output variable a plan reads has a producer that runs before its reader. At calculation time the value is materialized per `(user_commission, variable)` and injected into each consuming rule's Dentaku options hash.

## Scope

### In scope

- The `Variable` fourth type and its STI subclass.
- The `incentive_output_variables` and `plan_output_variables` entities, and the output binding on `rules`.
- Materialization of the per-`(user_commission, variable)` value and its accumulation semantics.
- The read path that delivers output values to consuming rules.
- Extending the `Rule` syntax validators so a rule referencing an output key can be saved at all.
- Plan-level validation including stage order.
- Confirmation that existing flows need no type exclusion, and the recorded reason why one would be wrong.
- GraphQL surface, the new permission, and the `app-webclient` authoring surface.
- **The statement display of an output value, on both statement screens.** Three marks, set by the engineer: the output variable appears in the upper variable listing identified as output and carrying its composed value; every commissioning that fed an output variable is marked with which variable it fed; and every commissioning whose rule reads an output variable is marked as having been calculated on one. The person accepting the declaration signs it — `statement-accept.component.html` collects a drawn signature — so a value that influences the payment without appearing on the screen is a value signed unseen. The spike names this half as *"the piece that satisfies the legal requirement"*.
- Test strategy, data migration, rollout sequence, execution order.

### Out of scope

- The incentive CSV bulk import of the output binding. `IncentiveDocument::Processor` builds rules from positional CSV columns (`app/workers/incentive_document/processor.rb:81-86`, using `row[0]` for value and `row[1]` for description); adding the binding changes a customer-facing template format. Documented as a limitation instead.

---

## Chosen approach

**Direction:** the design recorded in SPIKE §4, executed as a single backend change followed by a single frontend release.

Concretely:

- The output binding lives on `Rule`, not on `Incentive` or `Incentivation` — SPIKE §4 records the move and its reason: *"The client's actual request is the value of one specific faixa, and the faixa is the `Rule`; binding at incentive or incentivation level cannot express it"*.
- Registration of an output lives on its **own entity**, `IncentiveOutputVariable`, linking an incentive to the output variable its rules write. `incentive_variables` is untouched and keeps meaning exactly what it means today — the variables an incentive **reads**.
- **The two tables answer different questions and that is why they stay apart.** `plan_variables` exists to drive the goal-binding flow: it is the set of a plan's variables that need a meta, and the plan-finish screen walks it asking the operator for one. An output binding is not that — it answers "what does this rule write into", it is declared **per faixa** so one incentive commonly carries several different ones, and it never needs a meta. Folding it into either existing table would put two purposes in one collection and force every consumer of that collection to filter for the half it wants.
- **The per-faixa binding on `Rule` is the source of truth; the entity is its rolled-up index.** That roll-up is the pattern the codebase already uses: `incentive_variables` is itself a rolled-up index of what an incentive's formulas reference, rebuilt on every save from `Formula#referenced_identifiers`. The output entity is the same shape for the other direction, which is what makes "does this incentive write variable X" answerable without joining through rules.
- The value is materialized by **recomputing the sum at commissioning save** — never `+=` — into `aggregated_modifiers`, which is already the per-`(user_commission, variable)` store on the read path. What is summed is the **signed, commission-type-aware** expression, so a limiter contributes negatively.
- **Any incentive stage may write (export) an output variable through a rule binding — the deal (transactional) stage included.** Reading is the only constrained direction: **every stage except the deal stage may read one** — indicator, ranking, limiter and redemption. The deal stage writes but never reads; it is the exporter an indicator reader depends on, since the indicator stage is the first stage that may read and the deal stage is the only stage strictly before it.
- Plan-level validation, backed by an ordered stage constant, rejects a plan whose reader has no exporter in a strictly earlier stage. Reader ← eligible exporter stages: indicator ← deal; ranking ← deal, indicator; limiter ← deal, indicator, ranking; redemption ← deal, indicator, ranking, limiter.
- Rollout is one backend deploy per environment, then one frontend release, then the permission grant per account.

**Rationale (from engineer):** three points were set directly by the engineer's own description of the feature. The binding is optional per rule because *"ele pode salvar só uma faixa ou ele pode salvar todas"* is impossible if every rule must bind. The value is recomputed *"toda vez que criar um commissioning"* — the engineer specified the write moment; recompute rather than increment follows from Sidekiq being at-least-once (SPIKE §4.2b), which makes `+=` non-idempotent while `value = SUM(feeding commissionings)` is idempotent by construction. And the published value carries its sign, because the engineer's worked example of what the feature must express is *"essa pessoa ganhou R$ 300 nesse incentivo, R$ 200 nesse e perdeu R$ 100 nesse outro aqui. Resultado final: R$ 400."* — the limiter appears there as −100, and the arithmetic closes only if the sign travels with the value. Every remaining point was resolved under the ladder in `DECISION-AUTHORITY.md` — 4Shark's documented conventions and the surrounding code — and is recorded in § Technical decisions with the source that decided it.

**Source patterns referenced:**

| Pattern | Where it comes from |
|---|---|
| STI subclass shape (five lines, per-subclass `data_type` allow-list) | `app/models/easy_variable.rb`, `app/data_types/application_data_type.rb:4-6` |
| `enumerize` on a small closed set | `Variable#calculation` (`app/models/variable.rb:66`), `Plan#status` (`app/models/plan.rb:98`) |
| Variable-bearing FK already on `rules` | `db/schema.rb:1959-1961` (`variable_track_id` + its partial unique index) |
| Migration shape (`t.references`, inline `index:`/`foreign_key:`, explicit `null:`, `safety_assured` around `add_reference`) | `db/migrate/20260722215726_add_plan_id_to_plan_statement_portable_batches.rb` |
| Concurrent unique index (`disable_ddl_transaction!` + `algorithm: :concurrently`) | `db/migrate/20260729113429_add_unique_index_to_user_update_document_enrollments.rb:2-11` |
| New permission created by a data migration | `db/migrate/20260729113439_user_update_document_actions.rb` |
| Plan-level validation reasoning over the incentive set | `Plan#redemption_incentive_requirements` (`app/models/plan.rb:389-398`) |
| Options processor merged last, after `modifier_options` | `Commission::RedemptionOptionsProcessor` (computes in the consumer) and `Commission::LimiterOptionsProcessor` (computes in a preceding stage and persists) |
| Worker/data access | `~/.claude/docs/DATA-ACCESS.md` — `with_uncached_connection`, IDs not loaded objects, associations navigated per record |

---

## Execution phases

Phases 1-9 are development order on one branch; what blocks what is stated per phase. Under the chosen deploy shape they all ship in a **single backend deploy** (phases 1-8) plus a **single frontend release** (phase 9), so the phase boundaries are ordering and review units, not deploy units. Phases 10-12 are the rollout.

### Phase 1: Schema and model, inert

**Objective:** the fourth type, the two new columns and their model declarations exist; nothing reads or writes them yet.

**Components:**

- **Migration M1 — the `incentive_output_variables` table.** `t.references :incentive` and `t.references :variable`, each `null: false`, `foreign_key: true`, with the composite `index: { unique: true }` declared inline on the pair, per § Rails Migrations. **A brand-new table is invisible to the code still serving during the migration window**, which is what makes this the safest of the four migrations: nothing existing reads or writes it, no default is load-bearing, and no backfill exists to get wrong. `incentive_variables` is not touched by this feature at all and keeps its current shape (`db/schema.rb:950-955`).
- **Migration M1b — the `plan_output_variables` table.** The plan-level counterpart, same shape: `t.references :plan` and `t.references :variable`, `null: false`, `foreign_key: true`, composite `index: { unique: true }` inline. **It carries no `goal_type`**, and that absence is the point — `plan_variables` has one (`db/schema.rb:1600-1607`) because its whole purpose is the goal-binding flow, and an output variable never takes a meta. Also a brand-new table, so it is invisible to the code serving during the migration window.
- **Migration M2 — the output binding on `rules`.** `t.references` with inline `index:`/`foreign_key:` and explicit `null:`; the shape has precedent in the same table (`db/schema.rb:1959-1961`). `strong_migrations` flags `add_reference`, so it is wrapped exactly as the repository already does: `safety_assured { add_reference :plan_statement_portable_batches, :plan, foreign_key: true, index: true, null: true }` (`db/migrate/20260722215726_add_plan_id_to_plan_statement_portable_batches.rb:5`).
- **No separate index migration.** The uniqueness guarantee on `(incentive_id, variable_id)` ships inline with M1's `create_table`, so it needs neither `disable_ddl_transaction!` nor `algorithm: :concurrently` — those are required when adding an index to a table that already holds rows and takes writes, which a table created in the same migration does not.
- **`Variable::TYPES` + the STI subclass.** No migration: `variables.type` is a plain string column (`db/schema.rb:2565`, `t.string "type", limit: 8000`) and the constraint is application-side (`app/models/variable.rb:41`). The subclass mirrors `app/models/easy_variable.rb` — the two `rescue_unique_constraint` declarations and a `data_type` inclusion drawn from a new per-type allow-list alongside `DEAL_TYPES` / `INDICATOR_TYPES` / `EASY_TYPES` (`app/data_types/application_data_type.rb:4-6`). Uniqueness of key and name is already enforced per company (`db/schema.rb:2568-2569`), so no new namespace is needed. The type constrains `default` to zero; `validates :default, presence: true` (`app/models/variable.rb:35`) still applies, while the three indicator-only validations (`app/models/variable.rb:32,36,39`) do not.
- **`Rule` association.** `belongs_to :output_variable, class_name: 'Variable', optional: true`, with no manual presence validation — the binding is optional.
- **`IncentiveOutputVariable` and `PlanOutputVariable` models.** Each mirrors `app/models/incentive_variable.rb` — two `belongs_to … optional: true` with `inverse_of:`, and a presence validation per foreign key (§ Optional belongs_to). `IncentiveVariable` is not modified.

**Dependencies:** none. Blocks every other phase.

**Success criteria:**

- [ ] All three migrations generated with `bin/rails generate migration`, one action each, then run with `bin/rails db:migrate`; `db/schema.rb` committed alongside them.
- [ ] `spec/models/variable_spec.rb:35` updated — `it { is_expected.to validate_inclusion_of(:type).in_array(%w[DealVariable EasyVariable IndicatorVariable]) }` fails by construction against a fourth type. This is a required edit, not a regression.
- [ ] One subclass spec mirroring `spec/models/easy_variable_spec.rb` / `indicator_variable_spec.rb` / `deal_variable_spec.rb`.
- [ ] Association and presence validations on the new columns covered by shoulda-matchers one-liners, following `spec/models/incentive_variable_spec.rb`.
- [ ] Factory support: an output trait in `spec/factories/variables.rb` (which has `:indicator` and `:deal` today) and in `spec/factories/rules.rb`; a factory per new entity, mirroring the bare `spec/factories/incentive_variables.rb`.

### Phase 2: Confirm the existing flows need no exclusion

**Objective:** establish, by reading rather than by patching, that no existing consumer of `plan_variables` requires a type filter — and record why filtering there would be wrong.

**The direction is set by where the two collections put each half.** An output variable's **write** side lives entirely in its own entities — `incentive_output_variables` and `plan_output_variables`, plus the per-faixa binding on `rules`. Nothing about the write direction ever reaches `plan_variables`. Its **read** side is the opposite: when a rule's formula references an output key, the reading incentive links it in `incentive_variables` exactly as it links any other input (Phase 3), and `Plan#create_variables` rolls that into `plan_variables`. That membership is not an accident to be cleaned up — Phase 7 depends on it, and Phase 3 carries a spec pinning it precisely so a later scope cannot silently remove it.

**So a type filter on any `plan_variables`-derived read is forbidden.** It would drop a variable the plan genuinely reads, and the drop is silent. This covers `plan.variables`, `commission.variables` (which reaches through the plan) and any direct `PlanVariable` query.

**Where a flow does need to skip an output variable, the discriminator is the goal, not the type.** `plan_variables` already carries `goal_type`, an output row carries it blank (Phase 3), and `PlanVariable.with_goal` (`app/models/plan_variable.rb:14`, `where.not(goal_type: '')`) is the existing scope for that question — already used at `app/workers/plan/goals_processor.rb:12`. A goal-driven flow that must exclude rows without a meta filters on that, and the filter then applies equally to any variable of any type that carries no goal.

**Components:**

- **No production change.** Fifteen call sites already read through `variables.deals` / `variables.indicators` / `variables.easy` and exclude a fourth type by construction (inventory in `output-variables_call-sites_1.md` §1). The unscoped reads stay unscoped, each for its own reason: `app/services/commission/indicator_options_processor.rb:41` because Phase 7 needs output keys in the frozen snapshot; `app/workers/calendar_audit/producer.rb:19`, `app/models/calendar_audit.rb:30`, `app/workers/goal_dataset/migration/producer.rb:16` and `app/workers/commission/money_sanitizer_processor.rb:48` because each reads a collection whose output membership is legitimate; the two commission indicator worksheets because their lookup follows the same collection; `app/work_books/variable_audit_work_book/variables_work_sheet.rb:28` because it is a configuration catalog with a type column; and `app/workers/company/inactivator.rb:107`, `app/workers/company/activator.rb:110`, `app/workers/company/cleansing/variable_producer.rb:13` because covering every variable of a company is their purpose.

**The goal-less fan-out belongs to no task in this feature.** The calendar audit and the goal-dataset migration each fan out per variable without asking whether the row carries a goal, so they already enumerate goal-less rows today: `Plan#create_variables` (`app/models/plan.rb:434-436`) writes every row with no `goal_type`, the value is set only at the finish step (`app/graphql_mutations/finish_plan_graphql_mutation.rb:24`), and `Plan#clear` (`:461`) resets them all to nil. A plan between creation and finish, and any cleared plan, therefore feeds those producers goal-less rows of every existing type. An output variable adds volume to that, never a new behaviour — so tightening it is § Scope Discipline category 3, a follow-up outside this feature rather than a decision it has to take.

**Dependencies:** Phase 1 (the type must exist), Phase 3 (which establishes the membership this phase confirms).

**Success criteria:**

- [ ] No production file changes in this phase.
- [ ] The membership spec lives in Phase 3, where the behaviour it pins is introduced.

### Phase 3: Registration

**Objective:** saving an incentive records its inputs in `incentive_variables` and its outputs in `incentive_output_variables`, and the plan roll-up carries output variables without offering them a goal.

**Components:**

- **`Incentive#update_variables`** (an `after_save` callback) keeps writing input rows exactly as it does today; **its existing branches are not modified in shape**, and the ranking branch's `find_or_create_by` keeps its current meaning because no output row can ever be found there — outputs live in a different table. What the method gains is one more source of inputs and one sibling rebuild.
- **The reading branches must also consider output variables.** Today the indicator, limiter and redemption branch iterates `company.variables.indicators.enabled`, so an output key referenced by a formula would produce no input row at all. The branch gains the output scope, which is precisely what carries the variable into `plan_variables` **through the incentive that reads it**.
- **The output rebuild is a sibling of the same shape.** `incentive_output_variables` is rebuilt from the distinct `output_variable_id` values of the incentive's rules — one row per incentive-variable pair, however many faixas point at it. The per-faixa detail stays on `Rule`; this table is the index. An incentive may carry none, one, or several, because the binding is per faixa.
- **The plan roll-up mirrors the incentive level, one collection per direction.** `Plan#create_variables` (`app/models/plan.rb:434-436`) rolls `incentive_variables` up into `plan_variables`; a sibling rolls `incentive_output_variables` up into `plan_output_variables`, deriving it the same way `variable_ids` (`:438-445`) derives its own set. Both are rebuilt together whenever the plan's incentive set changes, so they never disagree about which incentives are in the plan.
- **That symmetry is what makes the plan validation a set comparison rather than a traversal.** "Is every output variable this plan reads also written by this plan?" becomes `plan_variables` (restricted to the output type) minus `plan_output_variables` — and the same two collections are what the authoring screen reads to render its panel and raise its flag, so the screen and the validation cannot drift apart by construction.
- **A rule that declares an output binding may only point at a variable of the output type.** The binding is what the type exists for; pointing it at an indicator or deal variable would let a formula-fed value be overwritten by a commission result. Validated on `Rule`, alongside the association.
- **`Plan#create_variables`** (`app/models/plan.rb:434-436`) populates `plan_variables` from every `incentive_variables.variable_id` of the plan's incentives (`variable_ids`, `:438-445`). Output variables **do** reach `plan_variables` — the read path requires them there — with **goal binding suppressed for the type**. `PlanVariable#goals_presence` (`app/models/plan_variable.rb:32-39`) only fires when `goal_type` is present, so a row with a blank `goal_type` validates cleanly; the surface to suppress is the plan-finish screen, where `PlanVariableInputGraphqlType` requires `goal_type` (`app/graphql_types/plan_variable_input_graphql_type.rb:5-6`) and offers a goal type for every `plan_variable`.

**Dependencies:** Phase 1.

**Success criteria:**

- [ ] `Incentive#update_variables` covered: inputs land in `incentive_variables` and outputs in `incentive_output_variables`, and each collection's rebuild leaves the other untouched.
- [ ] An incentive whose variable is both an input of one rule and the output of another produces a row in each table.
- [ ] An output variable reaches `plan_variables` and is not offered a goal on the plan-finish screen.

### Phase 4: Rule syntax validators — the blocker

**Objective:** a rule whose formula references an output variable key can be saved at all.

**This is a prerequisite for the read side, not optional polish.** Today such a rule fails validation, and the failure is silent about its cause. `Rule` validates every formula by evaluating it against a synthetic options hash built from positively-scoped variable queries — e.g. `app/models/rule.rb:213-219`:

```ruby
  def indicator_variables_options
    incentive.company.variables.indicators.enabled.each_with_object({}) do |variable, options|
      options["#{variable.key}_goal"] = rand(5000..10_000) # english variable
      options["meta_#{variable.key}"] = rand(5000..10_000) # portuguese variable
      options[variable.key] = rand(1..5_000)
    end
  end
```

That hash reaches `validate_syntax` (`app/models/rule.rb:177-185`), which calls the bang evaluator:

```ruby
  def validate_syntax(options = {})
    formula_error = formula.error

    return errors.add(:value, formula_error.reason, **formula_error.details) if formula_error.present?

    calculate!(options)
  rescue *PARSE_EXCEPTIONS => _e
    errors.add(:value, :invalid)
  end
```

`calculate!` is `Dentaku!(value, cast_values(options)).to_f` (`app/models/rule.rb:64-66`), and `Dentaku!` is `Dentaku.evaluate!` (`dentaku-3.5.7/lib/dentaku.rb:67-69`). An unbound identifier raises `Dentaku::UnboundVariableError`, a subclass of `Dentaku::Error` (`dentaku-3.5.7/lib/dentaku/exceptions.rb:6`), and `Dentaku::Error` is the first entry of `Rule::PARSE_EXCEPTIONS` (`app/models/rule.rb:9-10`). So the incentive refuses to save with a bare `errors.add(:value, :invalid)`, with no indication that the cause is an unknown variable key.

**Commit `ad88b4616` (2026-08-04, "validate the variables a formula references on every branch") resolves the diagnosis half of this and relocates the work.** `validate_syntax` no longer evaluates the formula against a synthetic hash of random values to discover an unbound identifier. It compares names: `unknown_identifier(rule_options.identifiers)` (`app/models/rule.rb:80-81`) finds the first referenced identifier the permitted set does not carry, and `errors.add(:value, :unknown_variable, variable: unknown_name)` (`:101-103`) reports it by name. The permitted set itself moved into a dedicated class, `Rule::Options` (`app/models/rule/options.rb`), whose queries each pluck keys rather than fabricating values.

**What this changes for this phase:** the permitted-identifier set already carries the company's output keys for every rule type that may read one. `Options#identifiers` (`app/models/rule/options.rb:40-48`) gives `output_variables` to the easy-company indicator branch and to the `else` arm — which covers `IndicatorRule`, `RankingRule`, `LimiterRule` and `RedemptionRule` — while the `formula?` branch, the deal (transactional) stage, carries none. That is exactly the rule: every stage except the deal stage may read, so the `else` arm covers all four reading types and needs no split, and the `formula` branch correctly withholds output keys from the one stage that may not read. The read-side syntax validation is therefore satisfied by the merged registration change; this phase's remaining work is confirmation and tests, not a branch rewrite.

**The primitive both this phase and the plan-level validation need is already in place and already adopted.** `Formula#referenced_identifiers` (`app/models/formula.rb:15-17`) tokenizes the formula and returns the distinct identifier names it references, without evaluating it. `Incentive#update_variables` reads its referenced set through it rather than by text matching (`app/models/incentive.rb`, `#referenced_identifiers`), so Phase 3 inherits a tokenizer-backed answer instead of introducing one. Use it wherever a phase needs the referenced set.

**Components:**

- `Rule::Options#output_variables` (`app/models/rule/options.rb:83-85`) plucks the company's enabled output keys, and `Options#identifiers` (`:40-48`) already merges it into the easy-indicator branch and the `else` arm — so a rule of any reading type (indicator, ranking, limiter, redemption) referencing an output key passes the name comparison. No builder or branch change remains; the work is the tests that pin this permitted set and its exclusion from the deal stage.
- The same `rescue` applies at runtime — `calculate` returns `0` (`app/models/rule.rb:58-62`) — so a missing output value at calculation time yields zero, never an error. That behaviour is unchanged.

**Dependencies:** Phase 3 (the validator needs to know which output variables the company has).

**Success criteria:**

- [ ] A rule referencing an output key saves through the incentive mutation on every reading type — indicator, ranking, limiter, redemption.
- [ ] A rule in a deal (formula) incentive referencing an output key is refused — the deal stage may not read, so its permitted set carries no output key.
- [ ] A rule referencing a genuinely unknown key still fails with `errors.add(:value, :invalid)`.

### Phase 5: Plan validation and the stage order

**Objective:** a plan whose incentive reads an output variable is rejected unless another incentive in the same plan, in a strictly earlier stage, exports it.

**Components:**

- **`Incentive::CALCULATION_ORDER`** — an ordered constant expressing Deal → Indicator → Ranking → Limiter → Redemption. That order has no representation in code today: it exists only in the enqueue graph across 41 call sites (mapped in `output-variables_pipeline_2.md`), and `Incentive::TYPES` (`app/models/incentive.rb:15`) is declared in a different order and carries no ordering semantics. **The enqueue graph remains the source of truth for execution; the constant becomes the source of truth for validation**, and a spec keeps the two aligned.
- **`Plan#output_variable_requirements`** — a fifth custom validation alongside the four at `app/models/plan.rb:58-61`, modelled on `redemption_incentive_requirements` (`:389-398`), which is its structural twin: it reasons over the plan's incentive set and adds to `:incentivations`. Two details differ from the twin. It must read `incentive_ids` (`app/models/plan.rb:421-425`), which excludes incentivations marked for destruction — the existing sibling uses `incentivations.map(&:incentive_id)` and does not. And the error must be added to `:incentivations` with **no dot**, so the bulk plan import reports it: `PlanDocument::Consumer` builds plans from a spreadsheet (`app/workers/plan_document/consumer.rb:158`, `:209`) and skips only attributes starting with `incentivations.` (`:212`, `next if attribute.to_s.start_with?('incentivations.')`).
- The plan picker filtered to compatible incentives (Phase 9) is the preventive form and is UX, not the guarantee. This validation is the guarantee.

**Dependencies:** Phases 3 and 4.

**Success criteria:**

- [ ] A spec asserting `CALCULATION_ORDER` matches the observed enqueue chain — this is the mechanism that keeps the constant and the graph from drifting.
- [ ] Validation branches covered: reader with no exporter; reader with an exporter in the same stage; reader with an exporter in a later stage; reader with an exporter in an earlier stage; two exporters into one variable.
- [ ] The bulk plan import surfaces the error rather than swallowing it.

### Phase 6: Materialization

**Objective:** the per-`(user_commission, variable)` output value exists, carries the sign it has for the person, and is correct under retry.

**Components:**

- **Write moment: at commissioning save, inside the existing consumer.** No new worker, no new `Computation` participation, no edit to the enqueue graph — which is also why the in-flight-deploy question does not arise for this feature at all.
- **Arithmetic: recompute, never `+=`.** `value = SUM(commissionings of the rules bound to this variable, for this user commission)`. Every `(user_commission, rule)` pair is an independent job (`app/workers/indicator_incentive/producer.rb:22`, `combinations = user_commission_ids.product(rule_ids)`), so a read-modify-write on a shared row loses updates; and Sidekiq is at-least-once, so `+=` is not idempotent while the recomputed sum is idempotent by construction.
- **What is summed: the signed, commission-type-aware expression, not the raw `value` column.** A money incentive's rules sum `Commissioning#money`; a points incentive's rules sum `Commissioning#points`. For a limiter that resolves to `value * -1` (`app/models/limiter_commissioning.rb`) — the negative contribution — and for every other stage it resolves to `value` unchanged (`app/models/commissioning.rb:60-70`). Beyond the engineer's worked example, this is what keeps a downstream formula's author ignorant of which incentive type produced the value: an unsigned publication would force the reader to know the writer's stage in order to know whether to add or subtract, which is exactly the incentive-to-incentive coupling the design removes.
- **Documented behaviour, not a defect to guard against:** `#money` returns zero when the incentive is points-typed and `#points` returns zero when it is money-typed, so an output variable bound by both a money rule and a points rule sums mixed units. That is the author's modelling choice — nothing in the platform prevents mixing units in a formula today, and no validation is added for it.
- **Storage: `aggregated_modifiers`.** Already unique on `(user_commission_id, variable_id)` (`db/schema.rb:86`), already purged on reprocess with no type scope (`app/workers/aggregated_indicator/purge/consumer.rb:17-21`), and already the source `IndicatorOptionsProcessor` reads. The write is an upsert against that unique index.
- **The race to close.** Two consumers writing to the same variable for the same user race on the *recompute*, not on the commissioning. The value is correct only if the aggregate query genuinely re-reads at that moment, inside its own transaction; a stale read produces a silently low number, which is the failure class the payroll cannot tolerate.
- **Writers: every stage's consumer — deal, indicator, ranking, limiter and redemption — because every stage may export an output variable.** The deal (transactional) consumer is a writer alongside the other four: an indicator reader depends on a deal exporter, so the deal stage's materialization is what makes the indicator's read non-empty. Each persists a commissioning only on a non-zero result — `indicator_incentive/consumer.rb:41`, `limiter_incentive/consumer.rb:40`, `ranking_incentive/consumer.rb:47`, `redemption_incentive/consumer.rb:37`, plus the deal consumer's own non-zero guard (`app/workers/deal_incentive/consumer.rb`, exact site confirmed at execution) — so a rule that evaluated to zero writes no commissioning row and therefore contributes nothing to the sum. A deal rule sums `Commissioning#money`, the same money expression as any money stage.
- **Retry idempotency is not uniform, and the materialization inherits it.** The indicator stage uses `IndicatorCommissioning.find_or_initialize_by(user_commission_id:, rule_id:)` (`app/workers/indicator_incentive/consumer.rb:54`), which survives a retry. The limiter, ranking and redemption stages construct a fresh record — `limiter_commissioning = LimiterCommissioning.new` (`app/workers/limiter_incentive/consumer.rb:41`) — so a retry hits the unique index at `db/schema.rb:457` and raises on `save!`. Redemption compensates by destroying its prior rows in its producer (`app/workers/redemption_incentive/producer.rb:30`); limiter and ranking do not. This is pre-existing and not introduced here; it bounds how much the materialization can rely on those rows being rewritable.
- **Guard the Calculator re-entry.** `AggregatedIndicator::Calculator::Producer` fans out over *every* row for the commission with no type scope (`app/workers/aggregated_indicator/calculator/producer.rb:20-21`) and its consumer calls `calculate!`, which falls back to `variable.format_default` when there are no `indicator_aggregations` — so any path re-entering the Calculator after output rows exist overwrites them with the default. Within one run the ordering makes this unreachable (the Calculator completes before any incentive stage begins). Closing the re-entry exposure means adding a type scope there.
- **Partial commissions.** Every worker in the chain branches on `partial` to load `PartialCommission` instead of `Commission` (e.g. `app/workers/indicator_incentive/consumer.rb:8-13`); `AggregatedIndicator#indicator` has a partial-specific `nil` return (`app/models/aggregated_indicator.rb:115-116`), so the materialization's zero-versus-absent semantics need checking against partials specifically.
- **Queue.** The work runs on the existing commission queue of the stage it hangs off, so nothing changes in `config/sidekiq_commission*.yml`, `config/initializers/hire_fire.rb` or Terraform.

**Cost recorded:** N recomputes per user per stage rather than one at the stage boundary — SPIKE §4.2b states it directly: *"Recomputing on every commissioning save is N times the work of recomputing once at the stage boundary for an identical result"*.

**Dependencies:** Phase 3. Independent of Phases 4-5, so it can run in parallel with them.

**Success criteria:**

- [ ] Several rules into one variable, and two incentives into one variable, produce the expected sum.
- [ ] A rule that evaluated to zero — and therefore wrote no commissioning row — contributes nothing.
- [ ] The engineer's worked example closes: two positive contributions and one limiter contribution of the same magnitude publish 300 + 200 − 100 = 400, which pins the signed expression against the raw `value` column.
- [ ] Idempotency under retry: running the materialization twice leaves the value unchanged. This is the property SPIKE §4.2b exists to protect and it is invisible in a single-run test.
- [ ] A reprocess clears the output rows (the purge at `aggregated_indicator/purge/consumer.rb:17-21` is unscoped, so this is free) and recomputes them.

### Phase 7: Read path

**Objective:** the materialized value reaches every consuming rule's Dentaku options hash.

**Components:**

- **The frozen snapshot already carries output keys.** It is written once, before any incentive stage (`app/workers/user_commission/indicator_options_consumer.rb:16-17`), and that consumer enqueues `DealIncentive::Producer` at `:22`. Because `IndicatorOptionsProcessor` reads `plan.variables` unscoped (`app/services/commission/indicator_options_processor.rb:41`), output keys land in the snapshot carrying their default — so a consuming formula reads a default until the fresh merge overwrites it, never an unbound variable.
- **A new `Commission::<name>OptionsProcessor`** alongside the six existing ones in `app/services/commission/` (`deal_options_processor.rb`, `deal_options_v2_processor.rb`, `indicator_options_processor.rb`, `limiter_options_processor.rb`, `ranking_options_processor.rb`, `redemption_options_processor.rb`). Two named precedents exist and differ: `RedemptionOptionsProcessor` computes inside the consumer, `LimiterOptionsProcessor` computes in a dedicated preceding stage and persists onto the user commission. Both merge last, after `modifier_options`.
- **The merge, in the four reading stages:**

| Consumer | Line | Current expression the merge joins |
|---|---|---|
| `app/workers/indicator_incentive/consumer.rb` | 29 | `options = deal_options.merge(user_commission.modifier_options)` |
| `app/workers/ranking_incentive/consumer.rb` | 44 | `options = deal_options.merge(modifier_options).merge(ranking_options)` |
| `app/workers/limiter_incentive/consumer.rb` | 37 | `options = deal_options.merge(modifier_options).merge(limiter_options)` |
| `app/workers/redemption_incentive/consumer.rb` | 34 | `options = deal_options.merge(modifier_options).merge(redemption_options)` |

- **The indicator consumer merges output too — it is a reading stage.** It reads output variables the deal stage exported, so its line 29 gains the output merge after `modifier_options`, exactly as the other three do. It remains a writer as well (Phase 6): the indicator stage both reads what the deal stage wrote and writes what the ranking/limiter/redemption stages may read.
- **The deal stage is not a reader, and that is what keeps its read path untouched.** It does not merge the snapshot wholesale — it filters it down to metric keys (`app/workers/deal_incentive/consumer.rb:30-32`, and the same shape at `app/workers/deal_incentive/period_processor.rb:20`), so an output key is filtered out by that `select` with no code change. The deal stage's write side (its exporting rules materialize output) is Phase 6; its read path adds nothing.
- Data access follows `~/.claude/docs/DATA-ACCESS.md`: `with_uncached_connection` around each access, IDs not loaded objects, associations navigated per record rather than joined.

**Dependencies:** Phase 6 (nothing to read otherwise) and Phase 4 (no rule can name the variable otherwise).

**Success criteria:**

- [ ] A rule in an indicator, ranking, limiter or redemption incentive reading an output variable evaluates against the materialized value, not the default.
- [ ] A plan with no output variable produces byte-identical options hashes to today.

### Phase 8: GraphQL surface and the permission

**Objective:** the authoring surface exists on the API, and the feature is reachable by nobody until the permission is granted.

**Components:**

- **Fields and arguments.** An output-variable field on `RuleGraphqlType` (`app/graphql_types/rule_graphql_type.rb:3-14`, which today exposes `commissionings`, `created_at`, `description`, `document_line`, `id`, `incentive`, `incentive_id`, `type`, `updated_at`, `value` and no variable field); the matching argument on `RuleInputGraphqlType` (`:4-8`); an output-variables field on `IncentiveGraphqlType` alongside its existing `variables`, so the plan-side picker can tell a writer from a reader. `IncentiveVariableGraphqlType` is not modified — the two directions are two collections, so nothing on a row has to say which one it is.
- **Both mutation rule allow-lists.** `create_incentive_graphql_mutation.rb:43-47` (`rules: %i[ description type value ]`) and `update_incentive_graphql_mutation.rb:39-45` (`rules: %i[ _destroy description id type value ]`). These are explicit `%i[...]` arrays — an unlisted argument is silently dropped.
- **The clone gap, which is the sharpest backwards-compatibility risk in the feature.** There is no backend clone mutation: `clone` is a permission and a UI action only — `IncentivePolicy#clone?` (`app/policies/incentive_policy.rb:28-33`), the permission string `incentive_clone` (`app/workers/company/admin/processor.rb:31`), and `actions << 'clone' if policy.clone?` (`app/graphql_types/incentive_graphql_type.rb:49`). The front has a clone component per incentive type (e.g. `app-webclient/src/app/indicator-incentives/clone/`) that prefills the create form, so a clone goes through `CreateIncentiveGraphqlMutation`. **Unless its allow-list carries the output binding — and the front clone builders carry it too (Phase 9) — a cloned incentive silently loses its bindings and produces a plan that validates but computes a different number.**
- **Migration M4 — the permission `Action` row**, created by a data migration in the established pattern (`db/migrate/20260729113439_user_update_document_actions.rb:5`, `Action.create!(key: ..., level: 'module', resource: ...)`), plus the key added to the hardcoded `MODULE_KEYS` list in `app/workers/company/admin/processor.rb:16-52` (where `incentive_clone` sits at line 31). The processor iterates that list at `:77-83` and resolves each key with `Action.get`, which goes through `ApplicationRecord.get_id` (`app/models/application_record.rb:134-140`) ending in `find_by!` — **so a key listed in `MODULE_KEYS` with no `Action` row raises `RecordNotFound` and the processor dies. M4 must land in the same deploy as the `MODULE_KEYS` entry, never after it.** M4 is also not idempotent: `Action.create!` raises on a re-run.
- **The gate** follows the shape of every sibling in `IncentivePolicy` (`app/policies/incentive_policy.rb:8-10`, `role.permission?('incentive_creation') || user.permission?('incentive_creation')`).
- **Contract constraints that must not be violated.** Every argument on `RuleInputGraphqlType` is `required: false` today, and the frontend declares the input type by name (`$rules: [RuleInputGraphql!]`) — so a newly-**required** argument would fail validation on every existing client, and the type name must not change. `field :type, String, null: false` (`app/graphql_types/variable_graphql_type.rb:33`) is a `String`, not a GraphQL enum, which is why a fourth type value is not a client-visible schema change. `Variable.for_type` (`app/models/variable.rb:55`) already backs the resolver's type filter (`app/graphql_resolvers/variable_graphql_resolver.rb:21`), and `create_variable_graphql_mutation.rb:4-11,30-40` already lists `type` in both arguments and `permit`, so creating an output variable needs no mutation change.

**Dependencies:** Phase 1; sequenced after Phase 5 so the front never offers a binding the backend rejects.

**Success criteria:**

- [ ] The new fields and arguments resolve; the argument is optional and the input type name is unchanged.
- [ ] A clone carrying an output binding round-trips through `CreateIncentiveGraphqlMutation` with the binding intact — covered by a test that clones and asserts the binding.
- [ ] The permission `Action` row exists, the `MODULE_KEYS` entry ships in the same deploy, and the permission is granted to nobody.

### Phase 9: `app-webclient`

**Objective:** an operator can bind an output variable on a rule, replicate it across the rules of an incentive, and pick compatible incentives when building a plan.

**Components:**

- **One control in the shared `rule/` module.** `app-webclient/src/app/rule/` holds `rule.model.ts`, `rule-create-form-builder.service.ts`, `rule-update-form-builder.service.ts`, `rule.service.ts`, `rule.module.ts`. The create builder is the whole surface for a rule's fields (`value`, `description`), and `Rule` in `rule.model.ts` carries `_destroy`, `description`, `expanded`, `id`, `value`, `type`.
- **Wiring in five incentive modules × three flows.** Each incentive type composes the shared builder — `IndicatorIncentiveCreateFormBuilder` injects `RuleCreateFormBuilder` and calls `rules: this.ruleFormBuilder.buildArray()` (`app-webclient/src/app/indicator-incentives/create/indicator-incentive-create-form-builder.service.ts:25`). The modules are `deal-incentive`, `indicator-incentives`, `limiter-incentives`, `redemption-incentives`, `rankifier-incentives`, each with `create/`, `update/` and `clone/`. **The clone flows are the part that must not be missed** — see the clone gap in Phase 8.
- **Replicate to all rules.** A form-level action on the rules `FormArray`. The array lives in each incentive builder, so the control sits at the incentive form level, not inside the shared rule module.
- **The plan-side picker**, offering only incentives compatible with the output variables already present. The plan create form builds `incentivationsAttributes` via `IncentivationCreateFormBuilderService` (`app-webclient/src/app/plan/create/plan-create-form-builder.service.ts:23`); the picker needs each candidate incentive's inputs and outputs, which is why `IncentiveGraphqlType` gains an output-variables field. This is UX; the plan validation from Phase 5 is the guarantee.
- **The variable creation screen** (`app-webclient/src/app/variable/create/variable-create-form-builder.service.ts`) already has a `type` control with a required validator, so offering the fourth type is a list change rather than a form change. Its `variableCalculation`, `variableFrequency` and `variableOverrideCalculation` helpers are conditionally required, matching the model where those three are validated only `if: :indicator?` — an output variable follows the deal/easy shape and requires none of them.

**Dependencies:** Phase 8.

**Success criteria:**

- [ ] The binding can be set, edited and cloned on all five incentive types.
- [ ] The replicate action sets one rule's output variable across the incentive's rule array.
- [ ] The plan picker offers only compatible incentives.

### Phase 10: Backend deploy

**Objective:** the backend change is live in all four environments, with the feature reachable by nobody.

**Components:**

- **One deploy per environment**, in progression. `beta-001` builds from `develop` and is where the full sequence is validated first — a real incentive with an output binding, a real plan, a real commission run; `demo-001` is the second non-productive gate; then the two productive stacks.

| Environment | Build branch | Command | Productive? |
|---|---|---|---|
| `beta-001` | `develop` | `gh workflow run deploy-beta-001.yaml -R 4shark/app` | no |
| `demo-001` | `master` | `gh workflow run deploy-demo-001.yaml -R 4shark/app` | no |
| `shared-001` | `master` | `gh workflow run deploy-shared-001.yaml -R 4shark/app` | **yes** |
| `atento-001` | `master` | `gh workflow run deploy-atento-001.yaml -R 4shark/app` | **yes** |

- **The productive gate is enforced, not advisory.** `DEPLOY-REFERENCE.md:98`: *"**This is enforced, not trusted:** `validate-productive-deploy.sh` (PreToolUse) blocks a `deploy-shared-001` / `deploy-atento-001` command unless a GO from the check is on record for that stack within the last 5 minutes"*. So each productive step is `bash ~/.claude/scripts/sidekiq-queue-check.sh --stack <stack>` followed immediately by the deploy, as one motion. `beta-001` and `demo-001` are never gated. `atento-001` additionally deploys a payroll worker on `sa-east-1` Fargate (`DEPLOY-REFERENCE.md:87`) which this feature does not touch but which shares the deploy.
- **The migration window.** In `app/.github/workflows/deploy-shared-001.yaml` the `prepare-and-migrate` job (`:371`) builds and pushes the image (`:384`, `image-tag: latest` at `:396`) and then runs `bin/rails db:migrate` (`:403`, `:458`), while the job that activates the new code depends on it and runs later (`:616`, `:621`). **Between those two points the schema is new and every serving container is old.** M1 and M1b create brand-new tables, which the old code neither reads nor writes; M2 is a nullable column on an existing table, equally unread; M4 changes no old-code behaviour. Nothing needs splitting, and there is no contract half — nothing is dropped or rewritten. `strong_migrations` is active with default checks (`Gemfile:78`; the initializer is `StrongMigrations.auto_analyze = true` with no `start_after` and nothing disabled).
- **Rollback is a redeploy of the previous image at every step.** The two tables and the column stay — rolling back a migration is not part of the deploy flow — which is harmless because the old code never reads or writes any of them. Output rows already written become unread and are purged by the next reprocess. There is no point of no return: nothing drops a column, rewrites data, or changes an existing cross-service contract. The closest candidate is a commission already calculated with output values — reverting the code stops producing new ones and a reprocess under the old code reproduces the old result, which is a recovery path rather than an irreversibility, but a reprocess on a productive stack is not free.

**Dependencies:** Phases 1-8. **Running the deploy is the engineer's** — an action outside version control that a PR diff neither shows nor reverts. The shape above is decided; the execution and its timing are not.

**Success criteria:**

- [ ] On `beta-001`: a commission with no output variables completes end to end, unchanged; one with an output variable produces the expected value; a rule naming an output key saves; a plan missing an exporter is rejected and the document import reports it.
- [ ] `Incentive` save still produces the same `incentive_variables` rows for incentives with no output binding.
- [ ] The new GraphQL fields resolve and the permission exists, granted to nobody.

### Phase 11: Frontend release

**Objective:** the authoring surface is live.

**Components:** one merge, which fans out into the per-client Netlify builds. `app-webclient` ships via Netlify, one site per client (`DEPLOY-REFERENCE.md:138`: *"**Netlify** — build+deploy combined at Netlify (publishes `dist/browser`), one Netlify site **per client** (whitelabel). NOT GitHub Actions."*), and `ls src/environments` returns 40 entries — two shared environment files and 38 per-client folders. The sites do **not** version independently: every one runs the same entry point against the same repository, `build.js` called by Netlify as `yarn build <project> [overrideSelector]` (`app-webclient/build.js:13-18`), where `project` selects an Angular project carrying that front's colors and assets. So this is one merge fanning out into 38 builds, not 38 coordinated releases. Which branch each site tracks lives in each site's Netlify settings rather than in the repository (`netlify.toml` carries no `[context.*]` block), which affects timing only — the frontend ships last and therefore never faces an old backend.

**Dependencies:** Phase 10 live in the target environment.

**Success criteria:**

- [ ] The authoring screens work against the deployed backend on every affected front.
- [ ] Rollback path confirmed: a Netlify redeploy of the previous build, per site.

### Phase 12: Permission grant

**Objective:** the feature becomes reachable, one account at a time.

**Components:** the permission system is 4Shark's release toggle (`DEPLOYMENT-STRATEGY.md:163`: *"**The permission system IS 4Shark's release toggle.** ... there is no client-facing screen to manage permissions, so 4Shark controls it manually and, by default, grants the permission to no one until the feature is proven."*). Grant on a single account, validate, then widen. Rollback is revoking the permission.

One boundary is worth recording: because `IncentivePolicy#update?` returns false when `record.plans.any?` (`app/policies/incentive_policy.rb:12-19`), granting the permission cannot retroactively change any incentive already in a plan. The blast radius of enabling it for an account is limited to incentives authored afterwards.

**Dependencies:** Phase 11.

**Success criteria:**

- [ ] The feature is reachable for the pilot account only.
- [ ] No existing plan's arithmetic changed.

---

## Technical decisions

| Decision | Choice | Rationale (from engineer / from draft) |
|---|---|---|
| Where an output registration is stored | Its own entity, `IncentiveOutputVariable`, on `incentive_output_variables`. `incentive_variables` is untouched | Engineer's call, on the ground that the two collections serve different purposes: `plan_variables` drives the goal-binding flow (the variables of a plan that need a meta) and `incentive_variables` records what an incentive reads, while an output binding answers "what does this rule write into", is declared per faixa, and never needs a meta. Keeping them apart also means `incentive_variables` keeps its exact current semantics, so the ranking branch's `find_or_create_by` needs no scope and cannot find the wrong row |
| The association name on `Incentive` | `has_many :output_variables, class_name: 'IncentiveOutputVariable'` | § Association Naming — the name states the role (`incentive.output_variables`) rather than restating the owner. The class name mirrors the existing `IncentiveVariable` so the pair reads as siblings in `app/models/` |
| The `Rule` output association name | `belongs_to :output_variable, class_name: 'Variable', optional: true` | § Association Naming — `output` distinguishes direction rather than restating the owner, so the stutter test keeps it. `optional: true` plus manual validation is the house rule; here no manual presence validation, because the binding is optional |
| Which stages write and which read | Any stage may write (export), the deal stage included; every stage except the deal stage reads — indicator, ranking, limiter, redemption. A reader requires an exporter in a strictly earlier stage | Engineer's definition of the feature (`DECISION-AUTHORITY.md` ladder, source 1): the transactional (deal) stage is the only stage that may not read an output variable, and for any reader to use one, some incentive in a strictly earlier stage must export it — so an indicator reader's exporter is a deal incentive. This governs over SPIKE §5's narrower scoping (which excludes the deal stage from writing): the deal consumer materializes as a writer (Phase 6) and the indicator consumer is a reader (Phase 7). The deal stage still never reads — its metric-key `select` at `deal_incentive/consumer.rb:31` filters output keys out of its options hash |
| Is the binding mandatory per rule | Optional | The engineer's own description — *"ele pode salvar só uma faixa ou ele pode salvar todas"* is impossible if every rule must bind |
| Materialization placement and storage | Recompute the sum (never `+=`) at commissioning save, stored in `aggregated_modifiers` | The engineer specified the write moment (*"toda vez que criar um commissioning"*); recompute rather than increment is forced by Sidekiq at-least-once (SPIKE §4.2b). `aggregated_modifiers` is already the per-`(user_commission, variable)` store, already purged on reprocess, already on the read path — § No Premature DRY rejects a new table with no benefit yet. **Cost recorded**: N recomputes per user per stage rather than one at the stage boundary |
| What the recompute sums | The signed, commission-type-aware expression, not the raw `value` column — `Commissioning#money` for a money incentive, `Commissioning#points` for a points one; `value * -1` for a limiter (`app/models/limiter_commissioning.rb`), `value` unchanged elsewhere (`app/models/commissioning.rb:60-70`) | The engineer's stated requirement, source 1 on the `DECISION-AUTHORITY.md` ladder. His worked example of what the feature must express is *"essa pessoa ganhou R$ 300 nesse incentivo, R$ 200 nesse e perdeu R$ 100 nesse outro aqui. Resultado final: R$ 400."* — the limiter appears as −100, and 300 + 200 − 100 = 400 holds only if the published value carries the sign as it affects the person's result; summing the raw `value` column would publish +100 and the arithmetic would not close. Independently: an unsigned publication would force a downstream formula's author to know which incentive type produced the value in order to know whether to add or subtract, reintroducing exactly the incentive-to-incentive coupling this design removes. **Consequence recorded, not guarded against**: `#money` returns zero for a points-typed incentive and `#points` zero for a money-typed one, so a variable bound by both a money rule and a points rule sums mixed units — the author's modelling choice, and no validation is added for it |
| Publish-only vs publish-and-pay | Publish-and-pay only. The rule creates its commissioning exactly as today; publishing is purely additive | § Scope Discipline. Nothing is excluded from any existing sum, `premio_grupo` is untouched, and the payment-type constraint at `app/models/commissioning.rb:13,17` is satisfied because the row exists anyway. No per-rule flag until someone asks for one |
| Do output variables reach `plan_variables` | Yes, with goal binding suppressed for the type | The only combination that works — the read path requires them there, and leaving goal binding on would surface them in the goal UI |
| Where the stage order lives | Ordered constant `CALCULATION_ORDER` on `Incentive`, plus a spec asserting it matches the enqueue graph | The spec is the sync mechanism the "nothing keeps them in sync" objection asked for. A single ordered constant is the standard shape; the alternative spreads the order across five STI subclasses |
| Does the incentive CSV import support the binding | No — documented limitation | § Scope Discipline. Not requested, and it changes a customer-facing template (`app/workers/incentive_document/processor.rb:81-86`) |
| Deploy shape | One backend deploy, then one frontend release | `DEPLOYMENT-STRATEGY.md` phases **only** if a trigger fires. The `Computation` key derivation is unchanged (`plan_#{id}`, `app/models/plan.rb:166-168`), job argument shapes are unchanged, and the materialization decision makes the step idempotent — no trigger fires, so a single backend deploy is legitimate by the framework's own rule. **The act of deploying remains the engineer's** — that is the residue, not the shape |
| Zero handling | The output type constrains `default` to zero | Materializing explicit zero rows would write one row per non-firing rule per user for no read benefit (SPIKE §4.3) |
| Whether any `plan_variables` consumer filters the output type | No. Every existing read stays unscoped | Engineer's call. The write direction lives entirely in `incentive_output_variables` / `plan_output_variables`, so the only way an output variable reaches `plan_variables` is as an **input a rule reads** — legitimate membership the read path depends on. A type filter there drops a variable the plan genuinely uses, silently. Where a flow must skip one, the discriminator is `goal_type` (blank on an output row) through the existing `PlanVariable.with_goal` (`app/models/plan_variable.rb:14`), which is a question about the goal rather than about the type |
| Materialization queue | Reuse the existing commission queue of the stage it hangs off | Zero cost — no new YAML entry, no new HireFire dyno block, and no Terraform change, since a worker service is declared by config-file path rather than by queue list (`terraform/app-shared-001/terraform.tfvars:110`) |

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A cloned incentive silently loses its output bindings | High — a plan validates and computes a different number than the operator authored | Extend both mutation allow-lists and all five front clone builders in the same change (Phases 8 and 9); cover with a test that clones and asserts the binding |
| The recompute reads a stale aggregate, so the last writer does not observe both commissionings | High — a silently low number, the failure class the payroll cannot tolerate | The write is an upsert against the existing `(user_commission_id, variable_id)` unique index (`db/schema.rb:86`) and the aggregate query re-reads inside its own transaction at the moment of write (Phase 6) |
| The Calculator overwrites output rows with the variable default | Medium — a silently zeroed output value | Unreachable within a single run by the chain's ordering (the Calculator completes before any incentive stage begins); the exposure is re-entry, closed by a type scope at `app/workers/aggregated_indicator/calculator/producer.rb:20-21` |
| Limiter and ranking commissioning writes are not retry-idempotent | Medium — a retried job raises on the unique index, and a commissionings-based sum inherits whatever those rows hold | Pre-existing, not introduced here. It bounds how much the materialization can rely on those rows being rewritable; redemption already compensates in its producer (`app/workers/redemption_incentive/producer.rb:30`), limiter and ranking do not |
| The stage order becomes a second representation of the enqueue graph | Medium — drift between validation and execution | The enqueue graph stays the source of truth for execution; a spec asserting `CALCULATION_ORDER` matches the observed chain is the sync mechanism (Phase 5) |
| The calendar-audit fan-out multiplies by `periods × users` per output variable an incentive reads | Low — volume added to a shape that already runs, not a new one | A type filter is not the lever: the variable is in `plan_variables` because a rule reads it, and removing it there breaks the read path. The producer already enumerates goal-less rows of every type, because `goal_type` is blank between plan creation and finish and again after a clear (`app/models/plan.rb:434-436,461`) — so this adds volume to existing behaviour and belongs to a follow-up rather than to this feature (Phase 2) |
| A rebuild of one registration collection drops the other | Medium — an incentive silently loses its inputs or its outputs | The two collections live in separate tables, so each `delete_all` reaches only its own rows and the ranking branch's `find_or_create_by` (`app/models/incentive.rb:174`) cannot find an output row. Phase 3 carries the spec that pins both rebuilds |
| The implementation sums the raw `value` column instead of the signed expression | Low — the choice is settled, so what remains is a coding slip rather than an open question | The recompute sums `#money` / `#points` per commission type, so a limiter contributes negatively. Phase 6 carries the test that reproduces the engineer's 300 + 200 − 100 = 400 example, which fails if the raw column is summed |
| M4's `Action.create!` is re-applied | Low — the migration raises | Not idempotent by construction; it must not be re-applied. It is a re-run hazard, not a rollback hazard |

---

## Assumptions

- **Only `app` and `app-webclient` are affected.** A grep for `IncentiveVariable`, `PlanVariable`, `aggregated_modifier`, `Commissioning` and `incentive_variables` across `onboarding`, `setup`, `integrator` and `lambda` returned no matches. `app-sdk-advpl`, `app-sdk-dotnet` and `app-mobileclient` were not opened, so whether either SDK models `Incentive` / `Rule` / `Variable` is unverified.
- **`/api/v3/` is not an authoring path for incentives, rules or plans.** `app/controllers/api/v3/` holds `clients`, `deals`, `goals`, `groups`, `indicators`, `products`, `roles`, `subsidiaries`, `users` and nothing else, and `grep -rn "incentive" config/routes.rb` returns nothing. The integrator feeds `indicators`, which feed `IndicatorVariable` values — output variables are never fed by it, which is the design's premise.
- **`Incentivation` needs no change.** It carries three foreign keys and one validation concern (`app/models/incentivation.rb:4-10,24-29`; `db/schema.rb:937-948`). The binding lives on `Rule`, the registration on `incentive_variables`, and the plan validation reaches incentives through `incentivations.incentive_id`, which already exists and is already what `Plan#redemption_incentive_requirements` uses (`app/models/plan.rb:392`). The engineer's earlier statement about altering the model traces to a superseded draft that put the binding on `Incentivation` — SPIKE §4 records the move at line 124.
- **The backwards-compatibility surface is bounded by `IncentivePolicy#update?`.** `return false if record.plans.any?` (`app/policies/incentive_policy.rb:12-19`) means an incentive attached to any plan is not updatable through the mutation, so no existing productive incentive can acquire an output binding and no existing plan's arithmetic can change without a new incentive being authored and added to a plan. Every risk above is scoped to newly-authored incentives.
- **The in-flight-commission reasoning is inference from read facts, not an executed test.** It rests on the `Computation` key derivation being unchanged (`app/models/plan.rb:166-168`, `app/models/computation.rb:48-54`), job argument shapes being unchanged, and the successor being resolved at execution time rather than carried in the payload (`app/workers/indicator_incentive/finalizer.rb:22`, `app/workers/tenant_worker.rb:51-58`). Under the chosen materialization the enqueue graph is not edited at all, which narrows the question further. Confirming it on `beta-001` — start a commission, deploy mid-chain, confirm completion — is available if the engineer wants the stronger guarantee before the first productive deploy.
- **A stalled chain cannot be resumed after 12 hours.** `Counter::DEFAULT_EXPIRATION_TIME = 12.hours.to_i` (`app/models/counter.rb:4`), refreshed on every increment, and `Counter#value` reads `connection.get(@key).to_i` (`:48-52`) — so once both keys expire, `done?` evaluates `0 == 0` and returns true even though the work never finished. A deploy window is minutes, so this is not reachable during a deploy; it matters because any manual recovery of a long-stalled chain must reprocess, not resume.
- **The two proposal decks named in SPIKE §6 remain unreviewed** — neither file is on this machine, so the interface proposal has not been read. If it constrains the authoring surface, Phase 9 should be re-sized against it.
- **`app/docs/architecture/PARALLEL_PROCESSING.md` does not exist.** `DEPLOYMENT-STRATEGY.md` cites it four times with line numbers and `app/CLAUDE.md` links `DATA-PROCESSING.md` in its place. Every `Computation` fact above was therefore read from `app/models/computation.rb` and `app/models/counter.rb` directly.
- **The autoscaling Lambda's own source** (the `worker-commission-autoscaling` package) was not read — only the environment Terraform supplies it. Whether it does anything per-queue beyond consuming the HireFire endpoint is unverified. The chosen queue decision makes this moot for this feature.

---

> **Authoring:** written by `@agent-plan-composer` from a validated `PLAN-SPIKE.md` plus the engineer's communicated choice. No new options, no new technical decisions, no new assumptions were introduced at the composer stage — every claim traces to the draft or the engineer's choice.
