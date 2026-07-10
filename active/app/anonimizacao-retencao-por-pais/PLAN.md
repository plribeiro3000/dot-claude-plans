# PLAN — Per-country anonymization retention window

## Context

Today the app anonymizes a deactivated client's user data after a single global window —
`ENV.fetch('USER_ANONYMIZING_WINDOW', 2008).days.ago` (`lib/application_configuration.rb:439-442`),
2008 days for every account regardless of country. Different countries mandate different legal
retention periods for employee data. This plan makes the retention window resolvable **per
account**, driven by the country that legally governs each account's data retention.

Research backing this plan (do not re-run — decisions below are already settled):
- `~/.claude/plans/active/spike/anonimizacao-por-pais/SPIKE.md` (v1) — the anonymization pipeline
  map and the Brazil/Mexico legal basis
- `~/.claude/plans/active/spike/anonimizacao-por-pais/SPIKE-v2.md` (v2) — the per-account premise,
  per-country legal research, and the naming/domain analysis
- `~/.claude/plans/active/spike/anonimizacao-por-pais/anonimizacao-por-pais_legal_sources_v2_country_retention.md`
  — every legal source per country, with URLs and verification status

## Settled decisions (engineer-approved)

1. **Resolution level**: per account (`Company`), one governing country per account, applied to
   every user of that account. NOT per-user. NOT derived from the user's address, the company's
   branch/domicile, nor `business_territories`.
2. **New column on `companies`**: `retention_jurisdiction_country_id` (FK → `countries`). The name
   is a deliberate departure from the codebase's bare-`country_id` convention (every existing
   `belongs_to :country` uses `country_id`, disambiguated by the owning table — SPIKE-v2 Finding 2),
   chosen because `companies` would otherwise collide with the multi-country `business_territories`
   meaning. "jurisdiction" grounded in records-management usage (ARMA International — SPIKE-v2
   Finding 8).
3. **New column on `countries`**: `anonymizing_window_days` (integer) — the window, per country.
4. **Window rule**: legal retention period **+ 1 month of buffer**, for every country, Brazil
   included. Conversion convention for the seed: 1 year = 365 days, 1 month = 30 days.
5. **Per-country values** (already decided, including the fragmented cases):

   | Country | Rule | Days | Legal basis (see legal-sources aux) |
   |---|---|---|---|
   | Brazil | 5y + 1m | 1855 | Composite (CLT/CDC/civil/fiscal), reduced from today's 2008 |
   | Mexico | 10y + 1m | 3680 | Código Civil Federal art. 1159 (civil prescription) |
   | Chile | 5y + 1m | 1855 | Dirección del Trabajo (previsional prescription) |
   | Argentina | 5y + 1m | 1855 | CCyC art. 2560 (generic civil, > 2y labor) |
   | Peru | 10y + 1m | 3680 | Código Civil art. 2001 (personal actions, > 4y labor) |
   | Guatemala | 2y + 1m | 760 | Código de Trabajo art. 264 |
   | Panama | 9y + 1m | 3315 | 2y labor prescription + 7y Ley 81/2019 buffer |
   | Colombia | 20y + 1m | 7330 | Decreto 1072 (SG-SST mandatory 20y — largest MANDATORY figure, not the 80y non-mandatory recommendation) |

6. **Brazil migrates** into the `countries` table (a real row, 1855 days). It is NOT kept on the
   ENV. Brazil's window is intentionally reduced from 2008 → 1855 days (anonymizes ~5 months
   earlier than today — irreversible per LGPD art. 12; engineer accepted this after being warned).
   **Cutover is all-at-once (no phased reduction for Brazil).** Rationale confirmed by the engineer:
   the platform must not retain longer than the legally-documented window, and the documentation
   already states 5 years + 1 month (`app/docs/architecture/API_PATTERNS.md:215,217`). The current
   production value (2008 days ≈ 5y6m, `terraform/app-shared-001/compute.tf:56` and
   `terraform/modules/atento_001_task_config/main.tf:53`) is ~5 months longer than that documented
   window — so the reduction ALIGNS the system with its own policy rather than introducing a new one.
7. **No global fallback — the country is mandatory by design.** An account with
   `retention_jurisdiction_country_id` still NULL (only possible during the Phase 1→2 window) is
   simply NOT eligible for anonymization — it is excluded from selection until backfill sets its
   country. There is NO 2008 default branch anywhere. Phase 3 enforces presence so NULL cannot persist.
8. **Phasing**: expand → backfill → contract (Parallel Change). The column starts nullable, is
   backfilled, then made mandatory in a second release. Each release is a normal single deploy —
   this change only alters the cron selection query, not any in-flight job contract, so no phased
   Sidekiq or maintenance window is needed (per DEPLOYMENT-STRATEGY: interruption alone doesn't
   justify phasing; the `Computation` counters already make an interrupted anonymization safe).

## The four selection sites that change

All four read the same global cutoff today and must change symmetrically (SPIKE v1 Finding 2). The
per-user consumer (`User::Anonymizer::Consumer`) receives only a `user_id` and does NOT change.

| Worker | File | Current cutoff |
|---|---|---|
| `Company::UserAnonymizer` | `app/workers/company/user_anonymizer.rb:9-10` | `Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window)` |
| `Company::ActionAnonymizer::Producer` | `app/workers/company/action_anonymizer/producer.rb:10` | same |
| `Company::DocumentRedactor::Producer` | `app/workers/company/document_redactor/producer.rb:10` | same |
| `User::Anonymizer::Producer` | `app/workers/user/anonymizer/producer.rb:14-24` | `User.where(company_id:, anonymized: false, disabled_at: ...window)` |

Fan-out entry point (unchanged, for reference): `Company::Anonymizer#perform`
(`app/workers/company/anonymizer.rb:7-11`) and the two cron tasks `anonymization:company` /
`anonymization:user` (`lib/tasks/cron.rake:114-150`).

## Technical decisions (resolved via Pattern Priming — engineer-confirmed)

- **Resolution is direct, per account — NO iteration over countries.** Each company resolves its
  own country and window: `company.retention_jurisdiction_country.anonymizing_window_days`. A user
  resolves to one company, which resolves to one country, which gives one window. The window cutoff
  lives on `Company` as `Company#anonymizing_window` (returns the `Time` cutoff, mirroring the
  `ApplicationConfiguration.user_anonymizing_window` it replaces).
- **Producers 1–3 (company-disablement — select disabled companies)**: select disabled companies
  that HAVE a country (`where.not(disabled_at: nil).where.not(retention_jurisdiction_country_id:
  nil)`), then keep the ones whose `disabled_at` is past their own `anonymizing_window`. Companies
  are few (they are clients, not users), so resolving each one's window is cheap; companies without
  a country are excluded by the `where.not`.
- **Producer 4 (user-disablement inside an active company)**: iterate enabled companies that have a
  country, resolve each company's window once, then `User.where(company_id:, anonymized: false,
  disabled_at: ...company_window)` database-side. The governing country is the company's, not the
  user's. Decompose the join (DATA-ACCESS rule 2 — worker, nobody waiting).
- **Index**: simple index on `retention_jurisdiction_country_id` alone, matching every sibling FK
  index in the codebase (`index_<table>_on_<col>`). NOT composite — engineer chose the codebase
  convention over the query optimization.
- **`countries.anonymizing_window_days` nullability**: nullable at the DB level (a new country row
  could exist before its window is set), but every existing country is populated by the data
  migration in Phase 1. Resolution never hits a NULL because selection excludes companies whose
  country is unset, and every seeded country has a value.
- **NO global default.** The country is mandatory by design (Phase 3). There is no
  `USER_ANONYMIZING_WINDOW` fallback branch in the resolution. The ENV constant's only remaining
  role is historical until Phase 3 lands; the new code does not read it.

## Execution phases

### Phase 1 — Expand (Release 1: schema + per-country values ONLY) — DONE, PR #5217

**Structure only — NO producer change, NO behavior change.** The four producers keep using the
global `ApplicationConfiguration.user_anonymizing_window` until Phase 3. This is the load-bearing
decision (engineer): because the producers do not resolve per country until the column is mandatory,
Phase 3 needs NO defensive nil handling — there is never a nil to guard against when the producers run.

1. Migration: add `countries.anonymizing_window_days` (integer, nullable) — generated, then `db:migrate`.
2. Migration: add `companies.retention_jurisdiction_country_id` (bigint, nullable) — one action.
3. Migration: **simple** index on `retention_jurisdiction_country_id` (concurrently +
   `disable_ddl_transaction!`), matching the codebase's bare-FK index convention (NOT composite —
   engineer's choice).
4. Migration: add the FK `validate: false`, then a separate `validate_foreign_key` migration.
5. Data migrations: **one migration per country** (`AddAnonymizingWindowDaysTo<Country>`), each
   `country = Country.find_by(acronym: '..'); return if country.nil?; country.update(...)` —
   matching the sibling per-country `AddFlagTo<Country>` migrations. **Brazil (1855, 5y+1m), Mexico
   (3680, 10y+1m), and Colombia (3680, 10y+1m) are seeded** — the figures the engineer settled on.
   Every other country stays NULL until the client/legal team confirms its window (the
   internet-sourced figures were NOT trusted for PII retention). Each confirmed value later lands
   as its own `AddAnonymizingWindowDaysTo<Country>` migration.
6. `Company belongs_to :retention_jurisdiction_country ... optional: true` (presence deferred to
   Phase 3); `Country has_many :retention_jurisdiction_companies ... dependent: :nullify`.
7. Tests: the two associations (shoulda-matchers), matching sibling model specs.
8. Changelog entry under `## [Unreleased]` (`### Added` — structure, not behavior).

**Completion criteria**: migrations applied, `schema.rb` updated, seed values verified, association
specs green, `/test` clean. **(met)**

### Phase 2 — Backfill (operational, between releases)

Assign `retention_jurisdiction_country_id` on every existing company. Data operation governed by
SCRIPT-DISCIPLINE (distrust the input, three-script per bucket, variables-not-constants, consolidated
report). The source of each company's governing country is operational input (which country each
account belongs to) — NOT auto-inferable from `business_territories` (multi-valued) or `branch` (a
different meaning). **Confirm the assignment source with the engineer before running.**

**Completion criteria**: zero companies with `retention_jurisdiction_country_id: nil`.

### Phase 3 — Contract (Release 2: mandatory column + activate per-country resolution)

By now every account has a country (Phase 2), so the producers resolve per account with NO nil handling.

1. Migration: `retention_jurisdiction_country_id` NOT NULL on `companies`.
2. `validates :retention_jurisdiction_country_id, presence: true` on `Company`.
3. `Company#anonymizing_window` → `retention_jurisdiction_country.anonymizing_window_days.days.ago`.
4. Change the four producers (`Company::UserAnonymizer`, `Company::ActionAnonymizer::Producer`,
   `Company::DocumentRedactor::Producer`, `User::Anonymizer::Producer`) to resolve per account via
   `Company#anonymizing_window` instead of the global cutoff. IDs-only + `Company.find` per id (join
   decomposition), consistent across all four. NO `where.not(retention_jurisdiction_country_id: nil)`
   filter — the column is mandatory now.
5. Fix `app/docs/architecture/API_PATTERNS.md` § "Anonymization and the 5-year rule": remove the
   stale "2590 days / ~7 years" claim (production is 2008) and generalize to the per-account, per-country window.
6. Tests: `Company#anonymizing_window` + the producer selection behavior.
7. Changelog entry (`### Changed` — behavior now per-country; **Brazil moves 2008 → 1855**).

**Completion criteria**: column NOT NULL, presence validated, producers resolve per account, tests green, `/test` clean.

## Risks

- **Brazil reduction is irreversible** (2008 → 1855). Anonymization cannot be undone (LGPD art. 12).
  Accepted by the engineer (all-at-once, aligning the system with the already-documented window).
  This takes effect in **Phase 3**, when the producers start resolving per country — the first
  `anonymization:company` run after that release anonymizes Brazilian accounts in the newly-exposed
  1855–2008-day band. Phase 1 (structure only) has no such effect.
- **Colombia/Panama legal basis is the weakest** (SPIKE-v2 Finding 7). Colombia 20y is the largest
  *mandatory* figure but covers a subset (SG-SST); Panama 9y is a composite. If legal review later
  revises these, it is a one-row data change in `countries` (the whole point of Option B).
- **Backfill correctness** (Phase 2): a wrong country on an account applies the wrong retention and
  can anonymize early. The three-script pre-flight/verify pattern (SCRIPT-DISCIPLINE) guards this.
- **Index absence** on `disabled_at` today means the current query is already unindexed; Phase 1
  adds the composite, improving rather than regressing it.

## Out of scope

- Per-user retention (explicitly excluded by the engineer).
- Auto-inference of an account's governing country (operational decision, Phase 2).
- A UI/admin surface to edit `retention_jurisdiction_country_id` (not requested; note as a possible
  follow-up if account creation/editing needs it).
