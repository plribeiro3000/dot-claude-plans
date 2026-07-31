# Auxiliary file — PostgreSQL ON CONFLICT / Read Committed / lost-update quotes

Consolidated because the spike's central risk finding (recompute-then-upsert is not
automatically race-free) depends on reading the official atomicity guarantee alongside the
general lost-update pattern together — one without the other over- or under-states the risk.

## ON CONFLICT DO UPDATE — the atomicity guarantee, and what it actually covers

Source: https://www.postgresql.org/docs/current/sql-insert.html

> "`ON CONFLICT DO UPDATE` guarantees an atomic `INSERT` or `UPDATE` outcome; provided there is no
> independent error, one of those two outcomes is guaranteed, even under high concurrency. This is
> also known as _UPSERT_ — 'UPDATE or INSERT'."

> "INSERT with an ON CONFLICT DO UPDATE clause is a 'deterministic' statement. This means that the
> command will not be allowed to affect any single existing row more than once; a cardinality
> violation error will be raised when this situation arises."

**What this guarantees**: exactly one of {insert, update} happens for the target row, and two
concurrent statements targeting the same conflicting row cannot both insert (no duplicate row, no
`RecordNotUnique`-class failure reaches the caller). **What this does NOT guarantee**: that a
*value* computed by the application (or by a subquery evaluated once at statement start) and fed
into the `DO UPDATE SET column = <value>` clause reflects everything committed by a concurrent
sibling transaction that is *also* writing that row. The atomicity is about the row mutation
itself, not about the freshness of an externally-supplied value.

## Read Committed — what gets re-evaluated when a target row is concurrently modified

Source: https://www.postgresql.org/docs/current/transaction-iso.html

> "The search condition of the command (the `WHERE` clause) is re-evaluated to see if the updated
> version of the row still matches the search condition. If so, the second updater proceeds with
> its operation using the updated version of the row."

> "`UPDATE`, `DELETE`, `SELECT FOR UPDATE`, and `SELECT FOR SHARE` commands behave the same as
> `SELECT` in terms of searching for target rows: they will only find target rows that were
> committed as of the command start time."

Read Committed re-evaluates the *target row's* qualification against its newest committed version
after a lock wait — it does not re-run an unrelated subquery against a different table (e.g., a
fresh `SUM` over `commissionings`) with a newer snapshot. A value computed once, before the
statement had to wait on a lock, is the value that gets written when the wait ends.

## The general lost-update pattern (community, corroborating source)

Source: https://oneuptime.com/blog/post/2026-01-25-postgresql-race-conditions/view

> "Both transactions read the same value, compute the same result, and the second update
> overwrites the first. This is a classic lost update problem."

> "The `FOR UPDATE` clause locks the selected rows until the transaction commits or rolls back.
> Other transactions attempting to lock the same rows will wait."

This is the shape of the risk for BE-6's materialization: two consumer jobs, each processing a
different rule bound to the same auxiliary variable in the SAME incentive stage (concrete fan-out
evidence in the SPIKE body), each independently `SELECT SUM(...)` over `commissionings`, then each
writes that computed sum to the SAME `aggregated_modifiers` row. `ON CONFLICT DO UPDATE`'s
atomicity guarantees the ROW WRITE does not corrupt or duplicate — it does not guarantee the
WINNING value is the correct, complete sum. The documented fix for this shape is application-level
locking around the read-compute-write sequence (`SELECT ... FOR UPDATE`, or a stronger isolation
level), not the choice of upsert primitive.

## Search that surfaced this consolidated view

Source: web search for `PostgreSQL "ON CONFLICT DO UPDATE" subquery race condition recompute sum
concurrent transactions lost update`, run 2026-07-30. The two sources above (oneuptime.com,
postgresql.org) were fetched directly; a third candidate (devandchill.com,
"Postgres: Building concurrently safe upsert queries") was fetched and found NOT to address this
scenario (its examples are a UUID→SERIAL-id upsert with no computed aggregate) — dropped per
citation discipline rather than stretched to fit.
