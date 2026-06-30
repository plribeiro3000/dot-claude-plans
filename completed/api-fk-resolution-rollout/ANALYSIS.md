# ANALYSIS: Error message quality when the FK mapping moves to the model

## Why this analysis exists

While implementing row 1 of `PLAN.md` (`IndicatorFactory::Parser` → Indicator model, PR #5075), two flaws in the original plan surfaced:

1. **The "regression specs" the rollout asked for were not actually regression specs.** The hotfix 3.32.1 bug was confined to models without `presence` validators on the migrated FK (Deal `client_id`/`product_id`, Role `parent_id`). On those, an unknown external_id silently became `nil`, no validator caught it, and the API returned a false success. **Every other model affected by this rollout** (Indicator, Goal, Subsidiary user, Groupification, UserIdentifierAction) has a `presence` validator on the migrated FK. With or without the migration, those endpoints return 422 — only the error message changes. There is no bug to regress on.

2. **The migration as drafted does not produce the message improvement that motivated the PR.** The model's `before_validation` resolver adds `errors.add(:user_id, :invalid)` when the mapping fails, but leaves `self.user_id` as `nil`. The `validates :user_id, presence: true` then fires inside the same `valid?` pass and adds `:blank` on top. The client receives both messages: `["can't be blank", "is invalid"]`. The promised `:blank` → `:invalid` upgrade did not happen.

This analysis reframes the rollout's goal and records the chosen pattern.

## What the rollout is actually about

Not a regression fix. Two non-bug objectives:

1. **Simplify controllers and factories** by eliminating the silent-rescue ID mapping in each parser, replacing it with a single declarative resolver on the model. The hotfix 3.32.1 pattern is the seed.
2. **Improve the error message** for the case "the client sent a value that didn't map to any registered resource". Today the API returns `["can't be blank"]` (false — the client sent something), or `["can't be blank", "is invalid"]` (confusing — both at once). The goal is a single accurate message that says exactly what happened.

The error message is the load-bearing piece of (2). The original plan used `:invalid` because that was the symbol the parser already added before the migration. After review, `:not_found` (the existing Rails/Devise key, defined in all eight project locales) is a better fit:

- PT-BR: `não encontrado`
- EN: `not found`

Semantically aligned with "the client referenced a resource that does not exist (yet) in the system". `:invalid` is the Rails Way default for "value is malformed" — close enough to work, but `:not_found` carries the specific meaning of "you referenced something that does not exist". No new i18n keys needed.

## The required behavior

The client-visible contract after the migration:

| Scenario                                          | Expected `errors[<fk>]`                     |
|---------------------------------------------------|---------------------------------------------|
| Client did not send the field                     | `[<:blank translation>]`                    |
| Client sent a value that did not map              | `[<:not_found translation>]`                |
| Client sent a value that mapped                   | `[]`                                        |

Today's behavior (after PR #5075 as-is, before this analysis applies):

| Scenario                                          | Actual `errors[<fk>]`                       |
|---------------------------------------------------|---------------------------------------------|
| Client did not send the field                     | `[<:blank>]`  ✅                            |
| Client sent a value that did not map              | `[<:blank>, <:invalid>]`  ❌                |
| Client sent a value that mapped                   | `[]`  ✅                                    |

The second row is the gap.

## Options considered

### Option A.1 — `after_validation` callback that strips `:blank` when `:invalid` is present

A callback runs after the `validates ... presence: true` has already added `:blank`. The callback walks the listed attributes, checks `errors.added?(attr, :invalid)`, deletes the attribute's errors, and re-adds `:invalid`.

Drawback: errors are generated and then deleted, which is gambiarra-shaped. Adds a callback to every model and requires an attribute list inside it.

### Option A.2 — Replace `validates ... presence: true` with a custom `validate` method

```ruby
validate :user_id_presence_unless_attempted

def user_id_presence_unless_attempted
  return if user_id.present?
  return if user_external_id.present?
  errors.add(:user_id, :blank)
end
```

Explicit, but loses the standard `validates ... presence: true` line that other engineers expect to see when scanning a model. Less discoverable.

### Option A.4 — `validates ... presence: true, unless: -> { *_external_id_present? }` **(chosen)**

Use Rails' built-in `unless:` option to skip the presence check exactly when the model is about to surface a `:not_found` error from the resolver instead.

```ruby
class Indicator < ApplicationRecord
  attr_accessor :user_external_id, :variable_external_id, :subsidiary_id

  before_validation :resolve_user_external_id
  before_validation :resolve_variable_external_id

  validates :user_id, presence: true, unless: -> { user_external_id_present? }
  validates :variable_id, presence: true, unless: -> { variable_external_id_present? }

  private

  def user_external_id_present?
    user_external_id.present?
  end

  def variable_external_id_present?
    variable_external_id.present?
  end

  def resolve_user_external_id
    return if user_external_id.nil?

    self.user_id =
      if subsidiary_id.present?
        UserIdentifier.get(company_id: company_id, subsidiary_id: subsidiary_id, value: user_external_id).user_id
      else
        UserIdentifier.get(company_id: company_id, value: user_external_id).user_id
      end
  rescue ActiveRecord::RecordNotFound
    errors.add(:user_id, :not_found)
  end

  def resolve_variable_external_id
    return if variable_external_id.nil?

    self.variable_id = Variable.get_id(company_id: company_id, key: variable_external_id)
  rescue ActiveRecord::RecordNotFound
    errors.add(:variable_id, :not_found)
  end
end
```

**Behavior per scenario:**

| Scenario                                   | `user_external_id_present?` | Presence runs?      | Resolver adds   | Final `errors[:user_id]` |
|--------------------------------------------|------------------------------|---------------------|------------------|---------------------------|
| Client did not send `user_id`              | `false`                      | yes (`unless false`) | nothing          | `[:blank]`                |
| Client sent `user_id` that didn't map      | `true`                       | no (`unless true`)   | `:not_found`     | `[:not_found]`            |
| Client sent `user_id` that mapped          | `true`                       | no (skip)            | nothing (ok)     | `[]`                      |

**Why A.4 over A.1 / A.2:**

- vs. A.1: no callback gymnastics. The error is never generated in the first place — no delete-and-re-add.
- vs. A.2: keeps `validates ... presence: true` in the model, so the rule is visible on the line where Rails engineers expect to find it. The `unless:` clause is the one-line annotation explaining the exception.

**Engineer decision recorded 2026-05-27:** this is the canonical shape the rollout will replicate across the entire API codebase.

## Where A.4 applies vs. where it does not

A.4 applies when the model already has a `presence` validator on the FK being migrated:

- **Indicator** — `user_id`, `variable_id` have presence.
- **Goal** — `user_id` / `group_id` / `variable_id` have conditional presence (`if: :group?`, etc.). A.4 still applies; the `unless:` clause must coexist with the existing conditional. (To be designed when row 2 starts.)
- **User**, **Groupification**, **UserIdentifierAction** — case by case when each row starts.

A.4 does **not** apply when the model intentionally permits a `nil` FK:

- **Deal `client_id` / `product_id`** (hotfix 3.32.1) — no presence validator; the resolver alone does the work.
- **Role `parent_id`** (hotfix 3.32.1) — same.

The hotfix models keep their current pattern. They are pinned in `PLAN.md` § "Out of scope".

## Follow-up: retroactively update the hotfix error symbol

The hotfix 3.32.1 resolvers use `errors.add(:client_id, :invalid)` / `errors.add(:product_id, :invalid)` / `errors.add(:parent_id, :invalid)`. The same upgrade to `:not_found` applies for consistency across the API. The corresponding regression specs in `deals_controller_regressions_spec.rb` need to be updated to assert on the new key.

Tracked as a follow-up cleanup, scope-separate from this rollout. Filed under "future work" in `PLAN.md`.

## Spec strategy under the new pattern

The specs added to `*_controller_regressions_spec.rb` files in PR #5075 today assert only HTTP 422 + zero creation — both true with and without the migration. They prove nothing.

Under A.4 they become real behavior tests because the body content actually changes:

- Old behavior: `errors[:user_id] == [t(:blank), t(:invalid)]`
- New behavior: `errors[:user_id] == [t(:not_found)]`

The spec must assert on the response body:

```ruby
it 'returns the not-found error on user_id' do
  expect(response.parsed_body).to eq('user_id' => ['não encontrado'])
end
```

4Shark spec convention: literal pt-BR string, never `I18n.t` (sibling specs follow this — e.g. `indicator_spec.rb` asserts on `['não é válido']`). The test locale is pt-BR.

This spec **fails** on the pre-migration code (returns `["não pode ficar em branco", "não é válido"]`) and **passes** on the post-migration code (returns `["não encontrado"]`). Negative-test criterion from `PLAN.md` § "Acceptance criteria" satisfied.

## The cascade problem and the resolved architecture

PR #5075 implementation surfaced that the original A.4 design did not handle cascading lookups cleanly. The factory parser's resolution of `Indicator#user_id` is a **three-level cascade**:

- **Level 1 — Subsidiary**: client sends a subsidiary external_id (string). `Subsidiary.get_id(company_id:, external_id:)` returns the internal `subsidiary_id` integer.
- **Level 2 — UserIdentifier**: using the internal `subsidiary_id` and the client-sent `value` (UserIdentifier.value), `UserIdentifier.get(company_id:, subsidiary_id:, value:)` returns a UserIdentifier whose `user_id` is the integer FK to assign to Indicator.
- **Level 3 — Indicator**: receives the already-resolved `user_id` integer. Save proceeds normally.

PR #5075's first attempt squeezed all three levels into the Indicator model's `before_validation`, which required `attr_accessor :subsidiary_id` on Indicator (a transient context carrier). Engineer rejected this — Indicator does not own subsidiary as a concept and should not declare it.

### Final architecture (engineer-decided 2026-05-27)

**Cascade lives in the controller, never in the consumer model.** The controller walks the cascade level by level, calling each model's existing class method (`Subsidiary.get_id`, `UserIdentifier.get(...).user_id`, `Variable.get_id`). When any level raises `ActiveRecord::RecordNotFound`, the controller catches and substitutes **sentinel `0`** (not `nil`) for the resolved value.

- `0` is a valid integer that satisfies the model's `presence: true` validator (does not trigger `:blank`).
- No real record has id `0` (Postgres sequences start at `1`), so `0` unambiguously signals "the client sent a value but it could not be resolved".
- Sentinel `0` propagates through subsequent cascade levels: a failed subsidiary resolution yields `subsidiary_id = 0`, which when passed to `UserIdentifier.get(subsidiary_id: 0, ...)` raises NotFound again, yielding `user_id = 0`. The cascade never short-circuits — the last level (Indicator) is always reached, and that is where the error is registered.

The Indicator model has no `attr_accessor` for any external_id and no resolver that performs lookups. It simply detects sentinel `0` on its FKs and registers `:not_found`:

```ruby
class Indicator < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :variable, optional: true
  # ...

  before_validation :ensure_user_id_found
  before_validation :ensure_variable_id_found

  validates :user_id, presence: true
  validates :variable_id, presence: true

  private

  def ensure_user_id_found
    return unless user_id == 0

    errors.add(:user_id, :not_found)
  end

  def ensure_variable_id_found
    return unless variable_id == 0

    errors.add(:variable_id, :not_found)
  end
end
```

Controller (subsidiaries variant — root variant omits the subsidiary step):

```ruby
def create
  # ...
  Indicator.transaction do
    @indicator = current_company.indicators.new(
      indicator_params_on_creation.merge(
        user_id: user_id_on_creation,
        variable_id: variable_id_on_creation
      )
    )

    if @indicator.save
      # ...
    else
      render json: @indicator.errors, status: :unprocessable_content
    end
  end
end

private

def subsidiary_id_on_creation
  Subsidiary.get_id(company_id: current_company.id, external_id: params[:subsidiary_id])
rescue ActiveRecord::RecordNotFound
  0
end

def user_id_on_creation
  value = params.dig(:indicator, :user_id)
  return nil if value.blank?

  UserIdentifier.get(
    company_id: current_company.id,
    subsidiary_id: subsidiary_id_on_creation,
    value: value
  ).user_id
rescue ActiveRecord::RecordNotFound
  0
end

def variable_id_on_creation
  key = params.dig(:indicator, :variable)
  return nil if key.blank?

  Variable.get_id(company_id: current_company.id, key: key)
rescue ActiveRecord::RecordNotFound
  0
end
```

No safe-navigation operator anywhere — 4Shark code style forbids it.

### Behavior matrix

| Scenario                                                            | `user_id` arriving at model | Presence runs?     | `ensure_user_id_found` adds | Final `errors[:user_id]` |
|---------------------------------------------------------------------|------------------------------|---------------------|------------------------------|---------------------------|
| Client did not send `user_id`                                       | `nil`                        | yes → `:blank`      | `nil`, not `0` — skips       | `[:blank]`                |
| Client sent `user_id`; subsidiary OK; identifier OK                 | real integer                 | no (present)        | non-zero — skips             | `[]`                      |
| Client sent `user_id`; subsidiary OK; identifier not found          | `0`                          | no (present)        | `:not_found`                 | `[:not_found]`            |
| Client sent `user_id`; subsidiary not found                         | `0` (via propagated sentinel)| no (present)        | `:not_found`                 | `[:not_found]`            |
| Client sent `user_id`; subsidiary not found and identifier missing  | `0`                          | no (present)        | `:not_found`                 | `[:not_found]`            |

The error key surfaced to the client is **always `user_id`** when a user-related failure happens, regardless of which cascade level actually failed. Business logic: resolving the user takes two inputs (subsidiary identifier + user value); either being invalid prevents user resolution, and the client-facing concept is "the user wasn't found". The client is creating an Indicator — they don't care about subsidiary or UserIdentifier as separate entities.

### Why this architecture (not the others considered)

- It preserves the engineer's intent that **single-level FKs go into the model** while **cascading FKs stay in the controller** — uniformly across all FKs of all models in the rollout. The model never holds transient context attrs (no `subsidiary_id`, no `user_external_id`, no `variable_external_id`).
- The sentinel `0` removes the need for a `unless: -> { *_external_id_present? }` clause on the presence validator. The model's only role is "detect the sentinel and turn it into a `:not_found` error". Simpler model.
- All resolution lookups remain encapsulated in their owning model's existing `get` / `get_id` methods. Nothing new is added to Subsidiary, UserIdentifier, or Variable.
- The cascade walker is a small set of private controller helpers — the same shape already used today by `user_id_on_update` and `variable_id_on_update` in PUT/DELETE actions (which were out of scope for migration). Convergent style across actions.

### Implication for the canonical pattern

The `PLAN.md` "canonical pattern" needs to be rewritten under this architecture. The shape no longer differs by "single-level vs cascading" — all FK resolution lives in the controller, all models have the same `ensure_<fk>_found` callback shape. The previous A.4 framing (`unless:` + `*_external_id_present?` predicates) is superseded.

### Spec strategy

The body-content spec convention (assert `errors[:user_id] == ['não encontrado']`) still applies. Both pre- and post-migration code return 422, but only post-migration returns the body with `não encontrado` cleanly — pre-migration returned the noisier `["não pode ficar em branco", "não é válido"]`. Spec falls in the negative-test on revert.

### Next step

1. Update `PLAN.md` "canonical pattern" with the controller-cascade + sentinel-0 + `ensure_<fk>_found` model shape.
2. Update PR #5075 (Indicator):
   - Strip `attr_accessor` for any external_id from `Indicator`.
   - Remove the existing resolver methods that perform lookups.
   - Add `ensure_user_id_found` and `ensure_variable_id_found` callbacks.
   - Restore plain `validates ..., presence: true` (remove `unless:`).
   - Replace `indicator_params_on_creation` rename-based shape with controller helpers that resolve to integer/0.
3. Re-run specs; the body-content assertion now reflects the new error key `:not_found` cleanly.
4. Move to row 2 (`GoalFactory::Parser`) with the locked-in pattern.

## Regression note (2026-05-31)

The no-`subsidiary_id` shape used in Deal/Goal/Indicator (`UserIdentifier.get(company_id:, value:)`) caused a production incident on shared-001 when the maqnelson integrator nightly burst put real volume on `PUT /api/v3/subsidiaries/:id/deals/:id`. The query lacks the `subsidiary_id IS NULL` predicate that the `user_identifiers` partial unique index requires, so Postgres fell back to the `(company_id)` single-col index and filtered by `value` in memory — O(n) on each company's identifier count. RDS db-1 saturated at 99.5% CPU for ~70 minutes; 93% of web requests returned 5xx.

Fix shipped in hotfix 3.33.1 (PR #5099): the 3 model callsites now pass `subsidiary_id: nil` explicitly, which makes the query hit the partial unique index in O(log n). Full timeline, root-cause analysis, and the additional `add_index :deals, [:company_id, :external_id]` follow-up live in `~/.claude/plans/active/app/elasticsearch-bulk-refresh-and-upgrade/ANALYSIS.md` (the parallel incident also exposed `Deal.get(company_id, external_id)` as a long-standing index gap, addressed by migration `20260531100514`).
