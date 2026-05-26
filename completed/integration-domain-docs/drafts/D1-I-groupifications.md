# Groupifications

A groupification is the link between a User and a Group, with an entry date and an exit date. The same User can be in N groups simultaneously (often is — a software engineer is in the "engineering" group AND the "tenured employees" group AND a project-specific group, each with its own compensation rule). A user can also leave a group and re-enter later; the platform tracks each cycle as a separate history record.

The API surface is intentionally minimal:

- `PATCH /groups/:group_id/groupifications/:id` — start the link (or restart it if a previous cycle is closed)
- `DELETE /groups/:group_id/groupifications/:id` — finish the link (set the exit date)

The `:id` in the URL is the User's identifier value, not an opaque groupification ID. The endpoint resolves to the underlying Groupification row and updates it.

There is no `POST /groupifications` create. The reason is the cycle nature: the row may already exist from a prior cycle, and the client should not need to know whether this is a first-time-ever link or a re-entry. The PATCH endpoint handles both: if no row exists, it creates one; if a row exists in inactive state (`ends_at` set), it reactivates it; if a row exists in active state, it rejects with "already active".

## Lifecycle

For a given (Group, User) pair:

- **First entry** — PATCH creates a new Groupification row with the supplied `starts_at` and a null `ends_at`, plus a new GroupificationHistory row with the same `starts_at`
- **Exit** — DELETE sets `ends_at` on the Groupification row and on the latest GroupificationHistory row
- **Re-entry** — PATCH updates the same Groupification row: clears `ends_at`, replaces `starts_at` with the new value, and creates a NEW GroupificationHistory row for the new cycle
- **Re-exit** — DELETE sets `ends_at` again, both on the Groupification (mirroring the latest cycle) and on the latest GroupificationHistory row

The Groupification row therefore holds the **current** state (active or not, current cycle's entry/exit dates), while the GroupificationHistory rows hold the **per-cycle** history. The platform consults the history for time-based queries (was this user in the group on date X?) and consults the current row for fast "is this user active in the group today?" checks.

## Chronology constraints

The platform enforces:

- For any single history record: `ends_at` must be after `starts_at`
- For consecutive cycles: the new cycle's `starts_at` must be after the previous cycle's `ends_at`

A re-entry attempt with `starts_at` earlier than the previous exit rejects. This guards against rewriting history accidentally — if the client genuinely needs to backdate a re-entry, that requires manual intervention by the 4Shark team, not an integration call.

## Why this complexity exists

A few real-world constraints drive the design:

- **Pro-rated calculations** — when a user joined the group mid-period, their commission share for that period must be pro-rated to the time spent in the group. The history records hold the dates needed for the calculation
- **Eligibility windows** — some compensation rules have backward-looking eligibility ("must have been in the group for at least 90 days before the period start"). The history walk answers that question
- **Long-running groups** — a group operating for 8 years has people who left long ago. The history must remain queryable; nothing is purged
- **Anonymized users** — a former employee whose record was anonymized still appears in the group history for traceability. The Groupification rows are not deleted when the user is anonymized

## Volumes worth knowing

Real-world examples driving the design:

- A Mexico tenant has 5,000 people in a single plan
- Call center clients see heavy churn — employees move between cells (group A → B → D), leave, come back
- A single user can be in 10+ groups simultaneously across long-running and short-running plans

The platform was built for these volumes, not retrofitted to them. The PATCH/DELETE shape (vs. a more elaborate workflow API) is part of that — minimal calls per state change, no batch wrappers, the integrator iterates one user at a time.

## Implication for the integrator

The integrator must drive groupification calls per (group, user) pair. The most common drift: the client's source data lists "current group memberships" without a history, and the integrator interprets the absence of a row as "user left the group" without a timestamp for the exit. The platform requires `ends_at` on DELETE; making it up risks chronology violations.

A robust integrator policy is to keep its own minimal record of "what was the last membership state we sent for this pair", and only emit a DELETE when the source data drops a row that was previously present. The exit date defaults to the day the change was detected, with the option for the client to override via a separate workflow.
