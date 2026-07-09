# SPIKE v2 — Per-account (company-level) anonymization retention window

## Investigation question

v1 investigated a per-USER resolution of the anonymization retention window and left open
"which jurisdiction source governs retention." The engineer has now settled that question with
a different premise: retention is resolved **at the account (Company) level, one country per
account, applied to every employee of that account** — not derived from a user's own address nor
from the company's headquarters/branch. This spike v2 investigates three questions under that
premise: (1) for each country 4Shark operates in, what is the legally-grounded retention/erasure
window for employee personal data, and how confidently is that number available in public
sources; (2) what is the correct domain name for the new `companies` column that points to the
country governing an account's retention, given the engineer's own candidate `legal_country` and
instruction to "look for the domain"; and (3) how the new `countries.anonymizing_window_days` +
`companies.<column>` pair changes the modeling and the four anonymization producer queries
already mapped in v1 — without deciding between options.

## Sources consulted

- `~/.claude/plans/active/spike/anonimizacao-por-pais/SPIKE.md` (v1, read in full) — the
  anonymization pipeline, the current global window, the Brazil/Mexico legal research, and the
  three architecture options already surfaced (superseded on the "which jurisdiction source"
  question by the engineer's company-level decision, but every code-pipeline finding still holds)
- `~/.claude/plans/active/spike/anonimizacao-por-pais/anonimizacao-por-pais_legal_sources_1.md` —
  Brazil (LGPD art. 16, CLT art. 11) and Mexico (Código Civil Federal art. 1159, CFF arts. 30/67,
  LFPDPPP) legal sources from v1, reused here, not re-fetched
- `lib/application_configuration.rb:439-442` (re-read this session) — the single global window
- `app/models/company.rb:12,71,73,76,78,88-101` (re-read this session) — `business_territories`
  (many countries per company, unchanged from v1), `has_one :branch`, and the `locale` enum (9
  values, no direct country FK)
- `app/models/company_branch.rb`, `app/models/company_business_territory.rb`,
  `app/models/register_type.rb`, `app/models/legal_document.rb`, `app/models/country.rb`
  (all re-read this session) — every existing `belongs_to :country` in the codebase, for the
  naming/domain-modeling research
- `db/schema.rb:505-590` (re-read this session) — `companies`, `company_branches`,
  `company_business_territories`, `countries` table definitions
- See auxiliary `anonimizacao-por-pais_legal_sources_v2_country_retention.md` — every legal
  source consulted this session for Chile, Colombia, Argentina, Peru, Panama, Guatemala, and a
  US reference, plus the ARMA International naming-grounding source, with URLs and verification
  status per Citation Discipline
- https://magazine.arma.org/2022/04/the-impact-of-data-protection-laws-on-your-records-retention-schedule/
  — ARMA International, "jurisdiction" as the records-management term for what drives a
  retention schedule (VERIFIED, full quote in the auxiliary file)

## Findings

### Finding 1: the company-level premise removes v1's central open question, but not its code-pipeline findings

v1's Finding 7 identified a genuine ambiguity — a user's own `state.country` and a company's
`business_territories` are two different, potentially disagreeing "country" signals, and no code
in the codebase designated either as canonical for retention. The engineer's new instruction
(one country per account, chosen deliberately by the account, not derived from address or HQ)
resolves that ambiguity by design: neither `states.country_id` (a user's address) nor
`company_branches.country_id` (a company's registered domicile/currency) nor
`company_business_territories` (a company's declared multi-country markets) is the source. A
new, dedicated field is the source. This makes v1's Findings 1–4 (the two producer pipelines,
the shared per-user consumer, the runbook's documented rationale for the composite ~5.5-year
Brazilian figure) still fully applicable — only the "how do we resolve which window applies"
step changes, from a per-user join to a straight `company.<new_column> → country →
anonymizing_window_days` lookup.

**Source:** `~/.claude/plans/active/spike/anonimizacao-por-pais/SPIKE.md` Findings 1–4 and 7 (v1,
already verified by direct file reads in that session).
**Significance:** the four producer call sites v1 named
(`Company::UserAnonymizer`, `Company::ActionAnonymizer::Producer`,
`Company::DocumentRedactor::Producer`, `User::Anonymizer::Producer`) still all need the same
symmetric change; the per-user `User::Anonymizer::Consumer` still needs no change (it receives
only a `user_id`, per v1 Finding 3).

### Finding 2: no existing `belongs_to :country` in the codebase carries a semantic prefix — the table name carries the meaning, not the column name

```ruby
# app/models/company_branch.rb:5
belongs_to :country, optional: true, inverse_of: :company_branches
```
```ruby
# app/models/company_business_territory.rb:5
belongs_to :country, optional: true, inverse_of: :business_territories
```
```ruby
# app/models/register_type.rb:6
belongs_to :country, optional: true, inverse_of: :register_types
```
```ruby
# app/models/legal_document.rb:5
belongs_to :country, optional: true, inverse_of: :legal_documents
```

**Source:** `app/models/company_branch.rb:5`, `app/models/company_business_territory.rb:5`,
`app/models/register_type.rb:6`, `app/models/legal_document.rb:5` (all read directly this
session).
**Significance:** every single `belongs_to :country` relationship in this codebase — a
company's registered branch/domicile, a company's declared business territories, a per-country
register-type (CPF/CNPJ-equivalent), a per-country legal document — uses the literal column name
`country_id`. Disambiguation comes entirely from the OWNING TABLE (`company_branches`,
`company_business_territories`, `register_types`, `legal_documents`), never from a prefix on the
column itself. This is directly relevant to the naming question: putting the new relationship on
`companies.country_id` (bare) would collide with this pattern in the worst way — `companies` has
no existing `country_id`, but the bare name would read as "the company's country," which is
exactly the ambiguity the engineer is trying to avoid (colliding with the multi-country
`business_territories` concept). A prefixed name on `companies` (e.g. `legal_country_id`) is
therefore a deliberate DEPARTURE from the codebase's own naming convention, not an application of
it — worth surfacing plainly rather than silently prefixing.

### Finding 3: `CompanyBranch` is the closest existing SHAPE (one country per company) but a different MEANING

```ruby
# db/schema.rb:536-550
create_table "company_branches", force: :cascade do |t|
  t.bigint "company_id", null: false
  t.bigint "country_id", null: false
  t.datetime "created_at", null: false
  t.string "currency_iso"
  t.string "currency_locale"
  t.string "currency_name"
  t.string "currency_symbol"
  t.decimal "exchange_rate", precision: 16, scale: 10
  t.bigint "holding_id", null: false
  t.datetime "updated_at", null: false
  t.index ["company_id"], name: "index_company_branches_on_company_id", unique: true
  t.index ["country_id"], name: "index_company_branches_on_country_id"
  t.index ["holding_id"], name: "index_company_branches_on_holding_id"
end
```
**Source:** `db/schema.rb:536-550` (re-read this session), `app/models/company.rb:73`
(`has_one :branch, class_name: 'CompanyBranch', dependent: :destroy, inverse_of: :company`).
**Significance:** `CompanyBranch` is a `has_one` — exactly ONE country per company, the same
cardinality the engineer wants for the new legal-retention country. But its columns
(`currency_iso`, `exchange_rate`, `holding_id`) show its actual domain meaning is the company's
registered legal entity / financial domicile — not necessarily the country whose retention law
should govern, per the engineer's own Chile-company-with-Argentina-employees example, where the
branch/domicile country and the desired retention-governing country could legitimately differ.
The engineer already excluded reusing `branch` or `locale` for this purpose. This finding does
not reopen that decision — it is presented because `CompanyBranch`'s TABLE SHAPE (a dedicated
`has_one` model with its own `country_id`, rather than a column embedded directly on
`companies`) is an available modeling pattern already proven in this codebase, distinct from the
naming question, and relevant to "What remains uncertain" below since the engineer specifically
asked for a column on `companies` itself.

### Finding 4: `countries` table has no existing numeric/duration column — `anonymizing_window_days` would be the first

```ruby
# db/schema.rb:572-579
create_table "countries", force: :cascade do |t|
  t.string "acronym"
  t.datetime "created_at", null: false
  t.string "flag_url"
  t.string "name"
  t.datetime "updated_at", null: false
  t.index ["acronym"], name: "index_countries_on_acronym", unique: true
end
```
**Source:** `db/schema.rb:572-579` (re-read this session).
**Significance:** confirms the engineer's own framing — `countries` currently holds only
identity/display data (acronym, name, flag). Adding `anonymizing_window_days` here is a genuinely
new kind of column for this table (a business rule, not identity data), which is worth naming
carefully for the same reason as Finding 2 — nothing in the existing table hints at a
convention to follow.

### Finding 5: `companies` has no index on `disabled_at` — a pre-existing gap the new per-country query inherits

```ruby
# db/schema.rb:505-534 — companies (full column list; no disabled_at index)
t.datetime "disabled_at"
...
t.index ["commission_queue_suffix"], name: "index_companies_on_commission_queue_suffix", unique: true
t.index ["disabler_id"], name: "index_companies_on_disabler_id"
t.index ["name"], name: "index_companies_on_name", unique: true
```
**Source:** `db/schema.rb:505-534` (re-read this session; matches v1's own
`anonimizacao-por-pais_schema_1.txt` excerpt of the same table).
**Significance:** per the ActiveRecord Query Discipline (index awareness, rule 3), any per-country
query filtering on `disabled_at` — whether the current single global cutoff or a per-country
cutoff — runs against `companies` with no index covering `disabled_at` at all, let alone a
composite covering the new FK + `disabled_at`. This is not new to v2 (v1's own schema audit did
not find one either), but a per-country query shape changes the selectivity pattern enough that
it is worth re-flagging here as a finding, not resolved.

### Finding 6: Brazil and Mexico legal figures (v1) restated for the comparison table

Reused verbatim from v1, not re-researched this session:
- **Brazil**: ~5.5 years (2008 days) — composite of CLT art. 11 labor quinquenal (5y, UNVERIFIED
  by direct fetch this session or last, but internally corroborated by 4Shark's own runbook),
  CDC art. 27 (5y), civil debt reach, fiscal reach, plus a 6-month buffer.
- **Mexico**: strongest verified candidate is 10 years (Código Civil Federal art. 1159, general
  civil-action prescription, VERIFIED). CFF arts. 30/67 give 5 years generally, up to 10 in
  specific cases (VERIFIED). LFPDPPP ties its "bloqueo" period to the underlying relationship's
  own prescription rather than a fixed number (VERIFIED). Mexican labor-specific windows (LFT)
  are considerably shorter — UNVERIFIED by direct fetch, signal only.

**Source:** `anonimizacao-por-pais_legal_sources_1.md` (v1 auxiliary, already Citation-Discipline
verified in that session).
**Significance:** restated here only so the comparison table below is complete in one place;
no new research performed on Brazil/Mexico this session.

### Finding 7: Chile, Argentina, Peru, Guatemala each have one dominant labor-law figure; Colombia and Panama do not reduce to one clean number

Full detail with URLs and quotes is in the auxiliary file
`anonimizacao-por-pais_legal_sources_v2_country_retention.md`. Summary:

- **Chile** — 5 years post-termination (Dirección del Trabajo dictamina, VERIFIED at two
  independent URLs), explicitly anchored to the previsional/social-security prescription reach.
- **Argentina** — 2 years labor-claims prescription (LCT art. 256, VERIFIED); 5 years generic
  civil prescription post-2015 reform (CCyC art. 2560, VERIFIED — this replaced the old 10-year
  civil figure, unlike Mexico where the pre-reform-style 10-year civil figure is still current).
- **Peru** — 4 years labor-claims prescription from termination (Ley 27321, VERIFIED); 10 years
  personal-action civil prescription (Código Civil art. 2001, VERIFIED); a possible 2-year
  data-protection-specific ceiling was found only via WebSearch summary, NOT independently
  fetch-verified (all three candidate URLs failed to yield the literal text) — UNVERIFIED.
- **Guatemala** — 4 months (contract-derived rights, Código de Trabajo art. 263, VERIFIED) or 2
  years (Code-derived rights, art. 264, VERIFIED) — no data-protection statute exists to
  cross-reference against (VERIFIED absence: "en Guatemala no existe una ley que regule
  específicamente la protección de datos personales").
- **Colombia** — does NOT reduce to one number. Labor-claims prescription is 3 years (CST art.
  488, VERIFIED); a narrow SG-SST record subset has a MANDATORY 20-year minimum (Decreto 1072
  art. 2.2.4.6.13, VERIFIED); general payroll/personnel-file retention has an 80-year
  NON-mandatory archival best-practice recommendation (Archivo General de la Nación guidance via
  a secondary source, VERIFIED as a recommendation, explicitly NOT confirmed as a legal mandate
  for private employers); a possibly-indefinite case-law framing (Sentencia T-926/2013) was
  found only in search summaries, NOT independently verified.
- **Panama** — labor prescription rules are fragmented by claim type (professional-risk claims 2
  years, VERIFIED; other figures attributed to art. 12 by search summaries only, UNVERIFIED); its
  data-protection statute (Ley 81/2019) DOES supply a fixed number, but it is a 7-year buffer
  AFTER the underlying retention obligation ends (VERIFIED), not the retention obligation itself.

**Source:** auxiliary `anonimizacao-por-pais_legal_sources_v2_country_retention.md`, every entry
cross-referenced with its URL and verification status.
**Significance:** this is the direct answer to the "is this available for every country" question
the engineer asked. It is NOT uniformly available — six of the eight investigated countries have
at least one solid, independently-fetch-verified labor-prescription figure; Colombia and
Guatemala/Panama's data-protection angle either produce multiple conflicting figures (Colombia)
or no data-protection-specific figure at all (Guatemala, confirmed absent; Panama's is a buffer,
not a base). See the comparison table below for the full picture, and "What remains uncertain"
for what this means for the "cadastrar o valor de cada país" premise.

### Finding 8: "jurisdiction" is the records-management industry's own term for exactly this concept

**Evidence:** "your records retention schedule is compliant with the data protection
requirements in the jurisdictions where your organization operates" — ARMA International (the
professional association for records/information management), quoted directly.
**Source:** https://magazine.arma.org/2022/04/the-impact-of-data-protection-laws-on-your-records-retention-schedule/
(VERIFIED, fetched directly this session).
**Significance:** grounds "jurisdiction" — rather than "domicile," "locale," or "legal" alone —
as the established outside-4Shark term for "the country whose law determines how long a record
must be kept." This is one input into the naming options below, not a decision.

## Comparison table — retention/erasure figure by country

| Country | Best-supported figure(s) | Legal basis | Status |
|---|---|---|---|
| Brazil (current 4Shark practice) | ~5.5 years (2008 days), composite | LGPD art. 16 (storage limitation) + CLT art. 11 (5y quinquenal) + CDC art. 27 (5y) + civil/fiscal reach + 6mo buffer | LGPD art. 16 VERIFIED (v1); CLT art. 11 UNVERIFIED by direct fetch, internally corroborated by 4Shark runbook |
| Mexico | 10 years (civil) / 5–10 years (fiscal) / no fixed number (data-protection framing) | Código Civil Federal art. 1159; CFF arts. 30/67; LFPDPPP art. 25 | All three VERIFIED (v1); labor-specific figure UNVERIFIED |
| Chile | 5 years from termination | Dirección del Trabajo dictámenes (anchored to previsional prescription) | VERIFIED (two independent URLs) |
| Argentina | 2 years (labor claims) / 5 years (generic civil, post-2015) | LCT art. 256; CCyC art. 2560 | Both VERIFIED |
| Peru | 4 years (labor claims) / 10 years (civil, personal actions) / possibly 2 years (data protection) | Ley 27321; Código Civil art. 2001; D.S. 016-2024-JUS reglamento | Labor and civil VERIFIED; data-protection figure UNVERIFIED |
| Guatemala | 4 months (contract rights) / 2 years (Code rights) | Código de Trabajo arts. 263/264 | Both VERIFIED; NO data-protection law exists (VERIFIED absence) |
| Colombia | 3 years (claims) / 20 years (SG-SST subset, mandatory) / 80 years (general personnel file, non-mandatory recommendation) / possibly indefinite (unverified case law) | CST art. 488; Decreto 1072 art. 2.2.4.6.13; AGN archival guidance | Multiple figures VERIFIED individually; NO single confident number for the general case |
| Panama | Fragmented by claim type (2 years for professional-risk claims confirmed); +7-year post-obligation buffer under data-protection law | Código de Trabajo art. 12 (partial); Ley 81/2019 | Professional-risk figure and the 7-year buffer VERIFIED; the claimed "general 2-year cap" is UNVERIFIED (search-summary only, and the fetched clause is narrower than a general cap) |
| United States (reference only, not a current 4Shark locale) | 1 year (EEOC, 2y for large filers/federal contractors) / 3 years (FLSA payroll) | EEOC recordkeeping regs; FLSA | Both VERIFIED; no single federal figure — state law adds further variation, not researched here |

**Countries WITHOUT a solid, confidently-citable single figure**: Colombia (multiple diverging
figures, none clearly "the" answer for the general employee-record case) and, to a lesser
degree, Panama (the general labor-prescription figure is fragmented by claim type and not fully
fetch-verified; only the data-protection 7-year buffer and the narrow professional-risk 2-year
figure are solid). Guatemala DOES have a solid labor-code figure but explicitly has NO
data-protection statute to validate it against, unlike every other country in this table.

## Naming options for the new `companies` column

Presented as options; not decided. All four assume the engineer's own framing (a `belongs_to`,
`optional: true`, per the codebase's Optional-`belongs_to` convention, plus a manual `validates
:<column>_id, presence: true` decision left open — see "What remains uncertain").

- **Option A — `legal_country_id`** (the engineer's own suggestion). Short, but "legal" is
  already used in this codebase for two unrelated concepts — the `manager_legal_module` /
  `operator_legal_module` boolean feature flags on `companies` itself (`db/schema.rb:517,520`),
  and `LegalDocument` (the per-country terms-of-service/consent model, Finding 2). A reader
  scanning `companies` columns could plausibly guess "legal_country" relates to one of those
  instead of retention.
- **Option B — `data_retention_country_id`**. Names exactly what the column is used for today
  (Finding 1, Finding 6). Matches the 4Shark Variable Naming policy's rule 2 ("the name must
  accurately describe what the variable holds"). Narrower than "legal" in a way that could
  undersell the field if it is later reused for a broader purpose (e.g. deciding which privacy
  policy or legal-document localization applies to the account, not just retention).
  Related: `~/.claude/docs/JURISDICTION.md` uses "jurisdiction" for the analogous per-front
  concept, but that document's concern is legal/privacy-policy display, not retention scheduling.
- **Option C — `retention_jurisdiction_country_id`**. Combines "retention" (the current use)
  with "jurisdiction" — the term ARMA International's own records-management literature uses for
  precisely this driver of a retention schedule (Finding 8). Explicit that the value is a legal
  authority, not merely an address. Longest of the four candidates, and a bigger departure from
  the codebase's own bare-`country_id` convention (Finding 2) than Option A or B.
  `data_retention_country_id` and `retention_jurisdiction_country_id` differ mainly in whether
  "retention" or "jurisdiction" leads.
- **Option D — `anonymization_country_id`**. Ties the name to the ONE feature that reads it
  today, mirroring 4Shark's own existing naming (`USER_ANONYMIZING_WINDOW`,
  `Company::Anonymizer`, `user_anonymizing_window` — Finding 1, v1 Finding 1). Narrowest of the
  four — if the field is ever consulted by a feature other than anonymization, the name would be
  misleading in the same way flagged for Option A (a name that undersells or misdescribes what
  the column is actually used for, per Variable Naming policy rule 2).

## Modeling and query-shape changes

### The two new columns

| Column | Table | Type | Notes |
|---|---|---|---|
| `anonymizing_window_days` | `countries` | integer, nullable | First non-identity column on this table (Finding 4). No existing convention to anchor a default against — open question below. |
| `<name pending>_id` | `companies` | bigint FK to `countries` | `optional: true` per the codebase's Optional-`belongs_to` policy (every existing `belongs_to :country` in this codebase already follows that pattern, Finding 2). Whether to add `validates :<column>_id, presence: true` (mandatory going forward) is open — see below. |

Per the ActiveRecord Query Discipline (index awareness, rule 3): every existing `country_id`
column that supports a lookup carries an index (`company_branches.country_id`,
`company_business_territories.country_id` — Finding 3, `db/schema.rb:536-550,552-560`). The new
FK on `companies` would need the same, since the four producer queries below join/filter on it.
This is a finding, not a decision to add the index unilaterally.

### Illustrative query shape — current vs proposed (NOT a code change to make now)

**Current** (repeated across all four producer files, per v1 Finding 2):
```ruby
Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window).pluck(:id)
```

**Proposed, illustrative only** — bounded loop over `countries` (small, fixed set), each
iteration a database-side `where`, consistent with the ActiveRecord Query Discipline (rule 2,
database-side shaping) and the Data Processing Pattern (IDs-only):
```ruby
# ILLUSTRATIVE ONLY — not a code change to make now, naming/defaults pending engineer decision
Country.find_each do |country|
  window_days = country.anonymizing_window_days || ApplicationConfiguration.default_anonymizing_window_days
  company_ids =
    Company.where(<pending_column>_id: country.id, disabled_at: ...window_days.days.ago).pluck(:id)

  company_ids.each do |company_id|
    user_ids = User.where(company_id: company_id, anonymized: false).pluck(:id)
    user_ids.each { |user_id| User::Anonymizer::Consumer.perform_async(user_id) }
  end
end

# companies with no <pending_column>_id set are NOT covered by this loop — see "fallback" below
```

This resolves v1's Finding 7 ambiguity (which jurisdiction source) by construction — there is
only one candidate source now (the new column), not two disagreeing ones. It does NOT resolve
v1's caution that all four producer call sites need the identical change applied symmetrically,
nor the pre-existing `disabled_at` index gap (Finding 5).

## What remains uncertain

- **Fallback for a company with no `<pending_column>_id` set.** Two candidate framings, carried
  over from v1 and still unresolved: the runbook frames the current window as a MAXIMUM
  ("the maximum we may keep the data, after which storage limitation requires erasing" —
  `LGPD-DATA-ERASURE.md:76`, already verified in v1), which argues for erasing on the SHORTEST
  applicable fallback; but under-erasing prematurely risks losing legal-defense capability, which
  argues for the LONGEST fallback (or simply the existing `ENV.fetch('USER_ANONYMIZING_WINDOW',
  2008)` default, unchanged). This spike does not resolve the tension.
- **Backfill of existing companies.** Every company created before the new column exists has no
  value. Which country to assign — inferred from `business_territories`/`branch` heuristically,
  or a manual/ops-driven assignment per account — was not investigated; it is an operational
  decision, not a codebase fact this spike can resolve.
- **Countries with no confident legal figure (Finding 7).** Colombia in particular does not
  reduce to one number in this research. If the design is "every row in `countries` gets an
  `anonymizing_window_days` value," Colombia (and to a lesser extent Panama) would need either an
  engineer/legal-team judgment call on which of the several found figures to encode, or a
  deliberate decision to leave that country on the global default rather than a country-specific
  value it cannot be confidently backed by a citation. This spike surfaces the gap; it does not
  fill it with a guess.
- **`legal_country_id` naming ambiguity with existing `companies` boolean flags.** Finding 2/
  Option A: `manager_legal_module` and `operator_legal_module` already use "legal" as a prefix
  for unrelated feature-flag concepts on the very same table. Whether that collision is
  acceptable in practice (a reviewer distinguishing by suffix — `_module` boolean vs `_country`
  FK) or worth avoiding is a naming-style judgment, not resolved here.
- **Column-on-`companies` vs a dedicated `has_one`-style table** (Finding 3). The engineer's
  brief already specifies "nova coluna na companies," so this spike does not treat it as an open
  question to decide — it is surfaced only because `CompanyBranch`'s shape (a separate table with
  its own bare `country_id`, `has_one` from `Company`) is the one precedent in this codebase for
  "exactly one country per company," in case the engineer wants to weigh it against the
  already-stated column-on-`companies` design.
- **Whether `countries.anonymizing_window_days` should be `NOT NULL` with a DB-level default
  (e.g. 2008) or nullable with the Ruby-side `|| default` fallback shown in the illustrative
  query above.** Not resolved — both are used elsewhere in this schema for different columns, and
  no single precedent points to one over the other for a brand-new business-rule column on
  `countries`.
- **Whether Brazil (and Mexico, if a number is eventually confirmed) should be migrated onto the
  new per-country mechanism, or remain on the literal `USER_ANONYMIZING_WINDOW` ENV default
  under whichever design is chosen.** Not decided here, carried over from v1.

## Suggested options for main and the engineer

**Naming** (§ "Naming options for the new `companies` column" above):
- Option A: `legal_country_id` (engineer's own suggestion)
- Option B: `data_retention_country_id`
- Option C: `retention_jurisdiction_country_id`
- Option D: `anonymization_country_id`

**Per-country retention value, given Finding 7's availability gap:**
- Option 1: encode every country's best-supported figure from the comparison table above,
  including Colombia's, picking one of its several diverging figures by engineer/legal-team
  judgment call
- Option 2: encode only the countries with a solid, VERIFIED, single figure (Brazil composite,
  Mexico civil, Chile, Argentina, Peru, Guatemala), and leave Colombia/Panama/others on the
  global `USER_ANONYMIZING_WINDOW` default until a confident figure is confirmed
- Option 3: treat this as a legal/compliance research task separate from the engineering change —
  ship the schema and the mechanism now with every country defaulting to the global window, and
  populate country-specific values in a later, dedicated pass

Each option is orthogonal to the naming decision and to the fallback/backfill open questions
above — none of them are decided here.
