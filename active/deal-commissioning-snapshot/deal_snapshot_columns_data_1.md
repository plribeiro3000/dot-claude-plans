# Auxiliary — Enumerated set of deal inputs consumed by the commission calculation

Referenced from `PLAN-SPIKE.md`. Every entry below is the literal option key(s) passed into
`Rule#calculate` from `app/app/workers/deal_incentive/consumer.rb:47-67`, or the underlying
`Deal`/`DealField` source of that key.

## Fixed deal attributes (always passed, both pt-BR and en keys map to the same source)

| Formula keys | Source | Column | Type |
|---|---|---|---|
| `valor`, `value` | `deal.sold_price` | `deals.sold_price` | `decimal(28,6)` |
| `estado`, `status` | `deal.status.key` | `deals.status_id` → `statuses.key` (joined at read time) | string (via association) |
| `quantidade`, `quantity` | `deal.quantity` | `deals.quantity` | `decimal(28,6)`, default `1.0` |
| `parcela`, `installment` | `deal.installment` | `deals.installment` | `integer`, default `1` |
| `dias_em_aberto`, `open_days` | `deal.open_days` (computed method) | derived from `deals.date` / `deals.originated_at` — no column | computed |
| `horas_trabalhadas`, `work_hours` | `deal.work_hours` | `deals.work_hours` | `decimal` |

Source: `app/app/workers/deal_incentive/consumer.rb:47-67`

```ruby
deal_value =
  if deal.for_client(incentive.client_id) && deal.for_product(incentive.product_id)
    rule.calculate(
      options.merge(
        valor: deal.sold_price,
        estado: deal.status.key,
        quantidade: deal.quantity,
        parcela: deal.installment,
        dias_em_aberto: deal.open_days,
        horas_trabalhadas: deal.work_hours,
        value: deal.sold_price,
        status: deal.status.key,
        quantity: deal.quantity,
        installment: deal.installment,
        open_days: deal.open_days,
        work_hours: deal.work_hours
      )
    )
  else
    0
  end
```

## Deal extra-field values (plan-defined, dynamic per company)

Source: `app/app/workers/deal_incentive/consumer.rb:33-45`

```ruby
variable_ids = Variable.with_uncached_connection { plan.variables.deals.ids }

variable_ids.each do |variable_id|
  variable = Variable.with_uncached_connection { Variable.find(variable_id) }
  deal_field = DealField.with_uncached_connection { deal.fields.find_by(variable_id: variable_id) }

  options[variable.key] =
    if deal_field.present?
      deal_field.formated_value
    else
      variable.default
    end
end
```

Each entry is keyed by `variable.key` (a per-company, per-plan dynamic string — e.g. the
incident's "T base cálculo consórcio") and its value comes from `DealField#formated_value`
(`app/app/models/deal_field.rb:23-25`):

```ruby
def formated_value
  variable.data_type.format(value)
end
```

`variable.data_type` is a polymorphic value object (`app/app/data_types/*.rb`:
`NumberDataType`, `PercentDataType`, `DurationDataType`, `BooleanDataType`, `StringDataType`,
`DateDataType`), so the formatted representation's Ruby type varies per variable
(`Variable#data_type` at `app/app/models/variable.rb:66`: `attribute :data_type, DataType.new`).
This variability is why a fixed set of typed columns cannot represent the extra-field portion
of the snapshot without also knowing every variable's data type ahead of time — see
"Option A vs Option B" in `PLAN-SPIKE.md`.

## Deal-options block (accumulated-deal or plan-goal fallback)

Source: `app/app/workers/deal_incentive/consumer.rb:21-32`

```ruby
deal_options =
  if incentive.accumulated_deals?
    AccumulatedDeal.with_uncached_connection do
      user_commission.accumulated_deals.find_by(client_id: incentive.client_id, product_id: incentive.product_id).options
    end
  else
    { meta: plan.goal.to_f }
  end

variables_keys = Metric.with_uncached_connection { plan.metrics.joins(:variable).pluck(:key) }
metric_options = user_commission.modifier_options.select { |key| variables_keys.include?(key) }
options = deal_options.merge(metric_options)
```

This block is **not deal-scoped** — it comes from `AccumulatedDeal#options` or the plan's goal,
and from `user_commission.modifier_options`, neither of which is a `Deal`/`DealField` column.
Whether these belong in the snapshot is an open question for the engineer (see PLAN-SPIKE
"Out of scope / open question") — they affect the calculation but are not deal state that gets
deactivated/reactivated the way the incident's `deals.disabled_at` did.

## What triggered zero-commission in the incident

`Plan#deals_for` (`app/app/models/plan.rb:267-281`) resolves the deal set a `DealIncentive::DealProducer`
fans out over:

```ruby
when SalesPlan
  if plan_slice_id.present?
    return if plan_slice.plan_slice_commission.nil?

    plan_slice.plan_slice_commission.document.deals
  else
    Sale.for(period: period, product_id: product_id, client_id: client_id).enabled
  end
```

`.enabled` is `ApplicationRecord`'s shared scope (`app/app/models/application_record.rb:20-26`):

```ruby
scope :enabled, lambda { |status = true|
  if [nil, '', true, 'true'].include?(status)
    where("#{table_name}.disabled_at": nil)
  else
    where("#{table_name}.disabled_at IS NOT NULL")
  end
}
```

A deal with `disabled_at` set at the moment `DealProducer` runs is excluded from `deal_ids`
entirely — no `DealCommissioning` row is ever created for it (`consumer.rb` is never invoked
for that deal), and the commission closes with whatever total the remaining deals produce
(zero, in the incident, because all 7 deals were disabled at that instant). This is a
**producer-time exclusion**, not a value miscalculation — the snapshot feature does not change
which deals are included, only what is recorded about the deals that ARE included.
