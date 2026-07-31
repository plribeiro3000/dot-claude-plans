# PLAN — Auxiliary (output) variables in `app`

> Reference: derived from `PLAN-SPIKE.md` (engineer-approved) and its auxiliary files
> `auxiliary-variables_call-sites_1.md`, `auxiliary-variables_pipeline_2.md`,
> `auxiliary-variables_rollout_3.md`. Background design record:
> `~/Projects/4Shark/dot-claude-plans/active/spike/incentive-calculated-variables/SPIKE.md` §4.
> Repository: `~/Projects/4Shark/app` (backend) and `~/Projects/4Shark/app-webclient` (frontend),
> branch `develop`.
> Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).

## Objective

Add a fourth `Variable` type — auxiliary — that the integration never feeds and the commission pipeline computes. Each `Rule` may optionally declare one auxiliary variable as its output; that rule's computed value for a user is written into that variable for that user, and several rules targeting the same variable sum. Saving an incentive registers its output variables in `incentive_variables` alongside its inputs, distinguished by a new `role`. At plan save, an incentive whose formula reads an auxiliary variable requires another incentive in the same plan, in a strictly earlier calculation stage, to export it. At calculation time the value is materialized per `(user_commission, variable)` and injected into each consuming rule's Dentaku options hash.

## Scope

### In scope

- The `Variable` fourth type and its STI subclass.
- The `role` column on `incentive_variables` and the output binding on `rules`.
- Materialization of the per-`(user_commission, variable)` value and its accumulation semantics.
- The read path that delivers auxiliary values to consuming rules.
- Extending the `Rule` syntax validators so a rule referencing an auxiliary key can be saved at all.
- Plan-level validation including stage order.
- Exclusion of auxiliary variables from existing unscoped flows.
- GraphQL surface, the new permission, and the `app-webclient` authoring surface.
- Test strategy, data migration, rollout sequence, execution order.

### Out of scope

- The statement / per-incentive breakdown display (SPIKE §5 "Statement display" — the transparency half of option E). Named in the spike as not superseded, but a separate deliverable with no dependency on this one in either direction.
- The incentive CSV bulk import of the output binding. `IncentiveDocument::Processor` builds rules from positional CSV columns (`app/workers/incentive_document/processor.rb:81-86`, using `row[0]` for value and `row[1]` for description); adding the binding changes a customer-facing template format. Documented as a limitation instead.

---

## Chosen approach

**Direction:** the design recorded in SPIKE §4, executed as a single backend change followed by a single frontend release.

Concretely:

- The output binding lives on `Rule`, not on `Incentive` or `Incentivation` — SPIKE §4 records the move and its reason: *"The client's actual request is the value of one specific faixa, and the faixa is the `Rule`; binding at incentive or incentivation level cannot express it"*.
- Registration lives on `incentive_variables` with a `role` column distinguishing inputs from outputs.
- The value is materialized by **recomputing the sum at commissioning save** — never `+=` — into `aggregated_modifiers`, which is already the per-`(user_commission, variable)` store on the read path. What is summed is the **signed, commission-type-aware** expression, so a limiter contributes negatively.
- The **indicator, ranking, limiter and redemption** stages may write an auxiliary variable; **ranking, limiter and redemption** may read one. The deal stage neither writes nor reads.
- Plan-level validation, backed by an ordered stage constant, rejects a plan whose reader has no exporter in a strictly earlier stage.
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

- **Migration M1 — `role` on `incentive_variables`.** Integer column with `enumerize`, **default = the input role**. The table today is a bare join with no timestamps and no unique index on the pair (`db/schema.rb:950-955`). The default is load-bearing, not cosmetic: the old code still serving during the migration window runs `incentive_variables.create(variable_id: variable.id)` with no role (`app/models/incentive.rb:156,160,164,168`), so a `NOT NULL` column with no default would fail every incentive save for the whole window. The default also makes every existing row correct with no data pass, which is why no separate backfill migration is needed.
- **Migration M2 — the output binding on `rules`.** `t.references` with inline `index:`/`foreign_key:` and explicit `null:`; the shape has precedent in the same table (`db/schema.rb:1959-1961`). `strong_migrations` flags `add_reference`, so it is wrapped exactly as the repository already does: `safety_assured { add_reference :plan_statement_portable_batches, :plan, foreign_key: true, index: true, null: true }` (`db/migrate/20260722215726_add_plan_id_to_plan_statement_portable_batches.rb:5`).
- **Migration M3 — unique index on `incentive_variables (incentive_id, variable_id, role)`.** Must follow M1. `disable_ddl_transaction!` + `algorithm: :concurrently` are mandatory together and mechanically enforced by `validate-concurrent-index-migration.sh`. Because `Incentive#update_variables` rebuilds the whole collection with `delete_all` on every save (`app/models/incentive.rb:150`), duplicates cannot arise through the normal path — the index is a guarantee, not a fix.
- **`Variable::TYPES` + the STI subclass.** No migration: `variables.type` is a plain string column (`db/schema.rb:2565`, `t.string "type", limit: 8000`) and the constraint is application-side (`app/models/variable.rb:41`). The subclass mirrors `app/models/easy_variable.rb` — the two `rescue_unique_constraint` declarations and a `data_type` inclusion drawn from a new per-type allow-list alongside `DEAL_TYPES` / `INDICATOR_TYPES` / `EASY_TYPES` (`app/data_types/application_data_type.rb:4-6`). Uniqueness of key and name is already enforced per company (`db/schema.rb:2568-2569`), so no new namespace is needed. The type constrains `default` to zero; `validates :default, presence: true` (`app/models/variable.rb:35`) still applies, while the three indicator-only validations (`app/models/variable.rb:32,36,39`) do not.
- **`Rule` association.** `belongs_to :output_variable, class_name: 'Variable', optional: true`, with no manual presence validation — the binding is optional.
- **`IncentiveVariable` role validation.** The model carries two presence validations today (`app/models/incentive_variable.rb:7-8`); the role joins them.

**Dependencies:** none. Blocks every other phase.

**Success criteria:**

- [ ] All three migrations generated with `bin/rails generate migration`, one action each, then run with `bin/rails db:migrate`; `db/schema.rb` committed alongside them.
- [ ] `spec/models/variable_spec.rb:35` updated — `it { is_expected.to validate_inclusion_of(:type).in_array(%w[DealVariable EasyVariable IndicatorVariable]) }` fails by construction against a fourth type. This is a required edit, not a regression.
- [ ] One subclass spec mirroring `spec/models/easy_variable_spec.rb` / `indicator_variable_spec.rb` / `deal_variable_spec.rb`.
- [ ] Association and presence validations on the new columns covered by shoulda-matchers one-liners, following `spec/models/incentive_variable_spec.rb`.
- [ ] Factory support: an auxiliary trait in `spec/factories/variables.rb` (which has `:indicator` and `:deal` today) and in `spec/factories/rules.rb`; `spec/factories/incentive_variables.rb` is currently a bare factory with no attributes and gains the role.

### Phase 2: Exclusions in existing flows

**Objective:** an auxiliary variable is harmless wherever it would otherwise be picked up silently. Independently valuable — this is the phase that contains the blast radius.

**Components:**

Fifteen call sites already read through `variables.deals` / `variables.indicators` / `variables.easy` and exclude a fourth type by construction with no code change (full inventory in `auxiliary-variables_call-sites_1.md` §1). The unscoped reads are handled per site:

- `app/workers/calendar_audit/producer.rb:19` — scoped. Its fan-out is `period_ids.product(user_ids, variable_ids)` (`:20`), so each auxiliary variable would add `periods × users` audit jobs per plan.
- `app/models/calendar_audit.rb:30` — `PlanVariable.where(plan_id: plan_ids).count`, the audit's expected row count, excludes auxiliaries. An auxiliary variable has no integration source, so counting it as "expected" produces a permanent false gap.
- `app/workers/goal_dataset/migration/producer.rb:16` — scoped.
- `app/workers/commission/money_sanitizer_processor.rb:48` — scoped.
- `app/work_books/commission_work_book/indicator_work_sheet.rb:29` and `app/work_books/plan_slice_commission_work_book/indicator_work_sheet.rb:36` — both get `.indicators` on the lookup. Each file already gates on `variables.indicators.exists?` at its line 12, so scoping the lookup restores the sheet's own declared subject.
- `app/work_books/variable_audit_work_book/variables_work_sheet.rb:28` — **left unscoped.** The audit workbook is a configuration catalog with a type column, and it already renders blank frequency for deal and easy variables (`:15-38`).
- `app/services/commission/indicator_options_processor.rb:41` — **left unscoped, deliberately.** Because it reads `plan.variables` with no type scope, auxiliary keys land in the frozen snapshot on their own carrying their default, so a consuming formula never hits the unbound-variable path at runtime. The read path in Phase 7 depends on this.
- `app/workers/company/inactivator.rb:107`, `app/workers/company/activator.rb:110`, `app/workers/company/cleansing/variable_producer.rb:13` — left unscoped. Covering every variable of a company is their purpose.

**Dependencies:** Phase 1 (the type must exist).

**Success criteria:**

- [ ] One spec example per site that gained a scope, asserting an auxiliary variable does not appear. These are cheap and they are the regression net for this phase.
- [ ] The three company-wide sites and the two deliberately-unscoped sites are left untouched.

### Phase 3: Registration

**Objective:** saving an incentive records its inputs and its outputs, each with the right role, and the plan roll-up carries auxiliary variables without offering them a goal.

**Components:**

- **`Incentive#update_variables`** (`app/models/incentive.rb:149-175`, an `after_save` callback declared at `:80`) writes output rows with the output role alongside the input rows it writes today. The method opens with `incentive_variables.delete_all` (`:150`), so the rebuild must not drop outputs.
- **The ranking branch is the one hazard.** `app/models/incentive.rb:172` uses `incentive_variables.find_or_create_by(variable_id: variable.id)` with no role scope — once roles exist, that call could find an output row and skip creating the input row. M3's unique index is where the defect would surface.
- **`Plan#create_variables`** (`app/models/plan.rb:434-436`) populates `plan_variables` from every `incentive_variables.variable_id` of the plan's incentives (`variable_ids`, `:438-445`). Auxiliary variables **do** reach `plan_variables` — the read path requires them there — with **goal binding suppressed for the type**. `PlanVariable#goals_presence` (`app/models/plan_variable.rb:32-39`) only fires when `goal_type` is present, so a row with a blank `goal_type` validates cleanly; the surface to suppress is the plan-finish screen, where `PlanVariableInputGraphqlType` requires `goal_type` (`app/graphql_types/plan_variable_input_graphql_type.rb:5-6`) and offers a goal type for every `plan_variable`.

**Dependencies:** Phase 1.

**Success criteria:**

- [ ] `Incentive#update_variables` role assignment covered: inputs and outputs both land with the right role, and the `delete_all` rebuild does not drop outputs.
- [ ] The ranking `find_or_create_by` branch covered — an incentive whose variable is both an input and an output of different rules produces both rows.
- [ ] An auxiliary variable reaches `plan_variables` and is not offered a goal on the plan-finish screen.

### Phase 4: Rule syntax validators — the blocker

**Objective:** a rule whose formula references an auxiliary variable key can be saved at all.

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

**Release 3.60.0 (2026-07-30) changed `validate_syntax` and does NOT resolve this.** The method now opens with a reasoned-error branch — `formula_error = formula.error` at `app/models/rule.rb:178`, returning `errors.add(:value, formula_error.reason, **formula_error.details)` when one is present. But `Formula#error` builds the AST and rescues only `Dentaku::ParseError` and `Dentaku::TokenizerError` (`app/models/formula.rb:14-21`). An unknown variable key parses and tokenizes cleanly; it fails at evaluation. So `formula.error` returns `nil`, execution falls through to `calculate!`, and the bare `:invalid` is still what the user sees. The blocker stands exactly as described.

**The same release also shipped the primitive this phase needs.** `Formula#referenced_identifiers` (`app/models/formula.rb:10-12`) tokenizes the formula and returns the distinct identifier names it references, without evaluating it — `app/CHANGELOG.md:27` records it as *"Identification of the variables a formula references"*. That is a direct answer to "which variable keys does this rule read", which both this phase and the plan-level validation need, and it is stronger than the `key_regex` text matching `Incentive#update_variables` uses today (`app/models/incentive.rb:149-175`), because it parses rather than pattern-matches. Prefer it wherever a phase needs the referenced set.

**Components:**

- Extend the synthetic options hash so auxiliary keys are bound for the incentive types that may read one — ranking, limiter and redemption. The four builder methods are `metrics_options` (`app/models/rule.rb:187`), `deal_extra_fields_options` (`:207`), `indicator_variables_options` (`:213`) and `easy_variables_options` (`:221`). (These line numbers have moved twice: SPIKE §4.5 cites `173,193,199,207` and an earlier draft of this plan cited `183,203,209,217`. Release 3.60.0 shipped on 2026-07-30 and pushed everything in `rule.rb` down — the numbers above are the current `develop` state, verified by opening the file. Cite this file by method name in review comments, not by line.)
- The same `rescue` applies at runtime — `calculate` returns `0` (`app/models/rule.rb:58-62`) — so a missing auxiliary value at calculation time yields zero, never an error. That behaviour is unchanged.

**Dependencies:** Phase 3 (the validator needs to know which auxiliary variables the company has).

**Success criteria:**

- [ ] A rule referencing an auxiliary key saves through the incentive mutation, on the incentive types that may read one.
- [ ] A rule referencing a genuinely unknown key still fails with `errors.add(:value, :invalid)`.

### Phase 5: Plan validation and the stage order

**Objective:** a plan whose incentive reads an auxiliary variable is rejected unless another incentive in the same plan, in a strictly earlier stage, exports it.

**Components:**

- **`Incentive::CALCULATION_ORDER`** — an ordered constant expressing Deal → Indicator → Ranking → Limiter → Redemption. That order has no representation in code today: it exists only in the enqueue graph across 41 call sites (mapped in `auxiliary-variables_pipeline_2.md`), and `Incentive::TYPES` (`app/models/incentive.rb:15`) is declared in a different order and carries no ordering semantics. **The enqueue graph remains the source of truth for execution; the constant becomes the source of truth for validation**, and a spec keeps the two aligned.
- **`Plan#auxiliary_variable_requirements`** — a fifth custom validation alongside the four at `app/models/plan.rb:58-61`, modelled on `redemption_incentive_requirements` (`:389-398`), which is its structural twin: it reasons over the plan's incentive set and adds to `:incentivations`. Two details differ from the twin. It must read `incentive_ids` (`app/models/plan.rb:421-425`), which excludes incentivations marked for destruction — the existing sibling uses `incentivations.map(&:incentive_id)` and does not. And the error must be added to `:incentivations` with **no dot**, so the bulk plan import reports it: `PlanDocument::Consumer` builds plans from a spreadsheet (`app/workers/plan_document/consumer.rb:158`, `:209`) and skips only attributes starting with `incentivations.` (`:212`, `next if attribute.to_s.start_with?('incentivations.')`).
- The plan picker filtered to compatible incentives (Phase 9) is the preventive form and is UX, not the guarantee. This validation is the guarantee.

**Dependencies:** Phases 3 and 4.

**Success criteria:**

- [ ] A spec asserting `CALCULATION_ORDER` matches the observed enqueue chain — this is the mechanism that keeps the constant and the graph from drifting.
- [ ] Validation branches covered: reader with no exporter; reader with an exporter in the same stage; reader with an exporter in a later stage; reader with an exporter in an earlier stage; two exporters into one variable.
- [ ] The bulk plan import surfaces the error rather than swallowing it.

### Phase 6: Materialization

**Objective:** the per-`(user_commission, variable)` auxiliary value exists, carries the sign it has for the person, and is correct under retry.

**Components:**

- **Write moment: at commissioning save, inside the existing consumer.** No new worker, no new `Computation` participation, no edit to the enqueue graph — which is also why the in-flight-deploy question does not arise for this feature at all.
- **Arithmetic: recompute, never `+=`.** `value = SUM(commissionings of the rules bound to this variable, for this user commission)`. Every `(user_commission, rule)` pair is an independent job (`app/workers/indicator_incentive/producer.rb:22`, `combinations = user_commission_ids.product(rule_ids)`), so a read-modify-write on a shared row loses updates; and Sidekiq is at-least-once, so `+=` is not idempotent while the recomputed sum is idempotent by construction.
- **What is summed: the signed, commission-type-aware expression, not the raw `value` column.** A money incentive's rules sum `Commissioning#money`; a points incentive's rules sum `Commissioning#points`. For a limiter that resolves to `value * -1` (`app/models/limiter_commissioning.rb`) — the negative contribution — and for every other stage it resolves to `value` unchanged (`app/models/commissioning.rb:60-70`). Beyond the engineer's worked example, this is what keeps a downstream formula's author ignorant of which incentive type produced the value: an unsigned publication would force the reader to know the writer's stage in order to know whether to add or subtract, which is exactly the incentive-to-incentive coupling the design removes.
- **Documented behaviour, not a defect to guard against:** `#money` returns zero when the incentive is points-typed and `#points` returns zero when it is money-typed, so an auxiliary variable bound by both a money rule and a points rule sums mixed units. That is the author's modelling choice — nothing in the platform prevents mixing units in a formula today, and no validation is added for it.
- **Storage: `aggregated_modifiers`.** Already unique on `(user_commission_id, variable_id)` (`db/schema.rb:86`), already purged on reprocess with no type scope (`app/workers/aggregated_indicator/purge/consumer.rb:17-21`), and already the source `IndicatorOptionsProcessor` reads. The write is an upsert against that unique index.
- **The race to close.** Two consumers writing to the same variable for the same user race on the *recompute*, not on the commissioning. The value is correct only if the aggregate query genuinely re-reads at that moment, inside its own transaction; a stale read produces a silently low number, which is the failure class the payroll cannot tolerate.
- **Writers: the indicator, ranking, limiter and redemption consumers.** Each persists only on a non-zero result — `indicator_incentive/consumer.rb:41`, `limiter_incentive/consumer.rb:40`, `ranking_incentive/consumer.rb:47`, `redemption_incentive/consumer.rb:37` — so a rule that evaluated to zero writes no commissioning row and therefore contributes nothing to the sum.
- **Retry idempotency is not uniform, and the materialization inherits it.** The indicator stage uses `IndicatorCommissioning.find_or_initialize_by(user_commission_id:, rule_id:)` (`app/workers/indicator_incentive/consumer.rb:54`), which survives a retry. The limiter, ranking and redemption stages construct a fresh record — `limiter_commissioning = LimiterCommissioning.new` (`app/workers/limiter_incentive/consumer.rb:41`) — so a retry hits the unique index at `db/schema.rb:457` and raises on `save!`. Redemption compensates by destroying its prior rows in its producer (`app/workers/redemption_incentive/producer.rb:30`); limiter and ranking do not. This is pre-existing and not introduced here; it bounds how much the materialization can rely on those rows being rewritable.
- **Guard the Calculator re-entry.** `AggregatedIndicator::Calculator::Producer` fans out over *every* row for the commission with no type scope (`app/workers/aggregated_indicator/calculator/producer.rb:20-21`) and its consumer calls `calculate!`, which falls back to `variable.format_default` when there are no `indicator_aggregations` — so any path re-entering the Calculator after auxiliary rows exist overwrites them with the default. Within one run the ordering makes this unreachable (the Calculator completes before any incentive stage begins). Closing the re-entry exposure means adding a type scope there.
- **Partial commissions.** Every worker in the chain branches on `partial` to load `PartialCommission` instead of `Commission` (e.g. `app/workers/indicator_incentive/consumer.rb:8-13`); `AggregatedIndicator#indicator` has a partial-specific `nil` return (`app/models/aggregated_indicator.rb:115-116`), so the materialization's zero-versus-absent semantics need checking against partials specifically.
- **Queue.** The work runs on the existing commission queue of the stage it hangs off, so nothing changes in `config/sidekiq_commission*.yml`, `config/initializers/hire_fire.rb` or Terraform.

**Cost recorded:** N recomputes per user per stage rather than one at the stage boundary — SPIKE §4.2b states it directly: *"Recomputing on every commissioning save is N times the work of recomputing once at the stage boundary for an identical result"*.

**Dependencies:** Phase 3. Independent of Phases 4-5, so it can run in parallel with them.

**Success criteria:**

- [ ] Several rules into one variable, and two incentives into one variable, produce the expected sum.
- [ ] A rule that evaluated to zero — and therefore wrote no commissioning row — contributes nothing.
- [ ] The engineer's worked example closes: two positive contributions and one limiter contribution of the same magnitude publish 300 + 200 − 100 = 400, which pins the signed expression against the raw `value` column.
- [ ] Idempotency under retry: running the materialization twice leaves the value unchanged. This is the property SPIKE §4.2b exists to protect and it is invisible in a single-run test.
- [ ] A reprocess clears the auxiliary rows (the purge at `aggregated_indicator/purge/consumer.rb:17-21` is unscoped, so this is free) and recomputes them.

### Phase 7: Read path

**Objective:** the materialized value reaches every consuming rule's Dentaku options hash.

**Components:**

- **The frozen snapshot already carries auxiliary keys.** It is written once, before any incentive stage (`app/workers/user_commission/indicator_options_consumer.rb:16-17`), and that consumer enqueues `DealIncentive::Producer` at `:22`. Because `IndicatorOptionsProcessor` reads `plan.variables` unscoped (`app/services/commission/indicator_options_processor.rb:41`), auxiliary keys land in the snapshot carrying their default — so a consuming formula reads a default until the fresh merge overwrites it, never an unbound variable.
- **A new `Commission::<name>OptionsProcessor`** alongside the six existing ones in `app/services/commission/` (`deal_options_processor.rb`, `deal_options_v2_processor.rb`, `indicator_options_processor.rb`, `limiter_options_processor.rb`, `ranking_options_processor.rb`, `redemption_options_processor.rb`). Two named precedents exist and differ: `RedemptionOptionsProcessor` computes inside the consumer, `LimiterOptionsProcessor` computes in a dedicated preceding stage and persists onto the user commission. Both merge last, after `modifier_options`.
- **The merge, in the three reading stages:**

| Consumer | Line | Current expression the merge joins |
|---|---|---|
| `app/workers/ranking_incentive/consumer.rb` | 44 | `options = deal_options.merge(modifier_options).merge(ranking_options)` |
| `app/workers/limiter_incentive/consumer.rb` | 37 | `options = deal_options.merge(modifier_options).merge(limiter_options)` |
| `app/workers/redemption_incentive/consumer.rb` | 34 | `options = deal_options.merge(modifier_options).merge(redemption_options)` |

- **The indicator consumer does not merge.** It is the first writer; nothing has been written before it. Its line 29 (`options = deal_options.merge(user_commission.modifier_options)`) is untouched.
- **The deal stage is untouched, and that is what makes it safe.** It does not merge the snapshot wholesale — it filters it down to metric keys (`app/workers/deal_incentive/consumer.rb:30-32`, and the same shape at `app/workers/deal_incentive/period_processor.rb:20`), so an auxiliary key is filtered out by that `select` with no code change.
- Data access follows `~/.claude/docs/DATA-ACCESS.md`: `with_uncached_connection` around each access, IDs not loaded objects, associations navigated per record rather than joined.

**Dependencies:** Phase 6 (nothing to read otherwise) and Phase 4 (no rule can name the variable otherwise).

**Success criteria:**

- [ ] A rule in a ranking, limiter or redemption incentive reading an auxiliary variable evaluates against the materialized value, not the default.
- [ ] A plan with no auxiliary variable produces byte-identical options hashes to today.

### Phase 8: GraphQL surface and the permission

**Objective:** the authoring surface exists on the API, and the feature is reachable by nobody until the permission is granted.

**Components:**

- **Fields and arguments.** An output-variable field on `RuleGraphqlType` (`app/graphql_types/rule_graphql_type.rb:3-14`, which today exposes `commissionings`, `created_at`, `description`, `document_line`, `id`, `incentive`, `incentive_id`, `type`, `updated_at`, `value` and no variable field); the matching argument on `RuleInputGraphqlType` (`:4-8`); a `role` field on `IncentiveVariableGraphqlType` (`:4-7`) so the plan-side picker can distinguish inputs from outputs.
- **Both mutation rule allow-lists.** `create_incentive_graphql_mutation.rb:43-47` (`rules: %i[ description type value ]`) and `update_incentive_graphql_mutation.rb:39-45` (`rules: %i[ _destroy description id type value ]`). These are explicit `%i[...]` arrays — an unlisted argument is silently dropped.
- **The clone gap, which is the sharpest backwards-compatibility risk in the feature.** There is no backend clone mutation: `clone` is a permission and a UI action only — `IncentivePolicy#clone?` (`app/policies/incentive_policy.rb:28-33`), the permission string `incentive_clone` (`app/workers/company/admin/processor.rb:31`), and `actions << 'clone' if policy.clone?` (`app/graphql_types/incentive_graphql_type.rb:49`). The front has a clone component per incentive type (e.g. `app-webclient/src/app/indicator-incentives/clone/`) that prefills the create form, so a clone goes through `CreateIncentiveGraphqlMutation`. **Unless its allow-list carries the output binding — and the front clone builders carry it too (Phase 9) — a cloned incentive silently loses its bindings and produces a plan that validates but computes a different number.**
- **Migration M4 — the permission `Action` row**, created by a data migration in the established pattern (`db/migrate/20260729113439_user_update_document_actions.rb:5`, `Action.create!(key: ..., level: 'module', resource: ...)`), plus the key added to the hardcoded `MODULE_KEYS` list in `app/workers/company/admin/processor.rb:16-52` (where `incentive_clone` sits at line 31). The processor iterates that list at `:77-83` and resolves each key with `Action.get`, which goes through `ApplicationRecord.get_id` (`app/models/application_record.rb:134-140`) ending in `find_by!` — **so a key listed in `MODULE_KEYS` with no `Action` row raises `RecordNotFound` and the processor dies. M4 must land in the same deploy as the `MODULE_KEYS` entry, never after it.** M4 is also not idempotent: `Action.create!` raises on a re-run.
- **The gate** follows the shape of every sibling in `IncentivePolicy` (`app/policies/incentive_policy.rb:8-10`, `role.permission?('incentive_creation') || user.permission?('incentive_creation')`).
- **Contract constraints that must not be violated.** Every argument on `RuleInputGraphqlType` is `required: false` today, and the frontend declares the input type by name (`$rules: [RuleInputGraphql!]`) — so a newly-**required** argument would fail validation on every existing client, and the type name must not change. `field :type, String, null: false` (`app/graphql_types/variable_graphql_type.rb:33`) is a `String`, not a GraphQL enum, which is why a fourth type value is not a client-visible schema change. `Variable.for_type` (`app/models/variable.rb:55`) already backs the resolver's type filter (`app/graphql_resolvers/variable_graphql_resolver.rb:21`), and `create_variable_graphql_mutation.rb:4-11,30-40` already lists `type` in both arguments and `permit`, so creating an auxiliary variable needs no mutation change.

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
- **The plan-side picker**, offering only incentives compatible with the auxiliary variables already present. The plan create form builds `incentivationsAttributes` via `IncentivationCreateFormBuilderService` (`app-webclient/src/app/plan/create/plan-create-form-builder.service.ts:23`); the picker needs each candidate incentive's auxiliary inputs and outputs, which is why `IncentiveVariableGraphqlType` gains `role`. This is UX; the plan validation from Phase 5 is the guarantee.
- **The variable creation screen** (`app-webclient/src/app/variable/create/variable-create-form-builder.service.ts`) already has a `type` control with a required validator, so offering the fourth type is a list change rather than a form change. Its `variableCalculation`, `variableFrequency` and `variableOverrideCalculation` helpers are conditionally required, matching the model where those three are validated only `if: :indicator?` — an auxiliary variable follows the deal/easy shape and requires none of them.

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
- **The migration window.** In `app/.github/workflows/deploy-shared-001.yaml` the `prepare-and-migrate` job (`:371`) builds and pushes the image (`:384`, `image-tag: latest` at `:396`) and then runs `bin/rails db:migrate` (`:403`, `:458`), while the job that activates the new code depends on it and runs later (`:616`, `:621`). **Between those two points the schema is new and every serving container is old.** M1's default is what makes that window safe; M2 is nullable and unread by old code; M3 is safe once M1's default is in place; M4 changes no old-code behaviour. Nothing needs splitting, and there is no contract half — nothing is dropped or rewritten. `strong_migrations` is active with default checks (`Gemfile:78`; the initializer is `StrongMigrations.auto_analyze = true` with no `start_after` and nothing disabled).
- **Rollback is a redeploy of the previous image at every step.** The columns stay — rolling back a migration is not part of the deploy flow — which is harmless because the old code never reads them, and M1's default keeps the old code writing valid rows. Auxiliary rows already written become unread and are purged by the next reprocess. There is no point of no return: nothing drops a column, rewrites data, or changes an existing cross-service contract. The closest candidate is a commission already calculated with auxiliary values — reverting the code stops producing new ones and a reprocess under the old code reproduces the old result, which is a recovery path rather than an irreversibility, but a reprocess on a productive stack is not free.

**Dependencies:** Phases 1-8. **Running the deploy is the engineer's** — an action outside version control that a PR diff neither shows nor reverts. The shape above is decided; the execution and its timing are not.

**Success criteria:**

- [ ] On `beta-001`: a commission with no auxiliary variables completes end to end, unchanged; one with an auxiliary variable produces the expected value; a rule naming an auxiliary key saves; a plan missing an exporter is rejected and the document import reports it.
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
| `incentive_variables.role` storage | Integer column with `enumerize`, default `input` | House pattern — `Variable#calculation` (`app/models/variable.rb:66`) and `Plan#status` (`app/models/plan.rb:98`) both use `enumerize`. The default is what makes M1 transparent to the old code during the migration window |
| The `Rule` output association name | `belongs_to :output_variable, class_name: 'Variable', optional: true` | § Association Naming — `output` distinguishes direction rather than restating the owner, so the stutter test keeps it. `optional: true` plus manual validation is the house rule; here no manual presence validation, because the binding is optional |
| Which stages write and which read | Writes from the indicator stage onward; reads in ranking, limiter and redemption. The deal stage neither writes nor reads | § Scope Discipline (the minimum that satisfies the request) plus SPIKE §5, which records that this *"makes the machinery substantially smaller and still covers the Colombia case"*. Avoids the metric-key `select` bypass at `deal_incentive/consumer.rb:31` |
| Is the binding mandatory per rule | Optional | The engineer's own description — *"ele pode salvar só uma faixa ou ele pode salvar todas"* is impossible if every rule must bind |
| Materialization placement and storage | Recompute the sum (never `+=`) at commissioning save, stored in `aggregated_modifiers` | The engineer specified the write moment (*"toda vez que criar um commissioning"*); recompute rather than increment is forced by Sidekiq at-least-once (SPIKE §4.2b). `aggregated_modifiers` is already the per-`(user_commission, variable)` store, already purged on reprocess, already on the read path — § No Premature DRY rejects a new table with no benefit yet. **Cost recorded**: N recomputes per user per stage rather than one at the stage boundary |
| What the recompute sums | The signed, commission-type-aware expression, not the raw `value` column — `Commissioning#money` for a money incentive, `Commissioning#points` for a points one; `value * -1` for a limiter (`app/models/limiter_commissioning.rb`), `value` unchanged elsewhere (`app/models/commissioning.rb:60-70`) | The engineer's stated requirement, source 1 on the `DECISION-AUTHORITY.md` ladder. His worked example of what the feature must express is *"essa pessoa ganhou R$ 300 nesse incentivo, R$ 200 nesse e perdeu R$ 100 nesse outro aqui. Resultado final: R$ 400."* — the limiter appears as −100, and 300 + 200 − 100 = 400 holds only if the published value carries the sign as it affects the person's result; summing the raw `value` column would publish +100 and the arithmetic would not close. Independently: an unsigned publication would force a downstream formula's author to know which incentive type produced the value in order to know whether to add or subtract, reintroducing exactly the incentive-to-incentive coupling this design removes. **Consequence recorded, not guarded against**: `#money` returns zero for a points-typed incentive and `#points` zero for a money-typed one, so a variable bound by both a money rule and a points rule sums mixed units — the author's modelling choice, and no validation is added for it |
| Publish-only vs publish-and-pay | Publish-and-pay only. The rule creates its commissioning exactly as today; publishing is purely additive | § Scope Discipline. Nothing is excluded from any existing sum, `premio_grupo` is untouched, and the payment-type constraint at `app/models/commissioning.rb:13,17` is satisfied because the row exists anyway. No per-rule flag until someone asks for one |
| Do auxiliary variables reach `plan_variables` | Yes, with goal binding suppressed for the type | The only combination that works — the read path requires them there, and leaving goal binding on would surface them in the goal UI |
| Where the stage order lives | Ordered constant `CALCULATION_ORDER` on `Incentive`, plus a spec asserting it matches the enqueue graph | The spec is the sync mechanism the "nothing keeps them in sync" objection asked for. A single ordered constant is the standard shape; the alternative spreads the order across five STI subclasses |
| Does the incentive CSV import support the binding | No — documented limitation | § Scope Discipline. Not requested, and it changes a customer-facing template (`app/workers/incentive_document/processor.rb:81-86`) |
| Deploy shape | One backend deploy, then one frontend release | `DEPLOYMENT-STRATEGY.md` phases **only** if a trigger fires. The `Computation` key derivation is unchanged (`plan_#{id}`, `app/models/plan.rb:166-168`), job argument shapes are unchanged, and the materialization decision makes the step idempotent — no trigger fires, so a single backend deploy is legitimate by the framework's own rule. **The act of deploying remains the engineer's** — that is the residue, not the shape |
| Zero handling | The auxiliary type constrains `default` to zero | Materializing explicit zero rows would write one row per non-firing rule per user for no read benefit (SPIKE §4.3) |
| The unscoped reads flagged for a decision | Both commission indicator worksheets get `.indicators` on the lookup; `CalendarAudit`'s expected-count query excludes auxiliaries; the variable audit workbook keeps them | Per site, from each site's own purpose. The worksheets already gate on `variables.indicators.exists?` at their line 12 — scoping line 29/36 restores the file's own declared subject. An auxiliary has no integration source, so counting it as "expected" produces a permanent false gap. The audit workbook is a configuration catalog with a type column and already renders blank frequency for deal and easy variables (`app/work_books/variable_audit_work_book/variables_work_sheet.rb:15-38`) |
| Materialization queue | Reuse the existing commission queue of the stage it hangs off | Zero cost — no new YAML entry, no new HireFire dyno block, and no Terraform change, since a worker service is declared by config-file path rather than by queue list (`terraform/app-shared-001/terraform.tfvars:110`) |

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A cloned incentive silently loses its output bindings | High — a plan validates and computes a different number than the operator authored | Extend both mutation allow-lists and all five front clone builders in the same change (Phases 8 and 9); cover with a test that clones and asserts the binding |
| The recompute reads a stale aggregate, so the last writer does not observe both commissionings | High — a silently low number, the failure class the payroll cannot tolerate | The write is an upsert against the existing `(user_commission_id, variable_id)` unique index (`db/schema.rb:86`) and the aggregate query re-reads inside its own transaction at the moment of write (Phase 6) |
| The Calculator overwrites auxiliary rows with the variable default | Medium — a silently zeroed auxiliary value | Unreachable within a single run by the chain's ordering (the Calculator completes before any incentive stage begins); the exposure is re-entry, closed by a type scope at `app/workers/aggregated_indicator/calculator/producer.rb:20-21` |
| Limiter and ranking commissioning writes are not retry-idempotent | Medium — a retried job raises on the unique index, and a commissionings-based sum inherits whatever those rows hold | Pre-existing, not introduced here. It bounds how much the materialization can rely on those rows being rewritable; redemption already compensates in its producer (`app/workers/redemption_incentive/producer.rb:30`), limiter and ranking do not |
| The stage order becomes a second representation of the enqueue graph | Medium — drift between validation and execution | The enqueue graph stays the source of truth for execution; a spec asserting `CALCULATION_ORDER` matches the observed chain is the sync mechanism (Phase 5) |
| The calendar-audit fan-out multiplies by `periods × users` per auxiliary variable | Medium — audit job volume grows per plan | Scoped in Phase 2 (`app/workers/calendar_audit/producer.rb:19-20` and `app/models/calendar_audit.rb:30`) |
| The ranking branch's `find_or_create_by` finds an output row and skips creating the input row | Medium — an incentive silently loses an input registration | `app/models/incentive.rb:172` gains a role scope in Phase 3; M3's unique index is where the defect would surface |
| The implementation sums the raw `value` column instead of the signed expression | Low — the choice is settled, so what remains is a coding slip rather than an open question | The recompute sums `#money` / `#points` per commission type, so a limiter contributes negatively. Phase 6 carries the test that reproduces the engineer's 300 + 200 − 100 = 400 example, which fails if the raw column is summed |
| M4's `Action.create!` is re-applied | Low — the migration raises | Not idempotent by construction; it must not be re-applied. It is a re-run hazard, not a rollback hazard |

---

## Assumptions

- **Only `app` and `app-webclient` are affected.** A grep for `IncentiveVariable`, `PlanVariable`, `aggregated_modifier`, `Commissioning` and `incentive_variables` across `onboarding`, `setup`, `integrator` and `lambda` returned no matches. `app-sdk-advpl`, `app-sdk-dotnet` and `app-mobileclient` were not opened, so whether either SDK models `Incentive` / `Rule` / `Variable` is unverified.
- **`/api/v3/` is not an authoring path for incentives, rules or plans.** `app/controllers/api/v3/` holds `clients`, `deals`, `goals`, `groups`, `indicators`, `products`, `roles`, `subsidiaries`, `users` and nothing else, and `grep -rn "incentive" config/routes.rb` returns nothing. The integrator feeds `indicators`, which feed `IndicatorVariable` values — auxiliary variables are never fed by it, which is the design's premise.
- **`Incentivation` needs no change.** It carries three foreign keys and one validation concern (`app/models/incentivation.rb:4-10,24-29`; `db/schema.rb:937-948`). The binding lives on `Rule`, the registration on `incentive_variables`, and the plan validation reaches incentives through `incentivations.incentive_id`, which already exists and is already what `Plan#redemption_incentive_requirements` uses (`app/models/plan.rb:392`). The engineer's earlier statement about altering the model traces to a superseded draft that put the binding on `Incentivation` — SPIKE §4 records the move at line 124.
- **The backwards-compatibility surface is bounded by `IncentivePolicy#update?`.** `return false if record.plans.any?` (`app/policies/incentive_policy.rb:12-19`) means an incentive attached to any plan is not updatable through the mutation, so no existing productive incentive can acquire an output binding and no existing plan's arithmetic can change without a new incentive being authored and added to a plan. Every risk above is scoped to newly-authored incentives.
- **The in-flight-commission reasoning is inference from read facts, not an executed test.** It rests on the `Computation` key derivation being unchanged (`app/models/plan.rb:166-168`, `app/models/computation.rb:48-54`), job argument shapes being unchanged, and the successor being resolved at execution time rather than carried in the payload (`app/workers/indicator_incentive/finalizer.rb:22`, `app/workers/tenant_worker.rb:51-58`). Under the chosen materialization the enqueue graph is not edited at all, which narrows the question further. Confirming it on `beta-001` — start a commission, deploy mid-chain, confirm completion — is available if the engineer wants the stronger guarantee before the first productive deploy.
- **A stalled chain cannot be resumed after 12 hours.** `Counter::DEFAULT_EXPIRATION_TIME = 12.hours.to_i` (`app/models/counter.rb:4`), refreshed on every increment, and `Counter#value` reads `connection.get(@key).to_i` (`:48-52`) — so once both keys expire, `done?` evaluates `0 == 0` and returns true even though the work never finished. A deploy window is minutes, so this is not reachable during a deploy; it matters because any manual recovery of a long-stalled chain must reprocess, not resume.
- **The two proposal decks named in SPIKE §6 remain unreviewed** — neither file is on this machine, so the interface proposal has not been read. If it constrains the authoring surface, Phase 9 should be re-sized against it.
- **`app/docs/architecture/PARALLEL_PROCESSING.md` does not exist.** `DEPLOYMENT-STRATEGY.md` cites it four times with line numbers and `app/CLAUDE.md` links `DATA-PROCESSING.md` in its place. Every `Computation` fact above was therefore read from `app/models/computation.rb` and `app/models/counter.rb` directly.
- **The autoscaling Lambda's own source** (the `worker-commission-autoscaling` package) was not read — only the environment Terraform supplies it. Whether it does anything per-queue beyond consuming the HireFire endpoint is unverified. The chosen queue decision makes this moot for this feature.

---

> **Authoring:** written by `@agent-plan-composer` from a validated `PLAN-SPIKE.md` plus the engineer's communicated choice. No new options, no new technical decisions, no new assumptions were introduced at the composer stage — every claim traces to the draft or the engineer's choice.
