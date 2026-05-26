# Resource integration_status lifecycle

A Resource on the integrator side is a long-lived document. It is created the first time the integrator sees the customer-side identifier, it accumulates Imports across every Job that touches it, and it is **never deleted** — only transitioned through states that capture what the platform thinks of it. The state machine has five values and a fixed set of transitions, modeled on `Resource#integration_status` via the `state_machines` gem.

## The five states

```
unknown    — initial seed before the first run touched it (legacy / restored)
pending    — created or restored, awaiting first successful integration
integrated — successfully pushed to the 4Shark API; the platform knows about it
disabled   — deactivated on the platform; not deleted
erased     — anonymized on the platform per the retention policy
```

`pending` is the default for a freshly created Resource. `unknown` exists for legacy reasons (Resources restored from S3 without a known platform-side state). The other three are the operational ones.

## The transitions

```
pending     → integrated   (event: integrate)
pending     → disabled     (event: disable)
integrated  → disabled     (event: disable)
integrated  → erased       (event: erase)
integrated  → integrated   (event: enable, re-affirms)
disabled    → integrated   (event: enable)
disabled    → disabled     (event: disable, idempotent)
erased      → integrated   (event: integrate, re-integration path)
```

The events `integrate`, `disable`, `enable`, `erase` correspond to the four kinds of API call the integrator makes for a given Resource. Each transition is fired by the Loader Consumer when the API responds successfully — the platform's response is what authoritatively flips the Resource's state on the integrator side.

## Why the Resource is never deleted

The most surprising property of the model is the absence of a `destroy` or `delete` event. A user who left the company three years ago is still in the integrator's MongoDB; a deal that was reversed is still there; a subsidiary that was closed is still there. The reasons are layered:

- **Audit.** The integrator's MongoDB **is** the audit log. Deleting a Resource would erase the trail of every integration that ever pushed a record about it. A customer asking "why did this user have a commission for this period in 2022?" would have no answer if the user had been deleted in the meantime.
- **Re-emergence.** Customers reactivate users routinely — a deactivated employee gets rehired, a disabled product gets relaunched, a closed subsidiary reopens. If the Resource were gone, the integrator would create a new one with the same external_id, losing continuity. Keeping the document and flipping its state preserves the continuity.
- **Anonymization is reversible-style, not deletion.** Brazilian labor law (the regulatory context the platform was designed against) requires keeping certain employee records for 5 years after termination, then anonymizing them. The platform models this as the `erased` state — the data is anonymized in place, but the record itself remains. The integrator mirrors this: an `erased` Resource still exists; its Imports are still there; the personal fields have been blanked. Deleting the Resource entirely would violate the retention rule by removing the record before the legal window closes.

## `pending → integrated` — the happy path

A new external_id arrives in the source. The integrator extracts it, transforms it into an API payload, and pushes a `POST` (or `PUT`) to the API. The API responds 2xx; the Loader Consumer fires the `integrate` event; the Resource transitions to `integrated`.

This is the path most Resources take on their first appearance. After this transition, the Resource is "live" on the platform — the customer's mobile/web app reflects it.

## `pending → disabled` — created already inactive

The customer's source occasionally emits a record that is already inactive at first sight. A user who was hired and then immediately deactivated within the same ETL window; a deal that was created and reversed before the integrator's next run picked it up. The integrator pushes the create call, then immediately pushes the deactivate call, and the Resource ends up at `disabled` without ever being `integrated`.

The state machine allows this — `pending → disabled` is a direct transition. There is no intermediate "must integrate first" requirement. This matches the customer's source: the row exists, the row is inactive, the integrator's job is to reflect both facts.

## `integrated → disabled` — the typical lifecycle

The most common transition. A user works for the company for a year, then leaves; the customer's source updates `users.active = false` (or moves the row to a `disabled_users` table, or whatever the customer's deactivation pattern is). The integrator picks up the change, fires the `disable` event, and the Resource transitions to `disabled`.

`disable` is idempotent — `disabled → disabled` is allowed. Re-disabling a Resource that is already disabled is a no-op on the platform side (the API absorbs the redundant call) and a no-op on the integrator side (the state machine accepts the transition without complaint). This matters because the integrator's source often re-emits "user is inactive" rows on every run; the integrator would push redundant calls if it tried to detect "already disabled" client-side.

## `disabled → integrated` — reactivation

A user comes back. The customer's source flips `users.active = true`; the integrator picks it up, fires the `enable` event, and the Resource transitions back to `integrated`. The platform reactivates the user; their historical commissions, goals, and identifiers are preserved.

The cycle disable/enable can repeat any number of times. Each transition fires its own API call, which the audit trail records.

## `integrated → erased` — anonymization

After the legal retention window expires (5 years + 1 month buffer in the Brazilian context, configurable on the platform), the platform anonymizes the user — removing the personal data while keeping the record itself. The integrator's `erase` event corresponds to this.

The trigger for `erase` is **not** the customer's source — the customer doesn't send "anonymize this user" rows. The platform initiates the anonymization on its own schedule and the integrator's role is just to keep its local Resource state in sync. In practice, the integrator detects via reconciliation queries that the platform now returns the user as anonymized and fires the `erase` event to mirror the state.

## `erased → integrated` — re-integration

A user who was anonymized comes back as a new hire. The customer's source emits a record with the same external_id (the legal retention window is over; the identifier can be reused). The integrator's existing Resource is in `erased` state; the `integrate` event accepts both `pending` and `erased` as valid sources, so the transition fires and the Resource returns to `integrated`.

This path is rare but real. The state machine accepts it explicitly via the `transition erased: :integrated` rule.

## Why no `unknown → *`

The `unknown` state has no outbound transitions in the standard machine. It is a terminal/quarantine state for Resources that landed in MongoDB without enough information to start the lifecycle — typically S3-restored Resources whose state was lost in some historical incident. Operational practice is to fix these by hand (set the state manually based on what the platform shows) rather than to model an automatic exit.

## Why this state machine, not a column

A simpler design would be a single `active` boolean on the Resource, flipping per the source's signal. The state machine adds the `pending`, `erased`, and `unknown` states, which a boolean cannot represent. The trade-offs:

- **`pending` matters because it is the gap between create and first successful integration.** A Resource that exists in MongoDB but failed to integrate (API rejected the call, network outage, retry exhausted) is `pending` — different from `disabled` (a successful deactivation) and different from `integrated` (a successful activation). Reports distinguish these meaningfully.
- **`erased` matters because the data is gone but the record remains.** An anonymized Resource has no personal data to push to the API; pushing the same data again would be re-identification. The state machine prevents that by gating the `disable` and `update` paths on the current state.
- **`unknown` is rare but has saved real onboardings** — a Resource that ended up in MongoDB through a manual import (the rare case where customer data was loaded from a CSV by a 4Shark engineer) starts in `unknown` until the next regular Job confirms what the platform sees.

The `state_machines` gem is overkill for two states; for five with constrained transitions, it earns its weight by enforcing the constraints in one place.

## What triggers each transition, in summary

```
integrate    triggered by   POST/PUT 2xx response                        from   pending or erased
disable      triggered by   DELETE/deactivate 2xx response               from   pending, integrated, or disabled (idempotent)
enable       triggered by   reactivate 2xx response                      from   integrated or disabled
erase        triggered by   platform-initiated anonymization detection   from   integrated only
```

The events are the verbs of the integrator's API contract; the states are the platform's view of the entity, mirrored on the integrator's side.

## Summary

Five states, eight allowed transitions, no deletion. The Resource document is the integrator's audit-trail anchor and the platform's lifecycle mirror. Disable is idempotent. Reactivation works. Anonymization is a state, not a deletion. The state machine enforces every constraint in one place, which is what makes the customer-facing report "X users disabled, Y reactivated, Z anonymized" trivially queryable.

This closes the integrator domain documentation. The thirteen chapters together describe what the integrator is, why it exists, how it is deployed, how it runs, what it reads from, what it writes to, how it transforms data, how it stores history, how it coordinates parallelism, how it self-checks, how it bootstraps, and how it tracks the records it pushes. Chapter 1 framed the persona and the contract; Chapter 13 closes the loop on what happens to a customer's record over its multi-year lifetime in the platform. Anything not covered here is either out of scope for this document (the 4Shark API itself, infrastructure provisioning details) or implementation-level detail that would not survive a refactor.
