# PLAN — Commissioning-metric variables in `app`

> Reference: `DOMAIN.md` in this directory is the authoritative current-state model. Background design
> record: `PLAN-SPIKE.md` and its auxiliary files `output-variables_call-sites_1.md`,
> `output-variables_pipeline_2.md`, `output-variables_rollout_3.md`, plus
> `~/Projects/4Shark/dot-claude-plans/active/spike/incentive-calculated-variables/SPIKE.md` §4.
> Repository: `~/Projects/4Shark/app` (backend) and `~/Projects/4Shark/app-webclient` (frontend),
> branch `develop`.
> Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).
>
> The `PLAN-SPIKE.md`, `TASKS-SPIKE.md` and the three auxiliary files predate the pivot and describe the
> earlier "fourth `OutputVariable` type" approach; where they conflict with this plan, the
> commissioning-metric model governs. `TASKS.md` § Status maps merged PRs to delivered work.

## Objective

A variable whose value the system produces from commission results — not from the integration — is an
ordinary `IndicatorVariable` that carries a `CommissioningMetric`. A `CommissioningMetric` links to a set
of `Rule`s; within a plan, per user, it aggregates (sum or average) the commissionings those rules
produced and writes the result as that user's internal `Indicator` for the variable. A later incentive
stage then reads that already-computed value by the variable's key, instead of the raw per-rule bands.

The feature is therefore a **specialization of `Metric`**, not a new variable type: `Metric` is an STI
base with `DealMetric` (aggregates deals over an interval — the pre-existing behaviour) and
`CommissioningMetric` (aggregates commissionings per plan/user — this feature). Both write the variable's
internal `Indicator`; they differ only in the source of the value.

At plan save, two validations hold over commissioning-metric variables: an incentive that **reads** one
requires an earlier-stage incentive whose rule **feeds** its metric (validation 1, enforced), and every
incentive that feeds one metric must be of a single incentive type (validation 2, not yet implemented).
Stage order: deal → indicator → ranking → limiter → redemption.

## Scope

### In scope

- The `Metric` STI base and its `DealMetric` / `CommissioningMetric` subtypes. **(delivered — #5431)**
- The rule link `Rule belongs_to :commissioning_metric`, replacing the earlier `output_variable` link. **(delivered — #5433)**
- Plan-level validation 1 — a reader requires an earlier-stage feeder, per incentive type. **(delivered — #5434)**
- Plan-level validation 2 — a single writer (feeding) incentive type per commissioning-metric variable. **(open — design + build)**
- Materialization: the `CommissioningMetric` computes its per-user value from the commissionings of its
  linked rules and writes the variable's internal `Indicator`. **(open — mechanism not yet built)**
- The read path that delivers the materialized value to a consuming rule. **(open — likely the existing indicator read path; to confirm)**
- Variable availability by incentive type — a commissioning-metric variable is excluded from the deal
  (transactional) incentive and selectable as a rule's feeding target elsewhere. **(open — placement undecided)**
- GraphQL authoring surface — expose the `commissioning_metric` binding on the rule create/update
  mutations and types, and close the clone gap. **(open — build; naming to settle at implementation)**
- The binding permission — the release toggle. **(open — build)**
- The `app-webclient` authoring surface: the commissioning-metric control on a rule, its replication
  across an incentive's rules, and the plan-side compatible-incentive picker. **(open — build)**
- **The statement display.** Three marks the engineer named: the commissioning-metric variable appears
  in the upper variable listing carrying its composed value; every commissioning that fed a metric is
  marked with which variable it fed; every commissioning whose rule reads a metric-fed variable is marked
  as having been calculated on one. The person accepting the declaration signs it
  (`statement-accept.component.html` collects a drawn signature), so a value that influences payment
  without appearing on the screen is a value signed unseen — the spike names this half as *"the piece
  that satisfies the legal requirement"*. **(open — build)**
- Test strategy, data migration, rollout sequence, execution order.

### Out of scope

- The incentive CSV bulk import of the binding. `IncentiveDocument::Processor` builds rules from
  positional CSV columns (`app/workers/incentive_document/processor.rb:81-86`, `row[0]` for value and
  `row[1]` for description); adding the binding changes a customer-facing template format. Documented as a
  limitation instead.

---

## Chosen approach

**Direction:** a `Metric` specialization, executed as a single backend change followed by a single
frontend release. The distinguishing trait of these variables is **who writes them**, not what they are:
a variable the user cannot register because the system computes its value is already modeled today as an
`IndicatorVariable` that has a `Metric` (`variable.rb:30`, `has_one :metric`), and a variable with a metric
already has all its indicators system-generated — enforced by `Metric#indicators_existence`
(`metric.rb:50-55`, the variable must carry no external indicator) and sealed on the read side by
`Indicator#internal_variable` (internal indicator ⟺ variable has a metric).

Concretely:

- **`Metric` is the STI base.** `Metric::TYPES = %w[DealMetric CommissioningMetric]` (`metric.rb:5`),
  `Metric::CALCULATIONS = { total: 0, quantity: 1, sum: 2, average: 3 }` (`metric.rb:4`). The base carries
  `belongs_to :variable` (unique — `index_metrics_on_variable_id`), and the base validations
  `variable_type` (numeric + indicator, `metric.rb:43-48`) and `indicators_existence`
  (`metric.rb:50-55`). Each subtype slices its own calculations and declares its own `enumerize`.
- **`CommissioningMetric < Metric`** (`commissioning_metric.rb`): `CALCULATIONS = sum | average`,
  `has_many :rules` (the rules whose commissionings feed it), and `validates :calculation`.
- **`DealMetric < Metric`** (`deal_metric.rb`): the pre-existing behaviour — `CALCULATIONS = total | quantity`,
  the interval/comparator/date columns, `#calculate` via `TotalAdapter` / `QuantityAdapter`.
- **The rule points at the metric, not at a variable.** `Rule belongs_to :commissioning_metric, optional: true`
  (`rule.rb:17`); `CommissioningMetric has_many :rules, dependent: :nullify` (`commissioning_metric.rb:6`).
  A rule contributing its commissioning to a metric fits the existing STI-by-incentive-type shape
  (`rule.rb:15`), and the metric already guarantees the variable is correct (indicator, numeric, no
  external indicator), so the earlier per-rule `output_variable_type` validation is gone.
- **No fourth variable type.** `Variable::TYPES = %w[DealVariable IndicatorVariable EasyVariable]`
  (`variable.rb:4`) is unchanged; the commissioning-metric variable is an `IndicatorVariable`. The unique
  `variable_id` index on `metrics` already guarantees a variable has at most one metric of any subtype, so
  it can never be both deal- and commissioning-fed — no new constraint.
- **Any stage's rule may feed a metric; reading is constrained to every stage except the deal stage.**
  The deal stage feeds but never reads; it is the exporter an indicator reader depends on, since the
  indicator stage is the first stage that may read and the deal stage is the only stage strictly before it.
- **Plan-level validation, backed by an ordered stage constant, rejects a plan whose reader has no feeder
  in a strictly earlier stage** (validation 1, enforced). Reader ← eligible feeder stages: indicator ←
  deal; ranking ← deal, indicator; limiter ← deal, indicator, ranking; redemption ← deal, indicator,
  ranking, limiter.
- Rollout is one backend deploy per environment, then one frontend release, then the permission grant per
  account.

**Rationale (from engineer):** the value is recomputed *"toda vez que criar um commissioning"* — the
engineer specified the write moment; recompute rather than increment follows from Sidekiq being
at-least-once (`SPIKE §4.2b`), which makes `+=` non-idempotent while `value = aggregate(feeding commissionings)`
is idempotent by construction. And the published value carries its sign, because the engineer's worked
example of what the feature must express is *"essa pessoa ganhou R$ 300 nesse incentivo, R$ 200 nesse e
perdeu R$ 100 nesse outro aqui. Resultado final: R$ 400."* — the limiter appears there as −100, and the
arithmetic closes only if the sign travels with the value. **How the metric's recompute is triggered and
where it writes in the commissioning-metric model is an open design point** (see § Materialization).

**Source patterns referenced:**

| Pattern | Where it comes from |
|---|---|
| STI subtype slicing a base's constant + its own `enumerize` | `commissioning_metric.rb`, `deal_metric.rb` over `metric.rb:4` |
| A metric writing a variable's internal indicators | `DealMetric` (the existing deal-based metric path) |
| Plan-level validation reasoning over the incentive set | `Plan#redemption_incentive_requirements` (`app/models/plan.rb`), the structural twin of validation 1 |
| Per-incentive-type dispatch of a plan validation | `Incentivation#commissioning_metric` → `Incentivation::<Type>IncentivationMetricValidator` (delivered) |
| Options processor merged last, after `modifier_options` | `Commission::RedemptionOptionsProcessor` / `Commission::LimiterOptionsProcessor` |
| Worker/data access | `~/.claude/docs/DATA-ACCESS.md` — `with_uncached_connection`, IDs not loaded objects, associations navigated per record |

---

## Execution phases

Phases carry a status. **Delivered** phases are merged to `develop` and reconciled to what shipped;
**open** phases are re-planned in the commissioning-metric model and carry the design questions that must
be answered when the phase is picked up. Under the chosen deploy shape all backend phases ship in a single
backend deploy and the frontend in a single release, so the phase boundaries are ordering and review
units, not deploy units.

### Phase 1: The `Metric` STI base and the two subtypes — DELIVERED (#5431)

`metrics.type` STI discriminator added and every existing row backfilled to `DealMetric` (all current
metrics are deal-based). `Metric::TYPES`, `CommissioningMetric` (calc sum/average, `has_many :rules`) and
`DealMetric` (calc total/quantity, the interval columns, `#calculate`) exist. No fourth variable type was
added; `Variable::TYPES` is unchanged. The deal-shaped uniqueness index became `DealMetric`'s concern; a
`CommissioningMetric`'s uniqueness is the existing unique `variable_id`.

### Phase 2: The rule link — DELIVERED (#5433)

`rules.output_variable_id` → `rules.commissioning_metric_id`; `Rule belongs_to :commissioning_metric`
(`rule.rb:17`). The output-variable type and its per-rule `output_variable_type` validation were removed.
Clean, because the feature is unlaunched (no production rows).

### Phase 3: Registration — DELIVERED, then reworked by the pivot (#5348 → #5431/#5433)

The earlier registration (`#5348`, `incentive_output_variables` / `plan_output_variables` entities) was
superseded when the pivot removed the output-variable type. In the commissioning-metric model the
feeding relationship is carried directly by `CommissioningMetric has_many :rules` and `Rule belongs_to
:commissioning_metric` — there is no separate registration entity.

**OPEN — the plan-set comparison.** Validation 1 (delivered) reasons per incentivation over the plan's
incentive set. Any future need to answer "which commissioning-metric variables does this plan write vs
read" as a set (for the authoring picker, or validation 2) must be derived from the incentives' rules and
their metrics, not from the removed `plan_output_variables` roll-up. How that set is computed and where it
is cached (if at all) is undecided.

### Phase 4: Rule syntax validation for a metric-fed key — DELIVERED / to confirm

A consuming rule references the commissioning-metric variable **by its key**, and that variable is an
ordinary `IndicatorVariable`, so its key is already in the indicator read scope that `Rule::Options`
builds — a downstream indicator/ranking/limiter/redemption rule referencing it should already pass the
name-comparison syntax check (`Rule#syntax`, `rule.rb:98-113`; `Rule#unknown_identifier`, `rule.rb:83-85`).
The deal (formula) stage carries no such key and correctly refuses to read one.

**OPEN — confirm the scope boundary.** Verify that a metric-fed variable's key is permitted for the four
reading stages and withheld from the deal stage exactly as the design requires, and that no extra scope
change is needed. If the metric-fed variable must be distinguished from an ordinary indicator variable at
syntax time, that distinction is net-new. Cover with tests.

### Phase 5: Plan validation and the stage order — DELIVERED (#5434), validation 2 OPEN

Validation 1 is enforced: `Incentivation#commissioning_metric` dispatches per incentive type to
`Incentivation::<Type>IncentivationMetricValidator` (`app/services/incentivation/`), each of which reads
the variables the incentive consumes (`IncentiveVariable.where(incentive_id:)`), the metrics behind them
(`CommissioningMetric.where(variable_id:)`), and whether an earlier-stage incentive's rule feeds each
metric (`Rule.where(incentive_id:, commissioning_metric_id:)`) — filtering `marked_for_destruction?`
in-memory so a removal in the same save counts. A metric with no earlier feeder adds
`metric_not_populated` on the incentivation's `:incentive_id` (the frontend lists per-`incentive_id`
errors after submit). The `INCENTIVE_TYPES` allow-list per validator encodes the strictly-earlier stage
order (Indicator ← DealIncentive; Ranking ← Deal, Indicator; Limiter ← Deal, Indicator, Ranking;
Redemption ← Deal, Indicator, Ranking, Limiter).

**OPEN — validation 2 (single writer type per metric).** Every incentive that feeds one
commissioning-metric variable must be of a single incentive type, so the variable is written at a single
calculation stage and holds one value per plan; feeders of two types would write it at two stages and give
it two values. The error is added on the `Incentivation` at plan save. Not yet implemented; its dispatch
likely mirrors validation 1's per-type family. **`Incentive::CALCULATION_ORDER`** — an ordered constant
Deal → Indicator → Ranking → Limiter → Redemption, kept aligned to the enqueue graph by a spec — is the
shared primitive both validations reason over; confirm whether validation 1 already introduced it or
whether the order is currently encoded only in the per-validator allow-lists.

### Phase 6: Materialization — OPEN (mechanism not yet built)

**Objective:** a `CommissioningMetric`, within a plan and per user, computes its value from the
commissionings of its linked rules and writes the user's internal `Indicator` for the variable, carrying
the sign the value has for the person, correct under retry.

**What DOMAIN.md settles:** the metric sums or averages (`calculation`) the commissionings of its
`has_many :rules`, per plan per user, and the result is the variable's internal `Indicator` — the same
role `DealMetric` fills for deal-based indicators. A commissioning is the computed result of one rule for
one user (`Commissioning belongs_to :rule`, `belongs_to :user_commission`).

**OPEN design questions the phase must answer:**

- **The trigger and the writer.** `CommissioningMetric` has no `#calculate` yet (unlike `DealMetric#calculate`),
  and there is no adapter that aggregates over commissionings. When does the metric recompute — at
  commissioning save inside the existing consumer, or at a stage boundary — and which worker writes the
  indicator? The engineer's *"toda vez que criar um commissioning"* points at commissioning save, but the
  writer in the commissioning-metric model is undecided.
- **Where the value is stored.** The earlier plan wrote `aggregated_modifiers`; the commissioning-metric
  model writes the variable's **internal `Indicator`** instead. Confirm the exact store (`indicators` /
  `aggregated_indicators` / `indicator_aggregations`) the metric-produced value lands in so the read path
  finds it.
- **The signed, commission-type-aware aggregate.** The value summed is the signed expression, not the raw
  `value` column — `Commissioning#money` for a money incentive, `Commissioning#points` for a points one;
  a limiter resolves to `value * -1` (`app/models/limiter_commissioning.rb`) and every other stage to
  `value` (`app/models/commissioning.rb`). `average` divides by the count of feeding commissionings, not
  by a fixed denominator — confirm the average's denominator semantics.
- **Recompute, never `+=`.** `value = aggregate(commissionings of the metric's rules, for this user)`;
  a read-modify-write on a shared row loses updates and is not idempotent under Sidekiq at-least-once.
- **The stale-read race.** Two feeders writing the same metric variable for the same user race on the
  recompute; the aggregate must re-read inside its own transaction at the moment of write, or a stale read
  produces a silently low number — the failure class payroll cannot tolerate.
- **Retry idempotency of the feeding commissionings is not uniform** (pre-existing): indicator uses
  `find_or_initialize_by` and survives a retry; limiter/ranking/redemption construct fresh records.
  This bounds how much the aggregate can rely on those rows being rewritable.
- **Partial commissions** branch on `partial` throughout the chain; the metric's zero-versus-absent
  semantics need checking against partials.

### Phase 7: Read path — OPEN (likely the existing indicator read path)

**Objective:** the materialized value reaches every consuming rule.

Because the metric-produced value is the variable's **internal `Indicator`**, a consuming rule may already
read it through the existing indicator options path rather than through a new options processor, which is
a simplification the pivot buys over the earlier `aggregated_modifiers` merge.

**OPEN — confirm the delivery.** Establish whether a rule in an indicator/ranking/limiter/redemption
incentive reading a metric-fed variable's key already evaluates against the materialized indicator, or
whether a merge step (a `Commission::<name>OptionsProcessor` alongside the six existing ones) is still
required and in which of the four reading consumers. A plan with no commissioning-metric variable must
produce byte-identical options hashes to today.

### Phase 8: GraphQL surface and the permission — OPEN (build)

**Objective:** the authoring surface exists on the API, and the feature is reachable by nobody until the
permission is granted.

- **Fields and arguments.** A `commissioning_metric` binding field on `RuleGraphqlType`
  (`app/graphql_types/rule_graphql_type.rb`) and the matching argument on `RuleInputGraphqlType`, declared
  `required: false` (every argument there is optional today, and the frontend declares the input type by
  name `$rules: [RuleInputGraphql!]`, so a newly-required argument would fail on every existing client and
  the type name must not change). A field on `IncentiveGraphqlType` distinguishing which metric variables
  an incentive feeds from which it reads, for the plan-side picker. **Exact field/argument names settle at
  implementation.**
- **Both mutation rule allow-lists carry the new argument.** `create_incentive_graphql_mutation.rb`
  (`rules: %i[ description type value ]`) and `update_incentive_graphql_mutation.rb`
  (`rules: %i[ _destroy description id type value ]`) — explicit `%i[…]` arrays, so an unlisted argument is
  silently dropped.
- **The clone gap — the sharpest backwards-compatibility risk.** There is no backend clone mutation:
  `clone` is a permission and a UI action only (`IncentivePolicy#clone?`, the permission string
  `incentive_clone`, `actions << 'clone' if policy.clone?`), so a clone goes through
  `CreateIncentiveGraphqlMutation`. Unless both allow-lists carry the binding **and** the front clone
  builders carry it (Phase 9), a cloned incentive silently loses its binding and produces a plan that
  validates but computes a different number. Covered by a test that clones and asserts the binding.
- **No new mutation.** Creating the variable is unchanged (`create_variable_graphql_mutation.rb`); the
  commissioning-metric variable is an ordinary `IndicatorVariable`. Creating the metric itself is a
  separate authoring action — **OPEN: whether the metric is created through its own mutation/screen or as
  part of the incentive/rule save.**
- **Migration M-perm — the permission `Action` row**, in the established pattern
  (`Action.create!(key: ..., level: 'module', resource: 'incentive')`,
  `db/migrate/20260729113439_user_update_document_actions.rb`), plus the key added to the hardcoded
  `MODULE_KEYS` list in `app/workers/company/admin/processor.rb` (where `incentive_clone` sits). The
  processor resolves each key with `Action.get` → `find_by!`, so a key in `MODULE_KEYS` with no `Action`
  row raises `RecordNotFound` and the processor dies — **the migration must land in the same deploy as the
  `MODULE_KEYS` entry.** `Action.create!` is not idempotent (raises on a re-run). **OPEN: the permission
  key name.**

### Phase 9: `app-webclient` — OPEN (build)

**Objective:** an operator can bind a commissioning metric on a rule, replicate it across the rules of an
incentive, and pick compatible incentives when building a plan.

- **One control in the shared `rule/` module** (`app-webclient/src/app/rule/`), added to the create and
  update form builders, wired into all five incentive modules × three flows (`create/`, `update/`,
  **`clone/`** — the clone flows are the part that must not be missed, per the Phase 8 clone gap).
- **Replicate to all rules** — a form-level action on the rules `FormArray`, at the incentive form level.
- **The plan-side compatible-incentive picker**, reading each candidate's fed vs read metric variables.
  UX, not the guarantee (validation 1 is the guarantee).
- **OPEN — the metric-creation screen.** There is no fourth variable type to offer; creating a
  commissioning-metric variable is creating an `IndicatorVariable` and attaching a `CommissioningMetric`
  (calculation sum/average) whose rules feed it. Whether this is a new screen, an extension of the variable
  screen, or folded into the incentive/rule authoring flow is undecided and depends on the Phase 8 answer.

### Phase 10: Backend deploy

**Objective:** the backend change is live in all four environments, with the feature reachable by nobody.

- **One deploy per environment**, in progression. `beta-001` builds from `develop` and is where the full
  sequence is validated first — a real incentive feeding a metric, a real plan, a real commission run;
  `demo-001` is the second non-productive gate; then the two productive stacks.

| Environment | Build branch | Command | Productive? |
|---|---|---|---|
| `beta-001` | `develop` | `gh workflow run deploy-beta-001.yaml -R 4shark/app` | no |
| `demo-001` | `master` | `gh workflow run deploy-demo-001.yaml -R 4shark/app` | no |
| `shared-001` | `master` | `gh workflow run deploy-shared-001.yaml -R 4shark/app` | **yes** |
| `atento-001` | `master` | `gh workflow run deploy-atento-001.yaml -R 4shark/app` | **yes** |

- **The productive gate is enforced, not advisory.** `validate-productive-deploy.sh` (PreToolUse) blocks a
  `deploy-shared-001` / `deploy-atento-001` command unless a GO from the queue check is on record for that
  stack within the last 5 minutes. So each productive step is
  `bash ~/.claude/scripts/sidekiq-queue-check.sh --stack <stack>` followed immediately by the deploy, as
  one motion. `beta-001` and `demo-001` are never gated.
- **The migration window.** The `prepare-and-migrate` job builds/pushes the image and runs
  `bin/rails db:migrate`, while the job that activates the new code runs later — between those two points
  the schema is new and every serving container is old. The delivered migrations (`metrics.type`;
  `rules.output_variable_id → commissioning_metric_id`) are already in `develop`; the only migration this
  plan still adds is the permission `Action` row, which changes no old-code behaviour. Nothing needs
  splitting and there is no contract half.
- **Rollback is a redeploy of the previous image at every step.** Nothing drops a column, rewrites data, or
  changes an existing cross-service contract, so there is no point of no return; the closest candidate is a
  commission already calculated with metric values, and a reprocess under the old code reproduces the old
  result (a recovery path, though a productive reprocess is not free).

**Dependencies:** Phases 1-8. **Running the deploy is the engineer's** — an action outside version control
that a PR diff neither shows nor reverts. The shape above is decided; the execution and its timing are not.

### Phase 11: Frontend release

**Objective:** the authoring surface is live.

One merge, which fans out into the per-client Netlify builds. `app-webclient` ships via Netlify, one site
per client (whitelabel), NOT GitHub Actions; every site runs the same entry point against the same
repository, so this is one merge fanning out into ~38 builds, not 38 coordinated releases. The frontend
ships last and therefore never faces an old backend.

### Phase 12: Permission grant

**Objective:** the feature becomes reachable, one account at a time.

The permission system is 4Shark's release toggle (default-deny): grant on a single account, validate, then
widen; rollback is revoking the permission. One boundary is worth recording: because
`IncentivePolicy#update?` returns false when `record.plans.any?`, granting the permission cannot
retroactively change any incentive already in a plan — the blast radius is limited to incentives authored
afterwards.

---

## Technical decisions

| Decision | Choice | Rationale / status |
|---|---|---|
| The "output" concept | A `Metric` specialization (`CommissioningMetric` on an `IndicatorVariable`), NOT a fourth variable type | Delivered (#5431/#5433). The distinguishing trait is who writes the variable, which the existing `variable.has_one :metric` already models; a metric variable already has only system-generated indicators |
| The rule link | `Rule belongs_to :commissioning_metric, optional: true` | Delivered (#5433). The metric guarantees the variable is correct (indicator, numeric, no external indicator), so the earlier per-rule `output_variable_type` validation was removed |
| The metric's calculation | `sum \| average`, sliced from `Metric::CALCULATIONS` on the subtype | Delivered. `DealMetric` uses `total \| quantity`; each subtype declares its own `enumerize` over the shared integer `calculation` column |
| Which stages feed and which read | Any stage's rule may feed; every stage except the deal stage may read | Engineer's definition (`DECISION-AUTHORITY.md` ladder, source 1): the deal stage is the only stage that may not read, and any reader needs a feeder in a strictly earlier stage |
| Validation 1 error surface | `metric_not_populated` on the incentivation's `:incentive_id` | Delivered (#5434). The frontend already lists per-`incentive_id` errors after submit, so the error surfaces on the incentive rather than as a generic base error |
| Validation 2 | Single feeding incentive type per commissioning-metric variable | **Open.** Keeps the variable written at a single stage so it holds one value per plan; feeders of two types would give it two values |
| Materialization trigger + store | Recompute the aggregate (never `+=`); write the variable's internal `Indicator` | **Open.** DOMAIN.md settles that the metric writes the internal indicator; the trigger (commissioning save vs stage boundary), the writing worker, and the exact indicator store are undecided. Recompute (not increment) is forced by Sidekiq at-least-once |
| What the aggregate sums | The signed, commission-type-aware expression (`#money` / `#points`; limiter `value * -1`), not the raw `value` column | Engineer's requirement (source 1): the 300 + 200 − 100 = 400 example closes only if the sign travels with the value; an unsigned publication would force a downstream author to know the feeder's stage |
| Where the stage order lives | Ordered constant `CALCULATION_ORDER` on `Incentive` + a spec asserting it matches the enqueue graph | **Open/confirm** — validation 1's per-validator `INCENTIVE_TYPES` allow-lists already encode the order; whether a shared `CALCULATION_ORDER` constant exists or is still owed depends on what #5434 introduced |
| Variable availability by incentive type | A commissioning-metric variable is excluded from the deal incentive | **Open** — no per-incentive-type variable-availability filter exists in the models today; placement (a new filter vs the GraphQL layer) undecided (DOMAIN.md § Remaining work) |
| Does the incentive CSV import support the binding | No — documented limitation | § Scope Discipline. Changes a customer-facing template |
| Deploy shape | One backend deploy, then one frontend release | No phasing trigger fires: the `Computation` key derivation is unchanged, job argument shapes are unchanged, and recompute makes the materialization idempotent. The act of deploying remains the engineer's |

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A cloned incentive silently loses its metric binding | High — a plan validates and computes a different number than the operator authored | Extend both mutation allow-lists and all five front clone builders in the same change (Phases 8-9); cover with a clone-and-assert test |
| The metric's recompute reads a stale aggregate | High — a silently low number, the failure class payroll cannot tolerate | The aggregate must re-read inside its own transaction at the moment of write (Phase 6) — **open until the writer is designed** |
| Limiter and ranking commissioning writes are not retry-idempotent | Medium — a retried job raises on the unique index, and a commissionings-based aggregate inherits whatever those rows hold | Pre-existing, not introduced here; redemption compensates in its producer, limiter and ranking do not. Bounds how much the aggregate can rely on those rows being rewritable |
| Validation 2 is absent | Medium — a metric variable fed by two incentive types holds two values and cannot be presented coherently | Build validation 2 (Phase 5) before the feature is granted to any account |
| The materialization mechanism is undesigned | Medium — Phase 6/7 cannot be estimated or built until the trigger, writer and store are decided | Resolve the § Materialization open questions first; the model and validation 1 do not depend on them |
| The stage order becomes a second representation of the enqueue graph | Medium — drift between validation and execution | A spec asserting `CALCULATION_ORDER` matches the observed chain is the sync mechanism (Phase 5) |
| M-perm's `Action.create!` is re-applied | Low — the migration raises | Not idempotent by construction; a re-run hazard, not a rollback hazard |

---

## Assumptions

- **Only `app` and `app-webclient` are affected.** A grep for `IncentiveVariable`, `PlanVariable`,
  `Commissioning`, `Metric` and `incentive_variables` across `onboarding`, `setup`, `integrator` and
  `lambda` returned no matches. `app-sdk-advpl`, `app-sdk-dotnet` and `app-mobileclient` were not opened,
  so whether either SDK models `Incentive` / `Rule` / `Variable` / `Metric` is unverified.
- **`/api/v3/` is not an authoring path for incentives, rules or plans.** `app/controllers/api/v3/` holds
  `clients`, `deals`, `goals`, `groups`, `indicators`, `products`, `roles`, `subsidiaries`, `users` and
  nothing else. The integrator feeds `indicators`, which feed `IndicatorVariable` values — a
  commissioning-metric variable's value is produced by the metric, never fed by the integrator, which is
  the design's premise.
- **The backwards-compatibility surface is bounded by `IncentivePolicy#update?`.**
  `return false if record.plans.any?` means an incentive attached to any plan is not updatable through the
  mutation, so no existing productive incentive can acquire a metric binding and no existing plan's
  arithmetic can change without a new incentive being authored and added to a plan.
- **The in-flight-commission reasoning is inference from read facts, not an executed test.** It rests on
  the `Computation` key derivation being unchanged, job argument shapes being unchanged, and the successor
  being resolved at execution time rather than carried in the payload. Confirming it on `beta-001` — start
  a commission, deploy mid-chain, confirm completion — is available if the engineer wants the stronger
  guarantee before the first productive deploy.
- **The materialization/read forward design is not yet grounded in code.** `CommissioningMetric` has no
  `#calculate` and no commissionings-aggregating adapter yet, and no read-path change is in `develop`. The
  Phase 6/7 descriptions here are the DOMAIN.md model plus the open questions, not a verified mechanism.
- **The two proposal decks named in SPIKE §6 remain unreviewed** — neither file is on this machine. If
  either constrains the authoring surface, Phase 9 should be re-sized against it.
