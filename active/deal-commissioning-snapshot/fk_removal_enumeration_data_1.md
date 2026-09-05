# Auxiliary — FK-removal change surface (raw enumeration)

Referenced from `PLAN-SPIKE.md`. Every entry below is a read or write of `commissioning.deal` /
`deal.commissionings` / the `commissionings.deal_id` column / a `joins(:deal)` scope, found by
grepping `app/app` and `app/lib` (backend) and `app-webclient/src` (frontend), with file:line and
a verbatim excerpt. Each site must be repointed to read through `CommissionedDeal` before
`commissionings.deal_id` is dropped (Phase 4 / CONTRACT).

Search commands run (backend): `grep -rn "\.deal\." --include="*.rb"`, `grep -rln "belongs_to
:deal\b"`, `grep -rn "joins(:deal)"`, `grep -rn "deal_id"`, `grep -rn "\.deal\b"`, `grep -rn
"\.commissionings\b"`. Search commands run (frontend): `grep -rn "deal {"`,
`grep -rn "commissionings"` under `app-webclient/src`.

## A. Model-level associations and scopes (backend)

1. **`app/app/models/commissioning.rb:6`** — the association itself.
   ```ruby
   belongs_to :deal, optional: true, inverse_of: :commissionings
   ```
   Removed in Phase 4, replaced by `belongs_to :commissioned_deal, optional: true, inverse_of: :commissioning`.

2. **`app/app/models/commissioning.rb:19`** — `collaborative_deals` scope, `joins(:deal)`.
   ```ruby
   scope :collaborative_deals, -> { joins(:deal).where.not('deals.deal_collaboration_id': nil) }
   ```
   Consumed by `CommissioningGraphqlResolver` (`with_collaborative_deals: true`). Repoint to
   `joins(:commissioned_deal).where.not('commissioned_deals.deal_collaboration_id': nil)`. Requires
   `deal_collaboration_id` to be a cached column on `commissioned_deals` — **not** in the engineer's
   original cache-field list (scalars / association captures / active / fields); discovered here as
   a required addition (see PLAN-SPIKE.md § "Additional cached column discovered by the enumeration").

3. **`app/app/models/commissioning.rb:37`** — `without_collaborative_deals` scope, `joins(:deal)`.
   ```ruby
   scope :without_collaborative_deals, -> { joins(:deal).where('deals.deal_collaboration_id': nil) }
   ```
   Same repoint and same dependency on caching `deal_collaboration_id`.

4. **`app/app/models/deal.rb:14`** — the reverse association, and the destroy cascade.
   ```ruby
   has_many :commissionings, dependent: :destroy, inverse_of: :deal
   ```
   This is the cascade exercised in production by `company/cleansing/deal_consumer.rb:12`
   (`deal.destroy!`). Removed in Phase 4, replaced by `has_many :commissioned_deals, dependent:
   :restrict_with_exception, inverse_of: :deal` — see PLAN-SPIKE.md § "Destroy-cascade requirement"
   for why `:restrict_with_exception` (a safety net) rather than `:destroy` (circular-destroy risk).

## B. GraphQL exposure (backend)

5. **`app/app/graphql_types/commissioning_graphql_type.rb:4-5`**.
   ```ruby
   field :deal, DealGraphqlType, null: true
   field :deal_id, ID, null: true
   ```
   `field :deal` resolves via graphql-ruby's default method call (`commissioning.deal`) — this is
   the field EVERY frontend query below actually hits. Both fields are removed once the frontend
   reads exclusively through the new `commissioned_deal` field (added in Phase 1/EXPAND, alongside
   the old ones — dual-read window).

6. **`app/app/graphql_types/deal_graphql_type.rb:7`**.
   ```ruby
   field :commissionings, [CommissioningGraphqlType], null: true
   ```
   The reverse GraphQL exposure (`Deal.commissionings`, live association). No confirmed frontend
   caller found (searched `app-webclient/src` for a `commissionings` field nested under a `deal`/
   `Deal` root query — none found; every `commissionings` occurrence in the frontend is a root-level
   query, not nested under `deal`). Kept only for symmetry with the association; removed in Phase 4
   alongside `deal.rb:14`, or earlier if confirmed genuinely unused.

7. **`app/app/graphql_resolvers/commissioning_graphql_resolver.rb:13-19`** — the `withCollaborativeDeals`
   GraphQL argument, driving items 2–3 above.
   ```ruby
   option(:with_collaborative_deals, type: Boolean) do |scope, with_collaborative_deals|
     if with_collaborative_deals
       scope.collaborative_deals
     else
       scope.without_collaborative_deals
     end
   end
   ```
   No change needed here itself — it calls the scopes named in A.2/A.3, which are what change.

## C. Backend read sites — `deal_commissioning.deal` (direct association read)

8. **`app/app/work_books/commission_work_book/deal_work_sheet.rb:56`** — the "Prêmio" (commission)
   XLSX export, one worksheet per commission.
   ```ruby
   deal = Deal.with_uncached_connection { deal_commissioning.deal }
   ```
   Reads `deal.product`, `deal.client`, `deal.date`, `deal.value`, `deal.external_id` afterward
   (lines 64-84) — every one of these is exactly the class of field the incident showed can have
   drifted since calculation. Repoint to `deal_commissioning.commissioned_deal` and its cached
   columns.

9. **`app/app/work_books/plan_slice_commission_work_book/deal_work_sheet.rb:49`** — the plan-slice
   variant of the same export.
   ```ruby
   deal = Deal.with_uncached_connection { deal_commissioning.deal }
   ```
   Reads `deal.date`, `deal.value` (lines 55-57). Same repoint.

## D. Backend reads of the `deal_id` column directly (not via the association)

10. **`app/app/models/commission.rb:142-149`** — `Commission#deals_count`.
    ```ruby
    def deals_count
      @deals_count ||=
        user_commissions
          .joins(:commissionings)
          .where('commissionings.type': 'DealCommissioning')
          .select('distinct commissionings.deal_id')
          .count
    end
    ```
    Raw SQL column reference (`commissionings.deal_id`) inside `select`. Breaks the moment the
    column is dropped. Repoint: join through `commissioned_deals` and select
    `'distinct commissioned_deals.deal_id'`.

11. **`app/app/models/partial_commission.rb:89-96`** — identical shape, `PartialCommission#deals_count`.
    ```ruby
    def deals_count
      @deals_count ||=
        user_commissions
          .joins(:commissionings)
          .where('commissionings.type': 'DealCommissioning')
          .select('distinct commissionings.deal_id')
          .count
    end
    ```
    Same repoint.

12. **`app/app/models/user_commission.rb:31-37`** — identical shape, `UserCommission#deals_count`.
    ```ruby
    def deals_count
      @deals_count ||=
        commissionings
          .where('commissionings.type': 'DealCommissioning')
          .select('distinct commissionings.deal_id')
          .count
    end
    ```
    Same repoint (this one has no explicit `.joins(:commissionings)` since `commissionings` is
    already the base scope — the join to `commissioned_deals` still has to be added).

13. **`app/app/work_books/commission_work_book/deal_work_sheet.rb:51`** and
    **`app/app/work_books/plan_slice_commission_work_book/deal_work_sheet.rb:44`** — ordering by the
    raw column.
    ```ruby
    user_commission.commissionings.deals.order(:deal_id).pluck(:id)
    ```
    `order(:deal_id)` sorts the exported rows by which deal they belong to. Once `deal_id` is gone
    from `commissionings`, this needs `.joins(:commissioned_deal).order('commissioned_deals.deal_id')`
    or an equivalent ordering key (e.g. `commissioned_deal_id`, if the report's grouping doesn't
    genuinely require ordering by the deal's own id — not decided here, see PLAN-SPIKE.md open
    questions).

14. **`app/app/workers/deal_incentive/consumer.rb:70-89`** — the write path itself (already quoted in
    the previous spike's aux file, repeated here for the FK-removal angle).
    ```ruby
    deal_commissioning =
      DealCommissioning.with_uncached_connection do
        DealCommissioning.find_or_initialize_by(user_commission_id: user_commission.id, rule_id: rule_id, deal_id: deal_id)
      end

    deal_commissioning.value = deal_value
    # ...
    deal_commissioning.payment_type_id = payment_type_id
    deal_commissioning.user_payment_type_commission_id = user_payment_type_commission.id
    DealCommissioning.with_uncached_connection { deal_commissioning.save! }
    ```
    `find_or_initialize_by(..., deal_id: deal_id)` finds the existing row by the SAME natural key
    (`user_commission_id`, `rule_id`, `deal_id`) that the DB-level unique index
    `commissionings_unique_deal_index` enforces (see item 16). Once `deal_id` leaves this table, the
    lookup must go through `commissioned_deals` — see PLAN-SPIKE.md § "Consumer.rb write-path
    change" for the decided replacement shape.

15. **`app/app/graphql_types/commissioning_graphql_type.rb:5`** — `field :deal_id, ID, null: true`
    (already listed as item 5, cross-referenced here as a `deal_id`-column read too, since
    graphql-ruby resolves it via `commissioning.deal_id`, a direct column read).

## E. Database constraints keyed on the `deal_id` column

16. **`app/db/schema.rb:456-460`** — the two partial unique indexes, both predicated on
    `deal_id`'s NULL-ness.
    ```ruby
    t.index ["deal_id"], name: "index_commissionings_on_deal_id"
    t.index ["rule_id", "user_commission_id"], name: "commissionings_unique_period_index", unique: true, where: "(deal_id IS NULL)"
    t.index ["user_commission_id", "rule_id", "deal_id"], name: "commissionings_unique_deal_index", unique: true, where: "(deal_id IS NOT NULL)"
    ```
    `commissionings_unique_period_index` enforces one row per `(rule_id, user_commission_id)` among
    the 4 non-deal `Commissioning` subtypes (`deal_id IS NULL` today is equivalent to `type <>
    'DealCommissioning'`, confirmed by `deal_incentive/consumer.rb:70-72` always setting `deal_id`).
    `commissionings_unique_deal_index` enforces one row per `(rule_id, user_commission_id, deal_id)`
    for `DealCommissioning` rows — this is the invariant "the same deal is never commissioned twice
    for the same rule and user_commission." **Both indexes are structurally destroyed the moment the
    `deal_id` column is dropped** — this is not optional cleanup, Postgres will not let the column
    be dropped while an index still references it. See PLAN-SPIKE.md § "Uniqueness-invariant
    requirement" for the decided replacement shape (a `type`-predicated index staying on
    `commissionings`, and a denormalized `(rule_id, user_commission_id, deal_id)` unique index moving
    to `commissioned_deals`).

## F. Frontend — GraphQL queries reading `commissioning { deal { ... } }`

Search: `grep -rn "deal {" app-webclient/src --include="*.ts"`, filtered to the four sites nested
under a `commissionings(...)` root query (as opposed to `userDealHistories { deal {...} }` or
`collaborativeDeals { collaborations { deal {...} } }`, which read a *different* FK — `UserDealHistory
belongs_to :deal` and a collaboration's own `deal` association respectively — and are **out of
scope** for this Commissioning→Deal removal; confirmed by reading their surrounding context).

17. **`app-webclient/src/app/user-commission/show/user-commission-show.component.ts:453-474`** —
    `getDealCommissionings()`, the query the engineer's brief named directly.
    ```ts
    nodes {
      deal {
        client { name }
        date
        dealCollaboration { collaborativeDeal { unitaryValue } value }
        description
        externalId
        fields { output variable { name } }
        installment
        value
      }
      dealId
      money
      points
      rule { description value }
    }
    ```
    Note `dealCollaboration { ... }` here — reads `Deal.dealCollaboration`, not itself a cached
    field in the engineer's brief (see PLAN-SPIKE.md open questions).

18. **`app-webclient/src/app/user-commission/show/user-commission-show.component.ts:348-369`** —
    `getCollaborativeDealCommissionings()`, same component, the collaborative-deal variant.
    ```ts
    nodes {
      deal {
        client { name }
        date
        dealCollaboration { collaborativeDeal { id unitaryValue } value }
        description
        externalId
        fields { output variable { name } }
        value
      }
      dealId
      money
      points
      rule { description value }
    }
    ```

19. **`app-webclient/src/app/statement/statement-show/statement-show.component.ts:354-382`** —
    `ListCollaborativeDealCommissionings` query.
    ```ts
    nodes {
      deal {
        date
        dealCollaboration { collaborativeDeal { id unitaryValue } value }
        description
        externalId
        value
      }
      dealId
      money
      points
      rule { value }
    }
    ```

20. **`app-webclient/src/app/statement/statement-show/statement-show.component.ts:429-458`** —
    `ListDealCommissionings` query.
    ```ts
    nodes {
      deal {
        date
        description
        externalId
        fields { output variable { name } }
        id
        value
      }
      dealId
      money
      points
      rule { value }
    }
    ```

**Confirmed out of scope** (read, but a different FK entirely — not `Commissioning.deal`):

- `app-webclient/src/app/user-history/user-history-show/user-history-show.component.ts:156` —
  `userDealHistories { nodes { deal { id, date, value, type } } }` — reads `UserDealHistory belongs_to
  :deal` (`app/app/models/user_deal_history.rb`), unrelated to `Commissioning`.
- `app-webclient/src/app/collaborative-deal/show/collaborative-deal-show.component.ts:54-57` —
  `collaborativeDeals { nodes { collaborations { deal { description soldPrice } } } }` — reads a
  collaboration's own `deal` association, unrelated to `Commissioning`.

## G. Specs (not enumerated line-by-line — follow-on work at implementation time)

- 8 spec files reference `deal_id` under `app/spec` (`grep -rl "deal_id" --include="*_spec.rb"
  app/spec`); none of them are `Commissioning`-scoped — they test `Deal` itself (`deal_field_spec.rb`,
  `deal_dataset_spec.rb`, `deal_indexation_batch_spec.rb`, `deal_eligibility_spec.rb`, the
  `deals_controller`/`deals/fields_controller` request specs). Not part of this FK-removal surface.
- `app/spec/models/commissioning_spec.rb` most likely exercises the `collaborative_deals` /
  `without_collaborative_deals` scopes (item 2/3) directly — confirmed present in
  `app/spec/models/` alongside `deal_commissioning_spec.rb`; not opened in this pass (spec content
  not read — flagged for the implementation phase, not a design input).
- No `factory :deal_commissioning` exists — only `factory :commissioning` (`app/spec/factories/
  commissionings.rb`), instantiated with `type:` and no `deal_id` trait. A `commissioned_deal`
  factory/trait will be needed at implementation time; not designed here.

## H. Existing "DealCache" naming — confirmed unrelated, cited to justify the chosen name

- `app/app/workers/user_commission/deal_cache_consumer.rb:17-34` and
  `app/app/workers/user_payment_type_commission/deal_cache_consumer.rb` — "DealCache" already names
  a **different** concept in this codebase: caching the AGGREGATE `deal_money`/`deal_points` sums
  onto `UserCommission`/`UserPaymentTypeCommission`, not a per-deal field snapshot.
  ```ruby
  deal_money =
    UserPaymentTypeCommission.with_uncached_connection do
      user_commission.user_payment_type_commissions.sum(:deal_money)
    end
  # ...
  user_commission.update(deal_money: deal_money, deal_points: deal_points, ...)
  ```
  Naming the new entity `DealCache` would collide with this existing vocabulary — one more reason
  `CommissionedDeal` is the name carried into `PLAN-SPIKE.md`, alongside it matching the
  `AggregatedIndicator` (past-participle + noun) naming idiom.
