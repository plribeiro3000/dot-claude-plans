# ANALYSIS — CommissioningMetric across the incentive and plan registration paths

> Scope: the four registration paths — incentive manual, incentive upload, plan manual, plan upload — and
> which of them must carry a rule's `commissioning_metric` binding. Repository: `~/Projects/4Shark/app`,
> branch `develop`. Internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1). Feeds the change
> that brings the incentive CSV binding in scope (the item PLAN.md § Scope had listed out of scope).

## Question

The commissioning-metric feature binds a metric to a rule through `Rule belongs_to :commissioning_metric`.
Manual incentive authoring already carries that binding; the question is which of the four registration
paths still needs work, and specifically whether the plan paths do.

## The binding lives on the rule, nowhere else

A `CommissioningMetric` is fed by rules (`commissioning_metric.rb:6` — `has_many :rules`) and consumed by a
later rule that names the metric's variable **by key in its formula text**. So the only thing a registration
path must carry to author the feature is a rule's `commissioning_metric_id` (the feed side); the consume side
is already just a variable key inside the formula string and needs no binding (PLAN.md Phase 4, delivered).

`CommissioningMetric` has no external identifier of its own — it is identified through its `variable`
(`commissioning_metric.rb`, no `reference`/`external_id`). A client references it by the **output variable's
external key**, which is the client's own internal ID for that variable.

## The four paths

### 1. Incentive manual (GraphQL) — DONE

`RuleInputGraphqlType` already declares `argument :commissioning_metric_id, ID` (`rule_input_graphql_type.rb:5`,
#5442), and both incentive mutations permit it in their `rules:` nest. The manual path passes our **internal**
id directly (the front picks the metric from a list), so no ID swap is involved. Nothing to do.

### 2. Incentive upload (CSV) — THE ONE PATH THAT NEEDS THE CHANGE

`IncentiveDocument::Processor` (`app/workers/incentive_document/processor.rb`) parses positional CSV columns.
An incentive header row uses columns 0–8 (name, description, commission_type, group, type, client, product,
rankifier, reference); a `#####` line separates incentives; every other row is a **rule** and is built from
only two columns:

```ruby
@incentive.rules.build(
  value: row[0].to_s.strip,
  description: row[1].to_s.strip,
  type: rule_type(@incentive),
  document_line: line
)
```

`row[2]` and beyond on a rule row are read by nothing today, so a trailing column there is additive: an
existing file with no such column resolves to blank → no binding, byte-for-byte unchanged behavior.

The ID-swap pattern is already the processor's idiom — every foreign reference is the client's external id
resolved through `get_id`, rescuing `RecordNotFound` to `nil`:

```ruby
Client.with_uncached_connection   { Client.get_id(company_id: company.id, external_id: external_id) }
Group.with_uncached_connection    { Group.get_id(company_id: company.id, external_id: external_id) }
Product.with_uncached_connection  { Product.get_id(company_id: company.id, external_id: external_id) }
```

The metric column follows the same shape: the client writes the **output variable's external key**; we resolve
`Variable.get_id(company_id:, key:)` → `CommissioningMetric.find_by(variable_id:)` → its id, rescuing to `nil`
and raising a `document_errors` row (`error_key: 'not_found'`) when the key resolves to no commissioning
metric — the same error treatment every other reference column already gets.

### 3. Plan manual (GraphQL) — NO CHANGE

`CreatePlanGraphqlMutation` builds a plan from `incentivations_attributes` (each an `incentive_id` +
`payment_type_id`), `responsible_ids`, and plan attributes — `create_plan_graphql_mutation.rb:4-16`,
`incentivation_input_graphql_type.rb`. A plan **references incentives that already exist**; it never carries
rules or metrics. The metric binding was authored when the incentive was created, upstream of the plan.

### 4. Plan upload (CSV) — NO CHANGE

`PlanDocument::Consumer` (`app/workers/plan_document/consumer.rb`) mirrors the manual path exactly: it links
each incentivation by `Incentive.get_id(company_id:, reference:)` and each responsible by
`UserIdentifier.get`, and builds plan attributes. It parses **no rules and no metrics**. There is nothing for
a commissioning-metric binding to attach to in a plan document.

## Conclusion

| Path | Needs change? | Why |
|---|---|---|
| Incentive manual (GraphQL) | No | `commissioning_metric_id` already on the rule input (#5442) |
| Incentive upload (CSV) | **Yes** | Rule rows carry no metric column; add one trailing, conditional |
| Plan manual (GraphQL) | No | Plan links existing incentives; no rule/metric surface |
| Plan upload (CSV) | No | Same — `PlanDocument::Consumer` parses only incentivation links + responsibles |

The plan uncertainty resolves cleanly: **the plan carries no rules, so it carries no metric binding, in either
registration path.** The whole change is one trailing column on the incentive CSV's rule rows.

## Proposed change (incentive upload)

- Add a trailing rule-row column (`row[2]`) holding the **output variable's external key**. Blank → no binding
  (existing files unaffected).
- Resolve it in the processor: `Variable.get_id(company_id:, key:)` → `CommissioningMetric.find_by(variable_id:)`
  → set `commissioning_metric_id` on the built rule; rescue `RecordNotFound` → `nil` + a `not_found`
  `document_errors` row, exactly like the client/product/group columns.
- One RSpec covering: a rule row with a valid metric key binds it; a blank column leaves the rule unbound and
  the file's existing rows unchanged; an unknown key raises the `not_found` document error.

Constraints honored: the contract is not broken (trailing, conditional column; header row and existing rule
columns untouched); the client uses their internal id (the variable's external key) and we swap to our
`commissioning_metric_id`, matching the processor's existing `get_id` idiom.

## The one thing to confirm (client-facing CSV contract)

What the client writes in the new column. The natural, code-consistent choice is the **output variable's
external key** (their internal ID for the variable the metric writes), resolved to our metric as above — it
matches how every other column in this file already carries a client external id. If the team would rather the
column carry something else (a metric-specific reference we do not model today), that changes the resolution
and possibly the model, so it is worth a nod before the code lands. Everything else in the proposed change is
decided by the existing pattern.
