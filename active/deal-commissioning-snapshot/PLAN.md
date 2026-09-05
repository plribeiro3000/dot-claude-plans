# PLAN — CommissionedDeal Intermediate Entity

> Reference: derived from `PLAN-SPIKE.md` and its auxiliary `fk_removal_enumeration_data_1.md`
> (both in this directory). Prior research `deal_snapshot_columns_data_1.md` is retained as the
> source of the cache-field list carried into this plan.
> Repositories: `app` (Rails backend), `app-webclient` (Angular front)

## Objective

`DealIncentive::Consumer` reads the **live** deal at commission-processing time
(`app/app/workers/deal_incentive/consumer.rb:47-67`); when the deal later changes or is
deactivated, both the value stored on `commissionings` and the value the front displays diverge
from what was actually used in the calculation. This plan closes that gap by placing a new
entity, `CommissionedDeal`, between `Commissioning` and `Deal`:

- `CommissionedDeal` holds a full cache of the deal's updatable fields, captured at the moment
  `DealIncentive::Consumer` builds the `DealCommissioning` row.
- `CommissionedDeal` carries the deal relationship itself — `Commissioning` no longer points at
  `Deal` directly.
- `app-webclient` reads deal data for commission-detail display exclusively from
  `CommissionedDeal`, never from the live `Deal`.
- The direct `Commissioning belongs_to :deal` foreign key (`commissioning.rb:6`) is removed once
  every reader has moved off it.

The entity is modeled on the indicator-aggregator idiom already in the codebase
(`AggregatedIndicator`/`IndicatorAggregation`) — see § Chosen approach. Topology becomes
`Commissioning` → `CommissionedDeal` → `Deal`.

`commissionings` is a table with a decade of history
(`db/migrate/2016/09/20160905190939_create_commissionings.rb`) and an unqueried row count, so the
FK removal runs as an **expand/contract** rollout across four phases, never a single migration.

## Scope

### In scope

- A new `commissioned_deals` table and `CommissionedDeal` model, modeled on
  `AggregatedIndicator`/`IndicatorAggregation`.
- Repointing `DealIncentive::Consumer` (`app/app/workers/deal_incentive/consumer.rb`) to
  populate `CommissionedDeal` on every new calculation.
- A backfill of every existing `DealCommissioning` row, using the deal's current state at
  backfill time.
- Repointing every backend and frontend reader currently going through `Commissioning.deal` /
  `Deal.commissionings` / the `commissionings.deal_id` column — the full enumeration in
  `fk_removal_enumeration_data_1.md`.
- Dropping `commissionings.deal_id` and the `Commissioning belongs_to :deal` association once
  every reader above is repointed.

### Out of scope

- The `deal_options`/`metric_options` block in `consumer.rb:21-32` — not `Deal`/`DealField`
  state, not part of this cache.
- The four non-deal `Commissioning` subtypes (`LimiterCommissioning`, `IndicatorCommissioning`,
  `RankingCommissioning`, `RedemptionCommissioning`) — deal-independent, confirmed by
  `deal_incentive/consumer.rb:70-72` always setting `deal_id` on `DealCommissioning` and never on
  the other four.
- `Plan#deals_for`'s producer-time exclusion of disabled deals — this plan records what was
  seen; it does not change which deals are seen.

## Chosen approach

**Direction:** An intermediate entity, `CommissionedDeal`, between `Commissioning` and `Deal`,
carrying a full cache of the deal's updatable fields plus the `Deal`/`Rule`/`UserCommission`
relationships that today live on `commissionings.deal_id` / `rule_id` / `user_commission_id`.

**Rationale:** `CommissionedDeal` is modeled on the indicator-aggregator idiom, per the naming,
association style, and destroy-direction discipline already established by
`AggregatedIndicator`/`IndicatorAggregation`/`PreAggregatedIndicator`/`PreIndicatorAggregation`
(all read in full during research). What carries over from that idiom:

- **Naming**: a past-participle prefix on the noun it wraps — `Aggregated` + `Indicator`,
  `Commissioned` + `Deal` follows the identical shape.
- **Every association is `optional: true` + `inverse_of:`**, no exception —
  `app/app/models/aggregated_indicator.rb:4-6`.
- **The FK-holding side never re-declares `dependent:` back toward its parent** —
  `app/app/models/indicator_aggregation.rb:6` (`belongs_to :aggregated_indicator, ...,
  optional: true`, no `dependent:`), while the parent's `has_many` carries the destroy —
  `aggregated_indicator.rb:6`. This single-direction discipline is direct precedent for this
  plan's own destroy-cascade requirement (§ Technical decisions).
- **`self.table_name =` is used only where the class name and physical table diverge for
  historical reasons** — `commissioned_deals` is a brand-new table with no legacy name to
  inherit, so `CommissionedDeal` needs no `self.table_name=`.

What does NOT carry over: `AggregatedIndicator`/`IndicatorAggregation` model a
many-to-many, computed-value relationship (a join table, a `#calculate!` method).
`CommissionedDeal` is a one-to-one, copied-value relationship — one `CommissionedDeal` per
`DealCommissioning`, holding a direct copy of one `Deal`'s fields, nothing aggregated or
computed. So `CommissionedDeal` takes the idiom's naming, association style, and destroy
discipline only — it needs no join table and no `#calculate!` equivalent.

**Source patterns referenced:**
- `app/app/models/aggregated_indicator.rb:1-125`, `app/app/models/indicator_aggregation.rb:1-13`,
  `app/app/models/pre_aggregated_indicator.rb:1-88`,
  `app/app/models/pre_indicator_aggregation.rb:1-11` — the idiom being copied.
- `app/app/models/commissioning.rb:1-71` — `Commissioning`/`DealCommissioning`, the association
  and both `joins(:deal)` scopes being removed.
- `app/app/models/deal.rb:1-202` — `Deal`, the `has_many :commissionings, dependent: :destroy`
  cascade being replaced.
- `app/app/models/sale.rb:6-8`, `app/app/models/call.rb:6-8` — the STI-subtype `#value`
  implementations the cached `value` column freezes (§ Cache field set).
- `app/app/graphql_types/deal_graphql_type.rb:37` — `field :value, Float`, the computed field the
  worksheets and the front actually read, never `sold_price` directly.
- `app/app/models/application_record.rb:50-65` — `with_uncached_connection`'s actual
  implementation (`connection_pool.with_connection { uncached { ... } }`), the basis for §
  Phase 1's transaction-wrapping requirement.
- `app/app/controllers/api/v3/deals/activity_controller.rb` — the codebase's own precedent for
  an explicit `Deal.transaction do ... end` around multiple writes, copied by § Phase 1's
  dual-write.
- `app/app/workers/deal_incentive/consumer.rb:1-99` — the write path this feature dual-writes
  into (Phase 1) and then repoints (Phase 4).
- `app/app/workers/commission/consumer.rb:1-53` — the frequent recalculation path
  (`commissionings.destroy_all`, line 24) the destroy-cascade requirement is grounded in.
- `app/app/workers/company/cleansing/deal_consumer.rb:1-21` — the rare `Deal`-destroy path
  (`deal.destroy!`, line 12) the destroy-cascade requirement is grounded in.
- `app/app/workers/plan_statement/migration/producer.rb:1-23`,
  `app/app/workers/plan_statement/migration/consumer.rb:1-26` — the cursor-driven,
  `Computation`-paced backfill precedent Phase 2 copies.
- `app/app/workers/user_commission/deal_cache_consumer.rb:1-44`,
  `app/app/workers/user_payment_type_commission/deal_cache_consumer.rb` — the existing,
  unrelated "DealCache" concept (aggregate money/points caching), grounding why
  `CommissionedDeal` and not `DealCache` is the name.
- `~/.claude/docs/RAILS-MIGRATIONS.md`, `~/.claude/docs/OPTIONAL-BELONGS-TO.md`,
  `~/.claude/docs/DATA-PROCESSING.md`, `~/.claude/docs/DATA-ACCESS.md`,
  `~/.claude/docs/DEPLOYMENT-STRATEGY.md`, `~/.claude/docs/BANG-METHOD-WEB-FLOW.md`,
  `~/.claude/docs/CODE-STYLE-RULES.md` — the conventions this plan's execution steps follow.
- [apidock.com — `ActiveRecord::Base.inheritance_column`](https://apidock.com/rails/ActiveRecord/Base/inheritance_column/class),
  [github.com/ankane/strong_migrations](https://github.com/ankane/strong_migrations) — the two
  external references governing, respectively, the `type` column and the two-deploy column
  removal.

## Cache field set

Every column `commissioned_deals` carries, with its source and type, unchanged from
`PLAN-SPIKE.md` § "Cache field set" plus `value` (added during FK-removal enumeration, § below):

| Column | Source | Type |
|---|---|---|
| `date` | `deals.date` | `date` |
| `description` | `deals.description` | `text` |
| `external_id` | `deals.external_id` | `string, limit: 8000` |
| `installment` | `deals.installment` | `integer` |
| `originated_at` | `deals.originated_at` | `date` |
| `quantity` | `deals.quantity` | `decimal(28,6)` |
| `sold_price` | `deals.sold_price` | `decimal(28,6)` |
| `value` | `deal.value` (computed, STI-subtype-dependent — e.g. `Sale#value = sold_price * quantity`, `Call#value = quantity`) | `decimal(28,6)` |
| `status_key` | `deal.status.key` (resolved association value, not the raw `status_id` FK) | `string` |
| `type` | `deals.type` | `string, limit: 8000` |
| `work_hours` | `deals.work_hours` | `decimal` |
| `disabled_at` | `deals.disabled_at` (the "active" state; `nil` ⇔ active — `application_record.rb:20-26`) | `datetime` |
| `client_external_id` | `deal.client.external_id` | `string` |
| `client_name` | `deal.client.name` | `citext` |
| `product_external_id` | `deal.product.external_id` | `string` |
| `product_name` | `deal.product.name` | `citext` |
| `user_identifier` | `deal.user.primary_identifier_value` (`app/app/models/user.rb:419-423`) | `string` |
| `deal_collaboration_id` | `deals.deal_collaboration_id` | `bigint` |
| `fields` | `{ variable.key => deal_field.formated_value }`, one entry per `plan.variables.deals` (`consumer.rb:33-45`) | `jsonb` |

`status_key` and `fields` are stored as **resolved values, not raw pointers**: `status_key` is
the deal's `status.key` string, not `status_id` — the calculation itself never uses `status_id`
(`consumer.rb:52,58`), and caching the raw FK would still require a live join at display time,
reopening the drift this feature closes. `fields` stores `DealField#formated_value`
(`app/app/models/deal_field.rb:23-25`), the already-formatted value — storing the raw value and
reformatting it at display time would let a later change to `variable.data_type` silently
reinterpret every historical record under the new type.

`value` caches the deal's own computed `#value` method, not merely its inputs —
`Sale#value = sold_price * quantity` (`app/app/models/sale.rb:6-8`), `Call#value = quantity`
(`app/app/models/call.rb:6-8`), and each subtype's own implementation. The worksheets and the
front never read `sold_price` for the displayed/exported figure; they read this computed value,
exposed as a distinct `field :value, Float` on `DealGraphqlType` (`deal_graphql_type.rb:37`) and
consumed at `commission_work_book/deal_work_sheet.rb:83`,
`plan_slice_commission_work_book/deal_work_sheet.rb:57`, and all four frontend query sites (§
Phase 3). Caching only `sold_price` and recomputing `value` at display time would show a
different number than was calculated for every non-`Sale` deal type — the exact drift this
feature exists to close. `sold_price` stays in the cache as its own distinct updatable field
regardless — `value`'s presence does not replace it.

`deal_collaboration_id` is a required column discovered by enumerating the FK-removal surface,
not part of the engineer's original scalar/association/active/fields list: `Commissioning`'s
`collaborative_deals` / `without_collaborative_deals` scopes (`commissioning.rb:19,37`) filter on
`deals.deal_collaboration_id`, and the `CommissioningGraphqlResolver`'s
`with_collaborative_deals` argument (`commissioning_graphql_resolver.rb:13-19`) depends on it — a
real, currently-serving GraphQL query path. Without this column, those two scopes cannot be
repointed off `deals` at all.

## Decided associations

```ruby
# app/app/models/commissioning.rb
has_one :commissioned_deal, dependent: :destroy, inverse_of: :commissioning
```

```ruby
# app/app/models/commissioned_deal.rb
class CommissionedDeal < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :commissioning, optional: true, inverse_of: :commissioned_deal
  belongs_to :deal, optional: true, inverse_of: :commissioned_deals
  belongs_to :rule, optional: true, inverse_of: :commissioned_deals
  belongs_to :user_commission, optional: true, inverse_of: :commissioned_deals

  validates :commissioning_id, presence: true
  validates :deal_id, presence: true
  validates :rule_id, presence: true
  validates :user_commission_id, presence: true

  attr_readonly :date, :description, :external_id, :installment, :originated_at, :quantity,
                :sold_price, :value, :status_key, :type, :work_hours, :disabled_at,
                :client_external_id, :client_name, :product_external_id, :product_name,
                :user_identifier, :deal_collaboration_id, :fields
end
```

```ruby
# app/app/models/deal.rb (Phase 1 — additive, alongside the still-present has_many :commissionings)
has_many :commissioned_deals, inverse_of: :deal
```

The foreign key lives on the new table — `commissioned_deals.commissioning_id`, not on
`commissionings`. The hot `commissionings` table gains no new column during EXPAND; it only
loses `deal_id` at CONTRACT (§ Phase 4b). A `Commissioning` reaches its `Deal` through
`commissioning.commissioned_deal.deal`. The 1:1 relationship between `Commissioning` and
`CommissionedDeal` is enforced by a unique index on `commissioned_deals.commissioning_id` (§
Phase 1 Migration 1), and the "one `DealCommissioning` per deal+rule+user" invariant is enforced
by a second unique index on `commissioned_deals (rule_id, user_commission_id, deal_id)` — which
is also why `rule_id` and `user_commission_id` are denormalized onto `commissioned_deals` (§
Uniqueness-invariant requirement).

All four `belongs_to` associations on `CommissionedDeal` — `commissioning`, `deal`, `rule`,
`user_commission` — follow the identical shape: `optional: true` on the `belongs_to` plus a
manual `validates :<x>_id, presence: true`, per `~/.claude/docs/OPTIONAL-BELONGS-TO.md`. This
mirrors the project's own canonical precedent for a mandatory FK —
`db/migrate/2026/01/...create_incentive_user_payments.rb`, cited in `RAILS-MIGRATIONS.md` as the
shape to copy:

```ruby
t.references :company, null: false, foreign_key: true, index: true
t.references :incentive_payment, null: false, foreign_key: true, index: true
t.references :user, null: false, foreign_key: true, index: true
```

Every one of the four associations is domain-mandatory — a `CommissionedDeal` always has a
`commissioning`, a `deal`, a `rule`, and a `user_commission` — so all four columns are declared
`null: false` at the schema level (§ Phase 1 Migration 1) and none relies on Rails' automatic
association-existence check, which the manual presence validation replaces to skip the
per-record `SELECT` it would otherwise add.

`self.inheritance_column = nil` is required because the cache includes a `type` column (the
deal's own `Sale`/`Call`/`CreditRecovery`/`ServiceSale` type) and Rails treats a column literally
named `type` as the STI discriminator unless told otherwise
([apidock.com](https://apidock.com/rails/ActiveRecord/Base/inheritance_column/class)). No prior
use of this technique exists in the project (`grep -rn "self.inheritance_column" app/app`
returns nothing) — this is the first use.

## Destroy-cascade requirement

Two currently-exercised call sites destroy `Commissioning` rows today, both through the column
being removed (`deal_id`):

- **Frequent path** — `app/app/workers/commission/consumer.rb:24`, on every commission
  recalculation:
  ```ruby
  Commissioning.with_uncached_connection { user_commission.commissionings.destroy_all }
  ```
  Once `CommissionedDeal` is a separate row, this call — unchanged — would leave
  `commissioned_deals` rows orphaned on every recalculation cycle unless the destroy cascades.
- **Rare path** — `app/app/workers/company/cleansing/deal_consumer.rb:9-12`, a real production
  data-cleansing flow:
  ```ruby
  deal = Deal.with_uncached_connection { Deal.find(deal_id) }
  # ...
  Deal.with_uncached_connection { deal.destroy! }
  ```
  Today this is caught by `Deal has_many :commissionings, dependent: :destroy`
  (`deal.rb:14`). After Phase 4, `Deal` has no direct FK to `commissionings` — the link is two
  hops away (`Deal → CommissionedDeal → Commissioning`).

Declaring `dependent: :destroy` on both `Commissioning has_one :commissioned_deal` and
`CommissionedDeal belongs_to :commissioning` simultaneously would create a circular destroy — a
`Deal`-driven destroy reaching `CommissionedDeal` (via `Deal has_many :commissioned_deals`),
whose `after_destroy` dependent-destroy on the `belongs_to :commissioning` side would reach
`Commissioning`, whose `before_destroy` dependent-destroy on the `has_one :commissioned_deal`
side would try to destroy the very `CommissionedDeal` row already mid-destroy. This is avoided by
construction: only `Commissioning has_one :commissioned_deal, dependent: :destroy` carries the
declaration; `CommissionedDeal belongs_to :commissioning` carries none. This matches the
`AggregatedIndicator`/`IndicatorAggregation` precedent cited in § Chosen approach — the
FK-holding side (`CommissionedDeal`, which holds `commissioning_id`) never re-declares
`dependent:` back toward its parent; the non-FK side (`Commissioning`) carries the destroy.

**Resolution**:

- `Commissioning has_one :commissioned_deal, dependent: :destroy` — Rails fires a `has_one`
  `dependent: :destroy` as a `before_destroy` callback (the associated `CommissionedDeal` is
  destroyed first, then `Commissioning`'s own destroy proceeds). This alone makes the frequent
  path correct with **zero code change** at that call site — `destroy_all` already invokes
  `.destroy` per record, which already triggers this callback. Present from Phase 1.
- The rare path requires an explicit code change to `company/cleansing/deal_consumer.rb`: before
  `deal.destroy!`, destroy each of the deal's `commissioned_deals`' owning `commissioning` first
  (which, via the rule above, destroys the `commissioned_deal` with it). `Deal has_many
  :commissioned_deals, dependent: :restrict_with_exception` (Phase 4a) then acts as a safety net
  — it raises loudly if that explicit step is ever skipped or incomplete, instead of failing on a
  silent orphan or a foreign-key violation deep in Postgres. This code change is Phase 4a — it
  only becomes load-bearing once `Deal has_many :commissionings, dependent: :destroy` is removed;
  through Phase 1–3 the old cascade still works unmodified.

## Uniqueness-invariant requirement

`db/schema.rb:456-460` carries two partial unique indexes, both predicated on
`commissionings.deal_id`:

```ruby
t.index ["rule_id", "user_commission_id"], name: "commissionings_unique_period_index", unique: true, where: "(deal_id IS NULL)"
t.index ["user_commission_id", "rule_id", "deal_id"], name: "commissionings_unique_deal_index", unique: true, where: "(deal_id IS NOT NULL)"
```

`deal_id IS NULL` today is true exactly for the four non-deal `Commissioning` subtypes (a
`DealCommissioning` row always sets `deal_id` — `consumer.rb:72`). Dropping the column destroys
**both** indexes structurally — Postgres refuses to drop a column an index still references, not
just the deal-specific one. Replacement:

- `commissionings_unique_period_index` → a `type`-predicated index on the same table, no
  `deal_id` involved: unique on `(rule_id, user_commission_id)` where `type <>
  'DealCommissioning'`.
- `commissionings_unique_deal_index` → moves to `commissioned_deals`, as a unique index on
  `(rule_id, user_commission_id, deal_id)` — unconditional, since `deal_id` is `NOT NULL` on
  every `commissioned_deals` row (§ Decided associations), unlike the column it replaces on
  `commissionings`, which was only ever populated for `DealCommissioning` rows. This
  denormalization is exactly why `rule_id`/`user_commission_id` are duplicated onto
  `commissioned_deals`: a cross-table composite unique constraint has no direct Postgres
  expression without a trigger, so the natural key is duplicated onto the table that needs to
  enforce it.

### Consumer.rb write-path change (Phase 4a)

Today's lookup (`consumer.rb:70-73`) finds the existing row by the natural key the DB constraint
enforces:

```ruby
DealCommissioning.find_or_initialize_by(user_commission_id: user_commission.id, rule_id: rule_id, deal_id: deal_id)
```

Once `deal_id` leaves `commissionings`, that natural key lives on `commissioned_deals` (§
Uniqueness-invariant requirement), so the lookup runs against `commissioned_deals` first, and the
owning `Commissioning` is reached from there — never the reverse, because
`commissioned_deals.commissioning_id` is `NOT NULL` (§ Decided associations) and cannot be set
before the `Commissioning` row it references exists:

```ruby
commissioned_deal =
  CommissionedDeal.with_uncached_connection do
    CommissionedDeal.find_by(user_commission_id: user_commission.id, rule_id: rule_id, deal_id: deal_id)
  end

if commissioned_deal.present?
  deal_commissioning = commissioned_deal.commissioning
else
  deal_commissioning =
    Commissioning.with_uncached_connection do
      DealCommissioning.create!(user_commission_id: user_commission.id, rule_id: rule_id)
    end
end
```

A found `commissioned_deal` already carries a valid `commissioning_id`, set when the pair was
first created under the same 1:1 constraint (§ Decided associations), so
`commissioned_deal.commissioning` resolves directly. A miss means this is the first calculation
for this `(rule_id, user_commission_id, deal_id)` triple, so a fresh `Commissioning` row is
created first — `commissioned_deals.commissioning_id`'s `NOT NULL` constraint leaves no other
order — and the `CommissionedDeal` row is then built against its `id`, the same ordering Phase
1's dual-write uses. This is a Phase 4a change — through Phase 1–3 the old `deal_id`-based lookup
on `commissionings` keeps working unmodified, and `commissioned_deal` is populated alongside it
(dual-write).

## Timestamp-preservation requirement (hard requirement)

`commissionings` carries **no timestamp columns at all** (`db/schema.rb:447-465`). Two
consequences:

1. **Nothing in this feature writes to `deals.created_at`/`deals.updated_at`.** Every access to
   `Deal` in the backfill (Phase 2) and in `DealIncentive::Consumer`'s dual-write (Phase 1) is a
   **read only** — `Deal.with_uncached_connection { Deal.find(...) }`, never `.save`, `.touch`,
   or `.update` on a `Deal` instance. The technique is the absence of any write call, not a flag
   to suppress `touch` — nothing in the backfill Consumer or the dual-write path calls a
   persistence method on `Deal` at all.
2. **`commissioned_deals`' own `created_at`/`updated_at` (via `t.timestamps`) are the new
   forensic signal this feature adds.** For a row created during normal operation (Phase 1
   onward), `created_at` is the actual calculation time. For a row created during the backfill
   (Phase 2), `created_at` is the backfill's run time, not the original calculation time — an
   accepted gap ("no worse than today's live read"; the forensic safety is the date, not the
   value). Nothing in the backfill reconstructs or backdates `created_at` for these rows.
3. **The Phase 4 migrations touch no row data.** `remove_index`/`add_index`/`remove_reference`
   are schema-only DDL — Postgres does not rewrite per-row timestamp columns for an index
   drop/add or a plain column removal. None of the backfill design uses `update_all` (§ Phase 2
   uses `commissioning.update(...)` per record, a scalar-field update on a table with no
   timestamp to disturb) or `touch` anywhere.

## Migration timeout requirement

Every migration in this plan — Migration 1 (Phase 1) through Migration 5 (Phase 4b) — declares
the project-standard `def self.statement_timeout` reading its own `ENV.fetch('MIGRATION_<timestamp>',
250)`, per `~/.claude/docs/RAILS-MIGRATIONS.md`. Each one operates on `commissionings` or
`commissioned_deals`, so each carries this per-migration timeout control individually — no
migration in the set is exempt, and no shared constant substitutes for it.

## Execution phases

### Phase 1: EXPAND — new entity, dual-write (`app`; one deploy)

**Objective:** Every new `DealCommissioning` created from this deploy onward also gets a
`CommissionedDeal`; the direct `Commissioning belongs_to :deal` path stays live and unchanged.

**Components:**

- **Migration 1 — `bin/rails generate migration CreateCommissionedDeals`**:
  ```ruby
  create_table :commissioned_deals do |t|
    t.references :commissioning, null: false, foreign_key: true, index: { unique: true }
    t.references :deal, null: false, foreign_key: true, index: true
    t.references :rule, null: false, foreign_key: true, index: true
    t.references :user_commission, null: false, foreign_key: true, index: true

    t.date :date
    t.text :description
    t.string :external_id, limit: 8000
    t.integer :installment
    t.date :originated_at
    t.decimal :quantity, precision: 28, scale: 6
    t.decimal :sold_price, precision: 28, scale: 6
    t.decimal :value, precision: 28, scale: 6, null: false
    t.string :status_key
    t.string :type, limit: 8000
    t.decimal :work_hours
    t.datetime :disabled_at

    t.string :client_external_id
    t.citext :client_name
    t.string :product_external_id
    t.citext :product_name
    t.string :user_identifier

    t.bigint :deal_collaboration_id

    t.jsonb :fields, null: false, default: {}

    t.timestamps

    t.index %i[rule_id user_commission_id deal_id], unique: true, name: "commissioned_deals_unique_deal_index"
  end
  ```
  A fresh `CREATE TABLE` takes no lock on any existing table — no `disable_ddl_transaction!`
  needed. The `index: { unique: true }` on `commissioning_id` enforces the 1:1 relationship
  declared in § Decided associations; the composite unique index on `(rule_id, user_commission_id,
  deal_id)` carries no partial `where` clause because every one of the four references is
  `NOT NULL` (§ Decided associations) and therefore always present. `precision`/`scale`/`limit`
  on `quantity`, `sold_price`, `work_hours`, `external_id`, `type` mirror the corresponding
  `deals` columns' own declarations (§ Cache field set table); confirm each against
  `db/schema.rb`'s `deals` table at migration-authoring time, along with each column's `null:`
  constraint, which should mirror the corresponding `deals` column's own nullability. `value` has
  no source column on `deals` to mirror — it is a computed method, not a stored column — so its
  `precision: 28, scale: 6` matches `sold_price`'s own declaration as the tightest reasonable
  bound and it is `null: false` unconditionally, since every deal type computes a value. Creating
  the table, its columns, and its indexes together is one conceptual operation under
  `~/.claude/docs/RAILS-MIGRATIONS.md`'s "When NOT to split" carve-out. Include the project's
  standard `def self.statement_timeout` at the bottom of the migration class per the same doc (§
  Migration timeout requirement). Run `bin/rails db:migrate`; commit the migration and the
  regenerated `db/schema.rb` together.

- **`app/app/models/commissioned_deal.rb`** (new model): as in § Decided associations.

- **`app/app/models/commissioning.rb`**: add `has_one :commissioned_deal, dependent: :destroy,
  inverse_of: :commissioning` **alongside** the still-present `belongs_to :deal, optional: true,
  inverse_of: :commissionings` (`commissioning.rb:6`).

- **`app/app/models/deal.rb`**: add `has_many :commissioned_deals, inverse_of: :deal`
  **alongside** the still-present `has_many :commissionings, dependent: :destroy` (`deal.rb:14`)
  — no `dependent:` on `commissioned_deals` yet (§ Destroy-cascade requirement; it only needs to
  be present, not the destroy owner, until Phase 4a).

- **`app/app/workers/deal_incentive/consumer.rb`** (dual-write): inside the existing
  `if deal_value.present? && deal_value.nonzero?` block, after the existing extra-fields loop
  (`consumer.rb:33-45`) and after `deal_commissioning` is found/initialized by the unchanged
  `deal_id`-based lookup (`consumer.rb:70-73`), wrap the existing `deal_commissioning.save!`
  (`consumer.rb:89`) together with the new `CommissionedDeal.create!` inside a single connection
  checkout and a single transaction, so the pair commits or rolls back together. `deal.value` is
  read directly off the already-loaded `deal` — no new query, since the computed method runs in
  memory against attributes already fetched:
  ```ruby
  commissioned_deal_fields = {}

  variable_ids.each do |variable_id|
    variable = Variable.with_uncached_connection { Variable.find(variable_id) }
    deal_field = DealField.with_uncached_connection { deal.fields.find_by(variable_id: variable_id) }
    value = deal_field.present? ? deal_field.formated_value : variable.default

    options[variable.key] = value
    commissioned_deal_fields[variable.key] = value
  end
  ```
  ```ruby
  ApplicationRecord.with_uncached_connection do
    ActiveRecord::Base.transaction do
      # existing line 89, now inside this transaction
      deal_commissioning.save!

      CommissionedDeal.create!(
        commissioning_id: deal_commissioning.id,
        deal_id: deal_id,
        rule_id: rule_id,
        user_commission_id: user_commission.id,
        date: deal.date,
        description: deal.description,
        external_id: deal.external_id,
        installment: deal.installment,
        originated_at: deal.originated_at,
        quantity: deal.quantity,
        sold_price: deal.sold_price,
        value: deal.value,
        status_key: deal.status.key,
        type: deal.type,
        work_hours: deal.work_hours,
        disabled_at: deal.disabled_at,
        client_external_id: deal.client.external_id,
        client_name: deal.client.name,
        product_external_id: deal.product.external_id,
        product_name: deal.product.name,
        user_identifier: deal.user.primary_identifier_value,
        deal_collaboration_id: deal.deal_collaboration_id,
        fields: commissioned_deal_fields
      )
    end
  end
  ```
  The ternary above (`deal_field.present? ? deal_field.formated_value : variable.default`)
  reproduces `consumer.rb:33-45`'s own existing conditional shape unchanged — it is pre-existing
  code being read, not new code this plan writes, and stays outside this plan's scope per §
  Scope Discipline (out-of-pattern code not blocking the task).

  `with_uncached_connection` (`app/app/models/application_record.rb:50-65`) is
  `connection_pool.with_connection { uncached { ... } }` — a connection checkout with the query
  cache disabled, **not** a transaction. Calling it separately around each write (one
  `with_uncached_connection` block for `deal_commissioning.save!`, a second, independent one for
  `CommissionedDeal.create!`) would let `deal_commissioning.save!` commit and return before the
  second block even begins, and the two blocks could check out different pool connections
  entirely — so a `CommissionedDeal` validation failure would leave a `DealCommissioning`
  persisted without its cache, the exact orphan this feature exists to prevent. This plan
  introduces the explicit `ActiveRecord::Base.transaction` block shown above, nested inside a
  single `ApplicationRecord.with_uncached_connection` checkout so both writes run on the same
  connection AND inside the same transaction, to deliver that atomicity: a `CommissionedDeal`
  validation failure raises and rolls both writes back together. The precedent for an explicit
  multi-write transaction in this codebase is `Deal.transaction do ... end` in
  `app/app/controllers/api/v3/deals/activity_controller.rb`. This transaction is what makes
  `CommissionedDeal.create!` (bang) the right call at this site, per
  `~/.claude/docs/BANG-METHOD-WEB-FLOW.md`: a mid-write validation failure must halt and roll the
  pair back — the dual-write is one transaction, not a chain that can be left half-done.

- **`app/app/graphql_types/commissioning_graphql_type.rb`**: add `field :commissioned_deal,
  CommissionedDealGraphqlType, null: true` — additive, does not touch the existing `field :deal`
  (`commissioning_graphql_type.rb:4-5`).

- **`app/app/graphql_types/commissioned_deal_graphql_type.rb`** (new type): exposes every column
  in § Cache field set, camelCase and alphabetically ordered per graphql-ruby convention
  (`clientExternalId`, `clientName`, `date`, …, `soldPrice`, `statusKey`, `type`,
  `userIdentifier`, `value`, `workHours`; `dateOfDeal` is not used — the field stays `date`),
  plus `deal` (the live `belongs_to :deal` association, needed by Phase 3's `dealCollaboration`
  read).

**No frontend change in this phase** — the new GraphQL field is additive and unread until Phase
3.

**Dependencies:** None — self-contained within `app`. Migration 1 only creates a new table and
takes no lock on any existing table, so this deploy carries none of the productive-app Sidekiq
queue-check triggers in `~/.claude/docs/DEPLOYMENT-STRATEGY.md` — that check applies to a
migration touching the hot `commissionings` table, which nothing in this phase does.

**Success criteria:**
- [ ] The migration generated via `bin/rails generate migration`, with `def self.statement_timeout`,
      run via `bin/rails db:migrate`, `db/schema.rb` committed
- [ ] `commissioned_deals` starts empty; no backfill executed in this phase
- [ ] Every `DealCommissioning` created after this deploy carries a linked `CommissionedDeal`
      with every column in § Cache field set populated, `value` included
- [ ] A test proving the frequent recalculation path
      (`Commissioning.with_uncached_connection { user_commission.commissionings.destroy_all }`,
      `commission/consumer.rb:24`) destroys the `commissioned_deal` row along with its
      `Commissioning` (via `dependent: :destroy`) and the rebuild recreates a fresh one
- [ ] A test proving that a `CommissionedDeal` validation failure inside the dual-write's
      transaction rolls back the paired `deal_commissioning.save!` as well — no
      `DealCommissioning` persists without its `CommissionedDeal`
- [ ] `CommissioningGraphqlType` exposes `commissioned_deal`; `CommissionedDealGraphqlType`
      exposes every cache column plus `deal`
- [ ] Deployed to every `app` environment before Phase 2 begins

### Phase 2: BACKFILL (background job; runs after Phase 1 ships; no deploy of its own)

**Objective:** Populate `CommissionedDeal` for every existing `DealCommissioning` row, using the
deal's current state at backfill time.

**Components:**

- **`CommissionedDeal::Migration::Producer`/`Consumer`**, modeled on the existing
  `plan_statement/migration/producer.rb`/`consumer.rb` cursor-driven, `Computation`-paced
  precedent (the codebase's established idiom for a one-time data migration over a table with no
  known upper bound on row count — a second such precedent exists at
  `app/app/workers/deal_dataset/migration/`):
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
  `CommissionedDeal::Migration::Producer` mirrors this shape, scoped to
  `Commissioning.where(type: 'DealCommissioning').where.not(deal_id: nil).where.missing(:commissioned_deal).order(:id)`,
  cursor-paged in batches of 10,000, same `Computation` key/re-enqueue mechanics. The
  `where.missing(:commissioned_deal)` anti-join relies on the unique
  `commissioned_deals.commissioning_id` index (§ Phase 1 Migration 1) for its plan and on the
  `commissionings` primary-key order for paging — index awareness per
  `~/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md` rule 3; confirm at implementation time
  whether an index on `commissionings.type` is needed for the type filter to perform at scale.
  The last-to-finish job in a batch calls the Producer again for the next page
  (`plan_statement/migration/consumer.rb:20-22`), bounding concurrency to one 10,000-row page in
  flight at a time.
- **`CommissionedDeal::Migration::Consumer`** (per `commissioning_id`, IDs-only per
  `~/.claude/docs/DATA-PROCESSING.md`): read-only against `Deal`/`Client`/`Product`/`User`/
  `DealField` (all through `with_uncached_connection`, per `~/.claude/docs/DATA-ACCESS.md`);
  build and save one new `CommissionedDeal` row with the deal's current field values, including
  `value` (the same field set and sourcing as Phase 1's dual-write), setting `commissioning_id`
  to the `Commissioning` row's own id; link is complete on creation since the FK lives on
  `commissioned_deals` (§ Decided associations) — no separate `commissioning.update(...)` step is
  needed. This Consumer performs a single write (one `CommissionedDeal` row against an
  already-existing `Commissioning`), so it needs no transaction spanning multiple writes — unlike
  Phase 1's dual-write, there is no second persisted record to keep in sync. The Producer's
  `where.missing(:commissioned_deal)` scope makes a re-run of the whole backfill idempotent — an
  already-backfilled row is excluded from the next page.

**Dependencies:** Phase 1 must be deployed to every `app` environment first. Before scheduling
this phase, confirm `Commissioning.where(type: 'DealCommissioning').count` to size the backfill's
wall-clock expectations — the Producer/Consumer design self-paces regardless of the answer.

**Success criteria:**
- [ ] Every pre-existing `DealCommissioning` row (i.e. every row with `deal_id` present and no
      linked `commissioned_deal` at the start of this phase) has a linked `CommissionedDeal`
      after the run completes
- [ ] Re-running the backfill after completion enqueues zero jobs (idempotency confirmed)
- [ ] No `Deal` record's `created_at`/`updated_at` changes as a result of this phase

### Phase 3: REPOINT READERS (backend repoints and the frontend deploy; backend may ship ahead
of frontend, frontend never ships ahead of backend)

**Objective:** Every site enumerated in `fk_removal_enumeration_data_1.md` categories C, D, and F
reads through `commissioned_deal` instead of `deal` / raw `deal_id`.

**Components — backend:**

- **`app/app/work_books/commission_work_book/deal_work_sheet.rb:56`** and
  **`app/app/work_books/plan_slice_commission_work_book/deal_work_sheet.rb:49`**: replace
  `Deal.with_uncached_connection { deal_commissioning.deal }` with
  `CommissionedDeal.with_uncached_connection { deal_commissioning.commissioned_deal }`, and
  repoint every field read afterward (`product`, `client`, `date`, `sold_price`, `external_id`)
  to the corresponding cached column on `commissioned_deal` (`product_name`, `client_name`,
  `date`, `sold_price`, `external_id`), plus the `deal.value` read at
  `commission_work_book/deal_work_sheet.rb:83` and
  `plan_slice_commission_work_book/deal_work_sheet.rb:57` to `commissioned_deal.value`.
- **`app/app/models/commission.rb:142-149`** (`Commission#deals_count`),
  **`app/app/models/partial_commission.rb:89-96`** (`PartialCommission#deals_count`),
  **`app/app/models/user_commission.rb:31-37`** (`UserCommission#deals_count`): replace the raw
  `select('distinct commissionings.deal_id')` (joined via `.joins(:commissionings)`) with a join
  through `commissioned_deals` and `select('distinct commissioned_deals.deal_id')`.
- **`app/app/work_books/commission_work_book/deal_work_sheet.rb:51`** and
  **`app/app/work_books/plan_slice_commission_work_book/deal_work_sheet.rb:44`**
  (`user_commission.commissionings.deals.order(:deal_id).pluck(:id)`): replace with
  `.joins(:commissioned_deal).order('commissioned_deals.deal_id')`, consistent with the
  join-based repoint applied to the `deals_count` methods above.
- **`app/app/models/commissioning.rb:19`** (`collaborative_deals` scope) and
  **`commissioning.rb:37`** (`without_collaborative_deals` scope): replace `joins(:deal)` with
  `joins(:commissioned_deal)` and `deals.deal_collaboration_id` with
  `commissioned_deals.deal_collaboration_id`.
- **`app/app/graphql_types/deal_graphql_type.rb:7`** (`field :commissionings`): no confirmed
  frontend caller reads this field nested under a `deal`/`Deal` root query — remove it in Phase
  4b, alongside `deal.rb:14`'s `has_many`.

**Components — frontend (`app-webclient`)**, shipped only after the backend repoints above and
Phase 1's `field :commissioned_deal` addition have shipped:

- **`user-commission-show.component.ts:453-474`** (`getDealCommissionings`),
  **`user-commission-show.component.ts:348-369`** (`getCollaborativeDealCommissionings`),
  **`statement-show.component.ts:354-382`** (`ListCollaborativeDealCommissionings`),
  **`statement-show.component.ts:429-458`** (`ListDealCommissionings`): each query's `deal
  { ... }` block becomes `commissionedDeal { ... }`, reading the same cached field names the
  table stores (`clientName`, `date`, `description`, `externalId`, `installment`, `soldPrice`,
  `value`, `fields { output variable { name } }`, …) instead of navigating to the live `deal`.
- **`dealCollaboration { collaborativeDeal { ... } value }`** — read by three of the four query
  sites (items 17–19 in the auxiliary) — is `Deal.dealCollaboration`, a live association read
  outside the cached field set. It continues to read live, reached via the still-live
  `commissionedDeal.deal.dealCollaboration` path: `CommissionedDeal belongs_to :deal, optional:
  true` (§ Decided associations) is never removed — only `Commissioning belongs_to :deal` is
  removed — so the nested query becomes `commissionedDeal { deal { dealCollaboration { ... } } }`.
  This `dealCollaboration.value` is a distinct field on the collaboration itself, unrelated to
  `CommissionedDeal.value`.
- **`app-webclient/src/app/commissioning/commissioning.model.ts:1-63`**: replace the front-end
  `Commissioning` model's `deal`/`dealId` fields with `commissionedDeal`.

**Confirmed out of scope for this repoint** (a different FK entirely, unaffected by this plan):
`user-history-show.component.ts:156` (`UserDealHistory.deal`) and
`collaborative-deal-show.component.ts:54-57` (a collaboration's own `deal`).

**Dependencies:** Phase 1 must be deployed (it added `field :commissioned_deal`, which the
frontend deploy in this phase requires). The backend repoints in this phase touch no schema —
pure Ruby read-path changes — and can ship ahead of the frontend deploy; the frontend deploy must
not ship before the backend's `field :commissioned_deal` exists, which is already true by the
time this phase starts.

**Success criteria:**
- [ ] All backend sites in category C and D of the auxiliary read through `commissioned_deal` /
      `commissioned_deals`, none through `deal` / raw `deal_id`, including the `value` reads at
      `deal_work_sheet.rb:83` and `:57`
- [ ] All four frontend query sites read `commissionedDeal` instead of `deal`, including `value`
- [ ] `dealCollaboration` still resolves correctly via `commissionedDeal.deal.dealCollaboration`
- [ ] The two confirmed-out-of-scope frontend sites are untouched
- [ ] Deployed: backend repoints first (any time after Phase 1), frontend deploy last

### Phase 4a: CONTRACT — ignored_columns, cascade cutover (`app`; one deploy)

**Objective:** `commissionings.deal_id` is no longer read anywhere in application code; the
uniqueness invariant and destroy cascade both run through `commissioned_deals`.

**Components:**

- **`app/app/models/commissioning.rb`**: `self.ignored_columns += ['deal_id']`.
- **`app/app/models/deal.rb`**: replace `has_many :commissionings, dependent: :destroy` with
  `has_many :commissioned_deals, dependent: :restrict_with_exception, inverse_of: :deal`.
- **`app/app/workers/company/cleansing/deal_consumer.rb`**: before `deal.destroy!`, explicitly
  destroy each of the deal's `commissioned_deals`' owning `commissioning` (which cascades to the
  `commissioned_deal` via `Commissioning has_one :commissioned_deal, dependent: :destroy`, §
  Destroy-cascade requirement).
- **`app/app/workers/deal_incentive/consumer.rb`**: switch the write path to the
  `CommissionedDeal`-first lookup (§ "Consumer.rb write-path change") — stop writing `deal_id` on
  new `DealCommissioning` rows.
- **`app/app/graphql_types/deal_graphql_type.rb`**: remove `field :commissionings` (§ Phase 3,
  backend components) and `app/app/models/deal.rb`'s prior `has_many :commissionings` line is
  already replaced above.
- **Migration 2 — `bin/rails generate migration AddCommissioningsUniqueNonDealIndex`**:
  ```ruby
  disable_ddl_transaction!

  def change
    add_index :commissionings, %i[rule_id user_commission_id],
              unique: true,
              where: "(type <> 'DealCommissioning')",
              algorithm: :concurrently,
              if_not_exists: true,
              name: 'commissionings_unique_non_deal_index'
  end
  ```
  The replacement index goes in FIRST, so the invariant it enforces is never unenforced even
  briefly. `if_not_exists: true` matches the `if_exists: true` already on the paired
  `remove_index` migrations in this phase, per `~/.claude/docs/RAILS-MIGRATIONS.md`'s retry-safety
  guidance for a `:concurrently` index — a partial failure can leave an `INVALID` index, and a
  retry without it raises "relation already exists". The call is wrapped across multiple lines,
  one argument group per line, per `~/.claude/docs/CODE-STYLE-RULES.md`'s 150-column ceiling.
- **Migration 3 — `bin/rails generate migration RemoveCommissioningsUniquePeriodIndex`**:
  ```ruby
  def change
    remove_index :commissionings, name: 'commissionings_unique_period_index', if_exists: true
  end
  ```
- **Migration 4 — `bin/rails generate migration RemoveCommissioningsUniqueDealIndex`**:
  ```ruby
  def change
    remove_index :commissionings, name: 'commissionings_unique_deal_index', if_exists: true
  end
  ```

**Dependencies:** Phases 1–3 fully shipped and confirmed — every backend and frontend read site
in the FK-removal enumeration repointed off `deal_id`/`deal`. Run the productive-app Sidekiq
queue check before this deploy — Migration 2 runs a concurrent index build against the hot
`commissionings` table.

**Success criteria:**
- [ ] `Commissioning.ignored_columns` includes `deal_id`; the column still physically exists
      (removed only in Phase 4b)
- [ ] `DealIncentive::Consumer` no longer writes `deal_id` on new `DealCommissioning` rows
- [ ] A test exercising `company/cleansing/deal_consumer.rb` against a `Deal` with at least one
      `commissioned_deal` confirms the explicit destroy step correctly cascades to
      `Commissioning`/`CommissionedDeal` with no orphan and no `Deal has_many
      :commissioned_deals, dependent: :restrict_with_exception` exception raised
- [ ] `commissionings_unique_non_deal_index` exists and enforces uniqueness for the four non-deal
      subtypes; `commissionings_unique_period_index` and `commissionings_unique_deal_index` are
      dropped
- [ ] Deployed to every `app` environment before Phase 4b

### Phase 4b: CONTRACT — column removal (`app`; a later, separate deploy from 4a)

**Objective:** `commissionings.deal_id` and its index are physically removed.

**Components:**

- **`app/app/models/commissioning.rb`**: remove the `belongs_to :deal` association line
  entirely (it was already functionally dead after Phase 4a's `ignored_columns`, and its removal
  is finalized here alongside the column drop).
- **Migration 5 — `bin/rails generate migration RemoveDealReferenceFromCommissionings`**:
  ```ruby
  def change
    safety_assured { remove_reference :commissionings, :deal }
  end
  ```
  Drops `deal_id` and `index_commissionings_on_deal_id` together, per
  `~/.claude/docs/RAILS-MIGRATIONS.md`'s "`add_reference` is one conceptual operation" carve-out
  applied symmetrically to its removal. `safety_assured` is required unconditionally for
  `remove_column`/`remove_reference` — "it's not possible to add a custom check for
  `remove_column` operations" ([ankane/strong_migrations](https://github.com/ankane/strong_migrations)).
  This is the one `safety_assured` use in this feature: a real, known, unavoidable risk (removing
  a column running code may still reference), accepted deliberately because every reader was
  confirmed repointed across Phases 3–4a.

**Dependencies:** Phase 4a must be deployed and confirmed for at least one full deploy cycle —
`strong_migrations` mandates the `ignored_columns` → `remove_column` sequence run as two separate
deploys ([blog.appsignal.com](https://blog.appsignal.com/2024/03/20/good-database-migration-practices-for-your-ruby-on-rails-app-using-strong-migrations.html)).
Before this migration ships, confirm every row in the FK-removal enumeration (`app`
category C/D + `app-webclient` category F) is repointed — this is the acceptance checklist for
this deploy, since a missed site fails with `NoMethodError`/`ActiveRecord::UnknownAttributeError`
at runtime, not at deploy time.

**Success criteria:**
- [ ] `commissionings.deal_id` and `index_commissionings_on_deal_id` no longer exist in
      `db/schema.rb`
- [ ] `Commissioning` no longer declares `belongs_to :deal`
- [ ] No `NoMethodError`/`ActiveRecord::UnknownAttributeError` on `deal_id`/`.deal` observed
      after deploy across every `app` environment

## Deploy sequencing

| Order | Phase | Repo | Deploy shape |
|---|---|---|---|
| 1 | Phase 1 (EXPAND) | `app` | One deploy: 1 migration + dual-write code, additive |
| 2 | Phase 2 (BACKFILL) | `app` | Background job, no deploy of its own; scheduled after Phase 1 confirmed live |
| 3 | Phase 3 backend repoints | `app` | One deploy: pure Ruby read-path changes, no schema |
| 4 | Phase 3 frontend | `app-webclient` | One deploy, after Phase 3 backend and Phase 1 both live |
| 5 | Phase 4a (CONTRACT — ignored_columns) | `app` | One deploy: 3 migrations + cascade/write-path cutover |
| 6 | Phase 4b (CONTRACT — column removal) | `app` | One deploy, a later deploy cycle than 4a: 1 migration |

Each `app` deploy in this sequence is checked against the three phasing triggers in
`~/.claude/docs/DEPLOYMENT-STRATEGY.md`: the `Computation` Redis key derivation is untouched
throughout, `DealIncentive::Consumer`'s enqueued-job argument shape
(`commission_id, user_commission_id, rule_id, deal_id, partial`) is untouched throughout, and no
non-idempotent step is introduced (Phase 2's backfill is idempotent by construction via
`where.missing(:commissioned_deal)`). What forces the multi-deploy sequence here is outside those
three triggers: `commissionings.deal_id` is read by application code across two repositories, and
`strong_migrations` mechanically requires the two-deploy `ignored_columns` →
`remove_column`/`remove_reference` sequence for any column removal, independent of whether the
three §6 triggers apply. Run the productive-app Sidekiq queue check
(`scripts/sidekiq-queue-check.sh`) immediately before the `app` deploy in this sequence that
carries a concurrent index build against `commissionings` (Phase 4a Migration 2) —
`commissionings` is a hot, high-write table.

## Technical decisions

| Decision | Choice | Rationale |
|---|---|---|
| Entity shape | Intermediate entity `CommissionedDeal` between `Commissioning` and `Deal`, modeled on `AggregatedIndicator`/`IndicatorAggregation` | Naming, association style, and single-direction destroy discipline already established in the codebase (§ Chosen approach) |
| FK direction between `Commissioning` and `CommissionedDeal` | `CommissionedDeal belongs_to :commissioning` (the FK lives on the new table); `Commissioning has_one :commissioned_deal` | Keeps `commissionings` free of any new column during EXPAND — it only loses `deal_id` at CONTRACT — and matches the `AggregatedIndicator`/`IndicatorAggregation` precedent, where the FK-holding side never re-declares `dependent:` toward its parent (§ Destroy-cascade requirement) |
| Null/optional pairing on `CommissionedDeal`'s four `belongs_to` | All four (`commissioning`, `deal`, `rule`, `user_commission`) use `optional: true` + `null: false` + manual `validates :x_id, presence: true` | Every one is domain-mandatory; matches the project's canonical mandatory-FK shape (`db/migrate/2026/01/...create_incentive_user_payments.rb`, cited in `RAILS-MIGRATIONS.md`) |
| `value` column | Cached alongside `sold_price`, populated from the already-loaded `deal.value` at capture time — no new query | The worksheets and the front read the computed `deal.value` (STI-subtype-dependent — `Sale#value = sold_price * quantity`, `Call#value = quantity`), never `sold_price` directly; caching only `sold_price` would show a different number than was calculated for every non-`Sale` deal type — the exact drift this feature exists to close |
| Dual-write transaction shape | `deal_commissioning.save!` and `CommissionedDeal.create!` run inside one `ApplicationRecord.with_uncached_connection` checkout wrapped in one `ActiveRecord::Base.transaction` | `with_uncached_connection` is a connection checkout with the query cache disabled, not a transaction — two separate calls to it can use different pool connections and commit independently; an explicit shared transaction on a single connection is required for the pair to actually roll back together on a `CommissionedDeal` validation failure |
| `AddCommissioningsUniqueNonDealIndex`'s `add_index` retry safety | `if_not_exists: true` added, matching the paired `remove_index` migrations' `if_exists: true` | A `:concurrently` index can fail partway and leave an `INVALID` index; a retry without `if_not_exists` raises "relation already exists" (`RAILS-MIGRATIONS.md` § if_not_exists/if_exists for retry safety) |
| Naming | `CommissionedDeal`, not `DealCache` or `Snapshot` | `DealCache` already names a different concept (`user_commission/deal_cache_consumer.rb:17-34` — aggregate money/points caching); the past-participle + noun shape matches `AggregatedIndicator` |
| `rule_id`/`user_commission_id` denormalization | Duplicated onto `commissioned_deals` | Required to re-express `commissionings_unique_deal_index` as a single-table constraint once `deal_id` leaves `commissionings` (§ Uniqueness-invariant requirement) |
| `self.inheritance_column = nil` | Set on `CommissionedDeal` | The cache includes a `type` column; Rails treats a literal `type` column as the STI discriminator by default |
| Destroy cascade direction | `dependent: :destroy` on `Commissioning has_one :commissioned_deal` only; `CommissionedDeal belongs_to :commissioning` carries none | Declaring it on both sides creates a circular destroy on a `Deal`-driven destroy path (§ Destroy-cascade requirement) |
| `status_key` vs `status_id` | Cache the resolved key string, not the raw FK | The calculation itself never uses `status_id`; caching the raw FK would still require a live join at display time |
| `fields` storage | Store `DealField#formated_value` (already-formatted), not the raw value | Reformatting a raw value at display time would let a later `variable.data_type` change silently reinterpret historical records |
| `deal_collaboration_id` inclusion | Added to the cache column list | Required by the `collaborative_deals`/`without_collaborative_deals` GraphQL filtering path, discovered during FK-removal enumeration |
| `dealCollaboration` nested read | Continues to read live, via `commissionedDeal.deal.dealCollaboration` | `CommissionedDeal belongs_to :deal` is never removed — only `Commissioning belongs_to :deal` is; the live association survives for this one nested read |
| Export ordering (`order(:deal_id)`) | `.joins(:commissioned_deal).order('commissioned_deals.deal_id')` | Consistent with the join-based repoint already applied to the `deals_count` methods reading the same column |
| `deal_graphql_type.rb:7`'s `field :commissionings` | Removed in Phase 4b | No confirmed frontend caller reads it nested under a `deal`/`Deal` root query |
| Backfill scope | Populate every existing `DealCommissioning` row from the deal's **current** state at backfill time | The deal's state at the original processing time is unrecoverable — no worse than today's live read; the forensic gap is accepted, timestamps on other tables are never touched |
| Backfill design | Cursor-driven Producer/Consumer, modeled on `plan_statement/migration/producer.rb`/`consumer.rb` | Established 4Shark idiom for a one-time migration over a table with no known upper bound on row count |
| Phasing | Expand/contract across 4 phases, with Phase 4 split into two separate deploys | `strong_migrations` mandates the two-deploy `ignored_columns` → `remove_column` sequence for any column removal, independent of the standard three phasing triggers, because `commissionings.deal_id` is read across two repositories |
| Migration shape (Phase 1, table creation) | `CREATE TABLE`, no `disable_ddl_transaction!` | A fresh table takes no lock on any existing table |
| Migration shape (Phase 4a, index changes on `commissionings`) | `algorithm: :concurrently` + `disable_ddl_transaction!` | `commissionings` is a hot, high-write table |

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Phase 4b (`remove_reference :commissionings, :deal`) is the highest-blast-radius step — every enumerated read site must be confirmed repointed first, or a missed site breaks in production with no schema-level warning beforehand | A missed site is a runtime `NoMethodError`/`ActiveRecord::UnknownAttributeError` in production, not a deploy-time failure | Treat the FK-removal enumeration (`fk_removal_enumeration_data_1.md`) as the acceptance checklist for Phase 4b; the `ignored_columns` step in Phase 4a gives one full deploy cycle of runway to catch a missed site (the column still physically exists during 4a) |
| Backfill (Phase 2) runs over an unknown, possibly multi-million-row table; row count not queried in this pass (no DB access) | Total wall-clock time to backfill is unestimated | Confirm `Commissioning.where(type: 'DealCommissioning').count` before scheduling Phase 2; the Producer/Consumer design self-paces regardless of the answer (10,000-row pages, one page in flight at a time) |
| `commissionings` is a hot, high-write table; Phase 4a's index swap runs against it while calculation traffic is live | Migration lock contention or a slow migration blocking calculation writes | Phase 4a's schema change uses the concurrent-index safe form (`if_not_exists: true` included for retry safety); run the productive-app Sidekiq queue check before that deploy |
| The circular-destroy hazard (§ Destroy-cascade requirement) is a genuine ActiveRecord footgun — a wrong direction would surface only when a `Deal` is actually destroyed, the rare path, meaning it could pass ordinary testing (which exercises the frequent recalculation path far more) and only fail during a cleansing run | A latent bug that only manifests during company data cleansing — a sensitive, infrequent operation | Single-direction rule stated as a hard constraint in this plan; a test exercising `company/cleansing/deal_consumer.rb` against a `Deal` with at least one `commissioned_deal` is part of Phase 4a's success criteria |
| The Phase 1 dual-write is two persistence calls (`deal_commissioning.save!`, `CommissionedDeal.create!`) that must succeed or fail together — `with_uncached_connection` alone does not guarantee this, since it is a connection checkout, not a transaction | Without the explicit wrapping transaction, a `CommissionedDeal` validation failure would leave a `DealCommissioning` persisted with no cache — the exact orphan this feature exists to prevent | Both writes run inside one `ApplicationRecord.with_uncached_connection` checkout wrapped in one `ActiveRecord::Base.transaction` (§ Phase 1); a dedicated test in Phase 1's success criteria proves the rollback |

## Assumptions

- `DealCommissioning.find_or_initialize_by(..., deal_id: deal_id)` (`consumer.rb:70-73`) can
  return an already-persisted `DealCommissioning` when the worker revisits one, but the frequent
  reprocess path (`commission/consumer.rb:24`) always destroys the whole `Commissioning` row
  first, so a revisit within `DealIncentive::Consumer` following a fresh destroy always builds a
  new `CommissionedDeal`, never re-links a stale one.
- `deal_id IS NULL` on `commissionings` today is exactly equivalent to `type <> 'DealCommissioning'`,
  confirmed by `deal_incentive/consumer.rb:70-72` always setting `deal_id` on `DealCommissioning`
  rows and no other subtype ever setting it — this equivalence is what the Phase 4a replacement
  index (`commissionings_unique_non_deal_index`) relies on.
- No `factory :deal_commissioning` exists in the test suite — only `factory :commissioning`
  (`app/spec/factories/commissionings.rb`), instantiated with `type:` and no `deal_id` trait. A
  `commissioned_deal` factory/trait is needed at implementation time for the tests in Phases 1
  and 4a's success criteria.
- `app-webclient`'s GraphQL client tolerates the new, nullable, previously-unrequested
  `commissioned_deal` field added to `CommissioningGraphqlType` in Phase 1 with no front-side code
  change required until Phase 3 explicitly reads it.
- `CommissionedDealGraphqlType` needs its own `deal` field (the live `belongs_to :deal`
  association) specifically to serve the `dealCollaboration` nested read in Phase 3 — every other
  field the frontend needs is served directly by the cached columns.
- Every `Deal` subtype (`Sale`, `Call`, `CreditRecovery`, `ServiceSale`) implements `#value`, so
  `deal.value` never returns `nil` for a `DealCommissioning`'s underlying deal, matching
  `commissioned_deals.value`'s `null: false` constraint.
- `deal_commissioning` and the new `CommissionedDeal` row both descend from `ApplicationRecord`
  (`DealCommissioning < Commissioning < ApplicationRecord`; `CommissionedDeal < ApplicationRecord`),
  so a single `ApplicationRecord.with_uncached_connection` checkout covers both models' writes on
  the same connection.

## Changelog

Both repos require a `CHANGELOG.md` entry under `## [Unreleased]` on their respective feature
branches, per `~/.claude/docs/CHANGELOG.md`:

- `app`: under `### Added` — an entry naming that commission calculations now retain the deal
  data used at processing time.
- `app-webclient`: under `### Changed` — an entry naming that commission detail now displays the
  values used at calculation time.
