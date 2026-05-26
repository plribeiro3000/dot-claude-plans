# Activity / no-delete pattern

4Shark is a financial platform: the historical record is part of the product. A commission paid in 2019 must remain explainable in 2026 — which Goal it was based on, which User received it, which Plan it belonged to. Deleting any of those records would break the historical chain. The platform therefore does not delete records; it deactivates them.

Every resource that supports deactivation — Client, Deal, Group, Product, Role, Subsidiary, User — exposes an `activity` sub-resource on its endpoint:

- `POST /api/v3/<resource>/:id/activity` — reactivate
- `DELETE /api/v3/<resource>/:id/activity` — deactivate

The naming is deliberate: the verb is on the activity, not on the resource. The client never deletes a Deal; it ends the Deal's activity.

## Why this is not a separate model

There is no `Activity` table. Each resource carries two columns — `disabled_at` (when) and `disabler_id` (which User did it) — that record the deactivation. The activity controllers toggle those columns through the parent's `enable` / `disable` methods. This was deliberate: a separate Activity table would have added a join to every read; carrying the state on the parent keeps reads cheap and keeps the historical attribution where it belongs (on the row that was deactivated).

The cost is that the activity history per resource is binary — there is one current state and one disabler, not a per-event log. If a Deal is deactivated, reactivated, deactivated again, the columns reflect only the most recent transition. The full per-event history lives in audit infrastructure that is not exposed via API.

## What "deactivated" means in domain terms

A deactivated record is invisible to most user-facing queries (default scopes filter it out) but remains queryable for historical purposes (commission calculation, statement generation, audit reports). Foreign keys pointing to a deactivated record are not invalidated — a Deal that referenced a deactivated Product still resolves to that Product.

This has a practical consequence for integration: the client cannot rely on "create a new resource with the same external_id as a deleted one". The original record still exists with the unique-per-company external_id constraint; the new call will fail with a uniqueness error. The correct flow is to reactivate the existing record, not to recreate it.

## Implication for the integrator contract

The integrator's contract with the real client must assume that nothing is ever truly gone. A client's normalized database might list an employee as "removed" — the integrator must translate that into a deactivation call against the existing User, not a delete-and-recreate cycle. If the client later "rehires" the same employee, the integrator must reactivate, not create a duplicate.

Drift in this dimension is one of the most common failure modes: the client's source system treats removal as absence ("the row is gone"); the integrator that does not understand the no-delete pattern translates absence into a delete attempt; the app rejects; the integration appears stuck.
