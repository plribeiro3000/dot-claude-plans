# Multi-identifier User + identifier promotion

A User can have one or more `UserIdentifier` rows. Each row has a `value` — the string the client uses to refer to the user — and a `primary` flag. Exactly one identifier per user is `primary: true`; the rest are secondary.

The primary identifier is the one referenced when other resources point at the user — a `Deal` payload's `user_id`, a `Goal` payload's `user_id`, a `Groupification` URL's `:id` — any of those resolve through `UserIdentifier.get(value).user`, regardless of whether the value matches a primary or a secondary identifier. The primary flag matters for outgoing references (when the platform serializes a user, the primary value is what appears) and for guarantees (the database enforces "exactly one primary per user" via a partial unique index).

## Why multiple identifiers

The need is the same as in the identity translation chapter: clients with multiple source systems have the same person enrolled with different IDs in each system. A call center with three CRMs has the same employee in all three under different IDs. Forcing the client to pick one and discard the others would break the integration with the systems that don't match.

Each identifier in the platform corresponds to one source system. The integration script generates the identifier values by prefixing the source system's ID (for example `intern-EMP-001`, `a1-EMP-001`, `a2-EMP-001` from the recommended pattern). The User is created once with all known identifiers; subsequent integration calls from any of those source systems resolve to the same User.

## Creation flow

Identifiers are nested in the User create payload via `identifiers_attributes`. A typical create looks like:

```json
{
  "user": {
    "first_name": "Maria",
    "last_name": "Silva",
    "identifiers_attributes": [
      {"value": "intern-EMP-001", "primary": true},
      {"value": "a1-EMP-001"},
      {"value": "a2-EMP-001"}
    ]
  }
}
```

If `primary` is omitted on an identifier, the controller defaults it to `true`. The strong_params validation then rejects payloads with more than one primary, deferring to the database's partial unique index.

## Adding identifiers after creation

The User update endpoint does NOT accept `identifiers_attributes`. To add or remove an identifier post-creation, the client must call the dedicated endpoints:

- `POST /users/:user_id/identifiers` — add a new identifier (defaults to non-primary)
- `DELETE /users/:user_id/identifiers/:id` — remove an identifier (refuses if the identifier is primary; the client must promote a different identifier first)

This is part of the broader create-vs-update asymmetry covered in the cross-cutting deliverable.

## Promotion — flipping which is primary

`POST /users/:user_id/identifier_promotions` with body `{"identifier": {"value": "a2-EMP-001"}}` flips the primary flag: the identifier matching the supplied value becomes primary, and the previously-primary identifier becomes secondary. The transaction sets all of the user's identifiers to non-primary first, then promotes the target — guaranteeing the unique-primary invariant holds throughout.

The reason this is a separate endpoint is that promoting an identifier is a deliberate business event, not a field update. It typically happens because of a contract change (the client now wants the platform to display a different ID by default) or because of a system migration (CRM A1 retired, the client wants A2's identifier promoted to primary). Either way, it deserves its own audit trail and its own integration call.

## Implication for the integrator

The integrator's contract with the client must include a "primary identifier policy" — given multiple identifiers, which one should be primary. Common policies:

- **First system wins** — the integrator picks one source system as the primary feed; that system's identifier is always primary
- **Contract-driven** — the client tells the integrator team which system's identifier should be primary at any given time; promotion is triggered manually when the policy changes

A drift to watch for: the client adds a new source system mid-stream and the integrator starts pushing identifiers from it without explicit guidance on whether to promote. Without a policy, the new identifier is added as secondary by default — usually correct, but sometimes the client expected the new system to take over as primary and the discrepancy is only noticed when reports show the wrong identifier.
