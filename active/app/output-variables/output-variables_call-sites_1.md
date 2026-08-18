# Auxiliary file 1 — complete call-site inventory for variable reads

Referenced from `PLAN-SPIKE.md` § "Exclusions in existing flows".

Repository: `~/Projects/4Shark/app`, branch `develop`. Every entry below was produced by
`grep -rn --include="*.rb" "\.variables" app lib` plus targeted greps for `plan_variables` /
`incentive_variables`, and each quote was read from the file at the line cited.

---

## 1. Reads that are POSITIVELY type-scoped — a fourth `Variable` type is excluded by construction

No code change is required at any of these sites for exclusion purposes. They are listed so the
plan can state the exclusion is verified rather than assumed.

| File:line | Verbatim |
|---|---|
| `app/models/incentive.rb:153` | `company.variables.easy.enabled.each do \|variable\|` |
| `app/models/incentive.rb:159` | `company.variables.deals.enabled.each do \|variable\|` |
| `app/models/incentive.rb:163` | `company.variables.indicators.enabled.each do \|variable\|` |
| `app/models/incentive.rb:171` | `company.variables.indicators.enabled.each do \|variable\|` |
| `app/models/rule.rb:183` | `incentive.company.variables.indicators.enabled.joins(:metric).each_with_object({}) do \|variable, options\|` |
| `app/models/rule.rb:203` | `incentive.company.variables.deals.to_h do \|variable\|` |
| `app/models/rule.rb:209` | `incentive.company.variables.indicators.enabled.each_with_object({}) do \|variable, options\|` |
| `app/models/rule.rb:217` | `incentive.company.variables.easy.enabled.to_h do \|variable\|` |
| `app/workers/aggregated_indicator/producer.rb:23` | `Variable.with_uncached_connection { plan.variables.easy.pluck(:id) }` |
| `app/workers/aggregated_indicator/producer.rb:25` | `Variable.with_uncached_connection { plan.variables.indicators.pluck(:id) }` |
| `app/workers/indicator_dataset/producer.rb:20` | `Variable.with_uncached_connection { plan.variables.easy.timetable.pluck(:id) }` |
| `app/workers/indicator_dataset/producer.rb:22` | `Variable.with_uncached_connection { plan.variables.indicators.timetable.pluck(:id) }` |
| `app/workers/deal_incentive/consumer.rb:33` | `variable_ids = Variable.with_uncached_connection { plan.variables.deals.ids }` |
| `app/graphql_resolvers/indicator_dataset_graphql_resolver.rb:20` | `variable_ids = variable_ids.map(&:to_i) & plan.variables.indicators.pluck(:id)` |
| `app/work_books/commission_indicator_audit_work_book/indicators_work_sheet.rb:54` | `variable_ids = Variable.with_uncached_connection { @plan.variables.indicators.order(:name).pluck(:id) }` |

**Correction to SPIKE §4.5 line numbers.** The spike cites the `Rule` syntax validators as
`rule.rb:173,193,199,207`. The actual lines in the current `develop` are `183`, `203`, `209`, `217`
(the methods are `metrics_options`, `deal_extra_fields_options`, `indicator_variables_options`,
`easy_variables_options`). The spike also cites `aggregated_indicator/producer.rb:23,25` and
`indicator_dataset/producer.rb:20,22`, which do match.

---

## 2. Reads with NO type scope — these pick up a fourth type silently

### 2a. Named by SPIKE §4.5 — all four confirmed

**`app/services/commission/indicator_options_processor.rb:41`**

```ruby
      variable_ids = Variable.with_uncached_connection { plan.variables.pluck(:id) }

      variable_ids.each do |variable_id|
        variable = Variable.with_uncached_connection { Variable.find(variable_id) }
        options[variable.key] = aggregated_indicator_value(user_commission_id: user_commission.id, variable: variable)
      end
```

`aggregated_indicator_value` (lines 51-60) falls back to `variable.format_default` on
`ActiveRecord::RecordNotFound`, so an output key lands in the snapshot carrying its default.

**`app/workers/calendar_audit/producer.rb:19`**

```ruby
        variable_ids = Variable.with_uncached_connection { plan.variables.pluck(:id) }
        combinations = period_ids.product(user_ids, variable_ids)
        calendar_audit.computation.increment_queue(by: combinations.count)
```

The product is `periods × users × variables`, so each output variable multiplies the audit
fan-out by `periods × users` jobs.

**`app/workers/goal_dataset/migration/producer.rb:16`**

```ruby
          variable_ids = Variable.with_uncached_connection { plan.variables.pluck(:id) }
          combinations = period_ids.product(variable_ids, user_ids)
```

**`app/workers/commission/money_sanitizer_processor.rb:48`**

```ruby
      variable_ids = Variable.with_uncached_connection { commission.variables.pluck(:id) }
      arguments = variable_ids.map { |variable_id| [commission.id, variable_id, partial] }
      Sidekiq::Client.push_bulk('class' => GoalDataset::Producer, 'args' => arguments)
```

### 2b. NOT named by SPIKE §4.5 — found by this inventory

**`app/work_books/commission_work_book/indicator_work_sheet.rb:12` and `:29`**

```ruby
      indicator_variable_presence = Variable.with_uncached_connection { @commission.variables.indicators.exists? }
```

```ruby
            @commission.variables.select(:id, :name, :data_type).index_by(&:id)
```

Line 12 gates on `variables.indicators` (positively scoped) but line 29 builds the lookup from the
unscoped `@commission.variables`, so an output variable would enter the workbook's index.

**`app/work_books/plan_slice_commission_work_book/indicator_work_sheet.rb:36`** — same shape:

```ruby
              @commission.variables.select(:id, :name, :data_type).index_by(&:id)
```

**`app/work_books/variable_audit_work_book/variables_work_sheet.rb:28`**

```ruby
        @company.variables.enabled.each do |variable|
```

The variable audit workbook enumerates every enabled company variable with no type scope.

**`app/workers/company/inactivator.rb:107`, `app/workers/company/activator.rb:110`,
`app/workers/company/cleansing/variable_producer.rb:13`**

```ruby
      variable_ids = Variable.with_uncached_connection { company.variables.pluck(:id) }
```

```ruby
      variable_ids = Variable.with_uncached_connection { company.variables.enabled.pluck(:id) }
```

```ruby
            company.variables.limit(10_000).pluck(:id)
```

These three intentionally cover every variable of a company (disable / enable / cleanse). Including
a fourth type is consistent with their purpose; they are listed for completeness, not as gaps.

**`app/workers/variable_document/processor.rb:58` and
`app/workers/easy_product/variable_document/processor.rb:57`**

```ruby
      if VariableDocument.with_uncached_connection { variable_document.variables.any? }
```

Scoped to a `VariableDocument`, which is the spreadsheet-import path for variables.

---

## 3. `plan_variables` — the goal-binding surface

`plan_variables` carries `goal_type` (`db/schema.rb:1617-1624`):

```ruby
  create_table "plan_variables", force: :cascade do |t|
    t.string "goal_type", limit: 8000
    t.bigint "plan_id"
    t.bigint "variable_id"
    t.index ["plan_id", "variable_id"], name: "index_plan_variables_on_plan_id_and_variable_id", unique: true
```

`Plan#create_variables` (`app/models/plan.rb:434-436`) populates it from every
`incentive_variables.variable_id` of the plan's incentives:

```ruby
  def create_variables
    variable_ids.each { |variable_id| plan_variables.create(variable_id: variable_id) }
  end
```

```ruby
  def variable_ids
    @variable_ids ||=
      Incentive
        .joins(:incentive_variables)
        .where('incentives.id': incentive_ids)
        .pluck('incentive_variables.variable_id')
        .uniq
  end
```

(`app/models/plan.rb:438-445`.)

Consumers of `plan_variables` that a fourth type would reach:

| File:line | Verbatim | Type-scoped? |
|---|---|---|
| `app/workers/commission_goal/producer.rb:18` | `variable_ids = Variable.with_uncached_connection { plan.plan_variables.pluck(:variable_id) }` | no |
| `app/workers/plan_goal_audit/producer.rb:14` | `variable_ids = PlanVariable.with_uncached_connection { plan.plan_variables.pluck(:variable_id) }` | no |
| `app/workers/plan/goals_processor.rb:12` | `plan_variable_ids = PlanVariable.with_uncached_connection { plan.plan_variables.with_goal.pluck(:id) }` | filtered by `with_goal` |
| `app/workers/groupification/processor.rb:17` | `plan.plan_variables.where(goal_type: 'UserGoal').pluck(:variable_id)` | filtered by `goal_type` |
| `app/models/calendar_audit.rb:30` | `variable_quantity = PlanVariable.where(plan_id: plan_ids).count` | no |

`PlanVariable#goals_presence` (`app/models/plan_variable.rb:32-39`) only fires when `goal_type` is
present, so an output `plan_variables` row with a blank `goal_type` validates cleanly. The
exposure is the picker: `PlanVariableInputGraphqlType` requires `goal_type`
(`app/graphql_types/plan_variable_input_graphql_type.rb:5-6`), and the plan-finish screen offers a
goal type for every `plan_variable`.

---

## 4. `incentive_variables` — the join the role column would live on

`db/schema.rb:950-955`:

```ruby
  create_table "incentive_variables", force: :cascade do |t|
    t.bigint "incentive_id"
    t.bigint "variable_id"
    t.index ["incentive_id"], name: "index_incentive_variables_on_incentive_id"
    t.index ["variable_id"], name: "index_incentive_variables_on_variable_id"
  end
```

No timestamps, no unique index on the pair — both confirm SPIKE §4.6.

`Incentive#update_variables` (`app/models/incentive.rb:149-175`) is an `after_save` callback
(`app/models/incentive.rb:80`: `after_save :update_variables`) that rebuilds the whole collection:

```ruby
  def update_variables
    incentive_variables.delete_all
```

Every read of the collection today is unrolled and ignores which variable plays which part:

- `app/models/plan.rb:441-443` — the plan roll-up quoted in §3 above.
- `app/graphql_types/incentive_graphql_type.rb:22` — `field :incentive_variables, [IncentiveVariableGraphqlType], null: true`
- `app/graphql_types/variable_graphql_type.rb:21` — `field :incentive_variables, [IncentiveVariableGraphqlType], null: true`

`IncentiveVariable` itself has no scopes and two presence validations
(`app/models/incentive_variable.rb:7-8`):

```ruby
  validates :incentive_id, presence: true
  validates :variable_id, presence: true
```
