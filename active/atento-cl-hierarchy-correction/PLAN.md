# PLAN — Atento Chile hierarchy/cargo correction (company 1780)

Correct the production hierarchy of Atento Chile so that every integrator-fed user's
**seat type (cargo)** and **immediate manager (parent)** match the current state of the
normalized base `users` table. Source of truth = `normalized.users.type` and
`normalized.users.parent_id`. Fix path = **4Shark-side, app Rails console** (engineer pastes
generated scripts into `bin/ecs run app-atento-001`). Integrator side only for the 4 stuck users.

- **Scope decision (engineer):** cargo **+** all immediate-manager divergences.
- **Approach decision (engineer):** 4Shark console (not customer-side `hierarchy` events).
- **Status:** Phase 1 (Discovery) complete + **REV2** redo cross-referencing `fsk_hierarchy` events.
  Phase 2 (Execution) **not started — awaiting approval + open items 1-5**.
  **Parent truth-source RESOLVED (engineer): `users.parent_id`** — hierarchy events are treated as noise/obsolete
  on the parent axis and are NOT applied. The original worklist (227 ops) stands.

## Resume tomorrow (data is point-in-time — integration runs overnight)

The CSVs / worklist / counts in this plan are a snapshot from 2026-06-02 and **will be stale** after
tonight's integration run. To resume:
1. Re-dispatch Phase 1 snapshots (same `integration-audit-snapshot-*.sh` configs in this plan — coordinates
   below are stable: clusters, regions, launch types, company 1780, `4sk_` join key, atento-cl is database mode).
2. Re-run the saved analysis scripts in `scripts/` (reconcile → generate_worklist → hierarchy_xref →
   parent_three_way → build_report_v2). **Edit the `base = ...` path in each to the new out_dir first.**
3. Fresh worklist + report come out; the **decisions below are durable** (don't re-ask): truth = `users.type`
   (cargo) + `users.parent_id` (parent); hierarchy events NOT applied; approach = console 4Shark; base forms
   with internal IDs; ordering promotion→parent_update→demotion. Still pending: open items 1-5.
4. The integration run may have changed the 4 pending / some seats — re-confirm counts before scripting.

## Coordinates

| Thing | Value |
|---|---|
| Integrator | `atento-cl` → `integrator-atento-cl-cluster` (Fargate, sa-east-1), runner `integrator-atento-cl-runner` |
| Backend (`atento001.app4shark.com`) | `app-atento-001-cluster` (Env tag `atento-001`, EC2, us-east-1), runner `app-atento-001-runner` |
| Company | `1780` (Atento Chile — multi-tenant scope on the dedicated Atento stack) |
| Normalized source | DatabaseSource, MSSQL, prefix `FSK_` (confirmed in database mode — `normalized:user` produced data) |
| Join key | `app UserIdentifier.value = "4sk_<normalized.users.id>"` (secondary, `primary=false`) ↔ `integrator mongo external_id` |

## Discovery artifacts (Phase 1)

All under `/tmp/integration-audit-20260602T140159Z/` (CSVs also retained in each stack's S3
`integration-audit/` prefix — keep, do not delete).

- `phase1-normalized-user.csv` — truth (id, type, parent_id, subsidiary_id, …), 3081 rows
- `phase1-mongo-user.csv` — integrator Resource state (external_id, integration_status), 3081 rows
- `phase1-app-user.csv` / `phase1-app-seat.csv` / `phase1-app-user-identifier.csv` / `phase1-app-seat-history.csv`
- `cargo-divergences.csv` — the 13 cargo + 4 not-linked
- **`correction-worklist.csv`** — the 227 ordered operations (THE Phase-2 input)
- `phase1-normalized-hierarchy.csv` — **REV2**: the `fsk_hierarchy` event log (1232 rows: 1223 update_parent, 5 promotion, 4 demotion; 2026-05-05..06-02). Task bug fixed and re-run OK.
- `correction-worklist-with-events.csv` — worklist annotated with whether a corrective hierarchy event already exists.
- HTML reports: `/tmp/integration_debug_phase1_atento-cl_app-atento-001_20260602T140159Z.html` (v1) and
  `/tmp/integration_debug_phase1_rev2_atento-cl_app-atento-001_20260602T140159Z.html` (**REV2 — current**).

## Findings (current state)

- 3081 normalized users; **2996 (97.2%)** already correct & active; all non-anonymized.
- **227 operations needed** (`correction-worklist.csv`):
  - **4 promotions** (truth higher than app) — norm 56, 341, 406, 1725.
  - **210 parent_updates** (cargo correct, immediate manager wrong).
  - **9 demotions** (truth lower than app) — incl. **7 users wrongly at Admin** (app shows 15 Admins vs 3 in the base).
  - **4 link-then-create** — norm 931, 932, 1794, 2399: integrator Resource `pending`, no `4sk_` identifier on app (never integrated).
- **68 users cargo-correct but disabled on app** — OUT OF SCOPE (UserActivity, not hierarchy). Reported, not touched.

### REV2 — parent truth fork (BLOCKER for the parent buckets)

Cross-referencing `fsk_hierarchy` against `fsk_users.parent_id` and the app, the customer's base is
**internally inconsistent** on the manager. Three-way over 3076 linked users:

| Comparison | Count |
|---|---|
| app == `users.parent_id` | 2853 |
| app == latest hierarchy event | 163 |
| `users.parent_id` vs events disagree | **832** |
| app reflects the latest event | only 180 / 848 → **668 update_parent events UNAPPLIED** |

The app tracks `users.parent_id`, not the event log. A batch of **1223 `update_parent` events dated
2026-05-05** landed in neither the app nor `users.parent_id`. So "correct the managers" forks, and the
two directions **conflict** for the 832 users:

- **Truth = `users.parent_id`** → ~221 app changes (original worklist; mostly bring app in line with the column).
- **Truth = `hierarchy` events** → ~668 app changes (apply the unprocessed 2026-05-05 reorg).

**Cargo is NOT affected** — `users.type` is the agreed truth, the 8 cargo events are consistent with it,
and 11 of the 13 cargo fixes have no event at all (console-only). Cargo buckets proceed; parent buckets wait.

## Correction model (how each op is applied)

Use the **base** forms (operate on internal `User.id`, which the audit gives us directly) —
NOT the `Api::*` forms (those re-resolve via `UserIdentifier.get`). Read on master:
`app/forms/seat_promotion_form.rb`, `seat_demotion_form.rb`, `parent_seat_form.rb`.

Common attrs: `company_id: 1780`, `user_id:` = app User.id, `parent_id:` = parent's app User.id,
`date:` = today (must be **strictly after** `seat.histories.last.starts_at` — no backdating),
`owner_id:` = the operator/system user id for history attribution.

| Operation | Form | Key validations (from code) |
|---|---|---|
| promotion | `SeatPromotionForm` | target `type ∈ seat.parent_seats`; parent present & `parent.type` strictly above target (`correct_parent`) |
| demotion | `SeatDemotionForm` | target `type ∈ seat.subordinated_seats`; **`conflicted?`** rejects if highest current subordinate ≥ target; `:same` no-op guard |
| parent only | `ParentSeatForm` | pass `type:` = seat's **current** type so `correct_parent` runs; `parent.type` strictly above; `:same_parent` guard |

All three: wrapped in `Seat.transaction` + `seat.lock!`, write a `SeatHistory` row, return `false` on
invalid (check `form.errors`). Promotion/demotion set **type AND parent atomically** — so a cargo fix
that also has a wrong parent is one call.

## Execution order (resolves the dependencies)

Process `correction-worklist.csv` in its sorted order: **promotions → parent_updates → demotions**,
each tier by target level (parents before children). Rationale:
1. Promotions first → managers reach their correct (higher) level before reports attach under them.
2. Parent_updates next → moves every report onto its correct manager. **This clears the demotion
   blockers** (a soon-to-be-demoted node loses its high-level children before step 3).
3. Demotions last, after children are gone → `conflicted?` no longer triggers.

## Buckets (Script Discipline — pre-flight → mutation → verification per bucket)

Variables only, never constants. Per-ID iteration (Data Processing Pattern). Log every row;
continue past per-row errors; capture failures for the verification pass.

**Bucket 0 — Resolve open flags (BEFORE any mutation).** 35 flagged rows in the worklist:
- **26 "current parent OUTSIDE integrator"** — app currently parents these under an Atento-own
  (non-`4sk_`) manager; normalized says an integrator manager. Confirm with engineer/customer this
  is a real divergence (not intentional cross-channel management) before moving them.
- **2 rows whose target parent is norm 931** (itself pending) → blocked until Bucket 1 links 931.
- **7 "normalized has parent, app=root"** — confirm before assigning a parent to a current root.

**Bucket 1 — Link/create the 4 pending** (norm 931, 932, 1794, 2399). For each: locate the existing
app user (by document/identifier the customer keys on — needs the normalized `unique_register_id`),
create `UserIdentifier value:"4sk_<id>" primary:false subsidiary_id:<from normalized>`, then on the
integrator: `User.find_by(external_id:"<id>").integrate!`. If no app user exists, the user must be
created first. Resolves the cross-dependency for the 2 rows parented under 931.

**Bucket 2 — 4 promotions** (`SeatPromotionForm`).

**Bucket 3 — 210 parent_updates** (`ParentSeatForm`), parents-before-children by target level.

**Bucket 4 — 9 demotions** (`SeatDemotionForm`), after Bucket 3 so children are already moved.
Pre-flight MUST re-check `conflicted?` per node (subordinate counts shift as Bucket 3 runs).

Each bucket: **pre-flight** (validate every target parent exists & is at the required level, target
type is a valid promotion/demotion from current, date > last history, no `:same`); run mutation only
if pre-flight is clean for that row; **verification** re-reads the touched seats and compares to the
worklist target.

## Phase 3 — Verification (re-audit)

Re-fire the same Phase-1 snapshots with `phase=3` (fresh `out_dir`) via the
`integration-audit-snapshot-*.sh` scripts, re-run `reconcile.py` / `generate_worklist.py`, and
confirm the worklist is empty (0 operations) except intentionally-deferred flagged rows. Optionally
filter the app `worker-user` / `web` CloudWatch group for the mutation window.

## Consolidated report (Script Discipline Rule 4)

On completion, produce one `.xlsx` in `~/Downloads/` — per-bucket counts (targeted / passed
pre-flight / mutated / verified / unresolved), plain-language outcomes, unresolved items with owners.

## Open items requiring engineer/customer input before Phase 2

0. **(REV2 blocker) Parent truth source:** `users.parent_id` or the `hierarchy` events? They conflict for
   832 users (~221 changes vs ~668, opposite directions). Also decide whether the unapplied 2026-05-05
   reorg should be investigated as an integration failure rather than fixed by hand. Nothing on the parent
   axis proceeds until this is answered. (Cargo is unaffected and can proceed.)
1. Confirm the 26 "outside-integrator parent" moves are wanted (or exclude them).
2. Confirm the 7 "assign parent to current root" moves.
3. Provide the resolution key for the 4 pending (how to find the existing app user) — or confirm they
   must be created fresh.
4. Confirm `owner_id` to stamp on the SeatHistory rows.
5. Confirm `date` policy (today's date is safe vs the no-backdating rule).

## Tooling finding (RESOLVED in REV2)

`integrator lib/tasks/integration_audit/normalized/hierarchy.rake` previously queried `FSK_HIERARCHIES`
(plural) and aborted. Engineer fixed it; re-run produced the event CSV used by this redo. No longer blocking.
