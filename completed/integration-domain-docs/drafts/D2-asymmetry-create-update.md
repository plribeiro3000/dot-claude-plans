# Asymmetry between create and update

The User and Deal endpoints accept different shapes on create vs. update. The differences are deliberate but operationally surprising — they are the source of correctness bugs in integrators that build update logic by mirroring create logic.

## The asymmetry

| Resource | Create payload | Update payload |
|---|---|---|
| User | accepts `identifiers_attributes`, `seat_attributes` nested (one fat call) | accepts neither — identifiers and seat must be modified through dedicated endpoints |
| Deal | accepts `fields_attributes` nested | accepts `fields_attributes` nested (same shape) |
| Other resources (Client, Product, Group, Role, Subsidiary, Goal, Indicator) | no nested attributes | no nested attributes |

For Deal, the nested-attribute behavior is symmetric. For User, it is not.

## Why User is asymmetric

User creation is a "first-time setup" event: the client needs to push everything about the user in one call (basic info, all known identifiers across source systems, the seat with role and parent). Forcing the client to do four sequential calls — User, then Identifier, then Identifier, then Seat — would multiply network round-trips and increase the chance of partial failure halfway through.

User updates are different. The most common updates are partial and targeted — change the email, change the manager, add a new identifier when a new source system comes online, promote an identifier when a contract changes. Each of those has its own dedicated endpoint with its own validation rules and its own audit trail. Allowing all of them to be expressed through a single fat update payload would either:

- Force the User update controller to multiplex into the dedicated controllers (re-implementing their logic) or
- Bypass the dedicated endpoints' validation rules (allowing inconsistent state)

The platform chose to keep the dedicated endpoints as the only path for those modifications, and made the User update endpoint accept only the User's own scalar fields.

This asymmetry applies specifically to the REST API. Other entry points to User modification — the GraphQL mutations and the bulk-upload workers — continue to accept `seat_attributes` through the `accepts_nested_attributes_for :seat, update_only: true` declaration on the model. The REST API's update endpoint deliberately does not opt into that path; the dedicated endpoints are the single source of truth for seat changes via integration.

## Why Deal is symmetric

Deal updates are typically full state replays: the integrator picks up a deal from the source system and pushes the current full state of it, including all custom fields. The fields are tightly coupled to the deal — a field never exists without its deal, and the integrator usually rewrites the whole field set when anything changes.

Allowing `fields_attributes` on Deal update means the integrator can do `PATCH /deals/:id` with the full new state and have the platform reconcile (create new fields, update existing fields, destroy fields no longer present via `_destroy: true`). That matches the integration shape for Deals.

## Implication for the integrator

The most common bug from this asymmetry: the integrator builds a "replay user state" routine that sends a User payload with `identifiers_attributes` to the update endpoint. The update endpoint silently ignores the nested attributes (strong_params filters them out), and the User's basic fields are updated while the identifiers remain whatever they were before the call.

The integrator must instead:

- For new identifiers: `POST /users/:user_id/identifiers`
- For removed identifiers: `DELETE /users/:user_id/identifiers/:id` (with care — primary identifiers must be promoted first)
- For seat changes: one of the three seat endpoints (`PATCH /seat`, `POST /promotions`, `POST /demotions`) depending on the kind of change
- For activity changes: `POST /activity` or `DELETE /activity`

A "replay" of user state therefore requires:
1. Fetch current state (or remember last sent state)
2. Compute the diff
3. Issue N calls to the dedicated endpoints, one per change

This is the operational reality of the User contract. Documenting it explicitly is the only way to prevent the silent-ignore bug from re-emerging in every new integrator implementation.
