# Singular resources

Two of the API's resources are declared as singular — there is no `:id` segment in their URL:

- `/api/v3/goals` — create, update (no path identifier)
- `/api/v3/indicators` — create, update, destroy (no path identifier)

Identity is recovered from the payload itself:

- **Goal** — `(variable, user_id or group_id, starts_at, ends_at)` together identify the row
- **Indicator** — `(variable, user_id, compiled_at)` together identify the row

Sending the same composite twice updates the existing row instead of creating a duplicate.

## Why singular

For Indicator, the answer is the deeper one: the client does not have a stable ID for it. Indicator data often comes from spreadsheets where rows do not have persistent identifiers — a row's position is not its identity, and the same business value reappears in different positions on different exports. The platform refuses to ask the client for an identifier the client cannot reliably produce. Identity is reconstructed from the data itself: who is the indicator for, what does it measure, when was it measured.

For Goal, the answer is composite identity. A goal is identified by what it targets, who it applies to, and when it is in effect. Adding a separate `external_id` would create a second identity that the client has to invent, store, and reconcile against the composite. The platform skips the redundancy: the composite IS the identity, and the URL reflects that.

## Consequence for the API contract

Singular resources have no `GET /api/v3/goals/:id` — there is no way to look up a specific goal by an opaque ID. Clients that need to inspect a goal must either remember the composite they used to create it, or hold their own reference to it through other channels. In practice, the integrator does not look up goals; it pushes them and trusts the composite uniqueness.

This is a deliberate trade-off: the platform optimizes for the integration scenario (push state, the server figures out whether it is new or an update) at the cost of inspection ergonomics. Inspection happens through other means (web UI, support queries, direct database access for the 4Shark team).

## Implication for retries and idempotency

Singular resources combine cleanly with the platform's idempotency-key behavior: a retry of a singular create with the same composite is a no-op — the existing row is found and updated to the same state, and if the value is unchanged, the response is cached. The composite uniqueness guarantees that retries cannot create duplicates regardless of whether the idempotency key was preserved correctly.

This makes singular resources the safest endpoints to retry from the integrator side. A Deal endpoint with a unique `external_id` has the same property; a singular Goal/Indicator achieves it without the client having to invent and track an identifier.
