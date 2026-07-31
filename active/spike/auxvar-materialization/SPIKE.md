# SPIKE — Materialization and read-path validation for auxiliary variables (BE-2, BE-6, BE-7)

> Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).
> Repository: `~/Projects/4Shark/app`, branch `develop`.
> Read in full before this spike: `~/Projects/4Shark/dot-claude-plans/active/app/auxiliary-variables/PLAN.md`
> and `TASKS.md`.

## Investigation question

Validate, step by step, the materialization and read path of the auxiliary-variables feature —
BE-2 (excluding the auxiliary type from existing unscoped variable flows), BE-6 (materializing the
per-`(user_commission, variable)` value), and BE-7 (the new options processor and its merge in the
three reading consumers) — against Sidekiq's own documented delivery guarantee, ActiveRecord's and
PostgreSQL's actual concurrency semantics for the write primitive, and 4Shark's own data-access and
query-discipline docs, so the three tasks can be broken into implementable micro-steps with a size
signal each. Any contradiction between `TASKS.md`/`PLAN.md` and the real sources is named
explicitly, and BE-6 is treated as the highest-risk task per the engineer's instruction.

## Sources consulted

**Sidekiq (delivery guarantee, signals)** — every quote re-fetched and confirmed present at the
cited URL:
- https://github.com/sidekiq/sidekiq/wiki/Best-Practices — at-least-once, not exactly-once;
  idempotency is the job's responsibility
- https://github.com/sidekiq/sidekiq/wiki/Job-Lifecycle — default 25 retries; a job can increment
  both Processed and Failed
- https://github.com/sidekiq/sidekiq/wiki/Signals — TSTP and TERM both let in-flight jobs finish;
  TERM has a 25-second hard timeout before a forced kill and Redis re-queue
- https://github.com/sidekiq/sidekiq/wiki/Reliability — the plain (non-Pro) fetch strategy can lose
  a job outright on a crash mid-processing
- See auxiliary: `auxvar-materialization_sidekiq_1.md` — all four quotes consolidated, plus the
  reasoning that ties them to "recompute, never `+=`"

**ActiveRecord 8.1.3 (write primitives)** — read directly from the vendored gem, not from
training-data memory of Rails behavior in some other version:
- `app/vendor/bundle/ruby/4.0.0/gems/activerecord-8.1.3/lib/active_record/relation.rb:658-934` —
  `insert`, `insert_all`, `upsert`, `upsert_all` doc comments and signatures
- See auxiliary: `auxvar-materialization_activerecord_1.rb` — the relevant excerpt verbatim

**PostgreSQL (concurrency semantics of the write)**:
- https://www.postgresql.org/docs/current/sql-insert.html — `ON CONFLICT DO UPDATE`'s atomicity
  guarantee and its scope
- https://www.postgresql.org/docs/current/transaction-iso.html — Read Committed's re-evaluation of
  a concurrently-modified target row
- https://oneuptime.com/blog/post/2026-01-25-postgresql-race-conditions/view — the general
  lost-update pattern and the `SELECT ... FOR UPDATE` fix
- https://devandchill.com/posts/2020/02/postgres-building-concurrently-safe-upsert-queries/ —
  fetched, found NOT to address a computed-aggregate upsert (its examples are a plain
  UUID→SERIAL-id mapping); dropped rather than stretched to fit, per citation discipline
- See auxiliary: `auxvar-materialization_postgres_1.md` — all three sustaining quotes plus the
  search that surfaced them

**4Shark's own docs**:
- `~/.claude/docs/DATA-ACCESS.md` — `with_uncached_connection`, join decomposition, IDs-only; read
  in full
- `~/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md` — ActiveRecord-first, database-side shaping,
  index awareness; read in full

**`app` codebase — read directly, not from `TASKS.md`'s citations alone** (every line number below
was re-opened and confirmed against the file at the time of this spike, 2026-07-30):
- `app/models/aggregated_indicator.rb` — whole file (125 lines); `calculate!`, `result`,
  `indicator`, `cache_id`, `self.table_name = :aggregated_modifiers`
- `app/models/commissioning.rb` — whole file; `#money`, `#points`
- `app/models/limiter_commissioning.rb` — whole file (15 lines); the `value * -1` override
- `app/models/application_record.rb` — whole file; `with_uncached_connection`, `self.get`,
  `self.get_id`, the cache-write callbacks (`cache_external_id`, `delete_external_id_cache`,
  `update_external_id_cache`)
- `app/models/reward.rb:45-109` — the in-repo precedent for pessimistic locking on a shared numeric
  column under concurrent workers. See auxiliary: `auxvar-materialization_reward_1.rb`
- `app/models/rule.rb` — whole file (227 lines); `PARSE_EXCEPTIONS`, `calculate`/`calculate!`, the
  four `_options` builder methods and their current line numbers
- `app/models/formula.rb` — whole file (23 lines); `referenced_identifiers`, `error`
- `app/workers/indicator_incentive/producer.rb`, `.../consumer.rb` — whole files
- `app/workers/limiter_incentive/consumer.rb`, `app/workers/ranking_incentive/consumer.rb`,
  `app/workers/redemption_incentive/consumer.rb` — whole files
- `app/workers/aggregated_indicator/consumer.rb`, `.../calculator/producer.rb`,
  `.../calculator/consumer.rb`, `.../purge/consumer.rb` — whole files
- `app/services/commission/indicator_options_processor.rb` — whole file (62 lines)
- `app/workers/calendar_audit/producer.rb` (1-27), `app/models/calendar_audit.rb` (20-38),
  `app/workers/goal_dataset/migration/producer.rb` (1-24),
  `app/workers/commission/money_sanitizer_processor.rb` (35-53),
  `app/work_books/commission_work_book/indicator_work_sheet.rb` (1-34) — the BE-2 call sites
- `db/schema.rb` — `aggregated_modifiers` (80-89), `commissionings` (446-464); confirmed both the
  unique index and the FK declarations
- `app/vendor/bundle/ruby/4.0.0/gems/dentaku-3.5.7/lib/dentaku/exceptions.rb` and `calculator.rb` —
  confirmed `UnboundVariableError < Error` and where it is raised
- `Gemfile.lock` — `sidekiq (8.0.10)`, `sidekiq-unique-jobs (8.1.0)`, `dentaku (3.5.7)`,
  `rails (8.1.3.1)`

## Findings

### BE-2 — Exclude auxiliary variables from unscoped flows

**Significance**: this task has essentially no concurrency hazard — it is adding a `.indicators` /
type filter to six already-read `Variable`/`Commissioning` queries. Its risk is completeness (did
every unscoped site get found?), not correctness under concurrency. Every line number `TASKS.md`
cites for this task was re-opened and matches the current file exactly — no contradiction found.

**Micro-steps**:

1. **`app/workers/calendar_audit/producer.rb:19`** — add `.indicators`/exclude-auxiliary scope to
   `variable_ids = Variable.with_uncached_connection { plan.variables.pluck(:id) }`.
   ```ruby
   # app/workers/calendar_audit/producer.rb:16-24
   plan_ids.each do |plan_id|
     plan = Plan.with_uncached_connection { Plan.find(plan_id) }
     user_ids = User.with_uncached_connection { plan.users.pluck(:id) }
     variable_ids = Variable.with_uncached_connection { plan.variables.pluck(:id) }
     combinations = period_ids.product(user_ids, variable_ids)
     calendar_audit.computation.increment_queue(by: combinations.count)
   ```
   **Hazard**: none new. The existing risk this line closes (unbounded fan-out
   `period_ids.product(user_ids, variable_ids)`) is already understood and cited correctly.
   **Verify**: a spec asserting a plan carrying an auxiliary variable produces the same
   `combinations.count` as before the auxiliary variable was added.
   **Size**: XS (one-line scope change plus one spec).

2. **`app/models/calendar_audit.rb:30`** — scope `PlanVariable.where(plan_id: plan_ids).count` to
   exclude auxiliary `plan_variables`.
   **Hazard**: none. This is a plain `.where` addition on an already-indexed foreign key
   (`plan_id`); `PlanVariable` needs a join to `variables` or a stored type/role column to filter
   on — confirm the join path exists before writing the scope (this is the one open question:
   `PlanVariable` itself has no `type` column today per `PLAN.md`'s schema description, so the
   exclusion must go through `joins(:variable).merge(Variable.where.not(type: 'AuxiliaryVariable'))`
   or equivalent — a detail `TASKS.md` does not spell out at the SQL level).
   **Verify**: a model spec pinning the count with and without an auxiliary variable present.
   **Size**: S (needs a join, not a bare column filter).

3. **`app/workers/goal_dataset/migration/producer.rb:16`** — same shape as step 1.
   **Size**: XS.

4. **`app/workers/commission/money_sanitizer_processor.rb:48`** — same shape as step 1.
   **Size**: XS.

5. **`app/work_books/commission_work_book/indicator_work_sheet.rb:29`** and its plan-slice sibling
   — add `.indicators` to `@commission.variables.select(:id, :name, :data_type).index_by(&:id)`,
   restoring the file's own line-12 gate (`@commission.variables.indicators.exists?`) that already
   declares this worksheet is about indicator variables only.
   **Size**: XS each (two files, same one-line change).

6. **Confirm the five deliberately-unscoped sites stay untouched** —
   `variable_audit_work_book/variables_work_sheet.rb:28`,
   `commission/indicator_options_processor.rb:41`, `company/inactivator.rb:107`,
   `company/activator.rb:110`, `company/cleansing/variable_producer.rb:13`. No code change; the PR
   diff must not touch these five files. **Size**: XS (a checklist item, not a code change).

**Contradiction check**: none found. All cited `file:line` pairs match the current `develop` state.

---

### BE-6 — Materialize the per-`(user_commission, variable)` auxiliary value

This is the task the engineer named as highest-risk, and the research confirms why: the concurrency
guarantee `TASKS.md` asserts ("the race is closed... the aggregate query re-reads at the moment of
write, inside its own transaction") is **incomplete** against the sourced evidence below. The
missing piece is not "recompute vs increment" — that part is correctly grounded in Sidekiq's own
at-least-once guarantee — the missing piece is that a recompute-then-write, however atomic the
*write* is, does not by itself protect the *value being written* from a concurrent sibling's write
to the same target row.

**Micro-step 1 — confirm the concrete concurrency window (not a bare pattern claim)**

The fan-out that puts two writers on the same `aggregated_modifiers` row is real and already in
the codebase: `IndicatorIncentive::Producer#perform` builds
`combinations = user_commission_ids.product(rule_ids)` (`app/workers/indicator_incentive/producer.rb:22`)
and dispatches one `Consumer` job per `(user_commission_id, rule_id)` pair via
`dynamic_push_bulk` (`:25`) — Sidekiq then runs these jobs **in parallel** across the worker pool.
If two rules of the same incentive (or two rules of two different incentives in the same
calculation stage) are both bound to the same auxiliary variable, their two `Consumer` jobs are two
concurrent Sidekiq jobs, each independently computing a sum over `commissionings` for that variable
and writing to the SAME `aggregated_modifiers` row keyed on `(user_commission_id, variable_id)`.
Cross-stage writes (e.g., an indicator rule and a later limiter rule) are naturally serialized by
the `Computation` stage-completion gate — the producer of a later stage does not run until the
prior stage's consumer fan-out is `done?` — so the genuine race window is **intra-stage**: multiple
rules of the SAME calculation stage bound to the same auxiliary variable, each processed by a
separate parallel consumer job. `TASKS.md`'s own criterion ("Several rules into one variable... and
two incentives into one variable, produce the expected sum") already asks for exactly this scenario
to be tested — the research below is what that test needs to actually pass under real concurrency,
not just in a single-threaded RSpec example.
**Size**: XS to document, but it changes the size of steps 3-4 below.

**Micro-step 2 — the write primitive: what each option in Rails 8.1.3 actually does**

Read directly from the vendored gem
(`app/vendor/bundle/ruby/4.0.0/gems/activerecord-8.1.3/lib/active_record/relation.rb:824-828`):

> "Updates or inserts (upserts) multiple records into the database in a single SQL INSERT
> statement. It does not instantiate any models nor does it trigger Active Record callbacks or
> validations."

This applies to `upsert`/`upsert_all` (and to `insert`/`insert_all`, same wording at `:658-661` and
`:668-671`). Three consequences for `AggregatedIndicator`:

- `AggregatedIndicator` carries `validates :user_commission_id, presence: true`,
  `validates :value, presence: true`, `validates :variable_id, presence: true`
  (`app/models/aggregated_indicator.rb:11-13`) — an `upsert`/`upsert_all` write skips all three.
- `ApplicationRecord`'s `before_save :delete_external_id_cache`, `after_create :cache_external_id`,
  `around_update :update_external_id_cache` (`app/models/application_record.rb:44-47`) never fire
  on an `upsert`/`upsert_all` write. `AggregatedIndicator.cache_id` is defined
  (`app/models/aggregated_indicator.rb:21-23`) and IS consulted elsewhere:
  `AggregatedIndicator.get(user_commission_id:, variable_id:)` is called from
  `Commission::IndicatorOptionsProcessor.aggregated_indicator_value`
  (`app/services/commission/indicator_options_processor.rb:51-60`, the exact method that writes the
  frozen snapshot `TASKS.md` relies on for "auxiliary keys land at their default"). `get` →
  `get_id` → `Rails.cache.read(cache_id) || find_by!(...).id` (`application_record.rb:171-177`) —
  note `get_id` never *writes* the cache itself; only the `after_create`/`around_update` callbacks
  do. So an `upsert`-written row is not a correctness risk for `.get` (it falls through to
  `find_by!`, which still returns the right row), but it never benefits from the cache — every
  subsequent `.get` on a materialized auxiliary variable is a live query, not a cache hit. This is a
  performance note, not a bug, and `TASKS.md` does not currently record it.
- **Per `~/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md` Rule 1**, `update_all`/`delete_all` are
  the named hazardous shapes because they "silently bypass every guarantee the application
  provides" and the doc requires "explicit engineer authorization" before Claude defaults to a
  bypass shape. `upsert`/`upsert_all` are not named in that doc's list, but the ActiveRecord source
  above shows they are the same class of bypass (no callbacks, no validations) — this is worth
  surfacing to the engineer as a genuine option-vs-default question, not assuming it is
  pre-authorized because `TASKS.md` says "the write is an upsert".

**PostgreSQL's own atomicity guarantee, and precisely what it does not cover** — the wording is
exact and worth quoting in full because BE-6's correctness rests on the difference:

> "`ON CONFLICT DO UPDATE` guarantees an atomic `INSERT` or `UPDATE` outcome; provided there is no
> independent error, one of those two outcomes is guaranteed, even under high concurrency."
> — https://www.postgresql.org/docs/current/sql-insert.html

This guarantees the ROW MUTATION is atomic (no duplicate insert, no lost `RecordNotUnique`
surprise). It says nothing about whether the *value* the caller supplies to `DO UPDATE SET
value = ...` reflects everything a concurrent sibling has already committed. Read Committed's own
documented re-evaluation only covers the **target row's WHERE-clause qualification**, not a
separate aggregate computed from a different table:

> "The search condition of the command (the `WHERE` clause) is re-evaluated to see if the updated
> version of the row still matches the search condition." — https://www.postgresql.org/docs/current/transaction-iso.html

Community corroboration for the general shape of the risk:

> "Both transactions read the same value, compute the same result, and the second update
> overwrites the first. This is a classic lost update problem."
> — https://oneuptime.com/blog/post/2026-01-25-postgresql-race-conditions/view

Applied to BE-6: Consumer A computes `SELECT SUM(...) FROM commissionings WHERE rule_id IN (...)
AND user_commission_id = ?` before Consumer B's own commissioning row is committed; Consumer B
computes the same SUM after A's row is committed (so B's sum is the correct, complete one); if A's
`ON CONFLICT DO UPDATE` write happens to land AFTER B's, A's stale, incomplete sum silently
overwrites B's correct one. Neither `ON CONFLICT`'s atomicity nor "recompute, never `+=`" prevents
this — both are true and both are insufficient alone. This is the concrete gap in `TASKS.md`'s
claim "the race is closed... the aggregate query re-reads at the moment of write, inside its own
transaction" — re-reading at write time is necessary but the finding above shows it is not
sufficient without a lock serializing the read-compute-write sequence itself.
**Size**: this is research, not code, but it changes step 3 below from S to M.

**Micro-step 3 — the write shape that closes the gap, with an in-repo precedent**

4Shark's own codebase already has a model doing exactly this shape — pessimistic row locking around
a read-compute-write sequence on a shared numeric column, explicitly for "financial operations":

```ruby
# app/models/reward.rb:61-75 (Reward#increment_budget)
def increment_budget(amount)
  return false unless amount.is_a?(Numeric)
  return false if amount.zero? || amount.negative?

  transaction do
    lock!
    increment!(:budget, amount)
    reload
    replenish! if exhausted? && available_budget.positive?
    true
  end
rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
  errors.add(:base, :invalid)
  false
end
```

The comment above it states the intent directly: *"Uses pessimistic locking (lock!) to prevent race
conditions in financial operations."* The equivalent shape for BE-6 —

```ruby
# Illustrative shape only — not a final implementation
AggregatedIndicator.with_uncached_connection do
  AggregatedIndicator.transaction do
    aggregated_indicator = AggregatedIndicator.lock.find_or_create_by(user_commission_id:, variable_id:)
    aggregated_indicator.value = recomputed_sum
    aggregated_indicator.save!
  end
end
```

— uses `lock` (row-level `SELECT ... FOR UPDATE`) so a second concurrent consumer targeting the
same row **waits** for the first to commit, then re-runs its own `SELECT SUM(...)` against the
now-committed state before writing — the sum it writes is therefore always computed AFTER any
sibling that got there first has already committed. This keeps the write on plain ActiveRecord
(callbacks and validations fire, satisfying Query Discipline Rule 1's default), and it is the
pattern this codebase already trusts for the same class of problem (a shared, concurrently-updated
numeric column). It does **not** use `rescue_unique_constraint` — `AggregatedIndicator` does not
declare it (confirmed: the model has no `rescue_unique_constraint(index:, field:)` call), so a bare
`find_or_create_by` racing on the FIRST-ever row for a pair would raise
`ActiveRecord::RecordNotUnique` on the loser — which Sidekiq's at-least-once retry then resolves on
its own (the retried job's `find_or_create_by` finds the now-existing row). `lock.find_or_create_by`
does not remove this first-row race entirely (the row does not exist yet, so there is nothing to
lock) — only the ROW LOCK on an *existing* row is what closes the ongoing-update race; the
first-creation race is a separate, already-tolerated hazard (a retry, not data corruption).
**Verify**: a test that fires two `Consumer` jobs concurrently (real threads or
`Sidekiq::Testing.inline!` is not sufficient — inline testing serializes execution and would not
reproduce the race; a genuine concurrency test needs two real DB connections/threads racing on the
same row, or the test settles for asserting the lock is present in the code path and trusting
Postgres's own `FOR UPDATE` semantics rather than reproducing the race empirically).
**Size**: M (the illustrative shape above is small, but the concurrency test is the genuinely hard
part of this task, and `TASKS.md`'s own criterion "Idempotency under retry: running the
materialization twice leaves the value unchanged" is a *different*, easier-to-test property than
the concurrent-writers race — the two must not be conflated in the task's test plan).

**Micro-step 4 — the aggregation query itself, checked against Query Discipline and Data Access**

The SUM must be database-side (`ACTIVE-RECORD-QUERY-DISCIPLINE.md` Rule 2) — e.g.
`Commissioning.where(user_commission_id:, rule_id: bound_rule_ids).sum(:value)` shaped per the
signed, commission-type-aware expression `TASKS.md` already specifies (money/points/limiter sign).
Index awareness (Rule 3): `db/schema.rb:457-458` already carries
`index ["rule_id", "user_commission_id"], name: "commissionings_unique_period_index", unique: true,
where: "(deal_id IS NULL)"` and `index ["rule_id"], name: "index_commissionings_on_rule_id"` — a
`WHERE user_commission_id = ? AND rule_id IN (...)` query can use either; no new index is needed,
confirming `TASKS.md`'s own claim.

Per `~/.claude/docs/DATA-ACCESS.md` Rule 2 (join decomposition, worker context): the bound-rule
lookup (`Rule.where(output_variable_id: variable.id).pluck(:id)`) and the commissioning sum should
be TWO separate single-table queries — not one `joins` — each wrapped in `with_uncached_connection`,
consistent with every existing consumer's pattern in this file set (all four already shown above
navigate associations per record rather than joining).
**Size**: S.

**Micro-step 5 — `AggregatedIndicator#calculate!` reuse question, answered**

`calculate!` (`app/models/aggregated_indicator.rb:25-47`) computes its value from `result`
(`:81-107`), which is built from `indicator_aggregations.pluck(:modifier_id)` (`:110`, inside the
private `indicator` method) — i.e., from `IndicatorAggregation` rows, which are populated only from
harvested/integrated `Indicator` data. An auxiliary variable is never fed by the integration
(`PLAN.md`'s own premise), so `indicator_aggregations` is **always empty** for an auxiliary
`AggregatedIndicator` row, which means `result.compact.blank?` is always true, which means
`calculate!` **always** falls through to `variable.format_default`
(`app/models/aggregated_indicator.rb:26-28`) and never computes the summed value BE-6 needs. Reuse
would not merely be redundant — it would be **actively wrong**: any code path that calls
`calculate!` on an auxiliary row (accidentally or via the Calculator's re-entry, `TASKS.md`'s own
decision D2) silently resets the row to the variable's default. This is exactly the failure mode
`TASKS.md`'s D2/Calculator-guard criterion already names and requires a type scope to prevent
(`app/workers/aggregated_indicator/calculator/producer.rb:20-21`) — the finding here **confirms**
that decision is correct and necessary, not merely cautious.

**Answer to the task's explicit question**: the auxiliary path must **bypass** `calculate!`
entirely — it needs its own write method (the recompute-and-lock shape above), never a call through
`calculate!`, `AggregatedIndicator::Consumer`, or `AggregatedIndicator::Calculator::Consumer`.
**Size**: XS to state, but this validates the whole shape of the Calculator-guard criterion in
`TASKS.md` rather than requiring a new one.

**Micro-step 6 — partial commissions, and a citation mismatch worth flagging**

`TASKS.md`'s criterion for partial commissions cites `AggregatedIndicator#indicator`
(`app/models/aggregated_indicator.rb:115-116`, `elsif user_commission.partial_commission.present?
nil`) as the place "zero-versus-absent semantics need confirming against partials." That method is
re-verified accurate at those line numbers — but it is a **private method used only by the existing
`calculate!`/`result` computation path** (confirmed by micro-step 5: it is never reached by an
auxiliary row, since `indicator_aggregations` is always empty for one). The citation therefore
points at code the new write path does not execute. The REAL partial-commission question for BE-6
is simpler and is not this method: does the new recompute-and-write correctly scope to
`user_commission_id` regardless of whether the enclosing job is driven by a `Commission` or a
`PartialCommission`? All four existing consumers already branch on `partial` only to choose which
commission class to look up (`Commission.find` vs `PartialCommission.find`,
e.g. `indicator_incentive/consumer.rb:8-13`) — the `user_commission_id`/`rule_id` values passed to
BE-6's new logic are identical either way, and `AggregatedIndicator` itself carries no
partial-specific column. So the partial case is handled by construction, not by a new branch — the
citation in `TASKS.md` should be corrected or dropped rather than implemented as written.
**Size**: XS (a documentation correction, not a code change).

**Micro-step 7 — the `Computation`/deploy-safety reasoning under retry**

Per `auxvar-materialization_sidekiq_1.md`: TSTP/TERM both let an in-flight job finish; a hard TERM
timeout (25s default) or a Sidekiq-process crash discards the job's in-memory state and re-queues it
for a full re-run (at-least-once). Combined with "recompute the full sum, never `+=`" (micro-step 2)
AND the row lock (micro-step 3), a re-run after interruption recomputes the identical, correct
target value — PROVIDED the lock closes the intra-stage race, which is the gap this spike's research
identifies. Without the lock, a re-run is still individually correct in isolation, but is not
protected from being clobbered by a concurrent sibling the same way a first run is not.
**Size**: XS (this step is a synthesis, not new code).

---

### BE-7 — Deliver the materialized value to every consuming rule

Lower risk than BE-6: this task reads an already-written value and merges it into an options hash,
so its concurrency exposure is limited to reading a possibly-in-progress BE-6 write.

**Micro-step 1 — confirm the merge sites, exactly as cited**

Re-verified line-for-line against `develop`:

```ruby
# app/workers/ranking_incentive/consumer.rb:44
options = deal_options.merge(modifier_options).merge(ranking_options)
```
```ruby
# app/workers/limiter_incentive/consumer.rb:37
options = deal_options.merge(modifier_options).merge(limiter_options)
```
```ruby
# app/workers/redemption_incentive/consumer.rb:34
options = deal_options.merge(modifier_options).merge(redemption_options)
```

All three match `TASKS.md` exactly. The new `Commission::AuxiliaryOptionsProcessor` merge is added
as a fourth `.merge(...)` after `modifier_options`, consistent with both named precedents
(`RedemptionOptionsProcessor` computing inline in the consumer;
`Commission::LimiterOptionsProcessor` computing in a preceding stage and persisting). **Size**: XS
per file, three files.

**Micro-step 2 — read-time race against an in-progress BE-6 write**

`Commission::AuxiliaryOptionsProcessor` reads `aggregated_modifiers` for the reading incentive's
bound variables while a DIFFERENT, EARLIER stage's BE-6 write for the SAME variable could
theoretically still be finishing (the stage-completion `Computation` gate prevents a LATER stage's
producer from starting until the earlier stage's consumer fan-out is fully `done?` — so by the time
BE-7's read runs, every earlier-stage BE-6 write for that variable has already committed). This is
the same cross-stage serialization already established in BE-6's micro-step 1 — no new hazard here,
only a confirmation that the ordering guarantee BE-7 depends on (reading only after the writing
stage completed) is the same guarantee that already governs the whole pipeline's stage sequencing.
**Verify**: a test with an indicator-stage-written auxiliary value read by a ranking-stage rule,
asserting the fresh value (not the frozen-snapshot default) is what the rule evaluates against.
**Size**: S.

**Micro-step 3 — the byte-identical-options regression test**

`TASKS.md`'s criterion "A plan with no auxiliary variable produces byte-identical options hashes to
today" is directly testable and low-risk: `Commission::AuxiliaryOptionsProcessor` should return
`{}` when the incentive/plan has no bound auxiliary variable, so `.merge({})` is a no-op.
**Size**: XS.

## Trade-offs surfaced

| Approach for BE-6's write | Pros | Cons | Source |
|---|---|---|---|
| `upsert`/`upsert_all` with `ON CONFLICT DO UPDATE` (as `TASKS.md` states) | Row-level atomicity for the insert-or-update outcome; no `RecordNotUnique` on first-write races | Skips all three `AggregatedIndicator` validations and every `ApplicationRecord` cache callback; does NOT protect the computed sum from a concurrent sibling's write (lost-update risk stands) | ActiveRecord source (`relation.rb:824-828`); PostgreSQL docs (`sql-insert.html`) |
| `transaction { AggregatedIndicator.lock.find_or_create_by(...); ...; save! }` (the `reward.rb` precedent) | Validations and callbacks fire (Query Discipline Rule 1 default); row lock closes the intra-stage lost-update race for an EXISTING row; matches an existing in-repo pattern for the same class of problem | First-ever-row race still raises `RecordNotUnique` on the loser (tolerated via Sidekiq retry, since `AggregatedIndicator` has no `rescue_unique_constraint`); one extra round trip (lock, then read, then write) vs a single upsert statement | `app/models/reward.rb:61-75`; `app/models/application_record.rb:28` (module included, but not declared on this model) |
| `find_or_create_by` + `update` with no lock (a literal reading of "the write is an upsert" as ActiveRecord-first but unlocked) | Simplest code; fires callbacks/validations | Does NOT close the lost-update race at all — this is the shape the research shows is insufficient despite "recompute-not-increment" | This spike's synthesis of the Sidekiq + PostgreSQL findings above |

## What remains uncertain

- Whether a genuine concurrent-writers test (two real threads/connections racing on one
  `aggregated_modifiers` row) is achievable in this repository's test setup, or whether the lock's
  correctness has to be asserted by code inspection plus trust in PostgreSQL's own documented
  `FOR UPDATE` semantics. Not found: an existing spec in this repository that tests a genuine
  cross-connection race (the `reward.rb` locking methods were read for their code and comments, not
  for their spec file, which this spike did not open).
- The exact join path needed to scope `PlanVariable.where(plan_id: plan_ids).count`
  (`app/models/calendar_audit.rb:30`) to exclude auxiliary variables — `PlanVariable`'s own schema
  was not re-opened in this spike to confirm whether a `type`/role column exists on that table or
  whether the exclusion must go through `joins(:variable)`.
- Whether 4Shark's engineers consider the callback/cache-population gap (micro-step 2 of BE-6) worth
  fixing, or whether the performance-only cost (a cache miss forcing a live query on every
  `IndicatorOptionsProcessor` read of a materialized auxiliary variable) is acceptable as-is.

## Suggested options for main and the engineer

- **Option A** — adopt the `reward.rb` locking precedent (`transaction { lock.find_or_create_by;
  ...; save! }`) as BE-6's write shape. Keeps the write on plain ActiveRecord (Query Discipline
  Rule 1's default), closes the intra-stage lost-update race for existing rows, and follows an
  established in-repo pattern rather than introducing a new one.
- **Option B** — keep `upsert_all`/`upsert` as `TASKS.md` currently implies, and add a SEPARATE
  serialization primitive around the read-compute-write sequence (e.g. a Postgres advisory lock
  keyed on `(user_commission_id, variable_id)`, acquired before the SUM and released after the
  upsert) to close the race without giving up the single-statement upsert. No advisory-lock gem or
  precedent exists in this codebase today, so this is more code than Option A for the same
  guarantee.
- **Option C** — accept the residual lost-update risk as documented, on the argument that the
  window is narrow (only intra-stage, only when 2+ rules of the same stage bind the same variable)
  and revisit if it is ever observed in practice. This trades a known, sourced correctness gap for
  less implementation work; § Decision Authority's reversibility gate would not obviously cover this
  choice, since a silently wrong commissioning number is the exact failure class `PLAN.md` itself
  calls out as one "the payroll cannot tolerate" (`PLAN.md:213`).

(No recommendation among these — the evidence shows the gap and the two closing shapes; the
engineer chooses.)
