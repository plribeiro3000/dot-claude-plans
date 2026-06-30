# PLAN-SPIKE — FPW Payroll Integration Redesign

> Branch: `feature/fpw-consumer-timeout-retry` (PR #5111)
> This plan extends what the PR already shipped (timeout-retry on check and validate consumers) with four additional pieces.

---

## Objective

Redesign the FPW payroll integration pipeline on top of PR #5111. The four additions are: (1) collapse the two-layer rescue in every consumer to a single method-level handler; (2) make `ExecuteConsumer` retryable with the same 5-retry cap; (3) handle the "Cadastre already exists" SOAP fault as success on retry; (4) enforce per-company serialization so only one payment integrates at a time per company, with a baton hand-off when a payment completes.

---

## Scope

### In scope
- One-level rescue redesign in `CheckConsumer`, `ExecuteConsumer`, `ValidateConsumer`
- Retry-up-to-5 for all three consumers (matching the spec already in check and validate; adding it to execute)
- Idempotency wrapper for `ExecuteConsumer` on Cadastre "already exists" SOAP fault
- Per-company distributed lock with baton hand-off in `Finalizer`

### Out of scope (planned follow-up)
- `attempts` jsonb column for per-attempt logging — mentioned here as a planned follow-up only; no design in this plan

---

## System map (grounded findings)

### Pipeline sequence
```
IntegratePaymentGraphqlMutation
  → Payment#integrate_by (state: final → integrating)
  → FpwIntegration::CheckProducer#perform
      payment.integrate!   # state enforced again (integrating → integrating)
      fan-out: push_bulk CheckConsumer per user_payment_id
  → CheckConsumer (reads FPW balance; persists PayrollRequest action=:check)
      computation.increment_executions
      when done? → enqueue ExecuteProducer
  → ExecuteProducer → fan-out ExecuteConsumer per user_payment_id
  → ExecuteConsumer (writes Cadastre/Atualize; persists PayrollRequest action=:execution)
      computation.increment_executions
      when done? → enqueue ValidateProducer
  → ValidateProducer → fan-out ValidateConsumer per user_payment_id
  → ValidateConsumer (reads FPW balance again; persists PayrollRequest action=:validation)
      computation.increment_executions
      when done? → enqueue Finalizer
  → Finalizer: payment.finish_integration! (state: integrating → integrated)
```

**Pattern 1: Integration trigger** — `app/graphql_mutations/integrate_payment_graphql_mutation.rb:13-14`
```ruby
if payment.integrate_by(user_id: current_user.id, from: remote_ip)
  FpwIntegration::CheckProducer.with_company_id(payment.company_id).dynamic_perform_async(payment.id)
end
```
Single entry point. No other caller of `CheckProducer` exists in the codebase.

**Pattern 2: Payment state machine** — `app/models/payment.rb:33-92`
```ruby
enumerize :status,
          in: {
            initial: 0, processing: 1, review: 2, final: 3, failed: 4,
            exporting: 5, exported: 6, integrating: 7, integrated: 8, integration_error: 9
          }, default: :initial

event :integrate do
  transition integrating: :integrating
  transition final: :integrating
  transition integration_error: :integrating
end
event :finish_integration do
  transition integrating: :integrated
end
event :integration_error do
  transition integrating: :integration_error
end
```
The "initial" state in the serialization requirement is the `Payment#status` `:initial` value (integer 0 in the `payments.status` column). A payment sits in `:initial` after creation and before `integrate_by` is called by the user.

**Pattern 3: `Payment#integrate_by`** — `app/models/payment.rb:122-130`
```ruby
def integrate_by(user_id:, from:)
  transaction do
    update!(integration_owner_id: user_id, integrated_from: from, integrated_at: Time.zone.now)
    integrate!
  end
rescue ActiveRecord::RecordInvalid
  errors.add(:base, :invalid)
  false
end
```
Transitions `final → integrating`. The mutation also transitions `integration_error → integrating` by the same event — a failed payment can be re-triggered.

**Pattern 4: Computation / done? counter** — `app/models/computation.rb:38-41`
```ruby
def done?
  queue_value == executions_value
end
```
Each producer calls `payment.computation.increment_queue(by: user_payment_quantity)`. Each consumer calls `payment.computation.increment_executions`. When the counters match the entire fan-out is complete and the next stage is enqueued. Counters live in Redis via `Sidekiq.redis_pool` with a 12-hour TTL (via `Counter`).

**Pattern 5: Finalizer** — `app/workers/fpw_integration/finalizer.rb:7-10`
```ruby
def perform(payment_id)
  payment = Payment.with_uncached_connection { Payment.find(payment_id) }
  Payment.with_uncached_connection { payment.finish_integration! }
end
```
`Finalizer` is called only from `ValidateConsumer` after the full fan-out completes. Today it simply calls `finish_integration!` and exits. The baton hand-off must be added here.

**Pattern 6: `Lock` class** — `app/models/lock.rb:4-39`
```ruby
def self.acquire(lock_key, lock_ttl = nil)
  result = Sidekiq.redis_pool.with do |connection|
    if lock_ttl.present?
      connection.call('set', "lock:#{lock_key}", 'true', nx: true, ex: lock_ttl.to_i)
    else
      connection.call('set', "lock:#{lock_key}", 'true', nx: true)
    end
  end
  acquired = result == 'OK'
  # block form: raises RaceConditionException unless acquired, yields, then deletes
end
```
The app already has a production-grade distributed lock primitive over `Sidekiq.redis_pool`. It supports TTL via `ex:`, uses `SET NX` (atomic), and has `delete`, `exists?`, `ttl` class methods. Block form auto-releases on exception via `ensure`. Used in forms, policies, workers (`Payment::Producer`, `DealElasticIndex::Refresher`), and `Groupification`.

**Pattern 7: Two-layer rescue (the gambiarra being removed)** — `app/workers/fpw_integration/check_consumer.rb:79-114`
```ruby
begin
  starts_at = Time.zone.now
  response = http.request(request)
  # ...
rescue *FpwIntegration::HTTP_TIMEOUT_EXCEPTIONS
  raise          # ← re-raise to escape the inner begin/rescue
rescue StandardError => e
  # record failure inline
end
# ...
rescue *FpwIntegration::CONNECTION_EXCEPTIONS, *FpwIntegration::HTTP_TIMEOUT_EXCEPTIONS => e
  # method-level: retry or mark failure
```
Same two-layer shape in `execute_consumer.rb:91-112` and `validate_consumer.rb:80-112`. The inner `rescue *HTTP_TIMEOUT_EXCEPTIONS; raise` was added by PR #5111 to let timeouts escape the inner `begin/rescue StandardError` and fall through to the method-level retry handler. The engineer identifies this re-raise as a gambiarra.

**Pattern 8: FpwIntegration constants** — `app/models/fpw_integration.rb:6-10`
```ruby
CONNECTION_EXCEPTIONS = [IO::EAGAINWaitReadable, Excon::Error::Timeout].freeze
HTTP_TIMEOUT_EXCEPTIONS = [Errno::ECONNRESET, Errno::EHOSTUNREACH, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError].freeze
MAX_TIMEOUT_RETRIES = 5
TIMEOUT_RETRY_BACKOFF = 5  # seconds
```

**Pattern 9: ExecuteConsumer — Atualize value is absolute** — `app/workers/fpw_integration/execute_consumer.rb:23-29`
```ruby
if payroll_check_request.balance.positive?
  api = 'AtualizeEventoPorDataDoFuncionario'
  value = payroll_check_request.balance + user_payment.billable_money
else
  api = 'CadastreEventoPorDataDoFuncionario'
  value = user_payment.billable_money
end
```
`Atualize` sets an absolute total (`prior_balance + billable_money`). Re-applying the same absolute value is idempotent — it produces the same result on FPW regardless of how many times the call lands. `Cadastre` creates a new record; the FPW/LG SOAP API rejects a duplicate Cadastre with a specific fault (see Open Question a).

**Pattern 10: `UserPayment#pending?` — guards all consumers** — `app/models/payment.rb:108-110`
```ruby
def pending?
  initial? || processing? || exporting? || integrating?
end
```
`UserPayment` uses `enumerize :integration_status` with states `{ pending: 0, success: 1, failure: 2, skipped: 3 }`. The `pending?` check in consumers is `user_payment.pending?` where the guard is the `enumerize`-generated `pending?` predicate (checks `integration_status == 'pending'`). This guard is the idempotency gate: a consumer that runs twice for the same `user_payment_id` skips all HTTP work on the second run if the first already set `integration_status` to `success` or `failure`.

**Pattern 11: The race condition ExecuteConsumer has today** — `app/workers/fpw_integration/execute_consumer.rb:18,25`
```ruby
payroll_check_request = PayrollRequest.with_uncached_connection { user_payment.payroll_check_request }
# ...
value = payroll_check_request.balance + user_payment.billable_money
```
Two concurrent `ExecuteConsumer` jobs for the same `(user_payment_id, company)` — possible today because nothing prevents two payments for the same company from being in `integrating` simultaneously — both read the same `payroll_check_request.balance` and both call `Atualize` with the same `value`. The second write stomps on whatever was already there but with the same absolute value so for a single payment's user_payments there is no data loss. **However**, if two *different payments* for the same company are integrating at the same time and share employees (same `MatriculaDofuncionario`), both read the existing balance at the start of their respective CheckConsumer; both add their own `billable_money`; both call Atualize. The last writer wins, and one payment's amount is silently lost. This is the core motivation for the per-company lock.

---

## Piece 1 — One-level rescue

### Problem
Each consumer has:
- Inner `begin/rescue StandardError` around `http.request` — handles connection failures mid-request
- Method-level `rescue *CONNECTION_EXCEPTIONS, *HTTP_TIMEOUT_EXCEPTIONS` — handles timeouts for retry

PR #5111 added `rescue *HTTP_TIMEOUT_EXCEPTIONS; raise` inside the inner block. The net effect is correct (timeout exits the inner block and reaches the method-level handler) but adds a non-obvious control flow.

### Option A: Remove the inner begin/rescue entirely — let all exceptions reach the method level

**Approach:** Delete the `begin/rescue StandardError` block. The `payroll_request` attribute assignments before and after `http.request` become sequential code. Any exception from `http.request` propagates directly to the method-level `rescue`. The method-level handler distinguishes timeout/connection errors (→ retry) from `StandardError` (→ mark failure inline and save).

**Current method-level handler (check_consumer.rb:124-133):**
```ruby
rescue *FpwIntegration::CONNECTION_EXCEPTIONS, *FpwIntegration::HTTP_TIMEOUT_EXCEPTIONS => e
  PayrollRequest.with_uncached_connection { payroll_request.increment!(:timeout_quantity) }
  if payroll_request.timeout_quantity <= FpwIntegration::MAX_TIMEOUT_RETRIES
    FpwIntegration::CheckConsumer.with_company_id(company.id).dynamic_perform_in(...)
  else
    PayrollRequest.with_uncached_connection { payroll_request.update(status: :failure, response_body: e.message) }
    UserPayment.with_uncached_connection { user_payment.update(integration_status: :failure) }
  end
```
The method-level handler would need a second `rescue StandardError => e` clause that marks the `payroll_request` and `user_payment` as failed and saves — same logic as the current inner block.

**Two-clause shape for the perform method:**
```ruby
rescue *FpwIntegration::CONNECTION_EXCEPTIONS, *FpwIntegration::HTTP_TIMEOUT_EXCEPTIONS => e
  # timeout path: increment timeout_quantity, retry or mark failure
rescue StandardError => e
  # all other errors: mark payroll_request failure, mark user_payment failure, save
```

**Pros:** No inner begin/rescue, no re-raise, linear control flow. Identical shape across all three consumers. The payroll_request.save that currently sits outside the inner block (line 116 in check_consumer) can move inside the non-timeout rescue clause, keeping save collocated with the mutation.

**Cons:** `payroll_request` must already be assigned before the rescue clauses are evaluated (which it is, via `find_or_create_by`). The `starts_at`/`ends_at` duration calculation that currently lives inside the inner block needs to move; `ends_at` must be computed inside the StandardError rescue clause. This requires care to not reference `starts_at` before it is assigned if an exception fires before `starts_at = Time.zone.now`.

**Risk:** Low. The behavior is identical; the structure is simpler.

### Option B: Keep the inner begin/rescue but replace the re-raise with explicit type dispatch

**Approach:** Inside the inner `rescue StandardError => e`, check `raise if (FpwIntegration::HTTP_TIMEOUT_EXCEPTIONS + FpwIntegration::CONNECTION_EXCEPTIONS).any? { |klass| e.is_a?(klass) }`. No separate `rescue *HTTP_TIMEOUT_EXCEPTIONS; raise` clause.

**Pros:** Preserves the inner block for duration tracking.

**Cons:** Uses `is_a?` dispatch inside a rescue clause, which is less idiomatic than separate rescue clauses. Still two rescue layers. Does not actually simplify the structure much.

**Engineer note:** Option A is what the engineer's phrase "collapse to a single method-level rescue" describes. Option B is included for completeness but does not satisfy the stated intent.

---

## Piece 2 — Retry-up-to-5 in all three consumers

### Current state
- `CheckConsumer` (PR #5111): method-level rescue increments `timeout_quantity`, retries via `dynamic_perform_in` if `<= MAX_TIMEOUT_RETRIES` — `check_consumer.rb:124-133`
- `ValidateConsumer` (PR #5111): same shape — `validate_consumer.rb:128-137`
- `ExecuteConsumer` (PR #5111): method-level rescue increments `timeout_quantity` but does NOT retry: it only marks failure — `execute_consumer.rb:122-129`

### The spec
- `timeout_quantity` starts at 0
- Incremented on EVERY timeout call, including the first
- Cap: `timeout_quantity <= MAX_TIMEOUT_RETRIES` (5)
- Final count after cap reached: 6 (1 initial + 5 retries)
- `TIMEOUT_RETRY_BACKOFF = 5` seconds

### What needs to change for ExecuteConsumer
The existing handler in `execute_consumer.rb:122-129`:
```ruby
rescue *FpwIntegration::CONNECTION_EXCEPTIONS, *FpwIntegration::HTTP_TIMEOUT_EXCEPTIONS => e
  if payroll_request
    PayrollRequest.with_uncached_connection { payroll_request.increment!(:timeout_quantity) }
    PayrollRequest.with_uncached_connection { payroll_request.update(status: :failure, response_body: e.message) }
  end
  UserPayment.with_uncached_connection { user_payment.update(integration_status: :failure) } if user_payment
```
Must be replaced with the check/validate pattern: increment, check `<= MAX_TIMEOUT_RETRIES`, either enqueue `ExecuteConsumer.dynamic_perform_in` or mark failure.

**Note on safety:** `ApplicationWorker` has no `sidekiq_options retry:` override (`app/workers/application_worker.rb:4`). Sidekiq default is 25 retries on any raised exception. The method-level rescue must consume all exceptions from `perform` — nothing may escape. Under Option A this is enforced by having both `rescue *TIMEOUT_EXCEPTIONS` and `rescue StandardError` at method level. The retry path itself does not raise; the `else` branch marks failure and saves — no exception escapes.

---

## Piece 3 — ExecuteConsumer retry idempotency (Cadastre "already exists")

### Problem
`Cadastre` (create-on-new) is the path where `payroll_check_request.balance` is not positive. The FPW/LG SOAP API rejects a duplicate create with a fault response. On a first timeout where the request was actually received and processed by FPW, a retry will resend the same `Cadastre` and receive a fault, causing the retry to be treated as a real failure when the original write succeeded.

### Verified code path
`execute_consumer.rb:23-29` — balance is read from `payroll_check_request.balance`. If `balance > 0`, the write is `Atualize` (idempotent). If `balance == 0`, the write is `Cadastre` (non-idempotent on duplicate). The FPW response for an HTTP success that contains a SOAP fault is NOT caught today: the current code checks `response.is_a?(Net::HTTPSuccess)` and sets status to `:success` when the HTTP layer returns 200, regardless of whether the SOAP envelope contains a `<Fault>`. SOAP 1.1 faults are typically returned with HTTP 500; SOAP 1.2 faults with HTTP 400 or 500. Whether LG/FPW returns HTTP 2xx or 5xx for a duplicate Cadastre is an open question (see Open Question a).

### Option A: Parse the SOAP fault string in ExecuteConsumer and treat "already exists" as success

**Approach:** After `response.is_a?(Net::HTTPSuccess)` fails (i.e., the server returned a non-2xx), parse `response.body` via `Hash.from_xml` (already used in `check_consumer.rb:88` and `validate_consumer.rb:89`). Navigate to the fault structure (`Envelope.Body.Fault.faultstring` or `Envelope.Body.Fault.Code.Subcode.Value` for SOAP 1.2). If the faultstring contains the known "already exists" text, treat the `payroll_request` as success and do not mark `user_payment` failure.

The parsed path depends on the SOAP version in use:
- SOAP 1.1 envelope: `parsed.dig('Envelope', 'Body', 'Fault', 'faultstring')`
- SOAP 1.2 envelope: `parsed.dig('Envelope', 'Body', 'Fault', 'Reason', 'Text')`

Both versions already exist in the codebase (`payroll_integration.soap1?` at `execute_consumer.rb:31`).

**Pros:** Explicit, testable given known fault text. Self-documenting via a named constant.

**Cons:** Requires knowing the exact faultstring text (see Open Question a). If the FPW API changes the error wording, this silently misclassifies the fault as a real failure. The happy path changes: when a Cadastre retry finds "already exists", the `user_payment.pending?` guard is still `true` (since the first attempt failed at the network level before `integration_status` was updated). The consumer must set `payroll_request.status = :success` and then proceed to `increment_executions` and the stage-advancement logic.

**Risk:** Cannot be pre-production-tested. Engineer has accepted this risk. The `response_body` column captures the raw fault XML, so production monitoring can observe the exact faultstring after the first failure. A flag in the code (constant or comment) should document this explicitly.

### Option B: Skip idempotency handling; accept that Cadastre retry after a timeout will mark failure

**Approach:** Do not add special fault handling. If a Cadastre timeout occurs and the retry finds the record already exists, the consumer marks `user_payment.integration_status = :failure`. A human operator then investigates via `response_body`.

**Pros:** Zero code change for this sub-problem. No risk of misclassification.

**Cons:** A real success is visible to the operator as a failure. The validate consumer would also fail for the same `user_payment` (balance check will show the correct value but the execution is marked failure, so the pipeline treats the payment as failed for that employee). Manual recovery needed.

**Engineer note:** The engineer confirmed the "already exists" error is guaranteed by the FPW/LG API. Option A is the intent; Option B is the fallback if the exact error string cannot be confirmed before merge.

---

## Piece 4 — Per-company serialization (distributed lock + baton hand-off)

### Problem
Today, nothing prevents two different `Payment` records for the same company from entering the `integrating` state simultaneously. The `integrate` state machine event allows `final → integrating` and `integration_error → integrating` with no cross-payment coordination. The race condition identified in Pattern 11 (two parallel executes read the same employee balance, both add billable_money, last writer loses one payment's amount) is real, present in production code, and the per-company lock is the fix.

### Lock key design
The lock must be:
1. Per-company (not per-payment)
2. Globally unique (not namespaced to a payment or period)
3. Held across the entire pipeline for a single payment, from CheckProducer start to Finalizer completion
4. Released only when no further `initial`-status payment exists for the same company

**Candidate key:** `"fpw_integration_company_#{company_id}"` — not prefixed with `lock:` since `Lock.acquire` adds that prefix internally (`app/models/lock.rb:7`: `"lock:#{lock_key}"`). Final Redis key: `lock:fpw_integration_company_<company_id>`.

### Where is the lock acquired?

The lock must be acquired at the point where integration begins and before `CheckProducer` fans out. There are two candidate locations:

**Option A: Acquire in `IntegratePaymentGraphqlMutation#execute`** — `app/graphql_mutations/integrate_payment_graphql_mutation.rb:13-14`
```ruby
if payment.integrate_by(user_id: current_user.id, from: remote_ip)
  FpwIntegration::CheckProducer.with_company_id(payment.company_id).dynamic_perform_async(payment.id)
end
```
The lock is checked here: if `Lock.exists?("fpw_integration_company_#{payment.company_id}")`, do not call `integrate_by` and do not enqueue `CheckProducer`. The payment stays in its current state (`final` or `integration_error`). The client observes the payment as not yet integrating — it will be picked up by the baton hand-off when the in-progress payment finishes.

**Pros:** Simplest. The mutation is the only entry point. No changes to workers.

**Cons:** The mutation returns a non-error response without the payment transitioning. The client must poll or receive an event to learn when the payment is picked up by the baton. The mutation response shape does not change (it returns `respond_with(payment)` already), but the calling client may interpret "payment still in final state" as a no-op.

**Option B: Acquire in `CheckProducer#perform`** — `app/workers/fpw_integration/check_producer.rb:9-37`
```ruby
def perform(payment_id)
  payment = Payment.with_uncached_connection { Payment.find(payment_id) }
  Payment.with_uncached_connection { payment.integrate! }
  # ... fan-out
```
The lock is checked here. If the lock is already held, `CheckProducer` does not call `payment.integrate!`, does not fan out, and the payment remains in `integrating` state (the mutation already called `integrate_by` which transitioned it). The payment's `status` would be stuck in `integrating` with no consumers running.

**Cons:** Leaves the payment in `integrating` with no worker driving it. The baton hand-off in `Finalizer` would need to query for payments in `integrating` state, not just `initial` state, to pick these up. More complex.

**Option C: Acquire in mutation with explicit "queued" semantic**

Gate the mutation using `Lock.exists?`. If locked, call `integrate_by` (transition to `integrating`) but do NOT enqueue `CheckProducer`. The payment is now `integrating` without an active job — it signals "queued, waiting for baton". The `Finalizer` scans for `integrating` payments with no active job. This requires tracking which `integrating` payments have an active `CheckProducer` job vs. which are waiting — there is no such field today.

**Cons:** Requires either a new column or a separate Redis set to distinguish "active integrating" from "waiting integrating". Significant added complexity.

**Preferred option for further design: Option A** — the payment stays in `final`/`integration_error` state, the lock gates the mutation, and the baton finds it by status query. The engineer must confirm which status to use (see Open Question b).

### Baton hand-off design

**Where:** `Finalizer#perform` — `app/workers/fpw_integration/finalizer.rb:7-10`. Today it calls `finish_integration!` and exits. The baton logic runs after `finish_integration!`.

**What it does:**
1. Look for any `Payment` for the same company that is in `initial` status (or another agreed-upon "waiting" status — see Open Question b) with `has_payroll_integration: true`
2. If found, pick one (e.g., lowest `id` to be deterministic), call `payment.integrate_by(...)` on it, and enqueue `CheckProducer` for it
3. If not found, call `Lock.delete("fpw_integration_company_#{company_id}")`

**Key constraint:** The lock is NOT released between payment N finishing and payment N+1 starting. The lock transfer is atomic from the perspective of any other process trying to acquire it. The baton holds the lock and passes it directly.

**Lock TTL for crash recovery:** The `Lock.acquire` call with a TTL provides a safety net when a crash prevents `Finalizer` from running. Without a TTL, a crash leaves the lock permanently held and the company's payments stuck. With a TTL, the lock expires and the next `IntegratePaymentGraphqlMutation` call can acquire it.

**TTL sizing options:**

| Option | TTL value | Rationale |
|--------|-----------|-----------|
| No TTL | — | Computation is guarant by `done?` counter; if Sidekiq crashes, dead jobs are retried by Sidekiq's retry mechanism |
| 24 hours | 86400 | Generous upper bound; a payment with thousands of employees and max retries should complete well within 24h |
| Configurable | `ApplicationConfiguration` key | Consistent with `payroll_open_timeout`, `payroll_read_timeout`, `payment_report_lock` patterns |

**Risk without TTL:** If `Finalizer` crashes after `finish_integration!` but before the lock release / baton hand-off, the lock is never released and subsequent payments for the same company will never integrate. A TTL is the correct defensive measure.

**Risk with short TTL:** If a legitimate pipeline run takes longer than the TTL (large fan-out + many retries), the lock expires while the payment is still integrating. A second payment could start, restoring the race condition. A generous TTL (24h) or a configurable one minimizes this risk.

**Query for "waiting" payments:**
```ruby
Payment.with_uncached_connection do
  Payment.where(company_id: company_id)
         .with_status(:initial)
         .order(:id)
         .limit(1)
         .first
end
```
This query uses the `company_id` index on `payments` (`index_payments_on_company_id`, confirmed in `db/schema.rb:1246`). There is no composite `(company_id, status)` index — for companies with many payments, this could be a Seq Scan with a filter. Index addition is out of scope for this PR but worth noting as a follow-up (see Risks).

### Option A: Use existing `Lock` class with TTL

**Approach:** `Lock.acquire("fpw_integration_company_#{company_id}", ttl)` in the mutation; `Lock.delete(...)` in `Finalizer` when no waiting payment is found, or pass the baton directly by starting the next payment without releasing.

**Pros:** `Lock` is the established pattern in the codebase. TTL support already exists (`lock.rb:12-16`). No new dependency. The `Lock.exists?` query is already used in policies (`app/policies/payment_policy.rb:9-15`).

**Cons:** `Lock.acquire` uses the block form for auto-release, but the per-company integration lock is NOT a short-lived block operation — it must persist across multiple Sidekiq jobs over minutes or hours. The block form would release too early. The non-block form (`Lock.acquire` returns `true/false`) is the correct path here — same as how `Payment::Producer` uses it (`app/workers/payment/producer.rb:12`).

**TTL consideration:** The non-block form with a TTL: `Lock.acquire("fpw_integration_company_#{company_id}", lock_ttl)`. `lock_ttl` should be a configurable value (via `ApplicationConfiguration`), consistent with the existing `payroll_open_timeout` and `payroll_read_timeout` configuration keys.

### Option B: Use `sidekiq-unique-jobs` with `:until_executed` per payment + per-company serialization

`sidekiq-unique-jobs` (v8.1.0) is in the Gemfile (`Gemfile.lock:703`). It provides `sidekiq_options lock: :until_executed` which prevents duplicate jobs. The `DealElasticIndex::Refresher` uses it (`app/workers/deal_elastic_index/refresher.rb:5`). However, this gem prevents duplicate *jobs of the same class + args*, not serialization of different payment IDs for the same company. Achieving per-company serialization with it would require a custom `lock_args` proc, which is non-trivial and undocumented for the baton pattern.

**Pros:** No manual Redis code.

**Cons:** Not designed for this use case. The baton hand-off (starting the next payment from `Finalizer`) would still require manual code. TTL behavior with `until_executed` is different from what we need. Net complexity is higher than Option A.

**Verdict:** Option B is not applicable here. Option A (existing `Lock` class, non-block form, with TTL) is the natural fit.

---

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|---|---|---|---|
| One-level rescue shape | A: Remove inner begin/rescue entirely; B: Keep inner block, replace re-raise with is_a? dispatch | A is simpler and matches the stated intent; B preserves more inner structure | □ |
| Cadastre "already exists" handling | A: Parse SOAP fault + treat as success; B: Accept failure, operator recovers | A requires knowing the exact faultstring (Open Question a); B is safe but increases operational burden | □ |
| Lock acquisition point | A: Gate in mutation (payment stays in final/integration_error); B: Gate in CheckProducer (payment stuck in integrating with no job) | A is cleaner; B creates a zombie state | □ |
| Lock TTL strategy | No TTL; 24h hardcoded; configurable via ApplicationConfiguration | No TTL risks permanent lock on crash; configurable is consistent with existing payroll config pattern | □ |
| "Waiting" payment status | Use `:initial` (payment never called integrate_by yet); or define another mechanism | Simplest; Open Question b clarifies the exact payment state | □ |

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| Lock not released on Finalizer crash | All subsequent payments for the company are permanently blocked | TTL on lock acquisition |
| Missing `(company_id, status)` index on `payments` | Baton hand-off query becomes a Seq Scan for companies with many payments | Follow-up migration to add composite index (out of scope for this PR) |
| Cadastre "already exists" faultstring mismatch | Real success is misclassified as failure on Cadastre retry | Capture faultstring via `response_body` in prod, monitor first occurrence, ship a fix before the TTL window |
| Computation counter desync on retry | If `increment_executions` runs once but the consumer retries via `dynamic_perform_in`, the counter increments twice for the same `user_payment` | `user_payment.pending?` guard (Pattern 10) prevents the HTTP work from running on re-entry; `increment_executions` is called outside the `if user_payment.pending?` guard — verify this is intentional (counter must always increment, even on a skip/retry, to signal completion) |
| Baton hand-off race — two Finalizers for the same company run concurrently | Both find a waiting payment and both start it | The lock is already held during baton; `Lock.acquire` with `nx: true` prevents double acquisition; the `integrate!` state machine transition is also idempotent (`integrating → integrating` is a valid no-op transition per `payment.rb:80`) |
| Long pipeline duration exceeds TTL | Lock expires; a second payment starts; race condition restored | Use a generous TTL or make it configurable |

---

## Open questions for the engineer

**(a) Exact FPW "already exists" SOAP fault shape.**
The codebase does not contain any Cadastre fault handling or example response bodies. The exact faultstring — the string we must match to identify "already exists" — is not known from the codebase. This must come from the FPW/LG API documentation, a prior production `response_body` row from `payroll_requests`, or the LG support team. Until this is confirmed, Piece 3 Option A cannot be implemented safely. Example shape to confirm:
```xml
<Fault>
  <faultcode>...</faultcode>
  <faultstring>???</faultstring>  <!-- exact string needed here -->
</Fault>
```

**(b) Which Payment status is "waiting for baton"?**
The serialization requirement says "a payment that would start does NOT start — it stays in its 'initial' state." Confirmed from code: `Payment#status` `:initial` is integer 0, the default. A payment created but never passed to `integrate_by` is in `:initial`. The baton hand-off should query `Payment.where(company_id: company_id).with_status(:initial).order(:id).limit(1).first`. Confirm: does the company ever have payments in `:final` state (approved but not yet integration-queued) that should also be picked up? Or is the intent strictly that the user calls `IntegratePaymentGraphqlMutation` for each payment, and the mutation gates the lock? If so, the user's second call to the mutation will simply do nothing (lock is held), and the baton must query `:initial` payments that have already been `integrate_by`-called. But `integrate_by` transitions `final → integrating`, so a payment queued for baton would be in `:integrating` with no active job — which is the zombie state (Option B above). This tension must be resolved by the engineer.

**(c) Chosen lock primitive and TTL.**
Which option from the "Technical decisions" table applies to TTL. Also: should `lock_ttl` be a new `ApplicationConfiguration` key (consistent with `payroll_open_timeout`/`payroll_read_timeout`) or a constant on `FpwIntegration`?

**(d) `user_payment.pending?` semantics on retry.**
When a timeout occurs and `dynamic_perform_in` re-enqueues the consumer, the second execution calls `user_payment.pending?`. Since the first attempt did not call `user_payment.update(integration_status: :failure)` (it escaped via the timeout rescue), `integration_status` is still `:pending` and the HTTP work runs again. This is the intended behavior — confirm it is correct for `ExecuteConsumer` as well, given that Cadastre may have already been written on the first attempt.

---

## Sources

- `app/graphql_mutations/integrate_payment_graphql_mutation.rb:13-14` — single integration entry point
- `app/models/payment.rb:33-92` — Payment state machine, all states and transitions
- `app/models/payment.rb:108-110` — `Payment#pending?` method
- `app/models/payment.rb:122-130` — `Payment#integrate_by`
- `app/models/payment.rb:96-106` — `Payment.lock_key` (period-scoped; not the company-scope key needed here)
- `app/models/user_payment.rb:40-55` — `UserPayment` `integration_status` enumerize + state machine
- `app/models/fpw_integration.rb:6-10` — constants: CONNECTION_EXCEPTIONS, HTTP_TIMEOUT_EXCEPTIONS, MAX_TIMEOUT_RETRIES, TIMEOUT_RETRY_BACKOFF
- `app/models/computation.rb:8-41` — Computation: acquire_lock, done?, increment_executions, increment_queue (Redis-backed via Sidekiq.redis_pool)
- `app/models/lock.rb:4-53` — `Lock` class: acquire (NX + TTL), exists?, delete — Sidekiq.redis_pool
- `app/models/counter.rb:1-59` — Counter: Redis INCRBY + EXPIRE, 12h TTL
- `app/models/payroll_request.rb:21-23` — `enumerize :action` (check/execution/validation), `enumerize :status` (pending/success/failure)
- `app/workers/fpw_integration/check_consumer.rb:79-133` — two-layer rescue, method-level retry handler (PR #5111)
- `app/workers/fpw_integration/execute_consumer.rb:23-29` — Atualize/Cadastre branch, absolute value logic
- `app/workers/fpw_integration/execute_consumer.rb:91-129` — two-layer rescue in execute (no retry currently)
- `app/workers/fpw_integration/validate_consumer.rb:80-137` — two-layer rescue, method-level retry handler (PR #5111)
- `app/workers/fpw_integration/check_producer.rb:9-37` — CheckProducer: `payment.integrate!`, fan-out, `increment_queue`
- `app/workers/fpw_integration/finalizer.rb:7-10` — Finalizer: only `finish_integration!` today; baton hook goes here
- `app/workers/application_worker.rb:4` — no `sidekiq_options retry:` override → Sidekiq default 25
- `app/workers/payment/producer.rb:12` — non-block `Lock.acquire` usage pattern (closest analogue to the per-company lock)
- `app/workers/payment/finalizer.rb:15` — `Lock.delete(payment.lock_key)` at end of pipeline (pattern for baton release)
- `app/workers/deal_elastic_index/refresher.rb:5,8` — `sidekiq_options lock: :until_executed` and block-form `Lock.acquire` with TTL
- `db/schema.rb:1243` — `payments.status` integer column (no composite index with company_id)
- `db/schema.rb:1283-1299` — `payroll_requests` table: `timeout_quantity` default 0, `response_body` string
- `Gemfile.lock:703` — `sidekiq-unique-jobs (8.1.0)` present in the project
