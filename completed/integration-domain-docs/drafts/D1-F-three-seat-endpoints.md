# Three seat-change endpoints

A user's seat — their position in the company hierarchy: role + manager — can change in three ways, each with its own endpoint:

| Endpoint | Method | Changes |
|---|---|---|
| `/users/:user_id/seat` | PATCH | manager only (role unchanged) |
| `/users/:user_id/promotions` | POST | role moves up the hierarchy + new manager |
| `/users/:user_id/demotions` | POST | role moves down the hierarchy + new manager |

This is the platform's most visible application of "one endpoint per behavior, not one endpoint with a 'what changed?' body". Each transition has different invariants, and trying to express all three through a single update endpoint would force the validation logic onto the client.

## Why three and not one

A "promotion" is not a "manager change with a side effect of role change". It is a distinct business event with its own rules:

- **Promotion** — the new role must be higher in the seat hierarchy than the current role; the new manager must hold a role higher than the new role
- **Demotion** — the new role must be lower than the current role; the new manager must still hold a role higher than the new role
- **Seat update** (manager change) — the role does not change; the new manager must hold a role higher than the user's current role

A single "PATCH /seat" with role and parent in the body would have to detect whether the change is up, down, or sideways; apply the right invariant; produce the right error message; emit the right history record. Splitting the endpoint puts each rule in its own form object and gives the client a clear, single-purpose contract per call.

## Why this is domain, not API design

The three endpoints reflect a real distinction in how companies talk about these events. A promotion is announced; a manager change is a routine reorganization. The platform mirrors that distinction at the integration boundary so that automation built around it (notifications, audits, analytics) can hook into the right event without inferring intent from a generic update.

It also gives the client a contract that fails loudly when the client's intent is mismatched. An attempt to "promote" a user to a lower role rejects with a clear error pointing at the mismatch. Through a single update endpoint, the same call would either silently succeed (changing the role downward without the system understanding it as a demotion) or fail with a generic invariant violation that does not name the intent.

## Operational notes

All three endpoints write to the same Seat record — there is one Seat per User. Promotion and demotion replace the role and the parent; seat update replaces only the parent. Each transition writes a new SeatHistory row, with the previous transition's row receiving an `ends_at` and the new row a `starts_at` (the `date` field in the payload).

The `parent_id` in all three payloads is the `value` of one of the new manager's identifiers — the controller resolves it to the manager's User, then to that User's Seat. The hierarchy is maintained at the Seat level: User → Seat → parent Seat → ... → root Seat. The chain of command is never a User → User chain.

## Constraints worth knowing

A few rules apply across all three endpoints:

- **Date chronology** — the `date` in the payload must be strictly after the previous SeatHistory row's `starts_at`. Backdating a transition before the most recent change is rejected. If the client genuinely needs to backdate, that requires manual intervention by the 4Shark team.
- **Concurrent-modification safety** — each transition takes a database lock on the Seat row before reading its histories, preventing race conditions when two integration calls touch the same user simultaneously.
- **No-op rejection** (seat update only) — the ParentSeatForm rejects with `same_parent` if the supplied `parent_id` resolves to the user's current parent. This catches accidental retries that would otherwise write a meaningless history entry.
- **Demotion guardrail** (demotion only) — the new lower role must still be at a strictly higher level than the highest-ranked subordinate the user currently has. Demoting a Director to Coordinator while the Director has Manager-level reports would create an inverted hierarchy locally; the platform rejects with `conflicted`. The integrator must reorganize the subordinates first.

These constraints exist because the hierarchy is the foundation of every commission calculation — an inverted or temporally-inconsistent hierarchy would compute the wrong rules for the wrong people.
