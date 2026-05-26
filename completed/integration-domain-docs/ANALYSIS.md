# API Surface Analysis — Models, Resources, and Relationships

**Date:** 2026-05-05
**Phase:** Phase 1.2 (Domain topic survey — refined to API-affected models only)
**Status:** Complete. Supersedes the lost Phase 1.1 API survey for high-level mapping (the per-endpoint detailed survey will be redone in Phase 3).

## Purpose

Inventory every model and resource that the integrator (or any external client) can affect via the app's REST API, and map their relationships. This is the foundation for Deliverables 1 and 2 of `PLAN.md` after the May 5 scope refinement: the documentation must describe the API-affected domain, not the entire app's domain.

## Method

1. Read `config/routes.rb` end-to-end (92 lines, all routes namespaced under `/api/v3/`)
2. Read every controller under `app/controllers/api/v3/` (top-level set; subsidiary-scoped variants follow the same shape with subsidiary in the path)
3. For each controller: extract the strong_params method, the model resolution calls (`*.get_id(...)`, `UserIdentifier.get(...)`), and the form/factory used
4. For each affected model: read the file, extract `belongs_to`/`has_many` and `accepts_nested_attributes_for` declarations
5. Cross-reference: for each association, check whether any API call establishes or modifies it (directly, via nested attributes, via URL path, or via payload key/value lookup)

Internal-only associations (history tables, audit rows, dataset snapshots, computation events) are excluded from the relationship map by design — they are not affected by the API.

## Resource catalog

The API exposes exactly these resources under `/api/v3/`. Each row also exists in subsidiary-scoped form under `/api/v3/subsidiaries/:subsidiary_id/...` when the company has the subsidiaries module enabled — the subsidiary-scoped variant aborts the call with HTTP 400 if used in the wrong mode (and vice-versa).

| Resource | Endpoint | Verbs | Backed by model |
|---|---|---|---|
| clients | `/clients` | create, update, activity (create/destroy) | Client |
| deals | `/deals` | create, update, activity, fields (create/update) | Deal |
| goals | `/goals` *(singular)* | create, update | Goal (STI: UserGoal, GroupGoal) |
| groups | `/groups` | create, update, destroy, activity, groupifications (update/destroy) | Group, Groupification |
| indicators | `/indicators` *(singular)* | create, update, destroy | Indicator |
| products | `/products` | create, update, activity | Product |
| roles | `/roles` | create, update, activity | Role |
| subsidiaries | `/subsidiaries` | create, update, activity, plus nested deals, goals, groups/groupifications, indicators, users | Subsidiary |
| users | `/users` | create, update, activity, plus identifiers, fields, identifier_promotions, promotions, demotions, seat | User, UserIdentifier, Field, Seat |

**Singular resources** (`goals`, `indicators`) have no URL identifier — the resource identity is composed from payload fields (Goal: `variable + user_id|group_id + starts_at + ends_at`; Indicator: `variable + user_id + compiled_at`). This is the API expression of the "no external_id for indicators" rule (Indicator has no stable client-side identifier).

**Goal STI** — `/api/v3/goals` accepts both `UserGoal` and `GroupGoal` discriminated by the `type` field in the payload. There is no separate endpoint per goal type.

## Models referenced via API but not directly managed

These models appear in API payloads or URLs but have no endpoint to create/update/delete them. The server resolves the client's payload key into the internal model row, and aborts if it does not exist.

| Model | Referenced as | Where | Resolved by |
|---|---|---|---|
| Variable | `variable` (key) | Goal create/update, Indicator create/update, DealField (Deal nested) | `Variable.get_id(company_id:, key:)` |
| Status | `status` (key, e.g. `booked`/`executed`) | Deal update | `Status.get_id(company_id:, key:)` |
| State | `state` (ISO 3166, e.g. `BR-SP`) | User create | `State.find_or_initialize_by(iso3166:)` |
| Company | implicit | every endpoint | `current_company` (from authenticated user) |

These are part of the API surface even though they have no CRUD — debugging integration issues requires understanding that, e.g., a missing Variable rejects every Goal/Indicator/DealField call that references it.

## Relationship map

Conventions:
- `→` direct foreign-key relationship on the model
- `(URL)` link established via the URL path
- `(payload-ref)` link established via a key/value the server looks up
- `(nested)` link established via `accepts_nested_attributes_for` in the parent's payload
- `(self)` self-reference

| Model | Has own endpoint | Relations established via API |
|---|---|---|
| **Client** | yes | → Company *(implicit, via `current_company`)* |
| **Deal** | yes | → Client *(payload-ref `client_id` → external_id)*<br>→ Product *(payload-ref `product_id` → external_id)*<br>→ User *(payload-ref `user_id` → identifier value via UserIdentifier)*<br>→ Status *(payload-ref `status` → key, lookup-only)*<br>→ Company *(implicit)*<br>↔ DealField *(nested `fields_attributes` on create AND update)* |
| **DealField** | no — only nested in Deal | → Deal *(parent)*<br>→ Variable *(payload-ref `variable` → key, lookup-only)* |
| **Field** *(User custom field)* | yes (`/users/:user_id/fields`) | → User *(URL)* |
| **Goal** *(STI: UserGoal/GroupGoal)* | yes *(singular)* | → User *(payload-ref `user_id` if UserGoal)*<br>→ Group *(payload-ref `group_id` if GroupGoal)*<br>→ Variable *(payload-ref `variable`)*<br>→ Company *(implicit)* |
| **Group** | yes | → Company *(implicit)* |
| **Groupification** | yes (`/groups/:group_id/groupifications/:user_id`) | → Group *(URL)*<br>→ User *(URL via UserIdentifier)* |
| **Indicator** | yes *(singular)* | → User *(payload-ref `user_id`)*<br>→ Variable *(payload-ref `variable`)*<br>→ Company *(implicit)* |
| **Product** | yes | → Company *(implicit)* |
| **Role** | yes | → Role *(self, payload-ref `parent_id` → external_id)*<br>→ Company *(implicit)* |
| **Seat** | yes (`/users/:user_id/seat`, plus promotions and demotions) | → User *(URL)*<br>→ Seat *(self, parent — payload-ref `parent_id` → identifier value of the superior user, server resolves to that user's seat)*<br>→ Role *(implicit via STI `type`; `before_validation :set_role` looks up `Role.find_by(external_id: type)`)* |
| **Subsidiary** | yes | → Company *(implicit)* |
| **User** | yes | → Company *(implicit)*<br>→ State *(payload-ref `state` → ISO 3166)*<br>→ Subsidiary *(URL in subsidiary mode; payload-ref `subsidiary_id` in root mode on create)*<br>↔ UserIdentifier *(nested `identifiers_attributes` ONLY on create)*<br>↔ Seat *(nested `seat_attributes` ONLY on create)* |
| **UserIdentifier** | yes (`/users/:user_id/identifiers`, plus identifier_promotions) | → User *(URL)*<br>→ Subsidiary *(implicit by company's subsidiaries_module setting; the field exists on the model but is set by the controller, not by the client)* |

## Cross-cutting findings

### 1. Identity translation pattern

Every controller translates client-side identifiers into 4Shark internal IDs before touching the database. Examples from the controllers read:
- `UserIdentifier.get(company_id: current_company.id, value: params[:user_id]).user_id`
- `Client.get_id(company_id: current_company.id, external_id: external_id)`
- `Variable.get_id(company_id: current_company.id, key: key)`
- `Status.get_id(company_id: current_company.id, key: key)`

The 4Shark internal ID never appears in API payloads in either direction. This is the implementation of the "ID mapping rule" that PLAN.md described abstractly.

### 2. Activity is not a model

The `activity` sub-resource on Client, Deal, Group, Product, Role, Subsidiary, User does not back any model file. Each parent has `enable` and `disable` methods that toggle two columns — `disabled_at` (timestamp) and `disabler_id` (User who disabled it). The activity controllers call those methods and nothing else. The "no-delete pattern" is implemented as columns on each parent, not as a separate Activity table.

### 3. Two field models for one concept

There are two distinct custom-field models with different contracts:

| | Field (User) | DealField (Deal) |
|---|---|---|
| Endpoint | `/users/:user_id/fields` (create + destroy) | `/deals/:deal_id/fields` (create + update); also nested in Deal |
| Payload | `{key, value}` | `{variable, value}` |
| Key resolution | free string (`key` validated only as `[a-zA-Z0-9_]*`) | server looks up Variable by key; reject if Variable does not exist |
| Type validation | none beyond presence | DealField validates `variable.deal?`, plus value format if Variable is `date?` |

Same conceptual feature ("attach extra business data to the resource"), two different design decisions. User custom fields are loose key/value pairs; Deal custom fields must reference a registered Variable.

### 4. Subsidiary mode guardrail

Every controller for a resource that exists in both root and subsidiary-scoped form starts with:

```ruby
if current_company.subsidiaries_module?
  render json: { error: 'Use subsidiary scoped api: /api/v3/subsidiaries/:subsidiary_id/...' }, status: :bad_request
  return
end
```

The subsidiary-scoped controllers do the inverse check. The client cannot accidentally use the wrong API surface — the server rejects with HTTP 400 and a message pointing to the correct path.

### 5. Three seat-change endpoints with distinct semantics

Changing a user's seat goes through one of three endpoints, each backed by a separate form object:

| Endpoint | Form object | Changes |
|---|---|---|
| `PATCH /users/:user_id/seat` | `Api::ParentSeatForm` | parent only (manager change, same role type) |
| `POST /users/:user_id/promotions` | `Api::SeatPromotionForm` | type to a higher role + parent |
| `POST /users/:user_id/demotions` | `Api::SeatDemotionForm` | type to a lower role + parent |

This is the "multiple endpoints per behavior" architectural decision (Deliverable 2 in the original PLAN.md) materialized concretely.

### 6. Singular resources

`goals` and `indicators` are declared as `resource` (singular) — there is no `:id` in the URL. Identity is a composite of payload fields. This composes naturally with the no-stable-ID nature of indicators and the user/group + variable + period composite identity of goals.

### 7. Asymmetry between create and update

This is the most operationally important finding for integration debugging:

| Resource | Create accepts nested | Update accepts nested |
|---|---|---|
| User | `identifiers_attributes`, `seat_attributes` | NONE — must use `/identifiers`, `/seat`, `/promotions`, `/demotions` separately |
| Deal | `fields_attributes` | `fields_attributes` (still nested) |

A client building an integration will have an asymmetric experience: creating a user is one fat call; updating identifiers or seat is N calls. This deserves a paragraph in the doc because it is the source of correctness bugs in the integrator.

### 8. Idempotency key on every state-changing endpoint

Every create/update/destroy in `/api/v3/` accepts `X-Idempotency-Key` and uses `cached?`/`cache(...)` helpers to short-circuit retries. Successful responses cache for 1 hour; errors do not cache. This pattern is documented further in the existing `~/.claude/plans/active/idempotency-key/` spike.

## Implications for the documentation plan

The original Deliverable 1 ("App Business Domain", topics A through G) has to be rewritten. The new chapter list, anchored on the API surface, is in the rewritten `PLAN.md`. Summary of the change:

- **Drops from D1**: Plan, Statement, Commission, Payment, Reward, Incentive, Mobile vs Web, Plan Acceptment, Plan Participation, Holding/Company hierarchy — none are in the API surface
- **Folds into new chapters**: ID mapping (A) becomes "Identity translation pattern" with concrete evidence; Activity (B) becomes "Activity is not a model"; Goal types (C) becomes "Goal — single endpoint, two STI types"; Custom fields (D) becomes "Custom fields — two models, one concept"; Groupifications (E), Role hierarchy (F), Cross-subsidiary (G) remain but are recontextualized within the API map
- **New chapters surfaced by this analysis**: Subsidiary mode guardrail, Three seat-change endpoints, Singular resources, Asymmetry create vs update, Variable as referenced-but-not-managed registry

Deliverable 2 (App API Exposure) is repositioned: instead of "how the domain is reflected through the API" (which now overlaps with D1), it covers cross-cutting API behaviors that are not per-resource — anonymization/5-year rule, idempotency, error contracts, the subsidiary mode pattern at the architectural level. See the rewritten PLAN.md.

## Open questions to verify

These came up during the analysis and should be confirmed before or during writing:

- **Subsidiary-scoped variants** — confirmed by route inspection that they exist and that root and scoped controllers each guard against the wrong mode, but I read only the root controllers in detail. Worth a spot-check on one or two subsidiary-scoped controllers (e.g., `subsidiaries/users_controller.rb`) to confirm the pattern is identical and to capture how `subsidiary_id` from the URL flows into the Identifier creation.
- **`identifiers_attributes` on User create** — only permits `value, primary`; no `subsidiary_id`. In subsidiary mode, the controller likely injects subsidiary_id from URL into each identifier's attributes. Confirm in `subsidiaries/users_controller.rb`.
- **Seat update via nested on User update** — model has `accepts_nested_attributes_for :seat, update_only: true` but the User update strong_params does NOT include `seat_attributes`. Either it is dead code in the model or there is a code path I missed. Worth confirming.
- **Activity controllers for non-User resources** — read only `users/activity_controller.rb`. Pattern is established (toggle `disabled_at`/`disabler_id` via parent's `enable`/`disable`), but sample one more (e.g., `deals/activity_controller.rb`) to be sure the pattern holds.
- **`Api::SeatPromotionForm` / `SeatDemotionForm` / `ParentSeatForm`** — read only the controllers, not the forms. The forms encapsulate the actual rules around what counts as a valid promotion/demotion (same-level moves, cross-level moves, parent-must-be-higher constraint). Worth opening when documenting Chapter "Three seat-change endpoints".
