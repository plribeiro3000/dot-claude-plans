# PLAN: Roll out model-level FK resolution to remaining API endpoints

## Final status (2026-05-28) — ROLLOUT COMPLETE

| Row | Migration | PR | Status |
|---|---|---|---|
| 1 | `IndicatorFactory::Parser` → Indicator | #5075 | ✅ merged |
| 2 | `GoalFactory::Parser` → Goal | #5079 | ✅ merged |
| 3 | `DealFactory::Parser` → Deal (`user_id`, `status_key`) | #5081 | ✅ merged |
| 4 | `UserFactory::Parser` → User + Seat + UserIdentifier | #5082 | ✅ merged |
| 5 | `GroupificationFactory::Parser` → Groupification | #5083 | ✅ merged |
| 6 | `UserIdentifierActionFactory::Parser` → UserIdentifierAction | #5084 | ✅ merged — turned out to be dead code, factory dropped |

Kaizen pass (independent of rollout): ✅ merged — deleted dead `def user_id` from both `Groups::GroupificationsController` and `Subsidiaries::Groups::GroupificationsController` (PR #5078).

### Follow-up work (all completed)

- ✅ **Companion work — upload document processors** (PR #5085) — workers migrated to use `*_external_id` virtual attrs; deleted factories confirmed unreferenced.
- ✅ **Validator rename** (`existing_*` → `*_presence`) consolidating the nil/zero shape across Indicator, Goal, Deal, Groupification, Seat (PR #5087).
- ✅ **Hotfix-symbol upgrade** (`:invalid` → `:not_found`) on Deal `client_id`/`product_id` and Role `parent_id` resolvers (PR #5088).
- ✅ **Sentinel-`0` validation end-to-end** (PR #5090) — Rails doc + DB FK constraint inventory + 38 regression specs covering literal `0` (integer + string) on every migrated endpoint. Audit found no functional gap: all FKs are protected (model `*_presence` validator + DB FK, except Seat#parent_id which is polymorphic). Specs documented in `/tmp/sentinel_zero_validation_audit_20260528_182000.html`.

### Deferred work (still in active/)

- ⏸ **DealField FK migration** — discovered during follow-up that `Api::V3::Deals::FieldsController` has the same silent-rescue shape but moving it to the consolidated Groupification pattern (sentinel 0 + `find_by || new` + `*_presence`) is a breaking API change (404 → 422 for invalid `deal_id` path and `variable` body). Plan + reference branch in `~/.claude/plans/active/api-fk-resolution-deal-field/PLAN.md`. To be picked up in a scheduled minor release with client coordination — explicitly not a hotfix.

### Canonical pattern (locked in across rows 1–4)

- **Model**: `attr_accessor :*_external_id` + `before_validation :resolve_*_external_id` + private predicate `*_external_id_present?`.
  - Single-level FK (e.g. variable_id, state_id, subsidiary_id, group_id) → resolver does the actual lookup inline (`Variable.get_id`, `State.find_by!`, `Subsidiary.get_id`, `Group.get_id`) with `rescue ActiveRecord::RecordNotFound → errors.add(:fk, :not_found)`.
  - Cascading FK (e.g. Indicator user_id, Deal user_id, Seat parent_id) → resolver only does **sentinel detection**: `if external_id.zero? then errors.add(:not_found) else self.fk = external_id end`. The actual cascade lives in the controller.
- **Controller**: `*_params_on_creation` permits the safe-savable fields; `.merge(...)` injects the virtual attrs. Cascading FKs read via private `*_on_creation` helpers that call the corresponding model class methods (`Subsidiary.get_id`, `UserIdentifier.get(...).user_id`, `UserIdentifier.get(...).user.seat.id`, etc.) with `rescue → 0` (sentinel propagation). No safe-navigation operator anywhere (4Shark style).
- **Presence validators** carry `unless: -> { *_external_id_present? }` when the FK has presence required, so when the cascade returns `0` (present, not blank), presence is skipped and the resolver's `:not_found` is the only message.
- **Error rekey** when API attribute name differs from FK column (e.g. `:status_id` → `:status`, `:variable_id` → `:variable`) — controller's error branch does the remap inline (same shape `if/each/add/delete` pattern across all migrated controllers).
- **No silent filtering** in helpers (e.g. don't filter `seat_type` by `Seat::API_TYPES.include?` — the model's `inclusion:` validator already produces "não está incluído na lista" with feedback).
- **Specs**: behavior specs (`*_controller_spec.rb`) cover `'and unknown <fk>'` contexts with `expect(response.parsed_body).to eq('<key>' => ['não encontrado'])`. Literal pt-BR strings, no `I18n.t` (4Shark convention). The `*_regressions_spec.rb` files are reserved for actual hotfix regressions — they only have `'with timeout'` contexts (and the genuine hotfix-3.32.1 regressions on Deal/Role).
- **Naming**: `*_params_on_creation`, `*_external_id_on_creation`, `subsidiary_id_on_creation`, `parent_subsidiary_id_on_creation` (suffix `_on_creation`, matching Deal/Indicator. Goal's pre-existing `_on_create` was normalized to `_on_creation` in row 2 PR.)

### Open items deferred to end of rollout (already in PLAN.md sections below)

- **Companion work — upload document processors** (engineer-flagged, blocking before declaring rollout done): audit each migrated model's upload-side worker. Verify no deleted factory is referenced by a worker (retroactive grep on `app/workers/` for IndicatorFactory, GoalFactory, DealFactory, UserFactory). For workers that do their own FK mapping, simplify them to use the new model `*_external_id` virtual attrs. GroupificationFactory is reused by upload — row 5 must preserve.
- **Sentinel-`0` validation end-to-end** (engineer-flagged, do at end): Rails doc + DB FK constraint inventory + integration test per endpoint with literal `0` in each FK + lockdown where gap is found + permanent spec.
- **Hotfix-symbol upgrade** (`:invalid → :not_found`) on Deal `client_id`/`product_id` and Role `parent_id` resolvers from hotfix 3.32.1. Scope-separate. Plus regression spec update.

## Context

Hotfix 3.32.1 (PR #5073) fixed three endpoints where an unknown client-supplied identifier silently resolved to `nil` and the API returned a false success (Deal `client_id`/`product_id` on update, Role `parent_id` on create). The fix moved the external→internal ID resolution from the controller (with `rescue ActiveRecord::RecordNotFound; nil`) into a `before_validation` callback on the model, via a virtual `*_external_id` attribute.

**Intent of this rollout (clarified 2026-05-27).** The hotfix fixed real bugs (Deal/Role on update). This rollout is **not** about fixing more bugs — the audit shows the silent-rescue pattern produces a vague-but-not-wrong response everywhere else (a 422 `:blank` from a presence validation, or a 404 from a failed lookup). The goal is:

1. **Simplify controllers** by removing the `Klass.get_id rescue nil` shape and the per-FK resolver methods.
2. **Improve error messages** from `:blank` (caused by `nil` resolution feeding a presence validator) to `:invalid` (explicit, from the model's `before_validation`).

Both benefits only materialize when the resolved FK is **persisted** by the request — i.e., the FK feeds a `save` or `update`. When the resolved FK is used purely to **look up** an existing record (`Indicator.get(... user_id: ..., variable_id: ...)`), the model never gets a chance to validate, the `before_validation` callback would never run, and the migration provides no benefit. Those rows are out of scope.

## Audit (2026-05-27)

Each row from the original draft was re-read in the codebase and classified `save` (migrate) vs `lookup` (keep) vs `dead` (delete the unused method).

| # | Original target | Classification | Reasoning |
|---|---|---|---|
| 1 | `IndicatorsController#update`, `#destroy` | **lookup** | `Indicator.get(... user_id:, variable_id:, compiled_at:)` is the lookup key; `update(value:)` writes no FK; destroy writes nothing. Model never instantiated when lookup fails. |
| 2 | `Subsidiaries::IndicatorsController#create` | **save** | Goes through `IndicatorFactory` — covered by row 9. |
| 2 | `Subsidiaries::IndicatorsController#update`, `#destroy` | **lookup** | Same shape as row 1, plus `subsidiary_id` also feeds the lookup. |
| 3 | `GoalsController#update` | **lookup** | `Goal.get(... user_id:, variable_id:, group_id:, ...)` is the lookup key; `update(:baseline, :direction, :value)` writes no FK. |
| 4 | `Subsidiaries::GoalsController#create` | **save** | Goes through `GoalFactory` — covered by row 10. |
| 4 | `Subsidiaries::GoalsController#update` | **lookup** | Same shape as row 3. |
| 5 | `Subsidiaries::UsersController#create` | **save** | Goes through `UserFactory` — covered by row 12. |
| 5 | `Subsidiaries::UsersController#update` | **lookup** | `UserIdentifier.get(... subsidiary_id:, value:)` is the lookup; `update` writes no FK (state goes through `find_or_initialize_by`, different pattern). |
| 6 | `Groups::GroupificationsController#update`, `#destroy` | **dead** | `def user_id` (lines 122–126) exists but is never called from any action. The factory does the resolution. Method should be deleted. |
| 7 | `Subsidiaries::Groups::GroupificationsController#update`, `#destroy` | **dead** (`user_id`) + **lookup** (`subsidiary_id`) | `def user_id` (lines 137–141) is dead. `subsidiary_id` IS used (passed to factory as a pre-resolved integer). |
| 8 | `DealFactory::Parser` | **save (partial)** | `client_id`, `product_id` already migrated in hotfix. Remaining: `user_id` (always passed to factory). `status_id`, `type` are by-key/by-enum and have presence validators on the model — optional migration for message consistency. |
| 9 | `IndicatorFactory::Parser` | **save (clean)** | `params.merge(user_id:, variable_id:)` — classic shape, fits the pattern directly. Subsidiary scoping wraps the `UserIdentifier.get` call. |
| 10 | `GoalFactory::Parser` | **save (clean)** | `params.merge(group_id:, user_id:, variable_id:)`. |
| 11 | `GroupificationFactory::Parser` | **save (architectural caveat)** | Exposes `parser.ids` consumed by `Groupification.find_or_initialize_by(parser.ids)` in `GroupificationFactory#groupification`. Migration cannot pass `*_external_id` to `find_or_initialize_by` (not real columns). Requires factory restructure (e.g., resolve once in model, look up by resolved IDs, OR change the lookup-then-initialize shape entirely). |
| 12 | `UserFactory::Parser` | **save (chain)** | `seat_parent_id` resolves a 3-hop chain (`UserIdentifier → User → Seat.id`). Migration is possible but model needs a multi-step resolver. `state_id` is by ISO3166 (`State.find_by!`), pattern shape fits but lookup type differs. |
| 13 | `UserIdentifierActionFactory::Parser` | **save (branching)** | Per-action resolution (`create` vs `promote`/`delete`) in `initialize`. Migration would move per-action resolvers to the model or to dedicated subclasses. Largest delta of the set. |

### Conclusions

- **Lookup rows (1, 2 PUT/DELETE, 3, 4 PUT, 5 PUT)** stay as-is. The current `rescue ActiveRecord::RecordNotFound; nil` shape in the controller is acceptable for lookup — when the lookup fails it falls into `find_by!` raising `RecordNotFound`, which the API handles as 404. Migration provides no behavioral or readability benefit.
- **Dead methods (rows 6, 7 — `def user_id`)** can be deleted as a kaizen pass; not a pattern migration.
- **Save rows (8–13)** are the real target. All are factory parsers feeding a `save`. Sequencing by risk:

## The pattern (canonical form — see ANALYSIS.md 2026-05-27 for the design rationale)

**FK resolution lives in the controller, never in the consumer model.** The controller walks the cascade level by level via private helpers, each calling the existing class method of the model that owns that level's lookup (`Subsidiary.get_id`, `UserIdentifier.get(...).user_id`, `Variable.get_id`, etc.). When any level raises `ActiveRecord::RecordNotFound`, the helper substitutes **sentinel `0`** and returns it. Sentinel `0` propagates through subsequent helpers — a failed subsidiary becomes `subsidiary_id = 0`, which when fed to `UserIdentifier.get(subsidiary_id: 0, ...)` raises again and yields `user_id = 0`. The cascade never short-circuits.

The consumer model has no `attr_accessor` for any external identifier, no resolver that performs lookups. It receives integers from the controller (real id, `0`, or `nil` when the client did not send the field) and detects the sentinel.

### Controller

```ruby
def create
  # ...
  Indicator.transaction do
    @indicator = current_company.indicators.new(
      indicator_params.merge(
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

def indicator_params
  params
    .require(:indicator)
    .permit(:compiled_at, :value, :variable, :user_id)
    .except(:variable, :user_id) # raw external values consumed by the helpers below
end

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

Notes:
- Helpers return `nil` when the client did not send the field, integer when found, `0` when the lookup failed.
- No safe-navigation operator (`&.`) anywhere — banned by 4Shark code style.
- The root (non-subsidiary) controller skips `subsidiary_id_on_creation` and calls `UserIdentifier.get(company_id:, value:)` directly.
- Helpers are named `<fk>_on_creation` to mirror the existing `<fk>_on_update` / `<fk>_on_destroy` helpers used for lookup-based PUT/DELETE actions.

### Model

```ruby
class <Model> < ApplicationRecord
  belongs_to :<assoc>, optional: true
  # ...

  before_validation :ensure_<assoc>_id_found

  validates :<assoc>_id, presence: true

  private

  def ensure_<assoc>_id_found
    return unless <assoc>_id == 0

    errors.add(:<assoc>_id, :not_found)
  end
end
```

Behavior table:

| Scenario                                | `<assoc>_id` arriving | Presence runs?    | `ensure_<assoc>_id_found` adds | Final `errors[:<fk>]` |
|-----------------------------------------|------------------------|-------------------|---------------------------------|------------------------|
| Client did not send the field           | `nil`                  | yes → `:blank`    | skips (not `0`)                  | `[:blank]`             |
| Client sent value that did not map      | `0`                    | no (`0` present)  | `:not_found`                    | `[:not_found]`         |
| Client sent value that mapped           | real integer           | no (present)      | skips (non-zero)                | `[]`                   |

Notes:
- The model has no concept of subsidiary, no virtual attrs, no rescue clauses.
- `presence: true` stays plain — no `unless:` clause. The sentinel `0` satisfies presence on its own (`0.blank?` is `false`).
- For models without a `presence` validator (Deal `client_id`, Role `parent_id` from hotfix 3.32.1), the same `ensure_<fk>_id_found` callback works without the validator line. The hotfix-era resolvers that emit `:invalid` should be upgraded to this shape — tracked under "Future work".
- Error symbol is `:not_found` (Rails/Devise standard key, present in all eight project locales). No new i18n entries required.

### Factory parser

The parser stops resolving the migrated FK. Its `params` method passes raw external values straight through; the controller helpers do the lookup. If after migration the parser does nothing more than rename keys, and the factory wrapper around it does nothing more than `.new` + `.save`, both classes can be removed (the controller calls `current_company.<models>.new(...)` directly). Decide per row.

### Behavior spec (replaces "regression spec")

The hotfix 3.32.1 specs were genuine regression tests (they caught a real bug). For this rollout there is no bug to regress on — the goal is message quality. Specs assert on response body content, not just status code, so they prove the new key reaches the client.

```ruby
context 'with unknown <assoc>_id' do
  before do
    post '/api/v3/<resource>s',
         params: { <resource>: { ..., <assoc>_id: 'NONEXISTENT_<ASSOC>' } }.to_json,
         headers: authorization_headers
  end

  it 'does not create <resource>' do
    expect(<Model>.where(...).count).to eq(0)
  end

  it 'returns the not-found error on <assoc>_id' do
    expect(response.parsed_body).to eq('<assoc>_id' => ['não encontrado'])
  end
end
```

The body assertion uses the **literal pt-BR string** the API returns under the test locale (`não encontrado` for `errors.messages.not_found`). 4Shark spec convention is "declarative text, never `I18n.t` lookups" — match the style of sibling specs (`indicator_spec.rb` asserts on `['não é válido']`, not on a lookup). This assertion fails on the pre-migration code (which returns `["não pode ficar em branco", "não é válido"]`) and passes on the post-migration code (`["não encontrado"]`).

## Scope — endpoints to migrate

All entries are factory parsers. Each row = one PR.

| # | Factory | Used by endpoints | Virtual attrs to add | Notes |
|---|---|---|---|---|
| 1 | `IndicatorFactory::Parser` | `POST /api/v3/indicators`, `POST /api/v3/subsidiaries/:subsidiary_id/indicators` | `user_external_id`, `variable_external_id` on `Indicator`; subsidiary scoping handled inside the resolver | Cleanest case — Indicator has presence validators on `user_id` and `variable_id`. |
| 2 | `GoalFactory::Parser` | `POST /api/v3/goals`, `POST /api/v3/subsidiaries/:subsidiary_id/goals` | `group_external_id`, `user_external_id`, `variable_external_id` on `Goal` | Conditional presence (`UserGoal` vs `GroupGoal`) — regression spec must cover both arms. |
| 3 | `DealFactory::Parser` (completion) | `POST /api/v3/deals`, `POST /api/v3/subsidiaries/:subsidiary_id/deals` | ADD `user_external_id` on `Deal` (client/product already done in hotfix). `status_key` and migration to `:invalid` for `status_id` optional — Deal has `validates :status_id, presence: true`, so today it returns 422 `:blank` and is not a bug. | Smallest delta; the hotfix did most of the work. |
| 4 | `UserFactory::Parser` | `POST /api/v3/users`, `POST /api/v3/subsidiaries/:subsidiary_id/users` | `seat_parent_external_id` + `parent_subsidiary_external_id` (chain) on `Seat` or as composite on `User`; `state_iso3166` on `User` | Chain lookup. Decide between (a) two virtual attrs on `Seat` that together resolve parent, or (b) a single composite resolver on `User` that walks the chain and writes `seat_attributes[:parent_id]`. |
| 5 | `GroupificationFactory::Parser` | `PUT/DELETE /api/v3/groups/:group_id/groupifications/:id` and subsidiary variant | `user_external_id`, `group_external_id` on `Groupification` | **Architectural caveat**: today `GroupificationFactory#groupification` does `Groupification.find_or_initialize_by(parser.ids)` — needs restructure because `find_or_initialize_by` cannot accept virtual attrs. Options: (a) resolve once in the factory before lookup, (b) move the find-or-init into the model. Decide on read. |
| 6 | `UserIdentifierActionFactory::Parser` | identifier mgmt actions | Per-action attrs — `new_subsidiary_external_id`, `subsidiary_external_id`, `user_identifier_value` | Largest delta. Per-action branching today; migration shape depends on whether `UserIdentifierAction` is one model or several. Read first, then plan. |

Each row = one PR.

### Kaizen pass (separate small PR)

Rows 6 and 7 of the original draft had a `def user_id` method in the controller that is never called from any action — pure dead code. Delete it in a single small PR, no factory or model change involved. Independent from the rollout above.

## Sequencing

1. **Row 1 (IndicatorFactory::Parser)** — cleanest match for the pattern. Indicator has presence validators on `user_id` and `variable_id`. Lowest risk. Validates the pattern outside the hotfix.
2. **Row 2 (GoalFactory::Parser)** — similar shape. Conditional presence makes the regression spec slightly heavier (two arms).
3. **Row 3 (DealFactory::Parser completion)** — small follow-up to the hotfix. Adds `user_external_id` to Deal; optional status migration left as a per-PR decision.
4. **Row 4 (UserFactory::Parser)** — first chain lookup. Stop here and decide on the design choice (composite on User vs split on Seat) before writing code.
5. **Row 5 (GroupificationFactory::Parser)** — architectural caveat; the factory restructure adds risk. Do after the simpler four are landed and the pattern is stable.
6. **Row 6 (UserIdentifierActionFactory::Parser)** — biggest delta; left for last so the team's confidence with the pattern is highest going in.

Kaizen cleanup (delete dead controller `user_id` methods in `Groups::GroupificationsController` and `Subsidiaries::Groups::GroupificationsController`) can land in parallel with any of the above — no dependency.

## Out of scope

- **Lookup endpoints** — `IndicatorsController` PUT/DELETE, `Subsidiaries::IndicatorsController` PUT/DELETE, `GoalsController` PUT, `Subsidiaries::GoalsController` PUT, `Subsidiaries::UsersController` PUT. The FK is used to find the existing record, not to save it. The model's `before_validation` would never run. See the Audit section above for per-row reasoning.
- **Adding `validates :<assoc>_id, presence: true`** to models that intentionally allow nil (Deal `client_id`/`product_id`, Role `parent_id`). The hotfix's design choice — `before_validation` adds `:invalid` only when an attempt was made — is the correct behavior and must be preserved.
- **API schema changes** — the inbound payload key stays `client_id`/`product_id`/`user_id`/`variable`/etc. The model exposes a `*_external_id` virtual attribute; the factory passes the inbound value through unchanged. Clients see no rename.
- **Status/key fields with existing presence validators** (Deal `status_id` produces a 422 with `:blank` today) — may apply the pattern for message consistency, but not a bug fix. Decide per PR.
- **Endpoints under `app/controllers/api/v1` or `api/v2`**. The audit found nothing relevant there; if anyone re-opens the audit, treat each new finding as a separate planning item.

## Risks

- **Factory parsers double-register errors during the migration window.** When a factory is converted, the parser stops resolving the migrated FK in the same PR — no transitional period. If a partial migration is ever attempted (some FKs migrated, others not), the parser must skip the migrated ones explicitly.
- **`before_validation` runs on every save.** Programmatic code paths (rake tasks, seeds, console scripts) MUST set the FK directly via `<assoc>_id`, NOT `<assoc>_external_id`. Setting only `<assoc>_external_id` works too, but assumes the model can do the lookup at that moment. If the lookup fails, `errors.add` fires — `save` returns false silently for the script. Caller is responsible for checking the return value. Document this in each model's PR description.
- **Multi-tenant scoping (`company_id`).** The resolver uses `self.company_id` from the record. For records built via association (`current_company.<model>s.new`), `company_id` is set before `before_validation` runs. Edge case: building a new record without the association (e.g., `<Model>.new(<assoc>_external_id: 'X')`) — `company_id` is nil, the lookup returns nothing, and `errors.add(:<assoc>_id, :invalid)` fires. This is correct behavior (you can't resolve external IDs without a tenant scope), but worth testing.
- **Subsidiary scoping in resolvers.** Several parsers wrap `UserIdentifier.get` with a `subsidiary_id` branch. The model resolver needs the same branch (or accepts a `subsidiary_external_id` virtual attr that resolves first). Decide per model.
- **GroupificationFactory restructure (row 5).** Today's `find_or_initialize_by(parser.ids)` cannot be preserved with virtual attrs — column names are required. The PR for row 5 will need a small design step before code: either resolve once in the factory and pass integer IDs to `find_or_initialize_by` (factory still does the rescue, model doesn't help), or restructure so the find-or-init lives in a model class method.

## Acceptance criteria (per PR)

For each row in the inventory:

1. Model has `before_validation :ensure_<assoc>_id_found` callback that adds `errors.add(:<assoc>_id, :not_found)` when `<assoc>_id == 0`. No `attr_accessor` for any external identifier on the consumer model. No resolver method that performs lookups.
2. Plain `validates :<assoc>_id, presence: true` (no `unless:`) where the model already required presence. Models that intentionally permit nil (Deal `client_id`, Role `parent_id`) carry the callback without the validator.
3. Controller defines a private helper `<assoc>_id_on_creation` per migrated FK. The helper returns `nil` when the client did not send the field, the resolved integer when found, and `0` on `rescue ActiveRecord::RecordNotFound`. No `&.` anywhere.
4. Cascading helpers reference earlier-level helpers by name (e.g. `user_id_on_creation` calls `subsidiary_id_on_creation`). Sentinel `0` propagates naturally — no short-circuit needed.
5. Factory parser drops its resolver method for the migrated FK. If the parser and factory wrapper have no remaining responsibilities after the migration, both classes are deleted.
6. Behavior spec in `spec/requests/api/v3/<resource>s_controller_regressions_spec.rb` (and subsidiaries equivalent) has a `context 'with unknown <assoc>_id'` block asserting (a) state preserved / no creation, (b) body equals `{ <assoc>_id: ['não encontrado'] }` (literal pt-BR string — 4Shark convention is never `I18n.t` in specs).
7. Negative test: revert the model callback; confirm the body assertion **fails** (proves the spec catches the change). Restore the fix; spec passes.
8. CHANGELOG entry under the current `## [Unreleased]` section: one bullet per migrated endpoint family (e.g., "Indicator creation with unknown user or variable").
9. Rubocop clean on every touched file.
10. PR title is the next minor version's changelog line, PR body is the changelog content.

## Companion work — upload document processors (in-rollout, blocking)

The 4Shark API has three ingestion surfaces. Only one — `/api/v3/*` — is what this rollout has been touching:

| Surface | Identifier shape | Mapping needed? | Touched by this rollout? |
|---|---|---|---|
| `/api/v3/*` (HTTP API) | client-side external IDs | yes — controller + model resolvers (this rollout) | yes |
| GraphQL (internal frontend) | internal integer IDs | no | no |
| Upload-based (Producer / Consumer documents) | client-side external IDs | yes — done in upload workers, sometimes via the same factories we're deleting | **not yet** |

Engineer note (2026-05-27): *"a gente não pode fazer merge só com isso aqui não. A gente tem que ver se tem mais algum lugar que faz esse mapeamento. […] As que não são utilizadas, elas estão fazendo o mapeamento dos IDs no próprio worker. Então a gente pode simplificar eles removendo o mapeamento do worker e passando a usar essas colunas novas que a gente tá criando aqui."*

The full rollout is **not done** until the upload side is reconciled. Concretely:

1. **Audit each upload document processor** (`app/workers/**/document_processor*`, `app/workers/**/document_consumer*`, etc. — exact locations TBD) for FK mapping logic. For each:
   - **If it uses one of the factories this rollout deletes** (Indicator/Goal/Deal so far; later UserFactory, UserIdentifierActionFactory): the upload path is broken the moment the factory is deleted. Either keep the factory alive until the upload is migrated, or migrate the upload in the same PR.
   - **If it does its own mapping in the worker** (the common case): simplify the worker to assign the `*_external_id` virtual attrs on the model and let the model resolve, instead of resolving manually in the worker. Same pattern, fewer code paths.

2. **GroupificationFactory is reused by upload** (engineer explicit). Row 5's restructure (`find_or_initialize_by(parser.ids)`) cannot break the upload path. The restructure plan must cover both the API and upload call sites.

3. **The factories deleted so far** (IndicatorFactory, GoalFactory, DealFactory) — confirm none are referenced by an upload worker. The grep audit before each delete needs to include `app/workers/`, not just controllers/specs. The deletes in PRs #5075/#5079/#5081 confirmed no controller/spec references; we have NOT confirmed worker references yet. **Verify this retroactively.**

4. **Acceptance criterion for closing the rollout**: every model migrated has been verified end-to-end against (a) the `/api/v3/*` endpoint (done per row) and (b) the matching upload document processor (this section). Until (b) is checked, the rollout is incomplete regardless of how many rows are merged.

When the rollout reaches the "validate sentinel-`0`" Future-work item, the same audit applies to upload entry points — they bypass the controller, so the sentinel never reaches the model from that path. Workers must use the same pattern (resolve to `0` on rescue, pass through `*_external_id`).

## Future work

- **Hotfix-symbol upgrade** (`:invalid` → `:not_found`). The hotfix 3.32.1 resolvers on `Deal#resolve_client_external_id`, `Deal#resolve_product_external_id`, and `Role#resolve_parent_external_id` emit `errors.add(..., :invalid)`. For cross-API consistency under the new canonical pattern, swap to `:not_found` in a follow-up PR and update `deals_controller_regressions_spec.rb` body assertions accordingly. Scope-separate from this rollout — the hotfix shipped with `:invalid` and the change is a message tweak, not a behavior fix.

- **Validate the sentinel-`0` approach end-to-end** (engineer-requested, 2026-05-27 — revisit after all endpoints in the rollout are migrated). The canonical pattern uses `0` as the sentinel returned by the controller cascade when a lookup fails — the consumer model then detects `<fk>_id == 0` in `before_validation` and adds `:not_found`. The assumption is that the model's own validations catch the sentinel **before** the save reaches the database, so `0` never gets persisted. Confirm this end-to-end:
  1. **Rails documentation pass.** Verify how Rails treats integer `0` against an `optional: true` `belongs_to` (no implicit `belongs_to` existence validator) and against a `presence: true` validator (we already know presence accepts `0` since `0.blank?` is `false`). Document the exact Rails behavior for the record.
  2. **Database constraint pass.** For each FK column in the migrated models (Deal `user_id`, `status_id`, `client_id`, `product_id`; Goal `user_id`, `group_id`, `variable_id`; Indicator `user_id`, `variable_id`; etc.), check `db/schema.rb` (or `\d <table>` in psql) for a real `FOREIGN KEY ... REFERENCES ...` constraint. Where the constraint exists, the DB itself rejects `INSERT ... user_id = 0` if no row with id 0 exists. Where it does NOT exist (rare but possible), the sentinel could leak. Build the inventory.
  3. **Real integration test.** Hit `POST /api/v3/deals` and `POST /api/v3/goals` (etc.) with `client_id: 0` directly in the payload — bypassing the cascade resolver path. The expected behavior:
     - If the model has `ensure_<fk>_id_found` covering this FK and the value 0 reaches the model, the model returns 422 with `:not_found` (good).
     - If the model does **not** cover this FK and there is a DB FK constraint, the insert fails with a Postgres error (loud but ugly — needs catch).
     - If the model does **not** cover this FK and there is **no** DB FK constraint, the row is created with `<fk>_id = 0` (silent corruption — must NOT happen).
  4. **Lockdown.** Where step (2) or (3) shows a gap, add either an `ensure_<fk>_id_found` callback or an explicit "reject 0 as FK" validation, and a permanent spec asserting the API behavior. Decide per FK.
  5. **Regression spec for the sentinel itself.** Once validated, add a permanent integration spec under `spec/requests/api/v3/` that POSTs each create endpoint with a literal `0` in each FK field and asserts the response is 422 with `:not_found` (or the equivalent guard). Files go under the `*_controller_spec.rb` (behavior) — not regression files — unless step (3) revealed a real bug (then regression).

  Do this only after all rows of the rollout are merged. Rationale: doing it now would force per-row revisits as each model changes; doing it once at the end gives a single coherent pass.

## References

- Hotfix 3.32.1 PR: https://github.com/4shark/app/pull/5073
- Memory of the originating commcenter incident: `~/.claude/memory/20260526-170000-api-deal-update-aceita-client-id-inexistente-vira-nil.md`
- Pattern primer: `app/models/deal.rb` (`attr_accessor :client_external_id` + `before_validation`), `app/controllers/api/v3/deals_controller.rb` (`deal_params_on_update` rename — only relevant when a controller is in scope; not the case for the rows in this plan), `spec/requests/api/v3/deals_controller_regressions_spec.rb` (regression shape).
- Audit grep snapshot of remaining silent-rescue spots: 23 `rescue ActiveRecord::RecordNotFound` lines in controllers/factories (re-run `grep -rn "rescue ActiveRecord::RecordNotFound" app/controllers/api/v3/ app/factories/` to refresh).
