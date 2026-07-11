# SPIKE — Business Territory vs. Retention Jurisdiction: Backfill Scenarios for `companies.retention_jurisdiction_country_id`

**Conducted by:** spike agent
**Date:** 2026-07-10
**Status:** Research complete — pending decisions

---

## Goal

4Shark's `app` backend added `companies.retention_jurisdiction_country_id` (the single country whose data-protection law governs a company's retention/anonymization window) and shipped the write path (GraphQL create/update mutations, presence validation). The next phase is a production backfill of existing companies, and the original plan was to derive `retention_jurisdiction_country_id` from a company's `business_territory` (the many-to-many `company_business_territories` join — "where the company does business"). The engineer flagged that business territory is a different concept from retention jurisdiction and can legitimately hold multiple countries, breaking down the 1:1 assumption for multi-territory accounts. Two demo companies exposed this: #633 "Atento Mexico API" (`business_territory = [BR, MX]`, suspected data error) and #488 "Conta Global" (`business_territory = [AR, BR, CO, MX, PE]`, a global-dashboard demo account with subaccounts, not a single multi-jurisdiction account).

This spike answers: (A) what shipped for the write path, (B) how `company_business_territories` rows get created, (C) what consumes business territory today (blast radius of changing one), (D) what hierarchy/subaccount model exists behind a "global" account, (E) what the anonymization machinery currently does with the new column, and (F) the scenario/option space for the backfill — without choosing an option.

---

## Method

Codebase analysis only (Grep/Read/git log/git show) against `~/Projects/4Shark/app` on `develop` at commit `1b6e1bb4e` (includes merged PRs #5220/#5221/#5222 plus #5217). No production database access, no AWS access needed for this question, no web research (the question is entirely internal-codebase). Read-only `git log -S`, `git show`, and `Grep` used to establish when each piece of the write path was introduced and what currently reads it.

---

## Sources consulted

- `db/schema.rb` — `companies`, `company_branches`, `company_business_territories`, `countries` table definitions
- `db/migrate/20260708190346_add_anonymizing_window_days_to_countries.rb` and siblings — the four `retention_jurisdiction_country_id` migrations plus the per-country window migrations
- `app/models/company.rb`, `app/models/company_business_territory.rb`, `app/models/country.rb`, `app/models/holding.rb`, `app/models/company_branch.rb`, `app/models/subsidiary.rb`, `app/models/client.rb`
- `app/graphql_mutations/create_company_graphql_mutation.rb`, `app/graphql_mutations/update_company_graphql_mutation.rb`
- `app/graphql_types/company_graphql_type.rb`, `app/graphql_types/company_branch_graphql_type.rb`, `app/graphql_types/company_business_territory_input_graphql_type.rb`
- `app/scopes/state_scope.rb`, `app/scopes/register_type_scope.rb`, `app/scopes/country_scope.rb`, `app/scopes/company_branch_scope.rb`
- `app/graphql_resolvers/company_branch_graphql_resolver.rb`, `app/graphql_resolvers/company_business_territory_graphql_resolver.rb`
- `app/workers/company/anonymizer.rb`, `app/workers/company/user_anonymizer.rb`, `app/workers/company/processor.rb`, `app/workers/holding/admin/processor.rb`, `app/workers/holding/president/processor.rb`, `app/workers/exchange_rate/processor.rb`
- `lib/application_configuration.rb` (`user_anonymizing_window`)
- `lib/tasks/cron.rake` (anonymization cron namespace)
- `docs/architecture/API_DOMAIN.md` (`Subsidiary scoping and cross-subsidiary management` section)
- `spec/models/holding_spec.rb`, `spec/models/company_branch_spec.rb`, `spec/factories/companies.rb`
- `git log`/`git show` on commits `3eb34f3da`, `6bb5cf483`, `77118f16b`, `e3afd9d6f`, `0919e6e20`, `fbdc67d28`, `9f724a668`
- See auxiliary: `retention_grep_1.txt` — raw grep dump of every `business_territor`/`retention_jurisdiction` occurrence in `app/` (excluding specs), backing Findings A and B
- See auxiliary: `retention_presence_commit_stat_2.txt` — full `git show --stat` of commit `6bb5cf483` (the presence-validation PR), backing Finding C's "blast radius of the presence validation" sub-finding (313 files touched)

---

## Findings

### Finding A1: The column, association, and validation that shipped

**Evidence:**
```ruby
# app/models/company.rb:8
belongs_to :retention_jurisdiction_country, class_name: 'Country', inverse_of: :retention_jurisdiction_companies, optional: true
...
# app/models/company.rb:80,83
validates :business_territories, length: { minimum: 1 }
...
validates :retention_jurisdiction_country_id, presence: true
```
```ruby
# db/schema.rb:524,535
    t.bigint "retention_jurisdiction_country_id"
...
    t.index ["retention_jurisdiction_country_id"], name: "index_companies_on_retention_jurisdiction_country_id"
```
```ruby
# db/schema.rb:2684
  add_foreign_key "companies", "countries", column: "retention_jurisdiction_country_id"
```

**Source:** `app/models/company.rb:8`, `:80`, `:83`; `db/schema.rb:524,535,2684`

**Significance:** The association is `optional: true` (per 4Shark's `Optional belongs_to` convention — see `~/.claude/docs/OPTIONAL-BELONGS-TO.md`), and the DB column carries **no `NOT NULL` constraint** — only an app-level `validates :retention_jurisdiction_country_id, presence: true`. This means: (1) a raw SQL read of the `companies` table today will show NULL for every un-backfilled row without any DB error; (2) the presence validation fires only when a `Company` record is `save`d/`update`d through ActiveRecord — reads and unrelated background jobs that only read the row are unaffected; (3) any code path that calls `.save`/`.update`/`.save!`/`.update!` on an existing company that still has `retention_jurisdiction_country_id == nil` will now fail validation, blocking that save, until the column is backfilled for that company.

### Finding A2: The write path (create/update mutations) and the front-facing GraphQL shape

**Evidence:**
```ruby
# app/graphql_mutations/create_company_graphql_mutation.rb:15
  argument :retention_jurisdiction_country_id, ID, required: false
```
```ruby
# app/graphql_types/company_graphql_type.rb:50-51
  field :retention_jurisdiction_country, CountryGraphqlType, null: true
  field :retention_jurisdiction_country_id, ID, null: true
```

**Source:** `app/graphql_mutations/create_company_graphql_mutation.rb:15`; `app/graphql_mutations/update_company_graphql_mutation.rb:11`; `app/graphql_types/company_graphql_type.rb:50-51`

**Significance:** Both `CreateCompanyGraphqlMutation` and `UpdateCompanyGraphqlMutation` accept `retentionJurisdictionCountryId` as a GraphQL `ID`, `required: false` at the GraphQL argument layer — the model-level `presence: true` validation is what actually enforces it, not the mutation argument. The commit that shipped this (`3eb34f3da feat(company): accept retention jurisdiction country on create and update mutations`) added it as `argument :retention_jurisdiction_country_id, ID, required: false` alongside `business_territories: [{ countryId: ... }]` as a **separate, sibling argument** in the same mutation call — the two were never conflated in the write path itself; the test added in that commit passes both `businessTerritories: [{ countryId: #{country.id}}]` and `retentionJurisdictionCountryId: #{country.id}` in the same mutation call (`spec/requests/graphql_mutations/graphql_controller_create_company_spec.rb`, added in commit `3eb34f3da`). The `app-webclient` front-end code itself is outside the scope of this spike (the `app` repo does not contain it); the engineer's statement that "the front passes it with a user-chosen country selector" was not independently verified in this spike.

### Finding A3: Presence validation has no DB-level backstop — only ActiveRecord enforces it

**Evidence:** confirmed via `db/migrate/20260708190429_add_retention_jurisdiction_country_id_to_companies.rb` (`add_column :companies, :retention_jurisdiction_country_id, :bigint` — no `null: false`) and the four migrations that followed only add an index and a (non-validating-at-write, later validated) foreign key, never a `NOT NULL` constraint or a `change_column_null`.

**Source:** `db/migrate/20260708190429_add_retention_jurisdiction_country_id_to_companies.rb:5`, `db/migrate/20260708190556_add_retention_jurisdiction_country_foreign_key_to_companies.rb:5` (`add_foreign_key ..., validate: false`), `db/migrate/20260708190618_validate_retention_jurisdiction_country_foreign_key_on_companies.rb:5` (`validate_foreign_key` — validates FK integrity for existing non-null rows only, not presence)

**Significance:** Confirms Finding A1's "no NOT NULL" claim from the migration side. There is no DB-level urgency to backfill (nothing breaks by simply having NULL rows sit in the table); the urgency, if any, is entirely about (a) any code path that re-saves an existing company failing validation until backfilled (see Finding C's sub-finding on the 313-file test blast radius) and (b) whatever downstream anonymization logic eventually reads the column (see Finding E — currently nothing does).

---

### Finding B1: `CompanyBusinessTerritory` model and its associations

**Evidence:**
```ruby
# app/models/company_business_territory.rb
class CompanyBusinessTerritory < ApplicationRecord
  belongs_to :company, optional: true, inverse_of: :business_territories
  belongs_to :country, optional: true, inverse_of: :business_territories

  validates :country_id, presence: true

  scope :for_company, ->(company) { where(company_id: company) if company.present? }
  scope :for_country, ->(country) { where(country_id: country) if country.present? }

  rescue_unique_constraint index: :index_company_business_territories_on_company_id_and_country_id, field: :country_id
end
```

**Source:** `app/models/company_business_territory.rb:1-13`

**Significance:** A plain join model — `(company_id, country_id)` with a unique index, so a company cannot have the same country twice, but nothing else constrains it. There is no domain-level cap on how many countries a single company can hold as business territory, and no cross-check against `retention_jurisdiction_country_id` or against `company_branches` (Finding D) anywhere in this model.

### Finding B2: The only write paths for `company_business_territories` rows in this repo

**Evidence:**
```ruby
# app/graphql_mutations/create_company_graphql_mutation.rb:6,51,54
  argument :business_territories, [CompanyBusinessTerritoryInputGraphqlType], required: false
...
        business_territories: %i[country_id]
...
        params[:business_territories_attributes] = params.delete(:business_territories) || []
```
```ruby
# app/graphql_mutations/update_company_graphql_mutation.rb:5,42,45
  argument :business_territories, [CompanyBusinessTerritoryInputGraphqlType], required: false
...
        business_territories: %i[id country_id _destroy]
...
        params[:business_territories_attributes] = params.delete(:business_territories) || []
```
```ruby
# app/models/company.rb:78
  accepts_nested_attributes_for :business_territories, allow_destroy: true, reject_if: :all_blank
```

**Source:** `app/graphql_mutations/create_company_graphql_mutation.rb:6,51,54`; `app/graphql_mutations/update_company_graphql_mutation.rb:5,42,45`; `app/models/company.rb:78`

**Significance:** `grep -rln "business_territor" app --include="*.rb" | grep -v "_spec.rb"` (full dump in `retention_grep_1.txt`) turns up exactly two mutation classes, the two model files (`company.rb`, `company_business_territory.rb`), three GraphQL-query scopes (read-only, Finding C), and GraphQL type/resolver read plumbing. **There is no rake task, no service object, no seed file, and no controller in the `app` repo that writes `company_business_territories` rows.** `db/seeds.rb` does not exist in this repo outside vendored gem examples (`vendor/bundle/.../search_object-1.2.5/example/db/seeds.rb`, irrelevant). `Company.create`/`Company.new(` outside of spec files appears exactly once in the whole repo, inside `CreateCompanyGraphqlMutation#execute` (`app/graphql_mutations/create_company_graphql_mutation.rb:25`). The `UpdateCompanyGraphqlMutation` nested-attributes shape (`id, country_id, _destroy`) allows fully replacing a company's business territory set — adding an arbitrary country or removing one — via a single mutation call, gated only by `CompanyPolicy#update?` (`role.permission?('company_update')`, `app/policies/company_policy.rb:12-17`), which additionally requires the company not be `disabled?` or `pending?`. The code does not show whether `company_update` permission is staff-only or can be held by a client-side admin role — **the code does not show this**; it depends on the specific role's permission grants, which live in production/seed data this spike did not have access to.

**Open question this raises for #633:** the code shows the mechanism by which a BR territory *could* have been added to a MX account (a single `UpdateCompanyGraphqlMutation` call with `businessTerritories: [{ countryId: <BR id> }]` and no `_destroy` on the existing MX row), but the code does not show *who* made that specific call or *when* — that is an audit-log/production-data question, not something a codebase read answers. See the Discovery Queries section below.

---

### Finding C1: `business_territories` gates dropdown/lookup scoping for non-"main" companies

**Evidence:**
```ruby
# app/scopes/country_scope.rb
class CountryScope < ApplicationScope
  def resolve
    if company.main?
      scope
    else
      scope
        .joins(:business_territories)
        .where('business_territories.company_id': user.company_id)
    end
  end
end
```
(`app/scopes/state_scope.rb` and `app/scopes/register_type_scope.rb` follow the identical shape, joining through `country: :business_territories` instead of `:business_territories` directly.)

**Source:** `app/scopes/country_scope.rb:1-13`; `app/scopes/state_scope.rb:1-13`; `app/scopes/register_type_scope.rb:1-13`

**Significance:** These three scopes back the `CountryGraphqlResolver`, `StateGraphqlResolver`, and `RegisterTypeGraphqlResolver` (confirmed: `scope_class CountryScope` / `StateScope` / `RegisterTypeScope` in the respective resolver files) — the GraphQL list queries a front-end dropdown calls to populate "which country / state / register type can this company pick from" (e.g., when creating a `Subsidiary`, whose `register_type` is validated against `REGISTER_TYPES` per `app/models/subsidiary.rb:5`, `MX_RFC_LEGAL` / `BR_CNPJ` etc.). `company.main?` is `!company.client?` (`app/models/company.rb:149-151`, `def main?; !client?; end`), itself derived from the `companies.client` boolean column (`db/schema.rb`, `default: true`) — **the code does not show what determines whether a specific company (e.g. #633 or #488) has `client: true` or `client: false`**, so whether this scoping even applies to them is an open question (see Discovery Queries). For a company where `main?` is false, removing a country from `business_territories` would remove that country (and its states/register types) from what that company's users can select in these three dropdown-backed flows the next time they query them; it does not retroactively invalidate already-created records that reference that country (e.g., an existing `Subsidiary` with a `MX_RFC_LEGAL` register type would not be deleted or revalidated).

### Finding C2: The presence-validation PR alone touched 313 test files — the practical blast radius of requiring `retention_jurisdiction_country_id` on every `Company` save

**Evidence:** `git show 6bb5cf483 --stat` (full output in auxiliary `retention_presence_commit_stat_2.txt`) shows `313 files changed, 1320 insertions(+), 343 deletions(-)` across `spec/models/`, `spec/forms/`, and `spec/requests/api/v3/**` — every spec file whose setup created a `Company` via `FactoryBot.create(:company, ...)` needed `retention_jurisdiction_country: country` (or an equivalent) added, because the base factory does not set it:
```ruby
# spec/factories/companies.rb
FactoryBot.define do
  factory :company do
    license_quantity { rand(150_000) }
    name { "Company#{rand(100_000)}" }
    status { 'final' }
    primary_webclient_host { 'client.app4shark.com' }
    type { 'CallCenter' }
    ...
  end
end
```
One concrete example of the touch pattern:
```ruby
# spec/forms/api/seat_demotion_form_spec.rb (diff from commit 6bb5cf483)
-  let(:company) { FactoryBot.create(:company, :call_center, countries: [country]) }
+  let(:company) { FactoryBot.create(:company, :call_center, countries: [country], retention_jurisdiction_country: country) }
```

**Source:** `retention_presence_commit_stat_2.txt` (full stat); `spec/factories/companies.rb:1-19`; commit `6bb5cf483` diff on `spec/forms/api/seat_demotion_form_spec.rb`

**Significance:** This is the clearest evidence available in-repo of how wide the presence validation's reach is: essentially every test-suite path that persists a `Company` record needed a companion fix. By the same mechanism, **any production code path that calls `.save`/`.update` on an existing, not-yet-backfilled company will fail validation** until that company has a `retention_jurisdiction_country_id`. This is a stronger practical argument for backfill urgency than the DB schema itself (which has no `NOT NULL` — Finding A3): the risk is not corrupted data, it is **blocked writes** to any company still missing the value.

### Finding C3: Countries table also gained the (currently unused) `anonymizing_window_days` column

**Evidence:**
```ruby
# db/schema.rb:574-582
  create_table "countries", force: :cascade do |t|
    t.string "acronym"
    t.integer "anonymizing_window_days"
    ...
  end
```
```ruby
# db/migrate/20260708221559_add_anonymizing_window_days_to_brazil.rb
class AddAnonymizingWindowDaysToBrazil < ActiveRecord::Migration[8.1]
  def change
    country = Country.find_by(acronym: 'BR')
    return if country.nil?
    country.update(anonymizing_window_days: 1855)
  end
end
```
(Sibling migrations set Mexico and Colombia to `3680` days; `20260708221704_add_anonymizing_window_days_to_mexico.rb`, `20260710123240_add_anonymizing_window_days_to_colombia.rb`.)

**Source:** `db/schema.rb:576`; `db/migrate/20260708221559_add_anonymizing_window_days_to_brazil.rb:1-11`; `db/migrate/20260708221704_add_anonymizing_window_days_to_mexico.rb:1-11`; `db/migrate/20260710123240_add_anonymizing_window_days_to_colombia.rb:1-11`

**Significance:** Only three countries (`BR`, `MX`, `CO`) currently have a non-NULL `anonymizing_window_days`. `grep -rn "anonymizing_window_days" app --include="*.rb"` returns zero matches outside the model column declaration itself — see Finding E. This means: even once `retention_jurisdiction_country_id` is backfilled for every company, a company whose jurisdiction country is anything other than BR/MX/CO would resolve to a NULL per-country window today, and (per Finding E) that fact currently has no operational consequence because nothing reads the column yet.

---

### Finding D1: No `parent_id`/self-referential hierarchy on `Company`; `Subsidiary` is a different, non-hierarchy concept

**Evidence:** `grep -rn "belongs_to :parent\|parent_company\|sub_company\|subaccount" app/models` returns matches only in `app/models/seat_history.rb:5` (`belongs_to :parent, polymorphic: true`), `app/models/role.rb:7` (`belongs_to :parent, class_name: 'Role'`), `app/models/seat.rb:10`, and `app/models/eligibility_period.rb:5` — all unrelated to `Company`. `Company` itself (`app/models/company.rb:1-176`) has no `parent_id`, no self-referential `belongs_to`/`has_many`, and no `parent`/`sub_company`/`subaccount` field or association.

```ruby
# app/models/subsidiary.rb:1-10
class Subsidiary < ApplicationRecord
  API_REGISTER_TYPES = %w[BR_CNPJ CL_RUT CL_RUT_LEGAL CO_NIT_LEGAL MX_RFC_LEGAL].freeze
  REGISTER_TYPES = %w[BR_CNPJ CL_RUT CL_RUT_LEGAL CNPJ CO_NIT_LEGAL MX_RFC_LEGAL].freeze

  belongs_to :company, optional: true, inverse_of: :subsidiaries
  ...
```

**Source:** `app/models/company.rb:1-176` (full file read); `app/models/subsidiary.rb:1-28`; `docs/architecture/API_DOMAIN.md:418` — *"Brazilian and Latin American companies of any size are typically structured as multiple legal entities — a holding plus N operating subsidiaries, each with its own tax ID and its own register type."*

**Significance:** `Subsidiary` is a legal-entity sub-record **within one Company** (a CNPJ/RFC/RUT filial) — not a separate `Company` row, and therefore not a candidate model for "one Company having several country-specific subaccount Companies". Whatever mechanism underlies the "Conta Global" (#488) subaccounts the engineer described, it is not `Subsidiary`.

### Finding D2: `Holding` (an STI subtype of `Company`) + `CompanyBranch` is the company-to-company hierarchy that exists in code

**Evidence:**
```ruby
# app/models/holding.rb
class Holding < Company
  rescue_unique_constraint index: :index_companies_on_name, field: :name
  has_many :branches, class_name: 'CompanyBranch', inverse_of: :holding, dependent: :destroy
end
```
```ruby
# app/models/company_branch.rb
class CompanyBranch < ApplicationRecord
  belongs_to :company, optional: true, inverse_of: :branch
  belongs_to :country, optional: true, inverse_of: :company_branches
  belongs_to :holding, optional: true, inverse_of: :branches

  validates :company_id, presence: true
  validates :country_id, presence: true
  validates :holding_id, presence: true
end
```
```ruby
# db/schema.rb:538-552
  create_table "company_branches", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.bigint "country_id", null: false
    ...
    t.bigint "holding_id", null: false
    ...
    t.index ["company_id"], name: "index_company_branches_on_company_id", unique: true
    ...
  end
```

**Source:** `app/models/holding.rb:1-8`; `app/models/company_branch.rb:1-11`; `db/schema.rb:538-552`; `app/models/company.rb:4,75` (`TYPES = %w[CallCenter EasyCompany Holding SalesCompany]`, `has_one :branch, class_name: 'CompanyBranch', ..., inverse_of: :company`)

**Significance:** `Company.TYPES` includes `Holding` as one of four STI subtypes. A `Holding`-type company `has_many :branches` (`CompanyBranch` rows), each `CompanyBranch` pointing to exactly one child `Company` (`company_id` has a **unique** index — one company can be a branch of at most one holding) and one `Country`. This is the code-level structure that could realize "one parent account, several country subaccounts underneath it". Feature-flag-shaped evidence corroborates this is a global/holding-scoped dashboard: `app/workers/holding/admin/processor.rb:6` and `app/workers/holding/president/processor.rb:6` both define `DASHBOARD_ACTION_KEYS = %w[holding_dashboard].freeze`, and `app/scopes/company_branch_scope.rb:5-9` gates the branch list query to `company.holding?` only (`if company.holding? ... company.branches ... else ... scope.none`). `git log --diff-filter=A -- app/models/company_branch.rb` shows this entire `Holding`/`CompanyBranch` structure was introduced in a single commit, `e3afd9d6f feat(*): Holding model`, dated **2025-04-24** — roughly 15 months before this spike — confirming the engineer's characterization that this is an existing-but-not-brand-new model.

### Finding D3: No code-level link found between `company_business_territories` and `company_branches`

**Evidence:** `grep -rn "CompanyBranch" app lib` (full list, see below) shows `CompanyBranch` referenced in: `app/models/holding.rb`, `app/models/company.rb` (the `has_one :branch` line only), `app/models/company_branch.rb` itself, `app/graphql_resolvers/company_branch_graphql_resolver.rb`, `app/workers/exchange_rate/processor.rb` (reads `CompanyBranch.pluck(:id)` to update `exchange_rate` from a currency API — unrelated to territory or retention), `app/scopes/company_branch_scope.rb`, `app/graphql_types/company_branch_graphql_type.rb`, and `lib/tasks/cron.rake` (the exchange-rate cron job description). None of these files, nor `app/models/company.rb`'s `Company::Processor` worker (`app/workers/company/processor.rb:1-24`, which only sets up `Status` records and dispatches to `EasyCompany::Admin::Processor` / `Holding::Admin::Processor` / `SuperAdmin::Processor` based on `company.type`), create, read, or cross-validate against `company_business_territories` when creating or managing a `CompanyBranch`. `grep -rln "CompanyBranch\.\|CompanyBranch\.new\|CompanyBranch\.create"` across the entire `app` repo returns exactly one file (`app/workers/exchange_rate/processor.rb`, a `.pluck(:id)` read, not a create).

**Source:** `app/workers/company/processor.rb:1-24`; `app/workers/exchange_rate/processor.rb:1-29`; full grep results enumerated above (no auxiliary file needed — the full match list is quoted directly)

**Significance:** The engineer's own description — *"Ele tem várias subcontas depois, através do Business Territory"* — describes subaccounts appearing "through Business Territory", but **the code does not show any automated mechanism that creates `CompanyBranch` rows from `company_business_territories` rows, or vice versa.** These are two independently-writable, independently-validated models with no code-level cross-reference found. This does not mean no such link exists — it may be a manual/operational step (someone manually creates the `CompanyBranch` rows to match the business territories when setting up a demo), or it may live in a different repo (`onboarding`) not in scope for this spike, or the engineer's phrasing may refer to a conceptual/process link rather than a coded one. **The code does not show this** — it is listed as an open question below, together with the discovery query needed to check whether `company_branches` rows actually exist for company #488's business-territory countries.

### Finding D4: `Holding` itself also has its own independent `business_territories`

**Evidence:**
```ruby
# spec/models/holding_spec.rb:12
  it { is_expected.to have_many(:business_territories).class_name(CompanyBusinessTerritory).inverse_of(:company).dependent(:destroy) }
```

**Source:** `spec/models/holding_spec.rb:12` (spec for the model behavior inherited from `app/models/company.rb:14`, since `Holding < Company`)

**Significance:** Because `Holding` is an STI subtype of `Company`, it inherits `has_many :business_territories` unmodified — a `Holding` row has its own `company_business_territories` rows (the countries **the holding itself** operates in, per the pre-existing 2023 business-territory concept) that are structurally independent of its `branches` (the `CompanyBranch` rows pointing at child companies, added in 2025). If company #488 "Conta Global" is in fact a `Holding`-type record, its `business_territory = [AR, BR, CO, MX, PE]` could be **either** (a) the holding's own operating countries (Finding D4's field) **or** (b) simply mirrored/duplicated from the aggregate of its branches' countries as a manual convenience, **or** (c) unrelated to the branches at all. The code alone cannot distinguish these without reading the actual `company_branches` rows for company #488 in production.

---

### Finding E1: The active anonymization mechanism is a single global window — `retention_jurisdiction_country_id` and `anonymizing_window_days` are not yet consumed anywhere

**Evidence:**
```ruby
# lib/application_configuration.rb:439-442
    # Default window of ~5.5 years for anonymization after company or user disablement
    def user_anonymizing_window
      Integer(ENV.fetch('USER_ANONYMIZING_WINDOW', 2008)).days.ago
    end
```
```ruby
# app/workers/company/user_anonymizer.rb
class Company < ApplicationRecord
  class UserAnonymizer < ApplicationWorker
    sidekiq_options queue: :anonymizing

    def perform
      company_ids =
        Company.with_uncached_connection { Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window).pluck(:id) }
      ...
```
```ruby
# app/workers/company/anonymizer.rb
class Company < ApplicationRecord
  class Anonymizer < ApplicationWorker
    sidekiq_options queue: :anonymizing
    def perform
      Company::UserAnonymizer.perform_async
      Company::DocumentRedactor::Producer.perform_async
      Company::ActionAnonymizer::Producer.perform_async
    end
  end
end
```

**Source:** `lib/application_configuration.rb:439-442`; `app/workers/company/user_anonymizer.rb:1-22`; `app/workers/company/anonymizer.rb:1-13`; `app/workers/company/action_anonymizer/producer.rb:10`; `app/workers/company/document_redactor/producer.rb:10`

**Significance:** `grep -rn "anonymizing_window_days\|retention_jurisdiction" app --include="*.rb" | grep -v spec` (Finding cross-referenced against B2's grep dump) shows these two new columns appear **only** in model associations, migrations, and the GraphQL create/update/type layer — **zero occurrences in any worker, cron task, or `ApplicationConfiguration` method.** Every anonymization worker (`Company::UserAnonymizer`, `User::Anonymizer::Producer`, `Company::ActionAnonymizer::Producer`, `Company::DocumentRedactor::Producer`) still filters exclusively on `Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window)`, a single ENV-driven constant (`USER_ANONYMIZING_WINDOW`, default `2008` days ≈ 5.5 years) applied identically to every company regardless of country. This same single-window design was itself the deliberate outcome of an earlier PR: `git log --oneline --grep=retention -i` shows `fbdc67d28 feat(anonymization): unify the retention window to ~5.5 years` (PR #5104, `feature/unify-anonymization-window`), and `CHANGELOG.md` records the entry *"Anonymization retention window unified to ~5.5 years"* under a prior release.

**Significance for backfill urgency:** because nothing currently reads `retention_jurisdiction_country_id` or `anonymizing_window_days` at anonymization time, a company with a NULL, wrong, or ambiguous jurisdiction today has **zero observable operational effect** on the anonymization cron — it still runs off the single global window exactly as before. The only currently-live consequence of a missing/wrong value is the presence-validation write-block described in Finding C2. Whatever code eventually wires `retention_jurisdiction_country_id` → `anonymizing_window_days` into the anonymization workers has not shipped yet — this spike found no branch, WIP commit, or rake task for it in this repo at the time of research.

### Finding E2: `cron.rake`'s own comment documents the single-window design as current

**Evidence:**
```
# lib/tasks/cron.rake:119-121
    # Orchestrates the anonymization of companies disabled longer than the configured
    # window (ApplicationConfiguration.user_anonymizing_window, ~5.5 years): user
    # anonymization, document redaction and action anonymization run in parallel.
```

**Source:** `lib/tasks/cron.rake:119-121`

**Significance:** Corroborates Finding E1 directly from the scheduled-task definition that actually triggers the cron in production (`cron:anonymization:company`).

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Backfill now, from business_territory, for single-territory companies only; leave multi-territory companies (like #633, #488) for manual review | Covers the "vast majority" case immediately with a mechanical, low-risk rule; multi-territory accounts get human judgment | Leaves an unknown number of companies un-backfilled — those companies will fail any subsequent `.save`/`.update` (Finding C2) until resolved | Derived from Findings A1, C2 — no option-specific code found |
| Wait to backfill until `#633`'s BR-territory data-error is understood/corrected in production | Avoids baking a data error into the new jurisdiction field twice (once via the wrong business_territory, again via a wrong jurisdiction) | Delays the presence-validation write-unblock for that company and any company like it | Engineer's own framing in the background section — not independently verified by code |
| Treat aggregator/holding accounts (like #488, if it is in fact a `Holding`) as out of scope for the current backfill, since retention jurisdiction may belong on each subaccount `Company`, not the aggregator | Avoids assigning a single jurisdiction to an account that structurally represents multiple countries' worth of data (Finding D2, D4) | The `holding_dashboard` feature is described by the engineer as "not yet in production" — if true, deferring these accounts may be safe, but the code alone does not confirm production status of any specific account | Findings D2, D4; engineer's own framing — the "not yet in production" claim itself was not independently verified by this spike (no feature-flag or `Action` enablement check was performed against production) |
| Backfill everyone uniformly from business_territory's first/only entry when there's exactly one, and flag every company with `business_territories.count > 1` into a manual-review bucket regardless of whether it looks like a data error or a genuine aggregator | Simple, mechanical rule; no code-level heuristic needed to distinguish "data error" from "real aggregator" | Requires a discovery query to separately identify which multi-territory companies are data errors (like #633) vs. real aggregators (like #488) before any manual assignment — the code does not provide this distinction on its own | Derived from Findings B1, B2, D3 |

---

## What remains uncertain

- **Who/what created the `[BR, MX]` business-territory row on company #633, and when.** The code shows the mechanism (`UpdateCompanyGraphqlMutation` with a `businessTerritories` nested-attribute array — Finding B2) but not the actor or timestamp for that specific production row. `company_business_territories` rows do carry `created_at`/`updated_at` timestamps in the schema (`db/schema.rb:554-562`), so a discovery query against production can answer "when" even though this spike cannot.
- **Whether `companies.client` is `true` or `false` for #633 and #488**, which determines whether the `CountryScope`/`StateScope`/`RegisterTypeScope` restriction (Finding C1) even applies to either account.
- **Whether company #488 is actually a `Holding`-type `Company` record**, and if so, whether it has any `company_branches` rows at all, and whether those rows' countries match its `business_territories` countries. Finding D3 shows the code has no automatic mechanism linking the two; only a production read can confirm what state #488 is actually in.
- **Whether the `holding_dashboard` feature (Finding D2) is genuinely inactive in production**, as the engineer states, or merely under-used. The code shows the `Action` (`key: 'holding_dashboard', level: 'root', resource: 'holding'`) and permission machinery exist and are wired to `Holding::Admin::Processor`/`Holding::President::Processor`, which run automatically whenever a `Holding`-type company is created (`Company::Processor#perform`, Finding D3) — so the *permission* exists for any `Holding` company today, whether or not any front-end surfaces a "global dashboard" UI for it. Whether a front-end UI consuming `company_branches` exists is outside this spike's scope (`app` repo only; the UI would live in `app-webclient`).
- **Whether the `onboarding` repo (a separate 4Shark backend, per `docs/PROJECTS-CATALOG.md`) has its own write path into `company_business_territories` or `company_branches`** via a shared database or a cross-service call. This spike was scoped to the `app` repo only, per the investigation brief; a cross-repo write path, if any, was not searched for.
- **What downstream consequence, if any, a wrong `retention_jurisdiction_country_id` has beyond the write-block described in Finding C2** — because Finding E1 shows nothing currently reads the column for anonymization purposes, there is currently no live "wrong window applied" risk, but this is time-bound to "as of this spike" — any future PR wiring the column into the anonymization workers would change this.

---

## Discovery queries for the engineer (cannot be run by this spike — no production access)

For each open question above, here is the concrete query/lookup that would resolve it, to run against production (or a synced read replica) directly, or via `bin/rails console` / an ECS-run console session per 4Shark's Script Discipline:

1. **Provenance of #633's BR territory row:**
   `CompanyBusinessTerritory.where(company_id: 633).order(:created_at)` — read `created_at`/`updated_at` per row, and cross-reference against `SecurityEvent`/audit-log entries around that timestamp if `app/models/security_events.rb`-backed auditing covers company mutations (not verified in this spike — the `docs/architecture/SECURITY_EVENTS.md` doc was not read; flagged as a further research pointer, not a finding).

2. **`client` flag for #633 and #488:**
   `Company.where(id: [633, 488]).pluck(:id, :client, :type)`

3. **Whether #488 is a `Holding` and has real `company_branches`:**
   `Company.find(488).type` and, if `Holding`, `Company.find(488).branches.pluck(:id, :company_id, :country_id)` — compare the resulting `country_id` set against `Company.find(488).countries.pluck(:id)` (the business-territory countries) to see whether they match, partially overlap, or are disjoint.

4. **Scale of the backfill — how many companies are single- vs. multi-territory:**
   `CompanyBusinessTerritory.group(:company_id).count.group_by { |_id, count| count == 1 }` (or the SQL-side equivalent, `CompanyBusinessTerritory.group(:company_id).having('count(*) > 1').count`, per 4Shark's database-side-shaping convention) to get the exact count of multi-territory companies needing manual review versus the single-territory majority that could be mechanically backfilled.

5. **Which companies already have `retention_jurisdiction_country_id` set (e.g. via the new front-end selector) vs. NULL:**
   `Company.where(retention_jurisdiction_country_id: nil).count` vs. `Company.where.not(retention_jurisdiction_country_id: nil).count`, to size the actual backfill population as of today (some companies may have already been assigned manually since the write path shipped on 2026-07-10).

---

## Suggested options for main and the engineer

- **Option A** — Mechanical backfill for single-territory companies now (from the discovery query in item 4); defer every multi-territory company (both data-error-shaped like #633 and aggregator-shaped like #488) to a manual-review bucket, resolved case by case.
- **Option B** — Fix #633's business-territory data first (remove the presumed-erroneous BR row) via discovery query 1's provenance check, then re-classify it as single-territory and let it flow through the mechanical rule in Option A.
- **Option C** — For aggregator/holding-shaped accounts (confirmed via discovery query 3), treat retention jurisdiction as a per-subaccount concern (assign it to each child `Company` under the `Holding`, not to the `Holding` record itself) rather than forcing a single value onto an account that structurally spans multiple countries.
- **Option D** — Leave any account tied to the not-yet-production `holding_dashboard` feature (Finding D2) out of the current backfill pass entirely, since (per the engineer) there are no real clients on that feature today and assigning it a jurisdiction now may not reflect how the feature will actually be used once shipped.

(No recommendation — these are the shapes the evidence supports; the engineer and main choose among them, or combine them.)
