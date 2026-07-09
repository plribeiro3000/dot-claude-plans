# SPIKE — Per-country anonymization retention window

## Investigation question

Today 4Shark anonymizes a deactivated client's user data after a single, global window
(`USER_ANONYMIZING_WINDOW`, defaulting to 2008 days ≈ 5.5 years) applied identically to every
country. The engineer was told Mexico requires 10 years of retention, different from Brazil.
This spike investigates: (1) how the current anonymization flow works end-to-end, (2) whether
and how a user's jurisdiction/country can be resolved today, (3) what legal basis exists for
the Brazilian ~5.5-year figure and the Mexican "10 years" figure, and (4) what options exist to
make the retention window configurable per country — without deciding which option to take.

## Sources consulted

- `lib/application_configuration.rb:439-442` — the single global window, `USER_ANONYMIZING_WINDOW`
- `app/workers/company/anonymizer.rb`, `app/workers/company/user_anonymizer.rb`, `app/workers/user/anonymizer/producer.rb`, `app/workers/user/anonymizer/consumer.rb`, `app/workers/company/action_anonymizer/producer.rb`, `app/workers/company/document_redactor/producer.rb` — the full anonymization pipeline (two independent cron-triggered flows)
- `lib/tasks/cron.rake:114-150` — the two cron tasks (`anonymization:company`, `anonymization:user`) and their documented pipelines
- `app/models/user.rb`, `app/models/state.rb`, `app/models/country.rb`, `app/models/legal_document.rb`, `app/models/company.rb` — the existing per-user jurisdiction resolution mechanism (used today for `/legalDocumentAcceptance`)
- `db/schema.rb` (companies, users, states, countries, company_business_territories) — confirms no direct country column on `companies`; jurisdiction reaches a user only via `state_id → states.country_id → countries`, or via `companies` → `company_business_territories` → `countries` (a company can have MANY countries)
- `~/.claude/docs/runbooks/compliance/LGPD-DATA-ERASURE.md` (read in full) — the current PII footprint, the pitfalls (R1–R7), the verification checklist, and 4Shark's own documented rationale for the ~5.5-year figure
- `~/.claude/docs/JURISDICTION.md` (read in full) — the existing "front is the jurisdiction unit, not the backend" control, and the Control A (naming guardrail) vs Control B (runtime per-user resolution) framework already solved for a structurally similar problem
- See auxiliary `anonimizacao-por-pais_code_1.rb` — consolidated anonymization pipeline code, all 8 files, for archival reference
- See auxiliary `anonimizacao-por-pais_code_2.rb` — consolidated jurisdiction-resolution code (`User`, `State`, `Country`, `LegalDocument`, `Company` excerpts)
- See auxiliary `anonimizacao-por-pais_schema_1.txt` — `db/schema.rb` excerpts for the five tables involved, with an index-awareness note
- See auxiliary `anonimizacao-por-pais_legal_sources_1.md` — every legal-research quote (Brazil + Mexico), with URLs and verification status per Citation Discipline
- https://lgpd-brasil.info/capitulo_02/artigo_16 — LGPD art. 16 literal text (VERIFIED)
- https://www.conceptosjuridicos.com/mx/codigo-civil-articulo-1159/ — Código Civil Federal art. 1159, 10-year general civil prescription (VERIFIED)
- https://contadormx.com/plazos-para-conservacion-de-la-contabilidad-y-documentacion-del-cff/ — CFF arts. 30 and 67, 5/10-year accounting retention (VERIFIED)
- http://www.ordenjuridico.gob.mx/Documentos/Federal/html/wo83178.html — LFPDPPP "bloqueo" definition and art. 25 (VERIFIED)

## Findings

### Finding 1: the retention window is a single global value, read from one method

**Evidence:**
```ruby
# lib/application_configuration.rb:439-442
# Default window of ~5.5 years for anonymization after company or user disablement
def user_anonymizing_window
  Integer(ENV.fetch('USER_ANONYMIZING_WINDOW', 2008)).days.ago
end
```
**Source:** `lib/application_configuration.rb:439-442`
**Significance:** every consumer of this method (six call sites across four worker files, see
Finding 2) gets the exact same cutoff regardless of the user's or company's country. There is
no parameter, no per-record variation, and no notion of "which country" anywhere in this
method's signature or callers.

### Finding 2: two independent pipelines, both anchored on the same global window

There are TWO separate cron-triggered flows, not one:

**Pipeline A — company-level disablement** (`anonymization:company`, daily 05:00 UTC):
```ruby
# app/workers/company/user_anonymizer.rb:9-20
def perform
  company_ids =
    Company.with_uncached_connection { Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window).pluck(:id) }

  company_ids.each do |company_id|
    user_ids = User.with_uncached_connection { User.where(company_id: company_id, anonymized: false).pluck(:id) }

    user_ids.each do |user_id|
      User::Anonymizer::Consumer.perform_async(user_id)
    end
  end
end
```
Fanned out from `Company::Anonymizer#perform` (`app/workers/company/anonymizer.rb:7-11`), which
also triggers `Company::DocumentRedactor::Producer` and `Company::ActionAnonymizer::Producer`
in parallel — same `Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window)`
cutoff repeated in each producer (`app/workers/company/action_anonymizer/producer.rb:9-10`,
`app/workers/company/document_redactor/producer.rb:9-10`).

**Pipeline B — individual user disablement inside a still-enabled company**
(`anonymization:user`, also daily 05:00 UTC):
```ruby
# app/workers/user/anonymizer/producer.rb:14-24
company_ids.each do |company_id|
  user_ids =
    User.with_uncached_connection do
      User
        .where(
          company_id: company_id,
          anonymized: false,
          disabled_at: ...ApplicationConfiguration.user_anonymizing_window
        )
        .pluck(:id)
    end

  arguments = user_ids.zip
  Sidekiq::Client.push_bulk('class' => User::Anonymizer::Consumer, 'args' => arguments)
end
```
**Source:** `app/workers/company/anonymizer.rb:1-13`, `app/workers/company/user_anonymizer.rb:1-23`, `app/workers/user/anonymizer/producer.rb:1-33`, `lib/tasks/cron.rake:114-150`
**Significance:** any per-country change must be applied symmetrically to BOTH pipelines (four
producer call sites total: `Company::UserAnonymizer`, `Company::ActionAnonymizer::Producer`,
`Company::DocumentRedactor::Producer`, `User::Anonymizer::Producer`) or the two flows will
silently diverge — e.g. a company-level disablement respecting the new per-country window while
an individual-user disablement inside an active company keeps using the old global one, or
vice versa.

### Finding 3: actual anonymization (the per-user consumer) is shared and unconditional

```ruby
# app/workers/user/anonymizer/consumer.rb:10-27
def perform(user_id)
  user = User.find(user_id)
  user.anonymized = true
  user.email = "#{User::ANONYMIZED_VALUE}@#{User::ANONYMIZED_VALUE}.com"
  user.unique_register_id = User::ANONYMIZED_VALUE
  user.first_name = User::ANONYMIZED_VALUE
  user.last_name = User::ANONYMIZED_VALUE
  user.save!

  identifier_values = user.identifiers.pluck(:value)
  actions_by_identifier_value = UserIdentifierAction.where(company_id: user.company_id, user_identifier_value: identifier_values)
  actions_by_new_identifier_value = UserIdentifierAction.where(company_id: user.company_id, new_user_identifier_value: identifier_values)
  action_ids = actions_by_identifier_value.or(actions_by_new_identifier_value).pluck(:id)
  Sidekiq::Client.push_bulk('class' => Company::ActionAnonymizer::Consumer, 'args' => action_ids.zip)

  user.identifiers.update_all(primary: false)
  user.identifiers.destroy_all
end
```
**Source:** `app/workers/user/anonymizer/consumer.rb:10-27`
**Significance:** the consumer receives only a `user_id` — it has no notion of "which window
applied" or "which country this user is in." The window decision happens entirely upstream, in
the producer's selection query (Finding 2). Any per-country solution only needs to change the
SELECTION query, not this consumer.

### Finding 4: the PII footprint and operational pitfalls are already documented in 4Shark's own runbook

The runbook (read in full) states the anchor and the composite legal basis for the current
window:

> "Window: `USER_ANONYMIZING_WINDOW` (env, 2008 days ≈ 5.5 years) — a single window for both
> flows. [...] Anchor: `company.disabled_at` for a deactivated company; `user.disabled_at` for a
> user disabled individually inside an active company. Same window either way."

**Source:** `~/.claude/docs/runbooks/compliance/LGPD-DATA-ERASURE.md:81-84`

> "The window is not arbitrary: it is the longest period the data can still be legally
> needed — the ~5-year reach of claims (labor quinquenal, CDC art. 27, civil debt, fiscal) plus
> a 6-month buffer so a proceeding filed near the 5-year edge is not destroyed mid-course."

**Source:** `~/.claude/docs/runbooks/compliance/LGPD-DATA-ERASURE.md:72-73`

The runbook also documents `Company::UserAnonymizer` as company-unscoped by design (pitfall
R2): "Its `perform` takes no argument and processes **every** disabled company in the window.
Never call it to target one client; use the per-record consumers." (`LGPD-DATA-ERASURE.md:142-144`).
The full PII footprint table (`users`, `user_identifiers`, `user_identifier_actions`, S3
document attachments, `user_audit_rows`) is at `LGPD-DATA-ERASURE.md:100-113`, and the
seven pitfalls (`UserDocument` destroy-cascade, non-scoped `UserAnonymizer`,
`UserIdentifierAction` anonymize-not-delete exception, IP redaction, email/Zendesk erasure) are
at `LGPD-DATA-ERASURE.md:136-172`.

**Significance:** any redesign of the window-selection logic must preserve every property this
runbook documents — the R2 non-scoping caveat in particular means a naive "run the whole
anonymizer once per country" restructuring is actually closer to the CURRENT shape (which
already loops per-company inside `perform`) than a departure from it.

### Finding 5: a user's country IS already resolvable today — used for `/legalDocumentAcceptance`

```ruby
# app/models/user.rb:376-378
def legal_documents
  @legal_documents ||= LegalDocument.enabled.for_company(company_id).for_country(state.country_id)
end
```
**Source:** `app/models/user.rb:376-378`

This resolves through `user.state_id → states.country_id → countries`:
```ruby
# app/models/state.rb:1-8
class State < ApplicationRecord
  has_many :users, dependent: :nullify, inverse_of: :state
  belongs_to :country, optional: true, inverse_of: :states

  validates :country_id, presence: true
  validates :iso3166, presence: true
```
**Source:** `app/models/state.rb:1-8`

And `state_id` presence is validated on `User` itself (with an ISO-3166-string escape hatch
used at import/API time):
```ruby
# app/models/user.rb:199
validates :state_id, presence: true, unless: -> { state_iso3166_present? }
```
**Source:** `app/models/user.rb:199`

**Significance:** this is the direct answer to the task's central question. 4Shark already has
a working, per-USER (not per-company) jurisdiction resolution mechanism in production, used
today to decide which `LegalDocument` a specific user must accept. The same `state.country`
join could resolve which retention window applies to that same user. This is also the exact
"Control B — runtime jurisdiction resolution" pattern `JURISDICTION.md` already names and
grounds in this same code path:

> "B — Runtime jurisdiction resolution (only if forced). Resolve the value from the user's
> jurisdiction at login (from the company/backend data — the same per-user source behind
> `/legalDocumentAcceptance`)."

**Source:** `~/.claude/docs/JURISDICTION.md:63`

### Finding 6: `state_id` is nullable at the database level despite the model validation

```
# db/schema.rb:2438-2439 (see auxiliary anonimizacao-por-pais_schema_1.txt)
t.integer "state_id"
```
No `null: false` constraint. `t.index ["state_id"], name: "index_users_on_state_id"` exists,
but nothing enforces the column at the DB layer — only `validates :state_id, presence: true,
unless: -> { state_iso3166_present? }` in the model (Finding 5).

**Source:** `db/schema.rb:2438` (auxiliary: `anonimizacao-por-pais_schema_1.txt`)
**Significance:** legacy users, or users created through a path that bypasses this validation
(bulk import before the validation existed, a direct DB write, etc.), could have `state_id:
nil`. Any per-country resolution built on this column needs an explicit fallback for that case
— see "What remains uncertain" below.

### Finding 7: a company can have MULTIPLE countries — there is no single "the company's country"

```ruby
# app/models/company.rb:12,71,76,78
has_many :business_territories, class_name: 'CompanyBusinessTerritory', inverse_of: :company, dependent: :destroy
# ...
has_many :countries, through: :business_territories
# ...
accepts_nested_attributes_for :business_territories, allow_destroy: true, reject_if: :all_blank
validates :business_territories, length: { minimum: 1 }
```
**Source:** `app/models/company.rb:12,71,76,78`, backed by
`db/schema.rb:552-560` (`company_business_territories`, unique on `[company_id, country_id]`
— i.e. many rows per company are structurally allowed)

**Significance:** this directly confirms the premise in the investigation brief. There is no
"the company's country" — a company legitimately declares one-or-more operating countries via
`business_territories`, which is a SEPARATE source of "country" from a user's own `state_id`
(Finding 5). This means TWO different, potentially disagreeing signals exist for "what country
is this user's data governed by":

1. **The user's own address** — `user.state_id → states.country_id` (used today for legal
   document acceptance)
2. **The company's declared business territories** — `company.business_territories → countries`
   (can be multiple per company)

Neither is designated in the current codebase as "the" jurisdiction source for retention
purposes — this spike found no code that resolves a single canonical country for either a user
or a company for any anonymization-adjacent purpose. This ambiguity is listed under "What
remains uncertain" rather than resolved here.

## Legal basis — Brazil vs Mexico

| Country | Cited figure | Candidate legal basis | Verification |
|---|---|---|---|
| Brazil (current 4Shark practice) | ~5.5 years (2008 days) after `disabled_at` | Composite: CLT art. 11 (labor claims, 5y quinquenal) + CDC art. 27 (consumer claims, 5y) + "civil debt" reach + fiscal reach, plus a 6-month buffer, per 4Shark's own documented rationale | LGPD art. 16 (storage-limitation basis) VERIFIED at https://lgpd-brasil.info/capitulo_02/artigo_16 — quote: "Os dados pessoais serão eliminados após o término de seu tratamento" plus the four listed retention exceptions. CLT art. 11's literal text could NOT be independently re-verified by direct fetch this session (6 URLs attempted, all failed — network/HTTP errors, see auxiliary `anonimizacao-por-pais_legal_sources_1.md`); the figure is internally corroborated by 4Shark's own runbook (`LGPD-DATA-ERASURE.md:72-73`, already verified by direct file read) |
| Mexico — best-supported candidate for "10 years" | 10 years | Código Civil Federal art. 1159 — general prescription for personal actions ("acciones personales"), the closest Mexican analog to the "civil debt" component of Brazil's composite figure | VERIFIED at https://www.conceptosjuridicos.com/mx/codigo-civil-articulo-1159/ — quote: "Se necesita el lapso de diez años, contado desde que una obligación pudo exigirse, para que se extinga el derecho de pedir su cumplimiento" |
| Mexico — fiscal/accounting alternative | 5 years generally, up to 10 years in specific cases | Código Fiscal de la Federación arts. 30 (general 5y) and 67 (extends to 10y for non-registration, missing accounting, non-filing, or fiscal-loss-carryforward cases) | VERIFIED at https://contadormx.com/plazos-para-conservacion-de-la-contabilidad-y-documentacion-del-cff/ |
| Mexico — data-protection framing | Not a fixed number — tied to whatever prescription period governs the underlying relationship | LFPDPPP ("bloqueo") — the blocking/retention period after processing ends equals the prescription period of the legal relationship that founded the processing | VERIFIED at http://www.ordenjuridico.gob.mx/Documentos/Federal/html/wo83178.html — quote: "El periodo de bloqueo será equivalente al plazo de prescripción de las acciones derivadas de la relación jurídica que funda el tratamiento" |
| Mexico — labor-specific | Considerably shorter than 10 years (as low as ~1 year for payroll docs post-termination; 2 months for some dismissal actions) | Ley Federal del Trabajo arts. 804, 516-522 | NOT independently fetch-verified this session — `WebSearch` summary only, does not sustain a Finding per Citation Discipline. Recorded as a signal that a direct labor-law basis (the Brazilian-shaped analog) does not appear to be where the Mexican "10 years" figure comes from |

**Key legal finding:** the "10 years" figure the engineer was given does not appear to map
cleanly onto a Mexican LABOR-law analog of Brazil's CLT-driven figure — Mexican labor-specific
document/claim windows found in this research are considerably shorter. The strongest
documented candidate for "10 years" is the Mexican Federal Civil Code's general prescription
period (art. 1159), structurally the same TYPE of basis ("civil debt reach") that is already
one ingredient of 4Shark's own Brazilian composite figure — just landing at a longer number
because Mexico's general civil prescription (10y) is longer than Brazil's (5y). This is
presented as a finding, not a conclusion — full source detail and every attempted URL (with
failures) is in `anonimizacao-por-pais_legal_sources_1.md`.

## Solution options for parametrizing the window per country

All three options share the same two prerequisites established in Findings 5–7: (a) resolve a
country per user (or per company, per the open question below) using the existing
`state → country` join (or `business_territories`), and (b) change the SELECTION query in the
four producer call sites (Finding 2) — the per-user consumer (Finding 3) needs no change.

**Current selection shape** (repeated four times today, one flat cutoff):
```ruby
Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window).pluck(:id)
```

### Option A — country → days map in `application_configuration.rb`, one query per country

Add a small country-acronym-keyed map (e.g. ENV-overridable per country, or a Ruby constant),
and replace each single flat query with one query PER configured country, joining through the
chosen jurisdiction source:

```ruby
# illustrative only — not a code change to make now
Company.joins(business_territories: :country)
       .where(countries: { acronym: country_code }, disabled_at: ...cutoff_for(country_code))
       .pluck(:id)
```

This keeps every query database-side per the ActiveRecord Query Discipline (rule 2) — the loop
iterates over a small, fixed set of configured countries, not over individual users, so it is
not the pluck+Ruby-reshape anti-pattern.

**Trade-offs:**
- Pros: no schema change; smallest code diff; keeps the existing IDs-only / per-record worker
  pattern intact end-to-end.
- Cons: N queries per producer run instead of 1 (N = number of configured countries — small,
  bounded); adding or changing a country's window requires an ENV/code change plus a deploy;
  the fallback for users/companies with no resolvable country (Finding 6) still needs an
  explicit decision.

### Option B — store the window on the `countries` table (data-driven)

Add a column (e.g. `countries.anonymizing_window_days`) via a proper Rails migration
(`bin/rails generate migration`, then `db:migrate`, per `RAILS-MIGRATIONS.md`), seeded per
country. Resolution still needs a join from `users`/`companies` through to `countries` —
either the same bounded per-country ActiveRecord loop as Option A (looping over
`Country.pluck(:id, :acronym, :anonymizing_window_days)`, itself small and bounded), or a
single SQL expression comparing `disabled_at` against a computed interval from the joined
column. The latter is raw SQL/Arel and would require explicit engineer authorization per the
ActiveRecord Query Discipline (rule 1: raw SQL only on explicit engineer authorization).

**Trade-offs:**
- Pros: legal/compliance can change a country's retention window as a data change, without a
  code deploy; centralizes the value alongside the `Country` model that already anchors
  `LegalDocument` and `register_types`.
- Cons: needs a migration plus a seed/backfill step; a wrong value in the database has the same
  blast radius as a wrong ENV value, but with less code-review visibility (no PR diff shows the
  number changing) unless a separate change-review process is defined for editing it.

### Option C — global default (ceiling) + narrow per-country override list

Keep `USER_ANONYMIZING_WINDOW` as the default for every country not explicitly listed, and add
a short, explicit override structure (a small Hash literal or a narrow table) only for
countries with a documented divergence — Mexico being the first entry. Resolution: for each
user/company, resolve country; if an override exists for that country, use it; otherwise fall
through to the existing global default.

**Trade-offs:**
- Pros: smallest DATA-SHAPE surface for the common case — most countries keep using the exact
  query shape that exists today; an override list is easy to audit (a short, explicit "these
  countries are different, and here is the citation for why").
- Cons: still needs the identical jurisdiction-resolution wiring as A/B — it changes only how
  the window VALUE is stored (map with a default vs. exhaustive table), not whether the
  restructuring of the four producer queries is needed. It is a data-shape variant of Option A,
  not an independent implementation path.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| A — code/ENV country map, per-country query loop | No schema change; smallest diff | Deploy required to add/change a country; N queries per run | Findings 1–3 |
| B — window stored on `countries` table | Legal/compliance can edit without a deploy; co-located with existing `Country` model | Needs a migration + seed; raw-SQL path (if chosen for the join) needs explicit authorization | Finding 5, `RAILS-MIGRATIONS.md`, ActiveRecord Query Discipline |
| C — default + narrow override list | Smallest data-shape footprint for the common case; easy to audit | Same query restructuring as A; just a different storage shape for the value | Derived from A |

## What remains uncertain

- **Which jurisdiction source governs retention: the user's own `state.country`, or the
  company's `business_territories`?** Finding 7 shows both exist and can disagree (a company
  can declare multiple business territories; a user's own state/address is a separate,
  independent field). No code in this codebase currently designates one as canonical for any
  anonymization-adjacent purpose — this is a design decision, not a fact this spike can resolve.
- **What is the fallback for a user/company with no resolvable country** (Finding 6:
  `state_id` is nullable at the DB level despite model-level presence validation)? Two
  candidate framings point in opposite directions: the runbook frames the window as a MAXIMUM —
  "the maximum we may keep the data, after which storage limitation requires erasing"
  (`LGPD-DATA-ERASURE.md:76`) — which argues for the SHORTEST applicable window as the safe
  fallback (erase sooner, avoid over-retention risk). But the window also exists to preserve
  legal defensibility during the claims-reach period, which argues for the LONGEST applicable
  window as the safe fallback (don't erase prematurely and lose the ability to defend a claim).
  This spike surfaces the tension; it does not resolve it.
- **What is the exact, legally-confirmed Mexican figure and its citation?** This spike found
  strong support for "10 years" via Código Civil Federal art. 1159 (general civil prescription)
  but could not confirm this is what the engineer's source actually meant, nor rule out the
  CFF's conditional 10-year fiscal-inspection window (art. 67) or a different basis entirely.
  Recommend confirming the exact source of the "10 years" instruction with whoever provided it
  before encoding a specific number.
- **CLT art. 11's literal text** could not be independently re-verified by direct `WebFetch` in
  this session (six URLs attempted, all failed for network/HTTP reasons — see
  `anonimizacao-por-pais_legal_sources_1.md`). The figure is corroborated internally via
  4Shark's own runbook, already verified by a direct file read, so the Brazilian side of the
  BR-vs-MX comparison rests on internal, not fresh external, verification of that specific
  article's text.
- **Backfill of `state_id`** for any existing users/companies that predate the validation, or
  were created through a path that bypasses it — the size of this gap in the current database
  was not queried (out of reach for a codebase-only spike; would need a read-only production
  query, e.g. `User.where(state_id: nil).count`, to quantify).
- **Whether Brazil should also migrate onto the new per-country mechanism**, or keep using
  `USER_ANONYMIZING_WINDOW` as a literal backward-compatible default under whichever option is
  chosen — not decided here.

## Suggested options for main and the engineer

- Option A: code/ENV country map + per-country query loop in the four existing producer files
- Option B: window value stored on the `countries` table, data-driven, migration-backed
- Option C: global default + narrow per-country override list (a storage-shape variant of A)

Each option additionally requires the engineer to decide the two open questions above (which
jurisdiction source, and what the no-country fallback should be) before implementation — those
decisions are orthogonal to which of A/B/C is chosen.
