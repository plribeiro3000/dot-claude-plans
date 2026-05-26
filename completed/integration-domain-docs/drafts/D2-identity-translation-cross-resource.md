# Identity translation pattern (cross-cutting view)

The chapter on identity translation in the per-resource document explains why the platform translates client identifiers to internal IDs. This section covers the pattern itself: how the translation is implemented at the controller boundary, how it fails, and what the integrator can rely on across every endpoint.

## The pattern

Every controller in `/api/v3/` that references a foreign key has the same shape:

1. Accept the client-supplied identifier in the strong_params (`client_id`, `product_id`, `user_id`, `variable`, `parent_id` — names vary but always the client's value)
2. Resolve the identifier to the internal database ID via a helper (`Client.get_id`, `Product.get_id`, `Variable.get_id`, `UserIdentifier.get(...).user_id`)
3. Substitute the resolved ID into the parameters before passing them to the model/factory/form

The substitution is intentional: from the model's perspective, the client supplied `client_id: 42` (the internal ID); the model never sees the original `client_id: "CLI-001"` string. This keeps the model layer ignorant of the API contract — the model knows only about internal IDs and the controllers handle the translation.

## What the integrator can rely on

- **Every reference is by key**. There is no endpoint that accepts an internal numeric ID. If the client doesn't have a value to send, the call cannot succeed; there is no fallback path.
- **The translation is consistent**. The same value sent twice resolves to the same internal ID — the lookup is deterministic and side-effect-free.
- **Unknown values fail early**. If any client-supplied identifier doesn't resolve, the call rejects before any state is mutated. There is no partial-write scenario where some references resolved and others didn't.

## How translations fail

The pattern catches `ActiveRecord::RecordNotFound` and returns nil. The nil flows into the strong_params, where the model validation rejects it with a presence error on the (now resolved) foreign key column.

The visible behavior:

- The HTTP response is 422 with a validation error
- The error field name is the **resolved column** (e.g., `product_id`), not the **payload key** (which was also `product_id` in this case but might be `variable` resolving to `variable_id`, or `user_id` resolving to `user_id` via UserIdentifier)
- The error message is the standard "can't be blank" Rails-style message

For the integrator team, this means a 422 with a `<resource>_id can't be blank` is almost always an unknown identifier, not actually a missing field. The integration log should distinguish:

- "client sent no value" (true blank — bug in integration)
- "client sent a value the server doesn't know" (translation failure — usually the resource was deactivated, deleted, or never created)

## Edge case — UserIdentifier resolution returns the User, not just the ID

For most lookups, the helper returns the internal ID directly. For `user_id` payload values, the lookup is `UserIdentifier.get(value).user_id` — it returns the user_id of whichever User owns the identifier, regardless of whether the supplied identifier is primary or secondary.

This is the integration-side mechanism that makes the multi-identifier User design work: any of the user's identifiers, not just the primary, can be used in any User-referencing payload. The client's source system can vary which identifier it emits, and the platform resolves them all to the same User.

## Cross-cutting reliability

Because the pattern is uniform, the integrator can build error handling once:

- catch 422s
- inspect the error fields
- if a field is a resolved foreign key column AND the original payload had a non-empty value for the corresponding payload key, treat it as a translation failure (unknown identifier)
- raise an alert with the offending key, the value sent, and the resource type

This kind of generic handling is much harder when the pattern is inconsistent — but in 4Shark's API, it is consistent across all endpoints under `/api/v3/`.
