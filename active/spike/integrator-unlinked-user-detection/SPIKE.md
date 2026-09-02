# SPIKE — Recurring detection of unlinked / stuck-pending users (integrator ↔ app)

## Question

The Atento MX reingresos incident surfaced a class of users that the integration cannot
reactivate on its own. We can identify a specific reported batch by hand, but we need a
**repeatable, mostly-automatic way to find ALL cases of this class** — across clients — and run
it periodically, so the divergence is surfaced before a customer reports it.

Scope is **detection**, not automatic correction (correction is the Scenario A reconciliation,
kept out of scope for now by decision).

## Confirmed root cause (from the Atento MX / company 1318 investigation)

The users that fail to reactivate were created on the app through a channel other than the
normalized integrator, then terminated **before** the Simplex integration was activated, so the
migration never linked them. When rehired, they re-enter Simplex and the integrator cannot adopt
them.

Evidence (43 reported users, company 1318, `integrator-atento-mx` / `atento-001`):

- **40 users**: integrator Resource `integration_status = pending`, `imports_count` 1–3 (the
  integrator retries the create every run and it fails every time). They exist in `fsk_users`
  (matched by RFC) but the app user has **no `4sk_<fsk_id>` identifier** — only the manual
  payroll-number primary identifier.
- **2 users**: correctly `integrated` (have the `4sk_` link) — a smaller state divergence
  (integrator `integrated`, app was `disabled`).
- **1 user**: absent from `fsk_users` entirely (Simplex/MIS never loaded them).

Timing (decisive):

- Simplex activation / mass migration = **June 2026** (9,908 rows created in `fsk_users` and as
  integrator Resources in `2026-06`; then only monthly increments: 377 Jul, 372 Aug, 31 Sep).
- The 40 pending users were **created on the app 2024-09 → 2026-02** (manual era) and
  **terminated 2025-12 → 2026-05 — all before June 2026** (40/40, zero after).
- They entered `fsk_users` only **Jul–Sep 2026** (after activation, on rehire).

So: created manually → terminated → Simplex activated while they were already disabled → excluded
from the active migration set → no `4sk_` link → rehired → integrator's create conflicts → stuck
`pending`.

## Why the integration cannot self-heal these

- Reactivation and every post-create operation for a User go through the **PUT URL keyed by
  `4sk_<external_id>`**, which requires the `4sk_` `UserIdentifier` to already exist on the app
  (`integrator/docs/architecture/INTEGRATOR_DOMAIN.md`, ch. 13 — "the PUT URL uses the API
  identifier `4sk_<external_id>` ... can only succeed if the corresponding UserIdentifier already
  exists on the app side").
- That identifier is created by the initial POST — which fails, because the app already has the
  user under the payroll identifier. The app rejects the duplicate on `unique_register_id`
  (`app/models/user.rb:249` — `rescue_unique_constraint index: :user_encrypted_unique_register_id_index,
  field: :unique_register_id`), returning 422.
- The Resource therefore stays `pending` forever; the reactivation never has an address to target.
- Secondary: the Atento MX normalized base has **no `FSK_USER_ACTIVITIES` table** (the
  `normalized:user_activity` audit failed with `Invalid object name 'FSK_USER_ACTIVITIES'`), so
  the `UserActivity` stream (ch. 21) has no source for this client — activation/deactivation does
  not flow through the integrator here at all.

## Key reframe for automation — the signal already exists

We do **not** need the manual three-store join (app identifiers + integrator Mongo + normalized
`fsk_users`) on every run. The gap has a **self-contained signature inside the integrator's own
MongoDB audit trail**:

> a `User` Resource with `integration_status = 'pending'` **and** at least one
> `imports.requests.response.status = 422` whose body is an identity/uniqueness conflict
> (`unique_register_id` / email already taken).

This is queryable per client with no cross-DB join, and the index already exists
(`INTEGRATOR_DOMAIN.md` ch. 9 — `imports.requests.response.status` is an indexed embedded path;
the README debug queries use exactly this shape). Every failing create is **already recorded**
in the audit trail (and already listed in the daily IntegrationReport email as a failed import —
the information is not hidden, just buried among all other failures and never isolated as a class
or tracked as a backlog across runs).

## The detector runs on our app, not the customer's source

The customer's source procedures are windowed and cannot enumerate the risk population: one
procedure returns active users, another returns only users deactivated in the last ~3 months. A
user deactivated more than 3 months ago and not yet rehired is in neither, and is therefore absent
from `fsk_users` too. The normalized base shares the source's blind spot — enumerating the at-risk
set from the source or from `fsk_users` is impossible, and a rehire only makes the user visible
again after the fact.

The app is the complete, permanent record and does not have that blind spot. The at-risk
population is **app users (per company) with no `4sk_` `UserIdentifier`**; the disabled subset are
the reactivation time-bombs. Measured for company 1318 (Atento MX):

- 23,394 users; 10,639 linked (`4sk_`); **12,755 unlinked**.
- **12,659 unlinked AND disabled** — the complete reactivation-risk list.
- Of those, only **5** are present in `fsk_users` today; **12,654 are invisible to the source**
  (deactivated outside the 3-month window). This is the direct measurement of the source blind
  spot: the source can enumerate ~0.04% of the risk; the app holds all of it.

So the recurring detector runs against our own app data, in two layers:

- **Proactive (primary), app-side:** per company, list users with no `4sk_` identifier — the
  disabled subset first. Independent of the source window; enumerates the full backlog and every
  future case before the rehire, from a database we own.
- **Reactive (complementary), integrator-side:** the `pending` + 422 identity-conflict signature
  in the integrator Mongo, which confirms the cases that already attempted and failed.

## Scenario taxonomy the detector should cover

| # | Scenario | Signal | Where detectable | Effort |
|---|---|---|---|---|
| 1 | **Unlinked user** (the Atento MX case) — app user exists via another channel, integrator create conflicts, stuck `pending` | Resource `pending` + request 422 identity conflict | integrator Mongo alone | low |
| 2 | **State divergence** — integrator `integrated` but app `disabled` (or inverse) | integrator status ≠ app `disabled_at` | integrator Mongo + app (RDS/API) | medium |
| 3 | **Absent from normalized base** — person on app / reported by customer but not in `fsk_users` | RFC on app with no `fsk_users` match | app + normalized SQL | high (needs a reference set of who "should" exist) |

Scenario 1 is the highest value and the cheapest to automate. Scenarios 2–3 need cross-store
joins and belong in a later phase (a broader periodic reconciliation report).

## Proposed detector (Scenario 1, primary)

A new integrator rake alongside the existing `integration_audit:*` family, e.g.
`integration_audit:pending_conflicts` (or `reconciliation:unlinked_users`):

1. Query Mongo for `User` Resources where `integration_status == 'pending'` and any embedded
   request has `response.status == 422` with an identity-conflict body (match the
   `unique_register_id` / "already been taken" shape — confirm the exact body against one live
   Resource when implementing).
2. Emit a CSV to S3 under `integration-debug/audits/...` (same contract as the existing audit
   rakes: one line per Resource — `external_id` (= `fsk_id`), conflicting identifier value,
   `imports_count`, last-attempt timestamp, response body).
3. Optional enrichment: join `fsk_users` (RFC, payroll, name) for a human-readable report — this
   needs the normalized DB (warm-up), so keep it optional / a second pass.

Run it via the same dispatch used in this investigation
(`~/.claude/skills/integration-debug/scripts/integration-audit-snapshot-*.sh`), which already
knows how to fire an audit rake per cluster and collect the CSV.

## Automation / cadence options (decision for the engineer)

- **A — Scheduled per-client rake (recommended).** Add the rake, then run it on a schedule across
  all normalized integrators (loop the `/integrators` list). Cheap, self-contained, produces the
  full backlog (not just today's failures) any time. Detection-only, matches the stated scope.
- **B — Fold into the daily IntegrationReport.** Add a dedicated "stuck pending / identity
  conflict" section to the existing per-run email so it is visible every day without a separate
  job. Lower operational overhead, but couples to the report and stays per-run rather than a
  backlog view.
- **C — Cross-store reconciliation report (phase 2).** Extend to Scenarios 2–3 with an app-side
  join (via the app `integration_audit:user`/`user_identifier` rakes already used here). Heavier;
  do only after A proves the volume.

Open decision the engineer should settle: whether "we can't correct" means detection-only
permanently, or whether the Scenario A reconciliation (create `4sk_<fsk_id>` + `integrate!`)
becomes a follow-up once detection is in place. The reconciliation is technically possible; it was
descoped here, not proven impossible.

## Next steps

1. Confirm the exact 422 conflict body against one live pending Resource (one Mongo query) to pin
   the detector's filter.
2. Implement `integration_audit:pending_conflicts` in the `integrator` repo (small rake next to
   the existing audit family).
3. Wire a periodic run across normalized integrators; deliver the CSV/report per client.
4. (Phase 2) decide on Scenarios 2–3 and on whether reconciliation is added.

## Artifacts from the investigation (local, this session)

- `/tmp/final_diagnosis.txt` — per-user integrator status.
- `/tmp/timing.txt`, `/tmp/hypothesis.txt` — creation/termination timing vs. June 2026 activation.
- `~/Downloads/integration_debug_atento-mx_reingresos_gap_*.xlsx` — consolidated report.
