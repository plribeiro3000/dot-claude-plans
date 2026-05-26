# The 25-stream fixed sequence and the role of ResourceType

The integrator processes resources in a fixed order — the same order, every run, regardless of customer shape. The order is hardcoded in the workers' chain-of-references and documented in the integrator repo's `CLAUDE.md`. It is not a feature, not a configuration parameter, not something a customer can change. The order is a domain decision, and changing it requires editing the codebase.

This chapter walks through the order and the reasons behind it.

## The sequence

```
1.  Subsidiary
2.  Hierarchy           — promotion / demotion of access level
3.  User::Admin
4.  User::President
5.  User::VicePresident
6.  User::Director
7.  User::Superintendent
8.  User::GeneralManager
9.  User::Manager
10. User::Coordinator
11. User::Supervisor
12. User::SalesRepresentative
13. User::Unknown        — runtime catch-all for unknown access levels
14. ParentUpdate         — change of immediate manager
15. UserIdentifier
16. Client
17. Product
18. Group
19. Groupification
20. UserField
21. UserActivity         — user deactivation / reactivation
22. Deal                 — sale transactions
23. DealExtraField
24. Modifier
25. Goal
```

After step 25, `Job::Finisher` closes the Job and emits the integration report.

## Why this order

The order is a sequence of dependencies. Every step downstream relies on the platform-side state produced by some earlier step. Walking through them:

### Subsidiary first

Subsidiaries are containers — every User belongs to a Subsidiary, every Deal belongs to a Subsidiary, every Goal scoped to a Group lives within a Subsidiary. If the API receives a User payload referencing a Subsidiary that does not yet exist on the platform, the call fails with a missing-reference error. So Subsidiaries must already be there when Users start arriving. This is the only step with no upstream dependency.

### Hierarchy before users

Step 2, **before** any User is registered, runs Hierarchy — the access-level promotions and demotions for users **who already exist** on the platform from previous runs. The reason is subtle:

The integrator's data shape attaches every User to a parent in the access-level tree. When a sales representative gets promoted to supervisor, two things change in the customer's source: the user's `type` becomes `Supervisor`, and other sales reps now report to them as their parent. If the integrator processed Users in normal sequence (Admin → ... → SalesRepresentative) and then Hierarchy after, the new Supervisor would land on the platform first as a SalesRepresentative (because, in the user table at the moment of extract, they may still appear at the old level), then immediately as a Supervisor on the second pass. In the meantime, sales reps trying to register with the now-Supervisor as their parent would resolve to a record that hasn't been promoted yet and would be rejected.

Running Hierarchy first means: take the existing platform-side users and apply their level changes before adding any new users. The promoted Supervisor is at supervisor level by the time the user-creation phase fires; the sales reps that depend on them resolve cleanly.

This is one of the trickiest decisions in the pipeline and the one most commonly questioned during onboarding. The shape only makes sense after walking through the case where it is missing.

### Users in level order

Steps 3 through 13 run the User stream once per access level, in **descending hierarchy order** (Admin first, SalesRepresentative last). This matches the parent-child relationship: a User at level N can have a parent only at level M < N (or no parent, in the case of Admin). Processing levels top-down guarantees that whenever a User is being registered, every potential parent is already there.

A SalesRepresentative reporting directly to an Admin — skipping every intermediate level — is also valid. The constraint is "parent must be at a strictly higher level"; intermediate levels are optional. So the order is a strict topological order over the partial-ordering of allowed relationships.

### `User::Unknown` after the named levels

Step 13 is `User::Unknown` — a catch-all for User records whose `type` field does not match any of the 10 supported access levels. Typo in the source (`Manger`), wrong-language label (`Gerente` where `Manager` was expected), custom value, deprecated value — anything outside the known set lands here.

The integrator does **not** silently drop these records. Instead, every User imported in this Job whose post-mapping `data.type` is outside the 10 known set is loaded into the API anyway. The API rejects the call (the seat type is invalid), and the rejection is recorded in the audit trail. The aggregate counts include these failures; the customer-facing email lists them in the failed-imports XLSX with the unknown type and the user's identifier.

Why surface the failure instead of swallowing it: a misconfigured `type` value at the customer's source is a real onboarding bug, and the platform boundary is the right place to surface it. Hiding the rows would mean the customer thinks integration is succeeding while a portion of their workforce is silently absent from the platform. Exposing them as visible failures forces the customer to fix the source.

`User::Unknown` runs unconditionally — it is always part of the chain, not conditional on having any candidate rows. If there are no unknowns, it executes a near-empty query and advances. The chain continuity is a feature: a customer can start with a clean source where Unknown is empty and stay that way, and the pipeline shape does not change.

### `ParentUpdate` after users

Step 14 is `ParentUpdate` — the change of immediate manager for users who already exist. Same Hierarchy table on the source side, different intent: where step 2 moves users between **levels**, step 14 moves them between **managers** at the same level. A SalesRepresentative who switches teams (still a SalesRepresentative, but now reporting to Supervisor B instead of Supervisor A) is a ParentUpdate event.

ParentUpdate runs **after** users because the new parent must already exist. If the new manager was hired as part of this run (registered in steps 3-12) and a sales rep is reassigned to them in step 14, the order guarantees the manager is on the platform before the reassignment hits the API.

Hierarchy and ParentUpdate split the same source table (`hierarchy`) into two passes with different filters. Their shared structural property — being keyed by `created_at` rather than `updated_at` — is documented in Chapter 12 (the bootstrap).

### `UserIdentifier` after users

Step 15 is `UserIdentifier`. A User can have multiple identifiers (one per source system the customer uses to refer to them — payroll number, badge ID, CRM contact ID, etc.). The User itself is registered with one primary identifier in steps 3-13; the others are pushed in step 15. `UserIdentifier` runs after users for the same reason as ParentUpdate — the User must exist before secondary identifiers can be attached.

### Catalog data

Steps 16-18 — Client, Product, Group — are catalog data. They do not reference Users directly; they're independent registries. The order between them is conventional rather than dependency-driven (a Product can reference a Client; a Group is independent). They run before Groupifications because Groupifications need Groups to exist.

### `Groupification` after groups and users

Step 19 — Groupification — links Users to Groups. Both must exist on the platform before the link can be created. Groups arrive in step 18; Users arrive in steps 3-13.

### `UserField` after users

Step 20 — UserField — attaches custom key-value attributes to Users. Same dependency: User must exist first.

### `UserActivity` after users

Step 21 — UserActivity — represents user deactivation and reactivation events. Users must exist before they can be deactivated. The integrator does **not** delete users; deactivation flips an `active` flag, preserving the user record and its history. Reactivation flips it back. Chapter 13 covers the lifecycle.

### Deals and modifiers

Step 22 — Deal — is sale transactions. Dependencies: User (the seller), Client (the customer of the sale), Product (the item sold). All three are upstream. Deals are typically the highest-volume resource in the pipeline; a customer with thousands of users can produce hundreds of thousands of deals per day.

Step 23 — DealExtraField — attaches custom attributes to Deals (referenced by registered Variables on the platform). Deals must exist first.

Step 24 — Modifier — adjusts a Deal's commission calculation (typically a multiplier). Same dependency: Deals must exist before Modifiers can attach to them.

### Goals last

Step 25 — Goal — defines per-User or per-Group performance targets. Dependencies: User (for user goals), Group (for group goals), and a registered Variable (defined platform-side, never created via the integrator). Goals running last is a soft choice — they could run earlier if dependencies allow — but conventionally they sit at the end as the "rules of the game" applied on top of the actor and transaction layers.

After Goal, `Job::Finisher` closes the run.

## How the order is encoded

The sequence has no runtime representation as a list. Each per-resource worker hardcodes the **next** resource in its chain:

- `Subsidiary::ExtractorProducer` has, somewhere in its execution, a reference to `Hierarchy::ExtractorProducer.perform_async`
- `Hierarchy::ExtractorProducer` has a reference to `User::Admin::ExtractorProducer.perform_async`
- ... and so on, with each link of the chain being one method call

Adding a step in the middle of the chain means editing two workers — the previous step (to point to the new resource) and the new resource's own worker (to point to what was previously the "next"). There is no central registry to update.

This is intentional: the order **rarely** changes. When it has changed (e.g., the addition of `ParentUpdate` between Users and UserIdentifier in PR #2120), the change is small — a couple of references — and gets reviewed inline with the rest of the new resource's code.

## Why the same fixed sequence for every customer

Every customer has every resource type, even if some of them have no data. A customer that doesn't track `Modifier` events still passes through step 24 — the `Modifier::ExtractorProducer` runs, finds zero Streams enabled for Modifier (or finds streams but extracts zero rows), and advances to the next step. The pipeline shape does not depend on what the customer integrates; it depends on what 4Shark's API supports.

This makes the order a **product** decision rather than a per-customer one. If 4Shark adds a new resource type (say, Region between Subsidiary and User), it gets a fixed slot in the sequence for every customer. Per-customer variation lives at the Stream level (which Source supplies the data, which mappings reshape it), not at the order level.

## ResourceType — the layer below the sequence

Each of the 25 entries in the sequence is a `ResourceType`, a Mongoid document with a `name` (e.g. `'Manager'`, `'ParentUpdate'`, `'UserIdentifier'`) and a `resource` (the underlying Resource subclass — `'User'`, `'Hierarchy'`, `'UserIdentifier'`).

Multiple `ResourceType` rows can share the same Resource:

- The 10 user-level types (`Admin`, `President`, ..., `SalesRepresentative`) all carry `resource: 'User'` — they are the same Resource model differentiated by a `type` filter on the source query
- `ParentUpdate` carries `resource: 'Hierarchy'` — same Resource model as the `Hierarchy` ResourceType, differentiated by which subset of hierarchy events it processes

This decoupling is what lets the pipeline have 25 logical steps backed by 15 underlying Resource classes. The Stream attaches to a `ResourceType` (not directly to a `Resource`), and the worker chain advances per `ResourceType`. The `Resource` is consulted only for the model-level concerns: identifier resolution, request body construction, state transitions.

The decoupling matters operationally because new logical sequence steps can be added without new Resource classes. ParentUpdate did not need a new model — it needed a new logical step in the sequence with a different filter. Spinning up that step is "create one ResourceType row, hardcode the worker chain pointers"; no schema changes, no migration, no new classes.

## Summary

Twenty-five resource types, one fixed order, three special cases (Hierarchy first, User::Unknown unconditional, ParentUpdate after users). The order is a partial-ordering of dependencies: every downstream step relies on platform state produced by some upstream step. ResourceType is the abstraction that lets the sequence have more entries than the underlying Resource hierarchy, without inventing new model classes.
