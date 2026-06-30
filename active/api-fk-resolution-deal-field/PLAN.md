# PLAN: Migrate `DealField` FK resolution to the model (deferred)

## Status

**Deferred — 2026-05-28.** PR #5089 (`feature/api-fk-resolution-deal-field-variable`) was closed without merge because it introduces breaking API behavior changes that we don't want to ship in an unscheduled release. The branch remains as reference for the resumption.

## Context

The `api-fk-resolution-rollout` (now in `~/.claude/plans/completed/api-fk-resolution-rollout/PLAN.md`, all PRs merged as of 2026-05-28) migrated FK resolution for Indicator, Goal, Deal, Groupification, Seat, User, UserIdentifier from controller-side `rescue → nil` to model-side `before_validation` resolvers (or controller `rescue → 0` sentinel + model `*_presence` validators) — so unknown external IDs return `422 {<fk>: ['não encontrado']}` instead of confusing 404/silent success. This is the **only** outstanding item from that rollout; everything else is shipped.

`DealField` was **not** in the original rollout scope. It was discovered during PR #5088 follow-up (2026-05-28) when the engineer asked whether the same logic applies to `Api::V3::Deals::FieldsController`. The investigation found two distinct lookups in that controller:

| Lookup | Source | Today's behavior on miss | Why it's a problem |
|---|---|---|---|
| `deal_id` | URL path `/api/v3/deals/:deal_id/fields` | 404 (global `rescue ActiveRecord::RecordNotFound`) | Correct REST semantic — path resource missing |
| `variable` | Body field on create + update | 404 (same global rescue from `Variable.get_id`) | **Wrong** — path is valid, the body is wrong, should be 422 |

The intended fix is to apply the rollout pattern to `variable` (and, for full parity with `Groupification`, also reframe `deal_id` as a 422-with-error-key path).

## Why this is deferred

The cleanest implementation — full Groupification-pattern parity — changes 3 public API responses:

1. **Create `POST /api/v3/deals/:deal_id/fields` with invalid `deal_id` path**: today returns `404` with empty body. Would return `422` with `{deal_id: ['não encontrado']}`.
2. **Update `PUT /api/v3/deals/:deal_id/fields` with invalid `deal_id` path**: same flip 404 → 422.
3. **Both endpoints with invalid `variable` in body**: today returns `404` with empty body. Would return `422` with `{variable: ['não encontrado']}`.

Items 1 and 2 are **breaking** for any client that branches on HTTP status (404 vs 422). Item 3 is also breaking in shape but semantically a fix (the response was already wrong). All three need a coordinated release with prior client communication.

The engineer chose not to ship now, in an unscheduled minor, just to fix DealField — too much risk for one endpoint family.

## What was tried — PR #5089 (closed without merge)

Branch: `feature/api-fk-resolution-deal-field-variable` (remains on origin as reference).

Two approaches were explored on the branch:

### Approach 1 — Hybrid (rejected by engineer)

Migrate only `variable` to the model via `attr_accessor :variable_external_id` + `before_validation :resolve_variable_external_id`. Update controller resolves `variable_id` with `rescue → 0` sentinel and adds an inline `if zero? render json: ...; return; end` check before `DealField.get(...)`. Keep `deal_id` returning 404 unchanged.

**Engineer rejection** (verbatim): *"voce ta de piada com a minha cara? o modelo tem que fazer isso. de onde foi que voce tirou esse codigo nojento? olha todos os outros locais"*.

Rejection rationale: the inline `if zero?` + manual JSON render in the controller is divergence from the consolidated pattern (Groupification — PR #5083 — and others). The model has to do the work.

### Approach 2 — Full Groupification pattern (works but breaks API)

The final state of the branch:

- **Model `app/models/deal_field.rb`**: removed `attr_accessor` and `before_validation` resolver. Added `validate :deal_presence` and `validate :variable_presence` — each one handles `nil → :blank` and `0 → :not_found`. Model knows nothing about external IDs anymore; it just validates the integers it receives.

- **Controller `app/controllers/api/v3/deals/fields_controller.rb`**:
  - All FK resolvers as `*_on_creation` / `*_on_update` private helpers that `rescue ActiveRecord::RecordNotFound; 0`.
  - **create**: `DealField.new(deal_id: deal_id_on_creation, variable_id: variable_id_on_creation, value: ...)` — model save dispatches the validators that detect the sentinels and add `:not_found`.
  - **update**: `DealField.find_by(deal_id:, variable_id:) || DealField.new(deal_id:, variable_id:)` — when either FK is 0, `find_by` returns nil, falls into `new`, save dispatches the same validators. Replaces the previous `DealField.get(...)` which raised `RecordNotFound` and would have leaked as 404.
  - Error rekey `:variable_id → :variable` inline in both branches (consistent with `goals_controller.rb`).

- **Specs**: `#deal_presence` and `#variable_presence` describes in `spec/models/deal_field_spec.rb`; controller `'and deal is invalid'` and `'and variable is invalid'` contexts updated in `spec/requests/api/v3/deals/fields_controller_spec.rb` (both create + update) to expect 422 with the appropriate error key.

- **CHANGELOG**: "Deal field creation with unknown deal or variable" and "Deal field update with unknown deal or variable" under Unreleased / Changed.

All 42 model + controller specs green, rubocop clean. The implementation itself is correct — the blocker is the API contract change, not the code.

## API breaking changes the resumption must coordinate

| Endpoint | Scenario | Before | After |
|---|---|---|---|
| `POST /api/v3/deals/:deal_id/fields` | Invalid `deal_id` path | 404 empty body | 422 `{deal_id: ['não encontrado']}` |
| `POST /api/v3/deals/:deal_id/fields` | Invalid `variable` in body | 404 empty body | 422 `{variable: ['não encontrado']}` |
| `PUT /api/v3/deals/:deal_id/fields` | Invalid `deal_id` path | 404 empty body | 422 `{deal_id: ['não encontrado']}` |
| `PUT /api/v3/deals/:deal_id/fields` | Invalid `variable` in body | 404 empty body | 422 `{variable: ['não encontrado']}` |
| `PUT /api/v3/deals/:deal_id/fields` | Deal field combo not found (deal and variable both valid but no record) | 404 (from `DealField.get`) | Creates a new record (upsert via `find_by || new`) — semantic change |

The fifth row is subtle but important — the `find_by || new` shape that Groupification uses turns the update into an upsert. For Groupification this is intentional (and matches how `start` / `finish` work in that domain). For `DealField`, today's behavior is "PUT requires the field to already exist (created via POST first)" — turning it into upsert changes semantics for clients that relied on the 404 to detect a missing record before creating it.

A safer-but-uglier alternative for the update is: keep `DealField.get` (raising), wrap the controller action with `rescue ActiveRecord::RecordNotFound → 404`, but resolve `variable_id` (and `deal_id`) with sentinel before the `.get` call so the sentinel itself maps to a clean 404 (or 422 with key, if preferred). Doesn't match Groupification 100% but preserves "PUT does not create" semantic.

## When to revisit

Open this plan when **any** of the following applies:

- A scheduled major or minor release is being prepared that can include breaking API changes.
- A client integration that uses `/api/v3/deals/:deal_id/fields` is being updated (good moment to coordinate the response shape change with them).
- Another rollout follow-up requires reopening the DealField surface anyway — bundle this into the same PR.

Do **not** open it as a standalone hotfix or minor patch — the value (clearer error messages) does not justify the breaking surface.

## Recommended path when resuming

1. **Confirm with stakeholders** (Customer Success / integration team) that no consumer of `/api/v3/deals/:deal_id/fields` is currently branching on `404 vs 422` for this endpoint. If anyone is, schedule client-side updates before the release.

2. **Decide on update semantic** — upsert (Groupification parity, simpler code) vs preserve-PUT (no implicit create, needs slightly different shape). Both are tractable; this is a product decision.

3. **Rebase `feature/api-fk-resolution-deal-field-variable` on `develop`** and resolve any conflicts. The branch should still apply cleanly unless DealField or the controller has been touched.

4. **Reopen as a fresh PR** against the next scheduled minor's `release/X.Y.Z` branch (not against `develop` for an unscheduled merge). Link this plan + the closed PR #5089 in the description.

5. **Add explicit upgrade-notes entry** in the CHANGELOG under the release section: name the four response-shape changes (the table above) so the release reviewer sees them.

6. **Once merged**, move this directory from `~/.claude/plans/active/` to `~/.claude/plans/completed/`.

## Acceptance criteria (when resumed)

- All four behaviors in the breaking-changes table are explicitly covered by `spec/requests/api/v3/deals/fields_controller_spec.rb` with body assertions on the error key.
- `DealField` model carries `deal_presence` and `variable_presence` (or equivalent) and does not need to know about external IDs.
- Controller uses sentinel-0 helpers (`deal_id_on_creation`, `variable_id_on_creation`, `variable_id_on_update`) consistent with `groupifications_controller.rb`.
- No `if zero?` checks or manual JSON renders in the controller for FK errors — all errors come from `model.errors` with the rekey block for API attribute name mismatch.
- Rubocop clean. CHANGELOG entries under the target release.

## References

- **Closed PR**: https://github.com/4shark/app/pull/5089
- **Reference branch**: `feature/api-fk-resolution-deal-field-variable` (on origin, last commit `be5e27a28`)
- **Pattern source — Groupification PR**: https://github.com/4shark/app/pull/5083
- **Goals controller (rekey reference)**: `app/controllers/api/v3/goals_controller.rb:116-122`
- **Groupification controller (pattern reference)**: `app/controllers/api/v3/groups/groupifications_controller.rb:41-55` and `app/controllers/api/v3/subsidiaries/groups/groupifications_controller.rb:43-57`
- **Parent rollout plan**: `~/.claude/plans/active/api-fk-resolution-rollout/PLAN.md`
- **Engineer rejection of hybrid approach (2026-05-28)**: *"voce ta de piada com a minha cara? o modelo tem que fazer isso. de onde foi que voce tirou esse codigo nojento? olha todos os outros locais"*
- **Engineer deferral decision (2026-05-28)**: *"isso vai quebrar a api e nao quero me preocupar com lancar outra versao agora. crie um plano para resolvermos isso no futuro"*
