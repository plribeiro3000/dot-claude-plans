# PLAN — Atento Payroll Integration Follow-ups

## Context

The Atento payroll integration (FpwIntegration, LG/SOAP) ran successfully in production.
Two follow-up items surfaced during that run and must be fixed. They are unrelated in
code but share the same trigger (the payroll run) and are tracked together here.

- **Stream 1 (front-end, `app-webclient`)**: the "Integration Report" button on the
  payment page opens the wrong screen — the user-payment listing (only *user* and
  *payment type* filters, no request log) instead of the payroll-request report that has
  the status filter and the per-request log. Regression connected to the Maqnelson work.
- **Stream 2 (backend, `app`)**: during the run, the payroll Sidekiq workers raised
  database-access exceptions that escaped to Sidekiq and were retried (the system
  self-recovered). Out of ~1,400 user payments, ~1,200 actually issued requests (the
  rest were zero-value and skipped); ~10 of those hit HTTP timeouts. Goal: stop the
  DB exception from exploding (handle it gracefully) and reduce the timeouts.

Both are low-risk, high-priority. Neither changes the in-flight job contract, so each
ships as a normal single deploy (see Deploy Notes).

---

## Stream 1 — Integration Report screen shows the wrong view

### Root cause (confirmed)

The "Integration Report" button routes to the **user-payments listing**, not to the
**payroll-request report**. The report screen that has the status/error filter and the
request log already exists and is not what the button opens.

- The button targets `/payments/:id/userPayments`:
  `app-webclient/src/app/payment/show/payment-show.component.html:25`
- `/userPayments` → `UserPaymentComponent`; the payroll-request report is a *different*
  route, `/payments/:id/integration` → `PaymentIntegrationComponent`:
  `app-webclient/src/app/payment/payment-routing.module.ts:38`
- The real report has the **status filter** (pending/success/failure), the **action
  filter** (check/execution/validation), and the **per-request log** (action, status,
  duration, created_at, user):
  `app-webclient/src/app/payment/integration/payment-integration.component.html:25`
- That report already adapts to Maqnelson: it hides the per-user column when the
  integration is `bulk` (Maqnelson), via `payrollIntegration.bulk`:
  `app-webclient/src/app/payment/integration/payment-integration.component.ts:76`,
  `...component.html:60`
- The backend GraphQL resolver already supports the `status` and `action` filters —
  no backend change needed for the filters:
  `app/app/graphql_resolvers/payroll_request_graphql_resolver.rb:10`

The engineer's hypothesis is correct: the button unconditionally sends every payment to
the user-payment listing (the view that suits Maqnelson, which has no per-user requests),
so FpwIntegration payments (Atento) never reach the report with the request log. The
recent Maqnelson work built/kept the improved report at `/integration` but the button was
never repointed to it (the last commit touching the button, `ae1d4a2c8`, only fixed the
route casing `user_payments` → `userPayments`; it did not change the destination).

### Open decision (needs the engineer)

How the button should branch:

- **Option A — route by integration type**: FpwIntegration (`bulk = false`) → `/integration`
  (the report with the log); Maqnelson (`bulk = true`) → `/userPayments` (the listing).
  Requires `payment-show` to know `payrollIntegration.bulk` (it currently does not query it;
  `payment-integration` does — the query pattern already exists to copy).
- **Option B — always route to `/integration`** and let the report adapt via `bulk`
  (it already hides the per-user column for Maqnelson). Simpler; open question is whether
  the Maqnelson bulk case is well-served by the payroll-request report or still wants the
  user-payment listing.

Recommendation to discuss: **Option A** matches the engineer's framing (Maqnelson is a
genuinely different view) and keeps each integration type on its intended screen.

### Tasks

1. Confirm the intended pre-regression behavior with the team (which screen each type
   should open) and pick Option A or B. *(git archaeology: verify whether the
   user-payments listing previously carried the status filter + log, to be certain nothing
   else must be restored — quick, optional.)*
2. Apply the chosen routing fix in `payment-show.component.html` (and, for Option A, add
   the `payrollIntegration.bulk` query to `payment-show`, copying the existing pattern from
   `payment-integration.component.ts`).
3. Verify against an FpwIntegration payment (Atento): the button opens the report with the
   status filter, action filter, and the request log; and against a Maqnelson payment: the
   intended view opens.
4. Follow the front-end Pattern Priming before writing (read the sibling components), then
   ship through to an open PR on `app-webclient`.

---

## Stream 2 — Payroll workers: swallow the DB exception, reduce timeouts

### Observed behavior

During the Atento run, the payroll workers raised **database-access exceptions** that
escaped to Sidekiq; Sidekiq retried and the jobs succeeded (self-recovery). Separately,
~10 of ~1,200 issued requests hit HTTP timeouts. The engineer wants the exception handled
so it does not explode, and the timeout count reduced.

### Exact exception (confirmed via Rollbar)

Rollbar item **App-Atento001-Api #1228** (production, first + latest 2026-07-22, total 2):

```
ActiveRecord::ActiveRecordError: cannot update a new record
  at block in FpwIntegration::CheckConsumer#perform (app/workers/fpw_integration/check_consumer.rb:115)
  at block (2 levels) in ApplicationRecord.with_uncached_connection (app/models/application_record.rb:42)
```

It is **not** a database connectivity error. It is `increment!` called on an **unsaved
record** in the timeout-rescue handler. The earlier "DB is failing" hypothesis is wrong.

### Root cause (confirmed)

The `payroll_request` is not persisted before the HTTP call, so the timeout handler's
`increment!` raises `cannot update a new record`.

Chain, in `check_consumer.rb` (identical in `execute_consumer.rb` and `validate_consumer.rb`):

1. `check_consumer.rb:66` — `user_payment.payroll_requests.find_or_create_by(action: :check)`
   runs with `request_body`/`request_headers` still blank; the model validates their presence
   (`app/models/payroll_request.rb:10`), so the create **fails validation and returns an
   unsaved record** (`find_or_create_by` does not raise).
2. `check_consumer.rb:73` — `request_body`/`request_headers` are set on the in-memory object.
3. `check_consumer.rb:81` — `http.request(request)`; on timeout it raises here, **before** the
   only `save` at `check_consumer.rb:106`.
4. `check_consumer.rb:115` — the timeout rescue runs `payroll_request.increment!(:timeout_quantity)`
   on the still-unsaved record → `ActiveRecord::ActiveRecordError: cannot update a new record`
   → escapes `perform` → Sidekiq retries → the retry's HTTP call succeeds and reaches line 106
   → self-recovery.

Two consequences beyond the noisy exception:

- The application's own timeout-retry logic (increment `timeout_quantity`, reschedule up to
  `payroll_max_timeout_retries`) **never runs on the first attempt** — it always throws this
  error instead of rescheduling. The recovery was Sidekiq's generic retry, not the payroll
  retry code.
- A request that times out on the first attempt is **never logged** (the `save` at line 106
  is never reached), so the report shows no row for it.

### Recommended fix (open for confirmation)

Persist `payroll_request` with its `request_body`/`request_headers` **before** the HTTP call,
in all three consumers. Then `increment!`/`update` in the rescues operate on a saved record,
the app's timeout-retry logic actually works, and the request is logged even when it times out
(it starts `pending`, the natural in-flight state). This replaces the earlier idea of adding
DB exception classes to the rescue lists — that idea was based on the wrong hypothesis.

### Open decisions (needs the engineer)

- **Where to persist.** Save right after setting `request_body`/`request_headers` (before the
  HTTP call), vs. `find_or_initialize_by` + explicit `save` before the call. Both fix it;
  confirm the shape before coding. The three consumers must be fixed together (same bug).
- **Timeout reduction.** The timeout/retry values are config
  (`ApplicationConfiguration.payroll_open_timeout` / `payroll_read_timeout` /
  `payroll_max_timeout_retries` / `payroll_timeout_retry_delay`). With the persist fix in
  place, the real timeout-retry logic will finally engage — decide whether that alone is
  enough, or also raise the read timeout / retry ceiling. (Engineer signalled minor — "é
  pouco" — but wants it addressed.)

### Tasks

1. Confirm the persist-before-HTTP fix shape with the engineer (open decision above).
2. Follow the Pattern Priming on the three consumers, then persist `payroll_request` before
   the HTTP call in `check_consumer.rb`, `execute_consumer.rb`, `validate_consumer.rb` — one
   coherent change across the three (they are structurally identical).
3. Verify: a timed-out first attempt now increments `timeout_quantity` and reschedules (no
   `ActiveRecordError`), and the request is logged as `pending` while in flight.
4. Review the timeout config and apply any agreed tuning.
5. Ship through to an open PR on `app`.

---

## Risks & Deploy Notes

- Both streams are backward-compatible. Stream 2 does not change the enqueued job argument
  shape nor the `Computation` key derivation, so it is a **single normal deploy** (no
  expand/contract, no maintenance window). Standard zero-downtime rules apply; only check
  the Sidekiq queue depth before deploying `app` (per `app/CLAUDE.md`).
- Stream 1 is `app-webclient` (Netlify) — front-only, no backend coupling.

## Open Questions

1. Stream 1 routing: Option A (route by `bulk`) or Option B (always `/integration`)?
2. Stream 1: did the user-payments listing previously carry the status filter + log, or was
   that always a separate report screen? (Confirms nothing else regressed.)
3. Stream 2: persist shape — save after setting body/headers, or `find_or_initialize_by` +
   explicit save before the HTTP call?
4. Stream 2: is the persist fix alone enough for the timeouts (the real retry logic engages),
   or also tune the read timeout / retry ceiling?
