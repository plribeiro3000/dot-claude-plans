# PLAN — Commcenter pre-go-live production data wipe

## Context

Commcenter goes live tomorrow. Before go-live, the test/training sales-and-commission
data loaded during onboarding must be removed from production so the platform starts
clean. Two stores are in scope:

- **App RDS** — backend `app-shared-001` (multi-tenant), `company_id = 2077`
- **Integrator MongoDB** — `integrator-commcenter` (single-customer stack)

Org structure (people + hierarchy + grouping + onboarding config) is **kept**; the
transactional sales/commission layer is **deleted**.

> **Multi-tenant warning.** `app-shared-001` hosts multiple companies. **Every** app
> query and deletion MUST be scoped through `company = Company.find(2077)` and its
> associations (`company.deals`, `company.user_histories`, …). A top-level
> `Model.where(...)` / `delete_all` without the company scope would destroy other
> tenants' production data. This is the single highest risk in this operation.

> **Deviation from the no-delete pattern (acknowledged).** `API_DOMAIN.md:76-103` states
> the platform never deletes records, only deactivates them, because the historical
> record is part of the product. This wipe is a **physical destroy**, which is the
> deliberate and correct choice for a pre-go-live reset (there is no historical record
> to preserve yet, and re-integration with the same external IDs requires the rows to be
> gone, not deactivated — `API_DOMAIN.md:96-97`). This is a one-off operational exception,
> not an API-contract operation.

---

## Term → model mapping (verified against code + locales on `origin/master`)

| Engineer's term (pt-BR) | Model(s) | Evidence |
|---|---|---|
| todas as parciais | `PartialCommission` | `config/locales/pt-BR/models/partial_commission.yml:27` → `'Parcial'` |
| todas as premiações | `Commission` + `UserCommission` | `commission.yml:32-33` → `'Premiação'/'Premiações'`; `user_commission.yml:8-9` → `'Premiação Individual'` |
| todas as declarações de resultado | `Statement` | engineer-confirmed; `statement.yml:17-18` → `'Declaração'` |
| todas as declarações de regra | `PlanStatement` | engineer-confirmed; `plan_statement.yml:12-13` → `'Declaração'` |
| todos os planos | `Plan` | `app/models/plan.rb` |
| todas as deals | `Deal` | `app/models/deal.rb` |
| todas as metas | `Goal` (UserGoal/GroupGoal STI) | `app/models/goal.rb` |
| todos os indicadores | `Indicator` (table `modifiers`) | `app/models/indicator.rb` |
| todos os clientes | `Client` (sales-domain, NOT tenant Company) | `app/models/client.rb` |
| todos os produtos | `Product` | `app/models/product.rb` |
| (added) pagamentos | `Payment` + `CommissionPayment` | engineer added — "apagar pagamentos, caso exista" |
| (added) User History | `UserHistory` (+ all `user_*_history` links) | engineer added — required to unblock deals/goals/declarations |

> **Correction logged:** an earlier mapping pass guessed "premiações" = `Incentive`. The
> locale proves "premiação" = `Commission`/`UserCommission`. `Incentive` is the
> incentive-campaign *config*, NOT "premiação". See scope-boundary item B below.

---

## Scope

### DELETE (in scope)

Top-level: `UserHistory`, `CommissionPayment`, `Payment`, `Statement`, `Commission`,
`UserCommission`, `PartialCommission`, `Deal`, `Client`, `Product`, `Indicator`,
`PlanStatement`, `Plan`, `Goal`.

Dragged in automatically via `dependent: :destroy` cascades (not separately listed but
will be destroyed): `commission_goals`, `commissionings`, `campaigns`, `approvals`,
`metrics`, `deal_fields`, `plan_participations`, `plan_variables`, `incentivations`
(the Plan↔Incentive link only), `goal_plans`, `requirements`, `indicator_aggregations`,
`accumulated_deals`, `aggregated_indicators`, `rankings`, `reward_transactions`,
acceptments, and the `user_*_history` link rows.

### KEEP (out of scope)

`User` (+ `Seat`/hierarchy + `SeatHistory`), `Group`, `Groupification` (+ their
histories), and the onboarding/config layer the go-live needs: `Subsidiary`, `Variable`,
`Calendar`/`Period`, `Role`, `PaymentType`.

> **UserHistory cascade is safe (verified).** `user_history.rb:8-15` —
> `UserHistory has_many :user_seat_histories / :user_groupification_histories /
> :user_deal_histories / … dependent: :destroy`. Each `user_*_history` is a pure link
> (`user_seat_history.rb:4-5`, `user_groupification_history.rb:4-5`,
> `user_deal_history.rb:4-5` — only `belongs_to`, no `dependent:`). Destroying
> `UserHistory` removes only the link rows; `Seat`, `Group`, `Groupification`, `Deal`,
> `Goal` are untouched.

### ⚠️ SCOPE BOUNDARY — confirm on review (defaulted conservatively; nothing executes until you approve)

- **A. Onboarding config kept.** Defaulting to KEEP `Subsidiary`, `Variable`,
  `Calendar`/`Period`, `Role`, `PaymentType` — the go-live config depends on these.
  Your "apaguemos todo o resto" was read as "all transactional data", not "all config".
  Flip any to DELETE if intended.
- **B. `Incentive` kept.** "premiações" resolved to `Commission`, and "declaração de
  regra" to `PlanStatement` — neither is `Incentive`. Defaulting to KEEP `Incentive`
  (+ its `Rule`s). Deleting all `Plan`s removes the `incentivation` links, so kept
  `Incentive`s become standalone config. Say so if `Incentive`/`Rule` should also go.

---

## Deletion order (app) — derived from the production `Company::Cleansing` chain

The production full-wipe workflow `Company::Cleansing::Processor`
(`app/workers/company/cleansing/`) is the authoritative, tested ordering. It is a
hardcoded linear chain `UserHistoryProducer → … → Finalizer` where the **`Finalizer`
destroys the Company itself** (`finalizer.rb`) and the chain also wipes
users/groups/variables/subsidiaries. **We cannot run the Processor** (it would destroy
the company and the kept config) and we cannot start mid-chain (it auto-advances to the
`Finalizer`). Instead we **invoke each in-scope producer individually**, in this order,
and neutralize the chain's auto-advance with an inflated `Computation` counter — the
chosen execution technique, detailed in § Execution technique below. This reuses the
production-tested consumer destroy logic (which already clears the restrict-blockers in
the right order) and runs in parallel via Sidekiq.

Order (each step is company-scoped, batched, clears restrict-blockers, then destroys):

| # | Resource | Clear first (restrict_* blockers) | Cascade footprint on destroy |
|---|---|---|---|
| 1 | `UserHistory` | — | all `user_*_history` link rows (unblocks 6,9,10,12) |
| 2 | `CommissionPayment` → `Payment` | — | payment chain |
| 3 | `Statement` | (user_statement_histories already gone via #1) | acceptment |
| 4 | `Commission` (+`UserCommission`) | — | user_commissions → eligibility_periods → deal_eligibilities/eligible_indicators, accumulated_deals, aggregated_indicators, commissionings, rankings, statement, reward_transaction |
| 5 | `PartialCommission` | — | commission_goals, deal_indexation_batches, user_commissions |
| 6 | `Deal` | `deal_eligibilities`, `fields` (DealField), deal document enrollments, commissionings | commissionings |
| 7 | `Client` | `deal_eligibilities` (restrict_with_error), `metrics` | deals[gone], incentives*, metrics |
| 8 | `Product` | `deal_eligibilities` (restrict_with_error), `metrics` | deals[gone], metrics |
| 9 | `Indicator` | `eligible_indicators`, indicator document enrollments | indicator_aggregations, pre_indicator_aggregations |
| 10 | `PlanStatement` | (user_plan_statement_histories already gone via #1) | acceptment, portable, user_field_snapshots |
| 11 | `Plan` | — | partial_commissions[gone], commissions[gone], plan_statements[gone], campaigns, approvals, plan_participations, plan_variables, incentivations, audits, rollbacks, goal_plans, acceptment |
| 12 | `Goal` | (user_goal_histories already gone via #1) | commission_goals, goal_plans, requirements |

> **Why the explicit blocker-clears matter.** `deal_eligibilities` is
> `restrict_with_exception` on `Deal` (`deal.rb:15`) and `restrict_with_error` on
> `Client`/`Product` (`client.rb:10`, `product.rb:10`); `eligible_indicators` is
> `restrict_with_exception` on `Indicator` (`indicator.rb:8`). These are owned by
> `EligibilityPeriod` (`eligibility_period.rb:9-10`), which is owned by both
> `UserCommission` (deleted at #4) **and** `User` (kept — `user.rb:57`). Because some
> eligibility_periods hang off kept Users, destroying user_commissions does **not**
> guarantee all eligibilities are gone — so the Deal/Client/Product/Indicator steps must
> clear `deal_eligibilities`/`eligible_indicators` explicitly (scoped via
> `company.deals` / `company.indicators`) or `Deal.destroy!` / `Indicator.destroy!` will
> raise mid-run. The pre-flight (Phase 2, script 1) counts these empirically.

---

## Integrator reset (`integrator-commcenter`, MongoDB)

Per engineer: clean the `jobs` collection, the `resources` collection, and the
`*_collection` family.

| Target | Model(s) | Note |
|---|---|---|
| `resources` | `Resource` (STI base, `resource.rb`) | `embeds_many :imports` → `embeds_many :requests` — embedded docs go with the parent. integration_status state machine reset by removal. |
| `jobs` | `Job` (`job.rb`) | `has_many :*_collections dependent: :destroy` + `has_one :metric (JobMetric)` |
| collection family | `ClientCollection`, `DealCollection`, `DealExtraFieldCollection`, `GoalCollection`, `GroupCollection`, `GroupificationCollection`, `HierarchyCollection`, `ModifierCollection`, `ProductCollection`, `SubsidiaryCollection`, `UserActivityCollection`, `UserCollection`, `UserFieldCollection`, `UserIdentifierCollection` (+ base `Collection`) | raw extracted staging data per job (`collection.rb`: `raw`, `stream_id`, `page`) |

> Dropping `jobs` via `.destroy` already cascades the `*_collection` family
> (`job.rb:6-20`); clearing all three explicitly also catches any collection orphaned
> from its job. Effect on go-live: the integrator forgets every prior run and every
> Resource's `integrated` state, so the next integration re-pushes everything from
> scratch — which is the intent.
> **Open (non-blocking):** engineer listed jobs/resources/collections but not `imports`
> or `requests` as separate targets — they are **embedded** in `Resource`, so dropping
> `resources` removes them automatically. No separate action needed.

---

## Execution model — three phases, three scripts per bucket (`SCRIPT-DISCIPLINE.md`)

Mutations are **manual**: I generate every script as text; the engineer pastes into
`bin/ecs run app-shared-001` (app) and `bin/ecs run integrator-commcenter` (integrator),
runs it, reports back. Nothing is auto-executed. Scripts use **variables, never
constants**, full English names, `find_each`/pluck-then-iterate per the Data Processing
Pattern, and are always company-scoped on the app side.

- **Phase 1 — Discovery (read-only).** Count every in-scope resource (app, scoped to
  company 2077) and every integrator collection. Confirms the premise and produces the
  baseline the verification phase diffs against. Scripts: `discovery-app.rb`,
  `discovery-integrator.rb` (this folder). **Run these first; report the numbers.**
- **Phase 2 — Execution (per bucket: pre-flight → mutation → verification).**
  - *Bucket A — app transactional wipe.* The mutation is **manual orchestration of the
    production `Company::Cleansing` producers** — see § Execution technique below.
  - *Bucket B — integrator reset* (jobs, resources, collection family).
  - Pre-flight runs after Phase 1 counts are in hand (asserts real numbers + that no
    other job holds the company's `Computation`); verification confirms zeros.
- **Phase 3 — Verification.** Re-count everything in scope; every in-scope count must be
  `0`; kept resources (users, groups, subsidiaries, variables, …) must be unchanged.

---

## Execution technique (Bucket A) — manual producer orchestration with inflated `Computation`

Chosen by the engineer. We reuse the production `Company::Cleansing` consumers (tested
destroy logic) but **drive the sequence by hand**, invoking one producer at a time and
neutralizing the chain's two auto-advance mechanisms.

**The two auto-advance mechanisms (both must be neutralized):**

1. **Consumer chaining.** Every consumer ends with
   `return unless company.computation.done?; NextProducer.perform_async`. `done?` is
   `queue_value == executions_value` (`computation.rb:done?`), both Redis counters keyed
   `…:company_2077` (`company.rb:152` → `Computation.new("company_2077")`).
   → **Neutralized by inflating `queue`** so it never equals `executions`.
2. **Producer empty-branch chaining.** Every producer is
   `if ids.any? { queue+push_bulk } else { NextProducer.perform_async }`
   (`deal_producer.rb`). The `else` fires the next producer when the resource is already
   empty — **independent of `done?`, so inflation does NOT stop it.**
   → **Neutralized by never invoking a producer when its resource count is 0** (check
   first; stop when it zeroes).

**Setup (once, at the start of Bucket A):**

```ruby
company = Company.find(2077)
company.computation.reset_queue
company.computation.reset_executions
company.computation.increment_queue(by: 1_000_000_000)   # >> total records; done? never true
```

> **`Counter` expires in 12h** (`counter.rb:4`, `DEFAULT_EXPIRATION_TIME = 12.hours`).
> If Bucket A spans >12h the inflation evaporates and chaining resumes — re-inflate if a
> long run is paused overnight. (Total real executions must also stay < 1e9 — trivially
> true.)

**Per-resource loop (the mutation), in the producer order below:**

```ruby
# example for one resource; repeat structure per producer in the ordered list
loop do
  break if company.deals.count.zero?                      # never invoke on empty (avoids else-chain)
  Company::Cleansing::DealProducer.perform_async(2077)    # queues up to 10_000; no chain (inflated)
  # wait for the `cleansing` Sidekiq queue + busy set to drain this batch, then re-check
  sleep 5 while Sidekiq::Queue.new('cleansing').size.positive? || Sidekiq::Workers.new.size.positive?
end
```

This handles the `limit(10_000)` batching: with inflation the consumer won't re-invoke
the producer, so we re-invoke it manually each batch, and **break on empty** so the
producer's `else` never chains into a kept resource.

**Producer order (in-scope only — every kept-resource producer is SKIPPED).** Same
relative order as the production chain; each driven to `count == 0` before the next:

1. `UserHistoryProducer` — clears all `user_*_history` links (unblocks deals/goals/declarations)
2. `CommissionPaymentProducer` → 3. `PaymentProducer`  *(pagamentos)*
4. `StatementProducer`  *(declaração de resultado)*
5. `CommissionProducer` → 6. `PartialCommissionProducer`  *(premiações + parciais; clears user_commissions → eligibility_periods → deal_eligibilities/eligible_indicators)*
   — SKIP `PaymentTypeProducer` (KEEP)
7. `CollaborativeDealDocumentEnrollmentProducer` → 8. `CollaborativeDealDocumentProducer` → 9. `CollaborativeDealProducer`
10. `DealDocumentEnrollmentProducer` → 11. `DealFieldEnrollmentProducer` → 12. `DealDocumentProducer` → 13. `DealProducer`  *(deals; enrollments are restrict_with_exception on Deal — must precede)*
14. `ClientProducer` → 15. `ClientDocumentProducer`  *(clientes)*
16. `ProductProducer` → 17. `ProductDocumentProducer`  *(produtos)*
18. `IndicatorDocumentEnrollmentProducer` → 19. `IndicatorDocumentProducer` → 20. `IndicatorProducer`  *(indicadores)*
21. `MetricProducer`
    — SKIP `VariableProducer`, `VariableDocumentProducer` (KEEP)
22. `CampaignProducer`
23. `PlanStatementProducer`  *(declaração de regra)*
24. `PlanProducer`  *(planos)*
    — SKIP `IncentiveDocumentProducer`, `IncentiveProducer`, `RankifierProducer` (KEEP by default — boundary B)
    — SKIP `GroupificationProducer`, `GroupProducer`, `GroupDocumentProducer` (KEEP)
25. `GoalProducer` → 26. `GoalDocumentProducer`  *(metas)*
    — SKIP everything after (Acceptment*, Calendar, PasswordReset, UserIdentifier, Audit, MonthlyUsage, User, UserDocument, Subsidiary) and **NEVER** `Finalizer`

> Acceptments tied to deleted Statements/PlanStatements/Plans cascade automatically
> (`has_one :acceptment dependent: :destroy`); standalone `AcceptmentProducer` is skipped.
> Same for `Audit` (plan audits cascade with the plan).

**Teardown (after Bucket A):** `company.computation.reset_queue;
company.computation.reset_executions` — leave the counter clean so future commission
processing for company 2077 is unaffected.

> **Pre-condition:** no commission/cleansing job may be running for company 2077 during
> the wipe — it shares the `company_2077` Computation counter and the inflation would
> corrupt its progress. commcenter is pre-go-live, so this should hold; confirm in
> pre-flight.

## Deliverable

Per `SCRIPT-DISCIPLINE.md` Rule 4: session closes with one consolidated `.xlsx` in
`~/Downloads/` — per-bucket counts (targeted / pre-flight-passed / deleted / verified),
plain-language outcomes, and any handoffs.

## Operational note

`app-shared-001` deploys are zero-downtime, but check Sidekiq queue depth before running
(the wipe enqueues nothing heavy itself, but the cascades run inline in the runner). The
runner is small; the per-resource batched iteration keeps memory bounded.
