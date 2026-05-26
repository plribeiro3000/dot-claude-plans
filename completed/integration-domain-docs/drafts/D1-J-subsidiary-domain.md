# Subsidiary scoping and cross-subsidiary management

A company can be configured to operate as a single legal entity (root mode) or as a group of legal entities (subsidiary mode). The configuration is per-company, set during onboarding, and rarely changes. The subsidiary chapter in the cross-cutting deliverable covers the API guardrail; this chapter covers the domain reasons subsidiary mode exists and the realities it has to model.

## Why subsidiaries exist as a domain concept

Brazilian and Latin American companies of any size are typically structured as multiple legal entities — a holding plus N operating subsidiaries, each with its own tax ID and its own register type. Tax law, labor law, and union agreements all attach to the legal entity, not to the parent group. A platform that treats the company as monolithic cannot represent the basic operational fact that "this employee's contract is with subsidiary B, even though the company brand is the parent name".

Subsidiary mode lets the company configure each subsidiary independently:

- Each subsidiary has its own CNPJ (or RFC, RUT, NIT, depending on country) and register type
- User identifiers are scoped per subsidiary — the same `value` (e.g., an employee number) can refer to two different people in two different subsidiaries
- Resources that vary per subsidiary live under the subsidiary in the API path

In root mode, none of this scoping exists; the company is one namespace.

## Cross-subsidiary management

Real-world organizations have managers who supervise reports in different subsidiaries from the one they themselves are assigned to. A regional director sitting in São Paulo manages local sellers across multiple Brazilian filiais. The director belongs to the holding's subsidiary; the sellers belong to their respective state subsidiaries.

The platform represents this with a separate field on User: `external_parent_subsidiary_id`. The user's own subsidiary is determined by where the user is assigned; the field declares which subsidiary's view should treat this user as a manager-from-outside. Without this field, every report up the chain would have to assume manager-and-report share a subsidiary, and the model would not fit the org reality.

The field is accepted only in subsidiary mode (`seat_attributes` in subsidiary-scoped User create permits it; root-mode User create does not). This is consistent — root mode has no subsidiaries, so cross-subsidiary management does not apply.

A second cross-subsidiary mechanism exists at the identifier level: when adding an identifier to a user via the subsidiary-scoped endpoint, the payload may optionally include a `subsidiary_id` that overrides the URL's subsidiary scope. This supports the case where a user in subsidiary A has an identifier scoped to subsidiary B (the same person registered in two subsidiaries' source systems with different IDs). Most clients do not use this — the URL's subsidiary scope is sufficient — but the flexibility exists for the rare cases where it is needed.

## What this means for the integrator

The integrator team configures the integration once, when the client is onboarded:

- **For root-mode clients**: the integration script targets the root API; subsidiaries are not modeled
- **For subsidiary-mode clients**: the integration script targets the subsidiary-scoped API; every resource creation includes the subsidiary context (URL or, in some cases, payload)

The integrator must also know whether the client uses cross-subsidiary management. If yes, every User payload that has `external_parent_subsidiary_id` set must reach the app correctly — failure to set it strands the user under the wrong subsidiary's hierarchy view, breaking reports for the manager.

A drift specific to this dimension: a manager moves between subsidiaries (reorganization), but the integration only updates the user's own subsidiary, not the `external_parent_subsidiary_id` of the reports. The reports continue to show up under the old subsidiary's chain of command for the manager view, while the manager themselves is shown under the new subsidiary. The fix requires updating the reports' rows, which the integrator may not realize is necessary.

## Why this is in the domain doc, not the API doc

The mode mechanics (which API surface to use, how the guardrail works, what the error message looks like) are cross-cutting API behavior and live in the cross-cutting deliverable. This chapter covers the domain question: why does the platform have two modes at all? The answer is the legal-entity reality of the markets it serves. The API surface is the implementation; the two-mode domain is the reason.
