# SPIKE — Tenant-scoped GraphQL argument DSL

> Status: **DEFERRED / parked** — draft for engineer review (rascunho de entendimento).
> No code written. Not being worked on now.
> Date: 2026-05-29

## Status & boundary (read first)

- **This SPIKE is NOT the fix for the recurring production error.** The recurring
  `PG::ForeignKeyViolation` on `groupifications.group_id = 0` is **already fixed on
  `develop`** (model-layer zero-sentinel: `group_presence` / `user_presence`). The only
  action item for *that* error is to ship `develop` to production (mind the Sidekiq queue
  depth before deploy). Nothing in this document blocks that.
- **This SPIKE covers a separate, deferred, low-urgency hardening:** the cross-tenant /
  IDOR gap where a valid id belonging to *another account* is accepted. It is reachable
  **only** via the UI/GraphQL surface and **only via a hand-forged request** — a normal UI
  user never holds a foreign id. It has **never been observed in 10 years**. API and upload
  are already safe (company-scoped `Group.get_id` mapping).
- **Decision taken in session:** do not work on this now. Capture the plan, close the
  session. Resume when prioritized. The two load-bearing open questions (open details #1
  tenant-path mapping, #2/#3 nil-vs-0 semantics) must be answered before any implementation.

## Question

Can we move the "coerce a cross-tenant / non-existent reference id → `0`" guard
into the **GraphQL argument layer** as a DSL, and force every future reference
argument to be classified explicitly (reference vs plain value)?

## Context — why this layer

- Recurring production error: `PG::ForeignKeyViolation` on `groupifications.group_id = 0`.
  Already fixed at the **model** layer on `develop` (zero-sentinel: `group_presence` /
  `user_presence` reject `0` with `:not_found` before the INSERT).
- Remaining gap: a **valid id belonging to another account** (cross-tenant / IDOR).
  Reachable **only** via the UI/GraphQL surface, and **only via a hand-forged request** —
  the UI populates selects from company-scoped queries, so a normal user never holds a
  foreign id.
- The API and upload paths are already safe: both map external→internal through
  `Group.get_id(company_id:, external_id:)` (`group_documents` consumer `consumer.rb:76-80`;
  `Api::V3::Groups::GroupificationsController:119`). Worst case there is `0`, already handled.
- **Do NOT put the check in the model** — the model is shared by API + upload + GraphQL.
  A tenant check in the model would add cost/complexity to API + upload, which do not
  need it. The guard belongs at the GraphQL boundary, which is the only exposed surface.
- Scale: **51 of 196** mutations declare at least one client-passed `argument :*_id, ID`;
  ~28 distinct reference types (`user_id`×10, `plan_id`/`period_id`/`group_id`×7, …).
  Hand-coding each is the wrong size → favors a DSL.

## Mechanism (verified against graphql-2.6.2)

- `Schema::Argument#prepare_value` calls a `prepare:` **proc** as
  `prepare.call(value, context)` — `argument.rb:259-260`:
  ```ruby
  elsif @prepare.respond_to?(:call)
    @prepare.call(value, context || obj.context)
  ```
- The GraphQL `context` carries `current_company` — set in `graphql_controller.rb:55`
  (`current_company: current_user.company`).
- `prepare` runs inside `coerce_arguments`, **before** `execute`. The coerced value then
  flows into the mutation's `@params` (built in `ApplicationMutation#resolve`), so any
  downstream `params.permit(:group_id)` already sees the coerced value. **No mutation body
  change is required** — only the argument declaration.
- `argument` is a plain, overridable class method — `has_arguments.rb:39`.
- The gem **already** infers an association name from the `_id` / `_ids` suffix for its
  built-in `loads:` feature — `has_arguments.rb:44-55`. Precedent for name-based inference.

## Proposed shape

Two class-level DSLs on `ApplicationMutation`, and **ban bare `argument`**:

- `single_argument :starts_at, String, required: false`
  — identical to today's `argument`. No checking. For plain scalar values.
- `reference_argument :group_id, ID, scope: Group` (final name TBD — e.g. `complex_argument`)
  — declares the argument **and** registers a `prepare:` proc that:
  1. value blank → leave as-is (`nil` → model `:blank`);
  2. else `context[:current_company].<association>.exists?(id: value)` is false → coerce to `0`;
  3. else keep the value.
- Override `argument` to **raise** in `ApplicationMutation`. Every new parameter is then
  forced through a deliberate choice: "is this a tenant-scoped reference (`reference_argument`)
  or a plain value (`single_argument`)?" This is the progressive-hardening forcing function —
  the engineer cannot accidentally add an unchecked reference id.

### Coercion reuses the existing model sentinel

Coerce to `0`, do **not** raise in the DSL. The model's existing `group_presence` /
`user_presence` (already on `develop`) turns `0` → `:not_found`. The DSL only **normalizes**;
the model remains the single source of the structured error. API + upload never reach the
mutation layer, so they are untouched.

## Open details — need decisions / further investigation

1. **model → company association mapping.** `scope: Group` → `current_company.groups`.
   Derive via `model_name.plural`, or require an explicit `:scope` / `:via`?
   **Not every reference is a direct `Company has_many`.** `variable_id`, `period_id`,
   `plan_id`, `status_id`, `seat_parent_id`, `parent_id`, etc. may be scoped *through*
   another resource, not through company directly. **This is unverified** — each of the
   ~28 reference types needs its tenant path confirmed before the full rollout.
2. **column.** Most references are by pk (`id`). Some are not obvious (`seat_parent_id` → User
   by id; `parent_id` → ?). Default to `id`, allow override per reference.
3. **nil vs 0.** Keep the distinction (`nil` = not provided → `:blank`; `0` = provided-but-invalid
   → `:not_found`)? Or collapse both to `0`? Affects error messages clients already see.
4. **value type / arrays.** `ID` arrives as a string; `exists?(id: "5")` is fine (PG casts).
   `*_ids` array arguments (batch mutations) are a separate shape — out of scope for the pilot.
5. **execution timing.** When `prepare` is a Symbol and `obj` is nil during variable pre-build,
   the gem defers (`argument.rb:245-250`). With a **proc** it uses `context || obj.context` —
   confirm `context` is non-nil for our mutations in both inline-arg and variable paths.
6. **banning `argument`.** Implement by aliasing the gem's `argument` and overriding to raise;
   `single_argument` / `reference_argument` call the alias. **Scope the ban to
   `ApplicationMutation` only** — not queries/types/other GraphQL members.

## Native alternative considered and rejected

graphql-ruby's `loads:` auto-loads the referenced object and supports scoping, but it
**replaces the id with an object** and raises/null on not-found — it does not fit the
"keep the id, coerce to `0`, reuse the model sentinel" approach. Rejected for this design.

## Rollout sizing

- **Pilot:** groupification — 2 mutations (`start`, `finish`) sharing one `groupification_ids`;
  references `group_id` + `user_id`, both direct `Company has_many`. Hotfix-sized.
- **Full:** 51 mutations / ~28 reference types, after the DSL **and** the per-reference
  tenant-path table are settled. Mirror the zero-sentinel rollout cadence (model fix first,
  then migrate the codebase incrementally).

## Next steps

1. Engineer confirms the DSL shape (two methods + ban `argument`) and the names.
2. Decide open details 1–6 above (1 and 5 are the load-bearing ones).
3. Build the pilot on groupification, establish the pattern + tests.
4. Only then plan the 51-mutation migration, with the verified per-reference tenant-path table.
