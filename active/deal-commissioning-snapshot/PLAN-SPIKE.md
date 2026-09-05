# PLAN-SPIKE — Deal Commissioning Snapshot (Intermediate Entity)

> Repositories: `app` (Rails backend), `app-webclient` (Angular front)
> Auxiliary: `fk_removal_enumeration_data_1.md` — full FK-removal change surface, file:line + verbatim excerpts
> Prior research (kept as background, superseded by this design): `deal_snapshot_columns_data_1.md` —
> the enumerated set of deal inputs the calculation consumes, still valid as the source of the
> cache-field list below.

This is a **decided design** — the engineer chose the direction described here. This document
grounds it against the codebase, enumerates everything the change touches, and sequences the
rollout. It does not present alternatives to the chosen direction; where a genuinely open
question remains (a point the decided design does not settle), it is called out explicitly as
such, not as a design option.

## Objective

A commission calculation reads the **live** deal at processing time (`DealIncentive::Consumer`);
when the deal later changes or is deactivated, the value stored on `commissionings` and the value
the front displays both diverge from what was actually calculated. The engineer decided to close
this by introducing a new entity, `CommissionedDeal`, between `Commissioning` and `Deal`:

- `CommissionedDeal` holds a full cache of the deal's updatable fields, captured at the moment
  `DealIncentive::Consumer` builds the `DealCommissioning` row.
- `CommissionedDeal` carries the deal relationship itself — `Commissioning` no longer points at
  `Deal` directly.
- The front (`app-webclient`) reads deal data for commission-detail display exclusively from
  `CommissionedDeal`, never from the live `Deal`.
- The direct `Commissioning belongs_to :deal` foreign key is removed once every reader has moved
  off it.

This is a schema change touching a table with a decade of history
(`db/migrate/2016/09/20160905190939_create_commissionings.rb` is the table's origin, per the prior
spike) and an unknown-but-plausibly-large row count (not queried in this pass — no DB access), so
it is executed as an **expand/contract** rollout, never a single migration.

## Scope

### In scope

- A new `commissioned_deals` table and `CommissionedDeal` model, modeled on the aggregator idiom
  already in the codebase (`AggregatedIndicator`/`IndicatorAggregation`).
- Repointing `DealIncentive::Consumer` to populate `CommissionedDeal` on every new calculation.
- A backfill of every existing `DealCommissioning` row, using the deal's **current** state (the
  engineer's own call — see § "Backfill design").
- Repointing every backend and frontend reader currently going through `Commissioning.deal` /
  `Deal.commissionings` / the `commissionings.deal_id` column (the full enumeration in the
  auxiliary file).
- Dropping `commissionings.deal_id` and the `Commissioning belongs_to :deal` association once the
  above are done.

### Out of scope (carried over from the prior research, unchanged)

- The `deal_options`/`metric_options` block in `consumer.rb:21-32` — not `Deal`/`DealField` state,
  not part of this cache.
- The 4 non-deal `Commissioning` subtypes (`LimiterCommissioning`, `IndicatorCommissioning`,
  `RankingCommissioning`, `RedemptionCommissioning`) — confirmed deal-independent.
- `Plan#deals_for`'s producer-time exclusion of disabled deals — this plan records what was seen,
  it does not change which deals are seen.

## The aggregator pattern — what is being copied, and why

The engineer's instruction was to model `CommissionedDeal` on the existing indicator-aggregator
idiom. Four files carry that idiom: `AggregatedIndicator`, `IndicatorAggregation`,
`PreAggregatedIndicator`, `PreIndicatorAggregation` (all read in full this pass).

**What the idiom actually is**, read across those four files:

- **Naming**: a past-participle prefix on the noun it wraps — `Aggregated` + `Indicator`,
  `PreAggregated` + `Indicator`. `Commissioned` + `Deal` follows the identical shape. This also
  settles the naming instruction — "not snapshot" — without inventing a new convention.
- **Every association is `optional: true` + `inverse_of:`**, with no exception, e.g.
  `app/app/models/aggregated_indicator.rb:4-6`:
  ```ruby
  belongs_to :user_commission, optional: true, inverse_of: :aggregated_indicators
  belongs_to :variable, optional: true, inverse_of: :aggregated_indicators
  has_many :indicator_aggregations, inverse_of: :aggregated_indicator, dependent: :destroy
  ```
- **The join/child side declares `dependent: :destroy` toward the parent's `has_many`**, e.g.
  `app/app/models/aggregated_indicator.rb:6` (`has_many :indicator_aggregations, ...,
  dependent: :destroy`) and, symmetrically, `IndicatorAggregation belongs_to :aggregated_indicator,
  foreign_key: :aggregated_modifier_id, inverse_of: :indicator_aggregations, optional: true`
  (`app/app/models/indicator_aggregation.rb:6`) — the FK-holding side never re-declares
  `dependent:` back toward its parent. This single-direction rule is exactly what this plan's own
  destroy-cascade requirement (below) needs, and the aggregator pattern is direct precedent for it.
- **`self.table_name =` is used only where the class name and the physical table diverge for
  historical reasons** (`aggregated_modifiers` for `AggregatedIndicator`,
  `modifier_aggregations` for `IndicatorAggregation` — `app/app/models/aggregated_indicator.rb:19`,
  `app/app/models/indicator_aggregation.rb:12`). `commissioned_deals` is a **new** table with no
  legacy name to inherit, so `CommissionedDeal` needs no `self.table_name=` — class name and table
  name match from the start.
- **`cache_ttl` is used only where the record itself is read-through-cached by key**
  (`app/app/models/aggregated_indicator.rb:17`, `cache_ttl 8.hours`) — not applicable here:
  `CommissionedDeal` is written once per `DealCommissioning` and read through its owning
  `Commissioning`/`DealCommissioning`, never looked up by a `cache_id`-style key of its own.

**What does NOT carry over**: `AggregatedIndicator`/`IndicatorAggregation` model a
**many-to-many, computed-value** relationship (one `AggregatedIndicator` aggregates SEVERALS
`Indicator` rows across time intervals via the `IndicatorAggregation` join table, then
`#calculate!` derives a single `value`). `CommissionedDeal` is a **one-to-one, copied-value**
relationship (one `CommissionedDeal` per `DealCommissioning`, holding a direct copy of one `Deal`'s
fields — nothing is aggregated or computed). So `CommissionedDeal` takes the aggregator idiom's
**naming, association style, and destroy-direction discipline**, and does not need a separate
join table (`IndicatorAggregation`'s role) or a `#calculate!` method (`AggregatedIndicator`'s
role) — those exist to solve a many-to-many/computed problem this feature does not have.

## Decided associations

```ruby
# app/app/models/commissioning.rb
belongs_to :commissioned_deal, optional: true, dependent: :destroy, inverse_of: :commissioning
```

```ruby
# app/app/models/commissioned_deal.rb
class CommissionedDeal < ApplicationRecord
  belongs_to :deal, optional: true, inverse_of: :commissioned_deals
  belongs_to :rule, optional: true, inverse_of: :commissioned_deals
  belongs_to :user_commission, optional: true, inverse_of: :commissioned_deals
  has_one :commissioning, foreign_key: :commissioned_deal_id, inverse_of: :commissioned_deal

  self.inheritance_column = nil
end
```

```ruby
# app/app/models/deal.rb
has_many :commissioned_deals, dependent: :restrict_with_exception, inverse_of: :deal
```

Three grounded decisions embedded in this shape, each forced by something already in the
codebase rather than a style preference:

1. **`rule_id`/`user_commission_id` are denormalized onto `commissioned_deals`.** See §
   "Uniqueness-invariant requirement" — without them, the DB-level constraint the removal deletes
   (`commissionings_unique_deal_index`) cannot be re-expressed on a single table.
2. **`self.inheritance_column = nil`** — the cache includes a `type` column (the deal's own
   `Sale`/`Call`/`CreditRecovery`/`ServiceSale` type, per the field list below), and Rails treats a
   column literally named `type` as the STI discriminator unless told otherwise
   ([apidock: `inheritance_column`](https://apidock.com/rails/ActiveRecord/Base/inheritance_column/class);
   worked example at
   [dev.julianpinzon.com](https://dev.julianpinzon.com/customising-single-table-inheritance-mapping-in-active-record)).
   Pattern not found in this project for this exact technique — confirmed absent by
   `grep -rn "self.inheritance_column" app/app` returning nothing; this is the first use.
3. **`dependent: :destroy` appears on exactly one side of the `Commissioning`/`CommissionedDeal`
   pair** — see the next section.

## Destroy-cascade requirement (discovered, not optional)

Two real, currently-exercised call sites drive `Commissioning` destruction today, and both go
through the SAME column (`deal_id`) that is being removed:

- **The frequent path** — `app/app/workers/commission/consumer.rb:24`, run on **every** commission
  (re)calculation:
  ```ruby
  Commissioning.with_uncached_connection { user_commission.commissionings.destroy_all }
  ```
  Every recalculation wipes all prior commissionings before `DealIncentive::Consumer` and its
  siblings rebuild them. Once `CommissionedDeal` exists as a separate row, this call — unchanged —
  would leave the corresponding `commissioned_deals` rows orphaned on every single recalculation
  cycle unless the destroy cascades.
- **The rare path** — `app/app/workers/company/cleansing/deal_consumer.rb:9-12`, a real production
  flow (company data cleansing):
  ```ruby
  deal = Deal.with_uncached_connection { Deal.find(deal_id) }
  # ...
  Deal.with_uncached_connection { deal.destroy! }
  ```
  Today this is caught by `Deal has_many :commissionings, dependent: :destroy`
  (`app/app/models/deal.rb:14`). After the redesign, `Deal` no longer has a direct FK to
  `commissionings` at all — the link is two hops away (`Deal → CommissionedDeal → Commissioning`).

**Why not `dependent: :destroy` on both hops**: declaring it on `CommissionedDeal has_one
:commissioning, dependent: :destroy` **and** on `Commissioning belongs_to :commissioned_deal,
dependent: :destroy` simultaneously creates a circular destroy — a Deal-driven destroy would
reach `CommissionedDeal`, whose `before_destroy` dependent-destroy would reach `Commissioning`,
whose `after_destroy` dependent-destroy would try to destroy the very `CommissionedDeal` row
already mid-destroy. This is a well-known ActiveRecord hazard (mutual `dependent: :destroy`
across a 1:1 pair) and is avoided here by construction, not by convention: only
`Commissioning belongs_to :commissioned_deal, dependent: :destroy` carries the declaration.

**The decided resolution**:

- `Commissioning belongs_to :commissioned_deal, dependent: :destroy` — a plain, single-direction
  ActiveRecord `belongs_to` cascade (Rails fires `dependent: :destroy` on a `belongs_to` in an
  `after_destroy` callback: the owning record is deleted first, then its associate). This alone
  makes the frequent path (`commission/consumer.rb:24`) correct with **zero code change at that
  call site** — `destroy_all` already invokes `.destroy` per record, which already triggers this
  callback.
- The rare path (`company/cleansing/deal_consumer.rb`) requires an explicit code change, because
  once `Deal` no longer has a direct FK to `Commissioning`, nothing automatically reaches the
  `Commissioning` row from the `Deal` side anymore. The fix: before `deal.destroy!`, destroy each
  of the deal's `commissioned_deals`' owning `commissioning` first (which, via the rule above,
  destroys the `commissioned_deal` with it). `Deal has_many :commissioned_deals, dependent:
  :restrict_with_exception` then acts as a safety net — it raises loudly if that explicit step
  were ever skipped or incomplete, instead of failing on a silent orphan or a foreign-key
  violation deep in Postgres.

This code change to `company/cleansing/deal_consumer.rb` belongs to Phase 4 (CONTRACT) — it only
becomes load-bearing once `Deal has_many :commissionings, dependent: :destroy` (the `deal_id`-based
one) is removed. During Phase 1–3 the old cascade still exists and still works unmodified.

## Cache field set

Carried over from the prior research pass (`deal_snapshot_columns_data_1.md`), which enumerated
every literal input `DealIncentive::Consumer` passes into `Rule#calculate`
(`app/app/workers/deal_incentive/consumer.rb:47-67`), plus the two updatable-field sources the
engineer separately named (the REST/GraphQL update surfaces and the activity API):

| Column | Source | Type |
|---|---|---|
| `date` | `deals.date` | `date` |
| `description` | `deals.description` | `text` |
| `external_id` | `deals.external_id` | `string, limit: 8000` |
| `installment` | `deals.installment` | `integer` |
| `originated_at` | `deals.originated_at` | `date` |
| `quantity` | `deals.quantity` | `decimal(28,6)` |
| `sold_price` | `deals.sold_price` | `decimal(28,6)` |
| `status_key` | `deal.status.key` (resolved association value, not the raw `status_id` FK) | `string` |
| `type` | `deals.type` | `string, limit: 8000` |
| `work_hours` | `deals.work_hours` | `decimal` |
| `disabled_at` | `deals.disabled_at` (the "active" state; `nil` ⇔ active — `app/app/models/application_record.rb:20-26`) | `datetime` |
| `client_external_id` | `deal.client.external_id` | `string` |
| `client_name` | `deal.client.name` | `citext` |
| `product_external_id` | `deal.product.external_id` | `string` |
| `product_name` | `deal.product.name` | `citext` |
| `user_identifier` | `deal.user.primary_identifier_value` (`app/app/models/user.rb:419-423`) | `string` |
| `deal_collaboration_id` | `deals.deal_collaboration_id` | `bigint` — see next section |
| `fields` | `{ variable.key => deal_field.formated_value }`, one entry per `plan.variables.deals` (`app/app/workers/deal_incentive/consumer.rb:33-45`) | `jsonb` |

**`status` is cached as the resolved key string, not the `status_id` foreign key.** The
calculation itself never uses `status_id` — it uses `deal.status.key`
(`app/app/workers/deal_incentive/consumer.rb:52,58`), the same treatment already given to
`client_name`/`product_name` (resolved display values, not raw FKs). Caching `status_id` instead
would still require a live join to `Status` at display time to show anything human-readable,
which reopens exactly the live-read problem this feature exists to close (`Status` rows are far
more stable than `Deal` rows, but the point of the cache is to freeze what was actually seen, not
to freeze a pointer to something that is usually stable).

**`fields` stores the already-formatted value (`DealField#formated_value`), not the raw
`DealField.value`.** `formated_value` calls `variable.data_type.format(value)`
(`app/app/models/deal_field.rb:23-25`); if the raw value were stored and reformatted at DISPLAY
time, a company that later reconfigures `variable.data_type` would silently reinterpret every
historical snapshot under the NEW type — reintroducing a version of the exact drift this feature
removes. Storing the value already resolved at calculation time closes that.

### Additional cached column discovered by the enumeration

`deal_collaboration_id` was **not** in the engineer's original field list (scalars / association
captures / active / fields). It surfaced from enumerating the FK-removal surface: `Commissioning`'s
`collaborative_deals` / `without_collaborative_deals` scopes
(`app/app/models/commissioning.rb:19,37`) filter on `deals.deal_collaboration_id`, and this is
what the `CommissioningGraphqlResolver`'s `with_collaborative_deals` argument
(`app/app/graphql_resolvers/commissioning_graphql_resolver.rb:13-19`) uses to split "collaborative
deal" commissionings from ordinary ones — a real, currently-serving GraphQL query path
(`app-webclient` items 18–19 in the auxiliary file). Without caching this column, those two
scopes cannot be repointed off `deals` at all. It is listed in the table above as a required
column, not an option.

## Uniqueness-invariant requirement (discovered, not optional)

`db/schema.rb:456-460` carries two partial unique indexes, both predicated on `commissionings.deal_id`:

```ruby
t.index ["rule_id", "user_commission_id"], name: "commissionings_unique_period_index", unique: true, where: "(deal_id IS NULL)"
t.index ["user_commission_id", "rule_id", "deal_id"], name: "commissionings_unique_deal_index", unique: true, where: "(deal_id IS NOT NULL)"
```

`deal_id IS NULL` is true today for exactly the 4 non-deal `Commissioning` subtypes (a
`DealCommissioning` row always has `deal_id` set — `deal_incentive/consumer.rb:72`). Dropping the
column destroys **both** indexes structurally — Postgres refuses to drop a column an index still
references — not just the deal-specific one. The decided replacement:

- `commissionings_unique_period_index` → re-expressed as a `type`-predicated index on the SAME
  table (no `deal_id` involved at all): unique on `(rule_id, user_commission_id)` where
  `type <> 'DealCommissioning'`.
- `commissionings_unique_deal_index` → the invariant it enforces ("the same deal is never
  commissioned twice for the same rule and user_commission") moves to `commissioned_deals`, as a
  unique index on `(rule_id, user_commission_id, deal_id)` where `deal_id IS NOT NULL` — which is
  exactly why `rule_id`/`user_commission_id` are denormalized onto `commissioned_deals` (§ Decided
  associations, point 1): a cross-table composite unique constraint has no direct Postgres
  expression without a trigger, so the natural key is duplicated onto the table that needs to
  enforce it, mirroring how `commissioning.rb`'s own `TYPES`-shaped table already carries
  subtype-specific columns that are `NULL` for other subtypes.

### Consumer.rb write-path change

`DealIncentive::Consumer`'s lookup (`app/app/workers/deal_incentive/consumer.rb:70-73`) currently
finds the existing row by the natural key the DB constraint enforces:

```ruby
DealCommissioning.find_or_initialize_by(user_commission_id: user_commission.id, rule_id: rule_id, deal_id: deal_id)
```

Once `deal_id` is gone from `commissionings`, the equivalent lookup runs against
`commissioned_deals` directly (which now carries the full natural key):

```ruby
commissioned_deal =
  CommissionedDeal.with_uncached_connection do
    CommissionedDeal.find_or_initialize_by(user_commission_id: user_commission.id, rule_id: rule_id, deal_id: deal_id)
  end
```

and the owning `DealCommissioning` is found/created through `commissioned_deal.commissioning`
(via the `has_one`) rather than through the old `find_or_initialize_by(..., deal_id:)` on
`Commissioning` itself. This is a Phase 4 (CONTRACT) change to `consumer.rb` — during Phase 1–2 the
old lookup keeps working unmodified (`deal_id` still exists on `commissionings`), and the new
`commissioned_deal` is populated alongside it (dual-write).

## FK-removal change surface

Full enumeration, file:line, and verbatim excerpts are in `fk_removal_enumeration_data_1.md`.
Summary by category:

| Category | Count | Representative sites |
|---|---|---|
| Model associations/scopes (backend) | 4 | `commissioning.rb:6,19,37`; `deal.rb:14` |
| GraphQL exposure (backend) | 3 | `commissioning_graphql_type.rb:4-5`; `deal_graphql_type.rb:7`; `commissioning_graphql_resolver.rb:13-19` |
| Direct `deal_commissioning.deal` reads (backend, XLSX export) | 2 | `commission_work_book/deal_work_sheet.rb:56`; `plan_slice_commission_work_book/deal_work_sheet.rb:49` |
| Raw `commissionings.deal_id` column reads (backend) | 5 | `commission.rb:147`; `partial_commission.rb:94`; `user_commission.rb:35`; both `deal_work_sheet.rb` `order(:deal_id)` sites; `consumer.rb:72` |
| DB constraints keyed on `deal_id` | 2 partial indexes | `db/schema.rb:456-460` |
| Frontend GraphQL queries (`commissioning { deal {...} }`) | 4 | `user-commission-show.component.ts:348-369,453-474`; `statement-show.component.ts:354-382,429-458` |
| Confirmed out of scope (different FK) | 2 | `user-history-show.component.ts:156` (`UserDealHistory.deal`); `collaborative-deal-show.component.ts:54-57` (a collaboration's own `deal`) |
| Specs (not enumerated — implementation-time follow-on) | ~8+ files | see auxiliary § G |

Every row in "Direct reads" and "Frontend queries" must be repointed before Phase 4 drops the
column (Phase 3, § below). The two DB constraints are handled as part of the Phase 4 migration
sequence itself, not as application-code repoints.

## Phase sequence (expand/contract)

4Shark's own deployment strategy names this exact shape as the canonical pattern for a
backward-incompatible column change: *"The 4Shark column-migration example is exactly this: (1)
add the new column + write to both (dual write) + backfill the old data via a background job; (2)
move reads to the new column, stop writing the old; (3) drop the old column"*
(`~/.claude/docs/DEPLOYMENT-STRATEGY.md:138`). This feature is that pattern with one extra step
(Phase 2, backfill, run as its own deploy-independent background job) inserted between expand and
contract.

**Why this is not a single deploy**: per the same document's three forcing triggers
(`DEPLOYMENT-STRATEGY.md:141-149`), none of the three literally fires (`Computation` key
derivation is untouched, `DealIncentive::Consumer`'s enqueued-job argument shape
`(commission_id, user_commission_id, rule_id, deal_id, partial)` is untouched, no non-idempotent
step is introduced). What DOES force phasing here is outside that document's three triggers and
specific to this change: **the column being removed (`commissionings.deal_id`) is read by
application code across two repositories** (the enumeration above), and `strong_migrations`
mechanically requires a two-deploy sequence for any column removal regardless
(`self.ignored_columns` deployed first, the `remove_column`/`remove_reference` — always wrapped in
`safety_assured`, since *"it's not possible to add a custom check for remove_column
operations"* — deployed second; [ankane/strong_migrations](https://github.com/ankane/strong_migrations),
[AppSignal: Good Database Migration Practices](https://blog.appsignal.com/2024/03/20/good-database-migration-practices-for-your-ruby-on-rails-app-using-strong-migrations.html)).
So the column-removal half of this feature is phased on its own terms, independent of whether any
of the three §6 triggers apply.

### Phase 1 — EXPAND (backend only; one deploy)

Schema (each item below is one migration, generated via `bin/rails generate migration`, per
`~/.claude/docs/RAILS-MIGRATIONS.md`; `create_table` and `add_reference` each count as one
conceptual operation under that doc's "When NOT to split" carve-out):

1. `create_table :commissioned_deals` — every column from the field-set table above, plus
   `t.references :deal, null: true, foreign_key: true, index: true`,
   `t.references :rule, null: false, foreign_key: true, index: true`,
   `t.references :user_commission, null: false, foreign_key: true, index: true`, and the
   replacement unique index:
   ```ruby
   t.index %i[rule_id user_commission_id deal_id], unique: true, where: "(deal_id IS NOT NULL)", name: "commissioned_deals_unique_deal_index"
   ```
   A fresh `CREATE TABLE` takes no lock on any existing table — no `disable_ddl_transaction!`
   needed.
2. `add_reference :commissionings, :commissioned_deal` — on a table this old and (presumably) this
   large, the safe form from `~/.claude/docs/RAILS-MIGRATIONS.md`'s own table applies
   (`add_reference ..., index: true, foreign_key: true` → `index: { algorithm: :concurrently },
   foreign_key: { validate: false }` + `disable_ddl_transaction!`), followed by a **separate**
   migration:
3. `validate_foreign_key :commissionings, :commissioned_deal`.

Application code (same deploy):

- `CommissionedDeal` model, associations as decided above.
- `Commissioning belongs_to :commissioned_deal, optional: true, dependent: :destroy, inverse_of:
  :commissioning` added **alongside** the still-present `belongs_to :deal`.
- `Deal has_many :commissioned_deals, inverse_of: :deal` added **alongside** the still-present
  `has_many :commissionings, dependent: :destroy` (no `dependent:` on `commissioned_deals` yet —
  see § Destroy-cascade requirement; it only needs to be present, not the destroy owner, until
  Phase 4).
- `DealIncentive::Consumer` (`consumer.rb:69-90`) changed to **dual-write**: still builds/saves
  `DealCommissioning` exactly as today (`deal_id` populated), and additionally builds/saves a
  `CommissionedDeal` with every field from the table above, linked via `deal_commissioning
  .commissioned_deal = commissioned_deal` (or the reverse, per the `has_one`). Both the old and new
  path are live from this point forward for every NEW calculation.

**No frontend change in this phase.** `CommissioningGraphqlType` gains a new
`field :commissioned_deal, CommissionedDealGraphqlType, null: true` (additive, does not touch
`field :deal`) so the data is queryable, but nothing in `app-webclient` reads it yet.

### Phase 2 — BACKFILL (background job; no deploy of its own; runs after Phase 1 ships)

Populates `CommissionedDeal` for every **existing** `DealCommissioning` row, using the deal's
current state. The engineer's own framing: this is *"no worse than today's live read, and the
forensic safety is the date, not the value"* — a backfilled row's `created_at` will read as the
backfill's run time, not the original calculation time, and that is accepted; what must not
happen is losing the timestamps that already exist on other tables (§ below).

**Design, modeled on `app/app/workers/plan_statement/migration/producer.rb` +
`consumer.rb`** — the codebase's own precedent for a cursor-driven, self-re-enqueuing backfill
over a table with no known upper bound on row count:

```ruby
# app/app/workers/plan_statement/migration/producer.rb:8-20 (the precedent, unmodified)
def perform(cursor = nil)
  plan_statements = PlanStatement.order(:id)
  plan_statements = plan_statements.where('id > ?', cursor) if cursor.present?
  plan_statement_ids = PlanStatement.with_uncached_connection { plan_statements.limit(10_000).pluck(:id) }

  return if plan_statement_ids.empty?

  next_cursor = plan_statement_ids.last
  computation = Computation.new('plan_statement_migration')
  computation.increment_queue(by: plan_statement_ids.count)
  arguments = plan_statement_ids.map { |plan_statement_id| [plan_statement_id, next_cursor] }
  Sidekiq::Client.push_bulk('class' => PlanStatement::Migration::Consumer, 'args' => arguments)
end
```

The Consumer processes one `commissioning_id` per job (pure IDs-only, per
`~/.claude/docs/DATA-PROCESSING.md`), and its last-to-finish job in a batch calls the Producer
again for the next page (`computation.pending?` check, `plan_statement/migration/consumer.rb:20-22`)
— this bounds concurrency to one 10,000-row page in flight at a time, never the whole table.
`CommissionedDeal::Migration::Producer`/`Consumer` follow the identical shape:

- **Producer**: `Commissioning.where(type: 'DealCommissioning').where.not(deal_id:
  nil).where(commissioned_deal_id: nil).order(:id)`, cursor-paged in batches of 10,000, same
  `Computation` key/re-enqueue mechanics.
- **Consumer** (per `commissioning_id`): read-only against `Deal`/`Client`/`Product`/`User`/
  `DealField` (all through `with_uncached_connection`, per `~/.claude/docs/DATA-ACCESS.md`); build
  and save ONE new `CommissionedDeal` row with the current field values; link it to the
  `Commissioning` via `commissioning.update(commissioned_deal_id: commissioned_deal.id)`.
  `where(commissioned_deal_id: nil)` in the Producer's scope makes a re-run of the whole backfill
  idempotent — an already-backfilled row is simply excluded from the next page.

### Phase 3 — REPOINT READERS (backend + frontend; can ship as separate deploys, in any order,
as long as all of them land before Phase 4)

Every site in the FK-removal enumeration's "Direct reads" and "Frontend queries" categories is
changed to read `commissioned_deal` instead of `deal`:

- Backend: `commission_work_book/deal_work_sheet.rb:56`, `plan_slice_commission_work_book/
  deal_work_sheet.rb:49` (read `deal_commissioning.commissioned_deal` instead of
  `deal_commissioning.deal`); `commission.rb:147`, `partial_commission.rb:94`,
  `user_commission.rb:35` (join through `commissioned_deals`, select
  `'distinct commissioned_deals.deal_id'`); both `order(:deal_id)` sites (order via the join or
  drop the ordering requirement — open question, see below).
- Frontend: all four `commissioning { deal {...} }` query blocks in
  `user-commission-show.component.ts` and `statement-show.component.ts` become
  `commissioning { commissionedDeal {...} }`, reading the SAME field names the cache stores
  (`clientName`, `productName`, `date`, `installment`, `soldPrice`, `fields`, …) instead of
  navigating to the live `deal`.

**Deploy order — backend before frontend, always**: a backend deploy that only ADDS
`field :commissioned_deal` is backward-compatible on its own (Phase 1 already shipped it); a
frontend deploy that reads a GraphQL field the backend does not yet expose breaks immediately. So
within Phase 3, backend repoints (which touch no schema, pure Ruby read-path changes) can ship
independently and in advance; the frontend deploy switching the four query blocks must ship no
earlier than the backend deploy that added `field :commissioned_deal` (Phase 1) — which has
already happened by the time Phase 3 starts, so ordering constraint is satisfied by construction,
not by extra coordination.

### Phase 4 — CONTRACT (backend only; **two** deploys, forced by `strong_migrations`)

**Deploy 4a**:

- `Commissioning`: `self.ignored_columns += ['deal_id']`.
- `Deal`: replace `has_many :commissionings, dependent: :destroy` with `has_many
  :commissioned_deals, dependent: :restrict_with_exception, inverse_of: :deal` (§ Destroy-cascade
  requirement).
- `app/app/workers/company/cleansing/deal_consumer.rb`: before `deal.destroy!`, explicitly destroy
  each of the deal's `commissioned_deals`' owning `commissioning` (§ Destroy-cascade requirement).
- `DealIncentive::Consumer`: switch the write path to the `CommissionedDeal`-first lookup (§
  Consumer.rb write-path change above) — stop writing `deal_id` on new `DealCommissioning` rows
  (it is about to disappear).
- Migrations (each a separate file, per one-action-per-migration):
  1. `add_index :commissionings, %i[rule_id user_commission_id], unique: true, where: "(type <>
     'DealCommissioning')", algorithm: :concurrently, name: 'commissionings_unique_non_deal_index'`
     + `disable_ddl_transaction!` — the REPLACEMENT index goes in FIRST, so the invariant it
     enforces is never unenforced even for an instant.
  2. `remove_index :commissionings, name: 'commissionings_unique_period_index', if_exists: true`.
  3. `remove_index :commissionings, name: 'commissionings_unique_deal_index', if_exists: true`.

**Deploy 4b** (a later, separate deploy — never the same one as 4a, per the ignored_columns
sequence `strong_migrations` requires):

4. `remove_reference :commissionings, :deal` (drops `deal_id` and
   `index_commissionings_on_deal_id` together, per RAILS-MIGRATIONS.md's "add_reference is one
   conceptual operation" carve-out applied symmetrically to its removal), wrapped in
   `safety_assured` — required unconditionally for `remove_column`/`remove_reference`, since *"it's
   not possible to add a custom check for remove_column operations"*
   ([ankane/strong_migrations](https://github.com/ankane/strong_migrations)). This is the ONE
   `safety_assured` use in this feature, and it is the canonical legitimate case
   `~/.claude/docs/RAILS-MIGRATIONS.md` names: a real, known, unavoidable risk (removing a column
   running code may still reference) accepted deliberately, not a bypass of a safe alternative
   that exists.

Between 4a and 4b, `Commissioning belongs_to :deal` (the model association) is also removed from
`commissioning.rb` — it can go in either 4a or 4b; 4b is the natural place since it is the deploy
that makes the column's removal final.

## Timestamp-preservation requirement (hard requirement)

`commissionings` carries **no timestamp columns at all** (`db/schema.rb:447-465` — no
`created_at`/`updated_at`) — this was the finding that explained why the original incident could
only be diagnosed via the DEAL's `updated_at`, never the commissioning's own. Two consequences for
this design:

1. **Nothing in this feature may touch `deals.created_at`/`deals.updated_at`.** Every access to
   `Deal` in the backfill (Phase 2) and in `DealIncentive::Consumer`'s dual-write (Phase 1) is a
   **read only** — `Deal.with_uncached_connection { Deal.find(...) }`, never `.save`, `.touch`, or
   `.update` on a `Deal` instance. The technique is absence of any write call, not a flag to
   suppress `touch`: nothing in the backfill Consumer or the dual-write path calls a persistence
   method on `Deal` at all, so there is no `touch: false` or `record_timestamps = false` to
   remember — the guarantee holds because the write surface simply never includes `Deal`.
2. **The `commissioned_deals` table's OWN `created_at`/`updated_at` are the NEW forensic signal
   this feature adds** (`commissionings` never had one; `commissioned_deals` will, via the
   standard `t.timestamps`). For a row created during normal operation (Phase 1 onward), `created_at`
   is the actual calculation time — genuinely useful going forward. For a row created during the
   backfill (Phase 2), `created_at` is the backfill's run time, not the original calculation time
   — this is the gap the engineer explicitly accepted ("no worse than today's live read"). Nothing
   in the backfill should attempt to reconstruct or backdate `created_at` for these rows (there is
   no reliable source for the true value, and a guessed date is worse than an honest "we don't
   know, this row's data reflects state as of the backfill run").
3. **The Phase 4 migrations touch no row data whatsoever** — `remove_index`/`add_index`/
   `remove_reference` are schema-only DDL operations; PostgreSQL does not rewrite or touch
   per-row timestamp columns for an index drop/add or (for a simple column removal without a
   table rewrite) a column drop. The risk in this feature was never the DDL — it is any
   `update_all`/`touch`/bulk-`save` a hand-written backfill script might reach for. None of the
   backfill design above uses `update_all` (§ Phase 2 uses `commissioning.update(...)` per record,
   a scalar-field update on a table that structurally has no timestamp to disturb) or `touch`
   anywhere.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **Phase 4b (`remove_reference :commissionings, :deal`) is the highest-blast-radius step** — every one of the ~11+ enumerated read sites must be confirmed repointed before this deploy, or the missed site breaks in production with no schema-level warning beforehand (an unconverted `deal_commissioning.deal` call simply raises `NoMethodError`/`ActiveRecord::UnknownAttributeError` at runtime, not at deploy time). | A missed site is a runtime error in production, not a deploy-time failure. | Treat the FK-removal enumeration (this document + the auxiliary file) as the acceptance checklist for Phase 4b — every row confirmed repointed (code review against the list) before that migration ships. The `Commissioning.ignored_columns` step in 4a gives one full deploy cycle of runway to catch a missed site (the column still exists in the DB during 4a, so a missed read site fails ONLY if it also tries to write `deal_id`, which Consumer.rb stops doing in the same deploy). |
| Backfill (Phase 2) runs over an unknown, possibly multi-million-row table with no row count queried in this pass (no DB access). | The `plan_statement/migration` precedent bounds concurrency to 10,000 rows in flight, but the TOTAL wall-clock time to backfill an unknown row count is unestimated. | Not researched further here — the engineer or a subsequent pass with DB access should confirm `Commissioning.where(type: 'DealCommissioning').count` before scheduling Phase 2; the Producer/Consumer design itself does not need to change regardless of the answer (it self-paces either way). |
| `commissionings` is described in the prior spike as a "hot, high-write table" — the `add_reference` in Phase 1 and the two `remove_index`/`add_index` operations in Phase 4a run against it while calculation traffic is live. | Migration lock contention or a slow migration blocking calculation writes. | Every schema change in Phase 1 and 4a uses the safe form (`algorithm: :concurrently` + `disable_ddl_transaction!` + `foreign_key: { validate: false }` followed by a separate `validate_foreign_key`) per `~/.claude/docs/RAILS-MIGRATIONS.md`; run the productive-app Sidekiq queue check (`scripts/sidekiq-queue-check.sh`) before each deploy per `~/.claude/docs/DEPLOYMENT-STRATEGY.md`. |
| The circular-destroy hazard identified in § Destroy-cascade requirement is a genuine ActiveRecord footgun, not a hypothetical — getting the direction wrong (declaring `dependent: :destroy` on both `Commissioning belongs_to :commissioned_deal` and `CommissionedDeal has_one :commissioning`) would surface as a double-destroy attempt only when a `Deal` is actually destroyed, which is the RARE path (`company/cleansing/deal_consumer.rb`) — meaning a wrong implementation could pass ordinary testing (which exercises the frequent recalculation path far more) and only fail during a cleansing run. | A latent bug that only manifests during company data cleansing — a sensitive, infrequent, hard-to-safely-retry operation. | The single-direction rule (§ Destroy-cascade requirement) is stated as a hard constraint in this document specifically so it survives into `BLUEPRINT.md`/implementation; a test exercising `company/cleansing/deal_consumer.rb` against a `Deal` with at least one `commissioned_deal` should be part of the Phase 4a test plan. |
| `deal_collaboration_id` (§ Additional cached column discovered) is a genuinely new addition to the cache-field list the engineer specified — not confirmed with the engineer before this document was written. | If not added, the `collaborative_deals`/`without_collaborative_deals` GraphQL filtering (a real, currently-serving query path) cannot be repointed at all, blocking Phase 3/4 for those two call sites specifically. | Listed as a required column in this document (not an option); flagged again below as an open question purely for the engineer's explicit confirmation, since it was discovered rather than specified. |

## Open questions for the engineer

- **`deal_collaboration_id` on `commissioned_deals`** — discovered as structurally required (see
  above), not in the original field list. Confirm it should be added; if not, the
  `collaborative_deals`/`without_collaborative_deals` scopes need a different resolution not
  designed in this pass.
- **`dealCollaboration { collaborativeDeal { unitaryValue } value }`**, read by three of the four
  frontend query sites (items 17–19 in the auxiliary file) alongside `deal {...}` — this is
  `Deal.dealCollaboration`, a live association read that is NOT part of the specified cache-field
  set. Whether this also needs caching (same drift risk, different data) or is intentionally left
  reading the live deal (a collaborative deal's split value is arguably a different kind of fact
  than the calculation inputs) is not decided here.
- **`order(:deal_id)` in the two export worksheets** (auxiliary file item 13) — whether the export
  genuinely needs ordering BY the deal's own id (in which case the join-based ordering is the
  fix) or whether ordering by `commissioned_deal_id`/insertion order would serve the same purpose
  with no join needed.
- **Actual row count of `commissionings` / `DealCommissioning` rows** — not queried in this pass
  (no DB access); needed to size the Phase 2 backfill's wall-clock expectations and to confirm the
  `add_reference` in Phase 1 genuinely needs the concurrent/deferred-validation safe form (it does
  regardless, per policy, but the actual number informs how urgently Phase 2 needs to run).
- **`app/app/graphql_types/deal_graphql_type.rb:7`'s `field :commissionings`** — no frontend
  caller was found reading it nested under a `deal`/`Deal` root query; confirm it is genuinely
  unused before removing it in Phase 4, or leave it in place if some caller exists outside the
  searched paths.

## Sources

- `app/app/models/commissioning.rb:1-71` — `Commissioning`/`DealCommissioning`, the association
  and both `joins(:deal)` scopes being removed
- `app/app/models/deal.rb:1-202` — `Deal`, the `has_many :commissionings, dependent: :destroy`
  cascade being replaced, `disabled_at`/`enabled?` (via `ApplicationRecord`)
- `app/app/models/application_record.rb:20-26` — the `enabled`/`disabled_at` mechanism ("active")
- `app/app/models/deal_commissioning.rb:1-5` — the STI subtype
- `app/app/models/aggregated_indicator.rb:1-125`, `app/app/models/indicator_aggregation.rb:1-13`,
  `app/app/models/pre_aggregated_indicator.rb:1-88`, `app/app/models/pre_indicator_aggregation.rb:1-11`
  — the aggregator idiom being copied (naming, `optional: true`+`inverse_of:` everywhere,
  single-direction `dependent: :destroy`, `self.table_name=` only for legacy-named tables)
- `app/app/workers/deal_incentive/consumer.rb:1-99` — the write path this feature dual-writes into
  (Phase 1) and then repoints (Phase 4)
- `app/app/workers/commission/consumer.rb:1-53` — the frequent recalculation path
  (`commissionings.destroy_all`, line 24) that the destroy-cascade requirement is grounded in
- `app/app/workers/company/cleansing/deal_consumer.rb:1-21` — the rare Deal-destroy path
  (`deal.destroy!`, line 12) that the destroy-cascade requirement is grounded in
- `app/app/workers/plan_statement/migration/producer.rb:1-23`,
  `app/app/workers/plan_statement/migration/consumer.rb:1-26` — the cursor-driven,
  `Computation`-paced backfill precedent this feature's Phase 2 copies
- `app/app/workers/deal_dataset/migration/producer.rb`, `company_producer.rb`, `consumer.rb` — a
  second existing `<domain>/migration/producer.rb`+`consumer.rb` precedent, confirming this is an
  established 4Shark idiom for one-time data migrations, not a one-off
- `app/app/workers/user_commission/deal_cache_consumer.rb:1-44`,
  `app/app/workers/user_payment_type_commission/deal_cache_consumer.rb` — confirmed a DIFFERENT
  existing "DealCache" concept (aggregate money/points caching), grounding why `CommissionedDeal`
  and not `DealCache` is the chosen name
- `app/app/graphql_types/commissioning_graphql_type.rb:1-19`,
  `app/app/graphql_types/deal_graphql_type.rb:1-54` — current GraphQL exposure being extended
  (Phase 1) then trimmed (Phase 4)
- `app/app/graphql_resolvers/commissioning_graphql_resolver.rb:1-20` — the
  `with_collaborative_deals` argument driving the two `joins(:deal)` scopes
- `app/app/scopes/commissioning_scope.rb:1-19` — confirmed no additional deal-based filtering here
- `app/app/work_books/commission_work_book/deal_work_sheet.rb:1-119`,
  `app/app/work_books/plan_slice_commission_work_book/deal_work_sheet.rb:1-72` — the two backend
  XLSX-export sites reading `deal_commissioning.deal` directly
- `app/app/models/commission.rb:142-149`, `app/app/models/partial_commission.rb:89-96`,
  `app/app/models/user_commission.rb:31-37` — the three `deals_count` methods reading
  `commissionings.deal_id` via raw SQL `select`
- `app/app/models/user.rb:419-423` — `User#primary_identifier_value`, the source of the cached
  `user_identifier` field
- `app/app/models/client.rb:1-30`, `app/app/models/product.rb:1-30` — the source models for
  `client_name`/`client_external_id`/`product_name`/`product_external_id`
- `app/app/models/deal_field.rb` (via the prior spike's citation, `formated_value` at lines 23-25)
  — the source of the `fields` jsonb cache and why the formatted (not raw) value is stored
- `app/app/controllers/api/v3/deals_controller.rb:92-156,278-305` — the REST update surface
  defining which deal fields are "updatable" (`UpdateDealParams`, `deal_params_on_update`)
- `app/app/graphql_mutations/update_deal_graphql_mutation.rb:1-56` — the GraphQL update surface
  (adds `type`/`user_id` beyond the REST surface)
- `app/app/controllers/api/v3/deals/activity_controller.rb:1-66` — the activity (enable/disable)
  API, the mechanism behind the cached `disabled_at`/"active" field and the exact API the original
  incident's deals were toggled through
- `app/db/schema.rb:447-465` (`commissionings`), `:706-748` (`deals`) — current schemas, the
  absence of timestamps on `commissionings`, and the two partial unique indexes being replaced
- `app-webclient/src/app/user-commission/show/user-commission-show.component.ts:330-404,417-509` —
  two of the four frontend query sites
- `app-webclient/src/app/statement/statement-show/statement-show.component.ts:330-458` — the other
  two frontend query sites
- `app-webclient/src/app/user-history/user-history-show/user-history-show.component.ts:140-159`,
  `app-webclient/src/app/collaborative-deal/show/collaborative-deal-show.component.ts:40-70` —
  confirmed out-of-scope `deal {...}` reads (different FK)
- `app-webclient/src/app/commissioning/commissioning.model.ts:1-63` — front-end `Commissioning`
  model (`deal`/`dealId` fields to be replaced by `commissionedDeal`)
- `~/.claude/docs/RAILS-MIGRATIONS.md` — one-action-per-migration, the "When NOT to split"
  carve-out for `create_table`/`add_reference`, the safe-form table for `add_reference`/
  non-concurrent `add_index`, `safety_assured` as the deliberate-known-risk override
- `~/.claude/docs/DEPLOYMENT-STRATEGY.md:132-176` — the phased-vs-single decision framework, the
  four-layer zero-downtime model, the canonical expand/contract column-migration example (line 138)
- `~/.claude/docs/DATA-PROCESSING.md`, `~/.claude/docs/DATA-ACCESS.md` — IDs-only processing,
  `with_uncached_connection`, join decomposition in workers
- [apidock.com — `ActiveRecord::Base.inheritance_column`](https://apidock.com/rails/ActiveRecord/Base/inheritance_column/class) —
  `self.inheritance_column = nil` to opt a `type` column out of STI
- [dev.julianpinzon.com — Customising Single Table Inheritance mapping](https://dev.julianpinzon.com/customising-single-table-inheritance-mapping-in-active-record) —
  worked example of the same technique
- [github.com/ankane/strong_migrations](https://github.com/ankane/strong_migrations) — column
  removal always requires `safety_assured` ("it's not possible to add a custom check for
  remove_column operations")
- [blog.appsignal.com — Good Database Migration Practices for Your Ruby on Rails App using Strong Migrations](https://blog.appsignal.com/2024/03/20/good-database-migration-practices-for-your-ruby-on-rails-app-using-strong-migrations.html) —
  the two-deploy `ignored_columns` → `remove_column` sequence
- See auxiliary: `fk_removal_enumeration_data_1.md` — full FK-removal enumeration with file:line
  and verbatim excerpts, organized by category (A–H)
- See prior research: `deal_snapshot_columns_data_1.md` — the original enumerated set of deal
  inputs the calculation consumes, still the source of the cache-field list in this document
