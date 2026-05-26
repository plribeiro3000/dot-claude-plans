# Hierarchy via Seat (not via User)

A user's place in the company hierarchy is held on a separate object — Seat — not directly on User. Each User has exactly one Seat (one-to-one); each Seat has a `type` (SalesRepresentative, Manager, Director, etc.) and a `parent` pointing to another Seat (the manager's seat). The chain of command is therefore Seat → Seat → Seat → ... → root Seat, never User → User.

## Why Seat exists as a separate object

A User's identity (name, document, email) and a User's position in the company (role, manager) change on different schedules. Someone gets promoted; their identity is the same but their role and manager change. Someone changes their email; their position is unchanged. Modeling those as separate objects lets each evolve independently and keeps the historical attribution clean — the SeatHistory table records every transition of position without polluting the User record.

Modeling the manager relationship at the Seat level (rather than User → User) also makes the validation rules expressible. A "the manager must be at a higher access level than the report" rule operates on the role types of the two seats, not on properties of the underlying users. A User → User parent would force the same rule to dereference both ends to their seats on every check.

## The 10 access levels

The platform supports 10 access levels exposed via API, plus one internal-only level above them:

```
[internal] SuperAdmin       ← not creatable via API
            Admin
            President
            VicePresident
            Director
            Superintendent
            GeneralManager
            Manager
            Coordinator
            Supervisor
            SalesRepresentative
```

Each level corresponds to a Seat `type` (STI). The API accepts the 10 listed; SuperAdmin exists for 4Shark's internal operational access and cannot be assigned through the integration channel.

## Tree rules

- The first node in the tree (typically Admin) has **no parent** — it is the root
- Every other node **must have a parent** at a strictly higher access level
- **Levels can be skipped**: a SalesRepresentative reporting directly to Admin is valid; the platform supports it because real organizations look like that

The skipping rule matters more than it sounds. Many organizations have shallow trees in some branches and deep trees in others — a regional sales team with three reporting layers, an operations team with one. Forcing every level to exist would turn the model into a fiction.

## Why explicit documentation matters

Many clients struggle with the tree concept because they come from operational organizational charts (org boxes), not engineering trees. The tree model is engineering: it gives the platform a clean, recursive structure for queries like "who are this person's subordinates?" or "who reports up to this person?" without requiring per-client topology code.

Documenting it explicitly is part of the platform's onboarding cost. The integrator team and the client both need to understand that the tree is the contract — there is no escape hatch for "this person reports to two managers" or "this person has no manager but isn't the root". Either the org fits the tree, or the client redefines what a "report" means until it does.

## Consequence for the integrator

The integrator's contract with the client requires building the tree from the source data. The most common shape: the client's normalized DB has a `hierarchy` table or column listing each employee's manager identifier. The integrator translates that into Seat creation calls — User first (which creates the Seat as part of the User creation, via `seat_attributes` nested), then `parent_id` resolved by manager identifier value to the manager's Seat.

Drift in this dimension is high-cost: a circular dependency in the source data (A reports to B who reports to C who reports to A) will reject at the app boundary, but only the link that closes the cycle will fail — the first two links succeed and the tree is left half-built. Recovery requires manually breaking the cycle in the source data and replaying the integration.
