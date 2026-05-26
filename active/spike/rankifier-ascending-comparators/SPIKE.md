# SPIKE — Fix ascending comparators (`<` and `<=`) in the rankifier system

**Conducted by:** Engineering
**Date:** 2026-03-09
**Status:** Research complete — pending decisions

---

## Goal

The rankifier system supports four comparators (`>`, `>=`, `<`, `<=`), but the ascending comparators (`<` and `<=` — "lower is better") are partially broken. The investigation answers:

1. What is the full impact of renaming `minimum` to a field that supports both directions (e.g., `baseline`)?
2. What calculation changes are needed per rankifier type for ascending comparators?
3. What validations need to change?
4. What database migration is needed?
5. Are there existing tests that cover ascending comparator behavior?
6. Are there API contracts or frontend usages referencing `minimum`?

---

## Method

- Full codebase search for all occurrences of `minimum` related to `rankifier_variable`
- Static analysis of calculation logic in `RankifierVariable#calculate` and its private helpers
- Review of all specs, factories, GraphQL types/mutations, locales, and migrations

---

## Evidence

### 1. Database Schema

**File:** `db/schema.rb`, line 1634

```
t.string "minimum", limit: 8000
```

The column is a `string` type (was converted from `decimal` in a 2018 migration). A rename to `baseline` requires a DB migration with `rename_column`.

No data transformation is needed — the semantic meaning of the stored value does not change (it is still a "starting point" value). For ascending, `baseline` represents the **maximum tolerated value** (the ceiling from which lower is better); for descending, it represents the **floor** (the minimum that must be reached). In both cases, the stored raw value remains the same kind of reference point.

---

### 2. Core Model Logic

**File:** `app/models/rankifier_variable.rb`

The field is used in 6 locations within this file:

| Line | Usage | Problem |
|------|-------|---------|
| 11 | `validates :minimum, presence: true, if: :weight?` | Only validates for WeightRankifier — correct scope |
| 42–44 | `def formatted_minimum` / `variable.format(minimum)` | Method name must change |
| 46–48 | `def output_minimum` / `variable.output(minimum)` | Method name must change |
| 87–92 | `minimum_achieved?` uses `value.send(comparator, ...)` | **Bug**: for `<`, `50 < 0` (min=0, goal=100, value=50) → false. Must invert logic for ascending |
| 94–96 | `achieved(value)` uses `(value - format(minimum)).abs` | `.abs` already handles direction neutrally — correct |
| 98–100 | `weight_goal` uses `(format(goal) - format(minimum)).abs` | `.abs` already handles direction neutrally — correct |

**Additional bugs found:**

`goal_calculation` (lines 52–59):
```ruby
def goal_calculation(value)
  return 0 unless goal_achieved?(value)

  if rankifier.multiple_variables?
    weight
  else
    value  # BUG: ascending + single variable → higher value = higher score (inverted)
  end
end
```

`goal_reach_calculation` (lines 73–79):
```ruby
def goal_reach_calculation(value)
  result = value / variable.format(goal)  # BUG: for ascending, lower value should produce higher ratio
  ...
end
```

---

### 3. `Ranking#calculate` Workaround

**File:** `app/models/ranking.rb`, lines 4 and 34

```ruby
ASCENDING_COMPARATORS = %w[< <=].freeze
...
goal_reach = nil if ASCENDING_COMPARATORS.include?(rankifier_variable.comparator)
```

This is an explicit workaround. `goal_reach` is forced to `nil` for ascending comparators because the ratio calculation is inverted. Once the calculation is fixed in `goal_reach_calculation`, this guard can be removed and `goal_reach` can be computed correctly.

---

### 4. GraphQL API Contracts

The field `minimum` is exposed in two GraphQL types — both are part of the public API contract with the frontend.

**Output type** — `app/graphql_types/rankifier_variable_graphql_type.rb`, line 9:
```ruby
field :minimum, String, null: true
```

**Input type** — `app/graphql_types/rankifier_variable_input_graphql_type.rb`, line 8:
```ruby
argument :minimum, String, required: false
```

**Mutations** — both permit `minimum` explicitly:

- `app/graphql_mutations/create_rankifier_graphql_mutation.rb`, line 26:
  ```ruby
  .permit(:name, :type, rankifier_variables: %i[cap minimum comparator goal variable_id weight])
  ```
- `app/graphql_mutations/update_rankifier_graphql_mutation.rb`, line 25:
  ```ruby
  .permit(:name, :type, rankifier_variables: %i[_destroy id cap minimum comparator goal variable_id weight])
  ```

A rename from `minimum` to `baseline` in the GraphQL layer is a **breaking change** for any client (frontend, mobile, third-party) currently using these fields.

---

### 5. Locales (i18n)

The field `minimum` has translated labels in **9 locale files**. All must be updated if the field is renamed:

| File | Current label |
|------|---------------|
| `config/locales/en/models/rankifier_variable.yml` | `'Minimum'` |
| `config/locales/pt-BR/models/rankifier_variable.yml` | `'Minímo'` (note: typo, should be `'Mínimo'`) |
| `config/locales/es/models/rankifier_variable.yml` | `'Mínimo'` |
| `config/locales/es-PE/models/rankifier_variable.yml` | `'Mínimo'` |
| `config/locales/es-AR/models/rankifier_variable.yml` | `'Mínimo'` |
| `config/locales/es-CO/models/rankifier_variable.yml` | `'Mínimo'` |
| `config/locales/es-MX/models/rankifier_variable.yml` | `'Mínimo'` |
| `config/locales/es-CL/models/rankifier_variable.yml` | `'Mínimo'` |
| `config/locales/es-PA/models/rankifier_variable.yml` | `'Mínimo'` |

Suggested translations for `baseline`:
- en: `'Baseline'`
- pt-BR: `'Base'`
- es (all variants): `'Base'`

---

### 6. Factory

**File:** `spec/factories/rankifier_variables.rb`

```ruby
factory :rankifier_variable do
  comparator { '<=' }
  weight { 20.0 }
  minimum { 0 }
  goal { 100 }
end
```

The factory default uses `<=` (ascending), which is already broken. The field reference `minimum` must be updated to `baseline` if the column is renamed.

---

### 7. Existing Tests

No test in the codebase covers the actual calculation behavior of ascending comparators. The specs for `RankifierVariable`, `WeightRankifier`, and `GoalReachRankifier` only test associations and validations — not the `calculate` method.

**Files with zero calculation tests:**
- `spec/models/rankifier_variable_spec.rb` — validations only
- `spec/models/weight_rankifier_spec.rb` — associations/validations only
- `spec/models/goal_reach_rankifier_spec.rb` — associations/validations only
- `spec/models/ranking_spec.rb` — associations/validations only

The `spec/requests/graphql_mutations/` specs test HTTP responses but do not exercise ascending comparator paths.

---

### 8. Migration History

Two historical migrations are relevant:
- `db/migrate/2018/03/20180314213524_change_rankifier_variable_minimum_type.rb` — changed column type from `decimal` to `string`
- `db/migrate/2018/03/20180323161726_set_rankifier_variables_new_comparator.rb` — backfills `minimum: rankifier_variable.minimum || 0`

These migrations confirm the column has been `minimum` since at least 2018 and carries real production data.

---

## Conclusions

### Bugs inventory

| Bug | Location | Root Cause |
|-----|----------|------------|
| `GoalRankifier` single-variable ascending: returns raw `value` as score | `rankifier_variable.rb:58` | Higher value = higher score, but ascending means lower value should win |
| `WeightRankifier` ascending: `minimum_achieved?` always false | `rankifier_variable.rb:91` | `value.send('<', format(baseline))` tests the wrong direction |
| `GoalReachRankifier` ascending: ratio is inverted | `rankifier_variable.rb:74` | `value / goal` gives 0→1 for higher values; ascending needs the inverse |
| `Ranking#calculate` ascending: `goal_reach` forced to `nil` | `ranking.rb:34` | Workaround for the broken `goal_reach_calculation` |

---

### Proposed calculation fixes

#### A. `GoalRankifier` — single variable, ascending

**Current (broken):**
```ruby
value  # higher value = higher score
```

**Proposed:**
```ruby
ascending? ? variable.format(goal) - value + variable.format(goal) : value
```

Wait — the semantics for `GoalRankifier` single-variable are: did you achieve the goal? If yes, return a score. For ascending (`value < goal`), the score should reflect how far *below* the goal the value is. The simplest correct behavior is: if the goal is achieved, return the goal value minus the actual value (lower value = higher score). However, this changes the meaning of the score dramatically.

**Safer option:** for `GoalRankifier` single-variable, always return a fixed value (like `weight`) when the goal is achieved — this is what the multi-variable path already does. This removes the "value as score" ambiguity entirely and makes descending/ascending behave identically.

**Proposed (simpler and consistent):**
```ruby
def goal_calculation(value)
  return 0 unless goal_achieved?(value)
  weight
end
```

This removes the distinction between single-variable and multi-variable, which was always semantically odd.

---

#### B. `WeightRankifier` — `minimum_achieved?`

**Current (broken):**
```ruby
value.send(comparator, variable.format(minimum))
# For ascending (<): 50 < 0 → false when min=0, goal=100 (baseline=0)
```

For ascending, `baseline` is the **maximum starting point**. The check should be: "did the value pass the baseline in the right direction?"

For descending (`>`): `value > baseline` → baseline is a floor
For ascending (`<`): `value < baseline` → baseline is a ceiling

**Proposed:**
```ruby
def minimum_achieved?(value)
  return false if baseline.blank?
  return false if value.blank?

  value.send(comparator, variable.format(baseline))
end
```

This is actually already correct in structure — the bug is that the **stored baseline value** for ascending must be the upper bound, not zero. If existing data has `baseline=0` for ascending variables, the fix also requires a data migration or a change in how the UI allows configuring ascending variables.

**Alternative without renaming:** Add an `ascending?` helper and invert the check:
```ruby
def minimum_achieved?(value)
  return false if minimum.blank?
  return false if value.blank?

  ascending? ? value.send(comparator, variable.format(minimum)) : value.send(comparator, variable.format(minimum))
end
```

This is identical — the actual fix is ensuring the stored `minimum/baseline` value is semantically correct for each direction.

---

#### C. `WeightRankifier` — interpolation (`achieved` and `weight_goal`)

Both `achieved` and `weight_goal` already use `.abs`, so they handle both directions neutrally. These are **correct as-is** once `minimum_achieved?` is fixed.

```ruby
def achieved(value)
  (value - variable.format(minimum)).abs.to_f  # correct for both directions
end

def weight_goal
  (variable.format(goal) - variable.format(minimum)).abs.to_f  # correct for both directions
end
```

---

#### D. `GoalReachRankifier` — inverted ratio

**Current (broken):**
```ruby
result = value / variable.format(goal)
# ascending: lower value = lower ratio (wrong — lower should be better)
```

**Proposed:**
```ruby
def goal_reach_calculation(value)
  result = if ascending?
             variable.format(goal) / value  # invert: lower value = higher ratio
           else
             value / variable.format(goal)
           end

  return 0 if result.instance_of?(Float) && result.nan?

  [result, (cap / 100.0)].min * weight / 100
end
```

Note: `variable.format(goal) / value` will produce `ZeroDivisionError` or `Infinity` if `value == 0`. A guard is needed:
```ruby
return 0 if value.nil? || value.zero?
```

---

#### E. `Ranking#calculate` — remove the `nil` workaround

**Current:**
```ruby
goal_reach = nil if ASCENDING_COMPARATORS.include?(rankifier_variable.comparator)
```

**Proposed:** Remove this line once `goal_reach_calculation` is fixed correctly. The `goal_reach` for ascending will be computed by `GoalReachRankifier`. For `GoalRankifier` and `WeightRankifier`, `goal_reach` is computed in `Ranking#calculate` itself (not delegated to the rankifier variable), so the ascending ratio formula needs to be applied there too:

```ruby
# Current (broken for ascending):
goal_reach = aggregated_indicator.value.to_f / rankifier_variable.formatted_goal
goal_reach *= 100 unless rankifier_variable.variable.percent?

# Proposed:
if ASCENDING_COMPARATORS.include?(rankifier_variable.comparator)
  goal_reach = rankifier_variable.formatted_goal / aggregated_indicator.value.to_f
  goal_reach /= 100 unless rankifier_variable.variable.percent?
else
  goal_reach = aggregated_indicator.value.to_f / rankifier_variable.formatted_goal
  goal_reach *= 100 unless rankifier_variable.variable.percent?
end
```

Division-by-zero guards are already present (`nan?` / `infinite?` checks on lines 32–33).

---

### Field rename: `minimum` → `baseline`

#### Decision needed: rename or keep?

The rename is **optional for the calculation fixes** — all bugs can be fixed without renaming the column. The rename only improves semantic clarity (making it explicit that the field means different things depending on direction).

**Arguments for renaming:**
- `minimum` implies a floor, which is wrong for ascending (where it's a ceiling/upper bound)
- `baseline` is direction-neutral and already used in the `Goal` model (`goal.rb:119`)
- Reduces cognitive overhead when reading ascending-specific code

**Arguments against renaming now:**
- Breaking change in the GraphQL API (frontend must update all usages of `minimum` in input/output)
- 9 locale files must be updated
- Factory, mutations, and GraphQL types must all be updated
- Adds scope to what could otherwise be a focused bug fix

**Estimated impact of rename:**

| Layer | Files | Change type |
|-------|-------|-------------|
| DB migration | 1 new migration | `rename_column :rankifier_variables, :minimum, :baseline` |
| Model | `app/models/rankifier_variable.rb` | Rename field refs + 2 methods |
| GraphQL output | `app/graphql_types/rankifier_variable_graphql_type.rb` | Rename field |
| GraphQL input | `app/graphql_types/rankifier_variable_input_graphql_type.rb` | Rename argument |
| GraphQL mutations (2) | `create_rankifier_graphql_mutation.rb`, `update_rankifier_graphql_mutation.rb` | Update `permit` lists |
| Locales | 9 `.yml` files | Rename key + update translated label |
| Factory | `spec/factories/rankifier_variables.rb` | Rename attribute |
| Specs | `spec/models/rankifier_variable_spec.rb` | Update `validate_presence_of(:minimum)` |
| **Total** | **~16 files** | All mechanical, no logic changes |

---

### Validations

Currently `minimum` is only required for `WeightRankifier` (`validates :minimum, presence: true, if: :weight?`).

This logic does not need to change for the calculation fixes. However, if the product team decides that ascending `GoalReachRankifier` variables should also require a `baseline` (e.g., to guard against division by zero), an additional validation condition would be needed.

**No validation changes are strictly required** to fix the bugs.

---

### New tests required

The following test scenarios are missing and must be added:

| Scenario | Spec file |
|----------|-----------|
| `WeightRankifier` ascending: `minimum_achieved?` with value below baseline | `spec/models/rankifier_variable_spec.rb` |
| `WeightRankifier` ascending: correct interpolation (higher score for lower value) | `spec/models/rankifier_variable_spec.rb` |
| `GoalRankifier` single-variable ascending: goal achieved returns correct score | `spec/models/rankifier_variable_spec.rb` |
| `GoalReachRankifier` ascending: ratio inverted correctly | `spec/models/rankifier_variable_spec.rb` |
| `GoalReachRankifier` ascending: division by zero guard (`value == 0`) | `spec/models/rankifier_variable_spec.rb` |
| `Ranking#calculate` ascending: `goal_reach` is not nil | `spec/models/ranking_spec.rb` |
| `Ranking#calculate` ascending: `goal_reach` reflects inverted ratio | `spec/models/ranking_spec.rb` |

Estimated: 7–10 new test cases.

---

### Effort estimate

#### Option A: Fix calculations only (no rename)

| Area | Files | Complexity |
|------|-------|-----------|
| `RankifierVariable` calculation logic | 1 | Medium |
| `Ranking#calculate` goal_reach fix | 1 | Low |
| New unit tests | 2 | Medium |
| **Total** | **3–4 files** | **Low-Medium** |

#### Option B: Fix calculations + rename `minimum` → `baseline`

| Area | Files | Complexity |
|------|-------|-----------|
| Everything in Option A | 3–4 | Low-Medium |
| DB migration | 1 | Low |
| Model, GraphQL types, mutations | 4 | Low |
| Locales | 9 | Low (mechanical) |
| Factory + specs | 2 | Low |
| **Total** | **~19 files** | **Medium** |

---

### Risks

1. **Division by zero in ascending `GoalReachRankifier`**: `value == 0` causes `Infinity` or `ZeroDivisionError`. A guard must be added.
2. **Existing data for ascending variables**: If any existing `WeightRankifier` ascending variables have `minimum=0` in production, `minimum_achieved?` will still fail (the stored value is semantically wrong for ascending). A data audit is needed.
3. **GraphQL rename is a breaking change**: The frontend must be updated in the same release if the field is renamed. Requires coordination.
4. **`goal_reach` in `Ranking#calculate` is computed independently of `GoalReachRankifier`**: The inverted ratio logic must be added in both places (model and controller-level calculation).

---

### Open questions

1. **Should `GoalRankifier` single-variable always return `weight` (not `value`)?** This is the safer fix and makes single/multi-variable behavior consistent, but it changes existing behavior for descending variables too. Confirm if any descending single-variable GoalRankifiers exist in production.

2. **For ascending `WeightRankifier`, what is the expected baseline for existing records?** A DB query is needed to confirm whether production ascending rankifier variables have semantically correct `minimum` values.

3. **Is the frontend aware of `minimum` semantics?** Does the frontend apply any special rendering or labeling for ascending variables that shows `minimum`/`baseline`?

4. **Should `baseline` be required for `GoalReachRankifier` ascending?** Without it, the inverted ratio `goal / value` has no defined "floor of acceptable values."

---

## Next Steps

The findings present two independent work items:

1. **Calculation bug fixes** (Option A) — can be implemented immediately. Use `@agent-planner` to create a PLAN.md for a focused fix covering `RankifierVariable`, `Ranking`, and new tests.

2. **Field rename** (Option B addition) — should be a coordinated decision involving frontend. If approved, it can be merged into the same feature branch as Option A or done as a follow-up.

Before implementation, the engineer should answer open questions 1 and 2 above — specifically whether existing production data for ascending variables is semantically correct.

> **Production data uncertainty (confirmed):** It is certain that ascending comparator configurations exist in production. However, it is not possible to determine at this point whether those records were actually used in commission calculations or simply configured but never processed. This means the `minimum` values stored may be semantically incorrect (e.g., `minimum=0` for ascending variables), but changing the calculation logic could silently produce different results for historical or future recalculations.
>
> **During implementation:** Before applying any calculation fix, a DB query must be run to inspect all `RankifierVariable` records with `comparator IN ('<', '<=')` and check their `minimum`, `goal`, and whether their associated `RankingIncentive` is linked to any completed `Commission`. This will determine whether a data migration is needed alongside the code change, and whether any historical rankings would be affected. Implementation must be paused at that point to present the findings to the engineer before proceeding.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
