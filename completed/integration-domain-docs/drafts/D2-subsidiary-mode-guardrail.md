# Subsidiary mode guardrail

The API has two parallel surfaces: a root-scoped surface (`/api/v3/users`, `/api/v3/deals`, etc.) and a subsidiary-scoped surface (`/api/v3/subsidiaries/:subsidiary_id/users`, `/api/v3/subsidiaries/:subsidiary_id/deals`, etc.). Each company is configured for exactly one of them. Calling the wrong surface returns HTTP 400 with a message pointing to the correct one.

## The two modes

A company has the **subsidiaries module** either enabled or disabled. The setting is per-company, set during onboarding, and rarely changes.

- **Disabled (root mode)** — the company operates as a single legal entity; resources live in a flat namespace; the root API is the only valid surface.
- **Enabled (subsidiary mode)** — the company is a group of legal entities (each with its own tax ID, its own register type per country); every resource that can vary per subsidiary lives under a subsidiary; the subsidiary-scoped API is the only valid surface.

The mode is not a feature flag. It changes the entire identity model. A user in subsidiary mode is identified by `(subsidiary, identifier value)` — the same identifier value can exist in two different subsidiaries and refer to two different people. In root mode, identifier values are unique per company.

Beyond identity scoping, the two modes accept slightly different payload fields. Subsidiary-mode User create accepts `external_parent_subsidiary_id` inside `seat_attributes` (the cross-subsidiary management field — see the per-resource doc); root-mode User create does not. Subsidiary-mode identifier create accepts an optional `subsidiary_id` in the payload that overrides the URL's subsidiary scope; root-mode does not. The strong_params per controller ensure each mode only accepts what is meaningful for it.

## The guardrail

Every controller for a resource that exists in both modes starts with the same shape of check: if the company is in subsidiary mode and the call hit the root API, abort; if the company is in root mode and the call hit the subsidiary-scoped API, abort. The error response is HTTP 400 with a body of the form:

```json
{ "error": "Use subsidiary scoped api: /api/v3/subsidiaries/:subsidiary_id/users" }
```

The directive in the message is intentional — the error tells the client exactly which surface to use, including the parameter shape. The client (or its integration script) can react to the mismatch with a single config change.

## Why

A misrouted call in this design would not just be "wrong"; it could create real data corruption. Inserting a user into the root namespace of a company that operates in subsidiary mode would break uniqueness invariants downstream — the next subsidiary-scoped call referencing the same identifier value would resolve to the wrong User. The platform refuses to accept the call rather than try to repair the inconsistency afterward.

The mode mismatch is the most expensive class of integration bug: it happens at write time but is not detected until read time, and by then the wrong rows are already in production. The guardrail exists because allowing the call to succeed and trying to clean it up later was tried and proven worse than a hard reject.

## Operational note for the integrator team

When configuring an integrator for a new client, the very first thing to verify is which mode the client is in, and to point the integration script at the matching API surface. This is a one-line decision in the integrator's config, but getting it wrong is unrecoverable without manual data repair. Treat the mode as a contract term, not a runtime detail.
