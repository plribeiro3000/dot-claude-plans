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
   `retention_jurisdiction_country_id` still NULL (only possible during the transition before Phase 5)
   is simply NOT eligible for anonymization — it is excluded from selection until backfill sets its
   country. There is NO 2008 default branch anywhere. Phase 5 enforces presence so NULL cannot persist.
8. **Phasing**: expand → write-path → backfill → contract (Parallel Change). The column starts
   nullable; the write-path (creation/edit accepts and persists the country) ships and deploys
   BEFORE the backfill, so new accounts are born with a country while the existing ones are
   backfilled — closing the gap instead of leaving a window where fresh accounts are created NULL.
   The column is then made mandatory in a final release. Each release is a normal single deploy —
   this change only alters the cron selection query, not any in-flight job contract, so no phased
   Sidekiq or maintenance window is needed (per DEPLOYMENT-STRATEGY: interruption alone doesn't
   justify phasing; the `Computation` counters already make an interrupted anonymization safe).
9. **Write-path ships before the backfill (engineer-corrected ordering).** Account creation and
   edit must accept and persist `retention_jurisdiction_country_id` — and be deployed to
   production — before the backfill runs. Otherwise any account created between the backfill and
   the final deploy is born NULL, re-opening the gap the backfill just closed. The field is a
   **user-chosen country selector** — the jurisdiction is a deliberate choice and may diverge from
   the account's locale/territory, so it is picked explicitly, not derived — with a **tooltip**
   explaining what the field means and asking the user to set it carefully. Backend:
   `CreateCompanyGraphqlMutation` / `UpdateCompanyGraphqlMutation` (`app`). Front: `app-webclient`
   company create + update forms.

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
- **NO global default.** The country is mandatory by design (Phase 5). There is no
  `USER_ANONYMIZING_WINDOW` fallback branch in the resolution. The ENV constant's only remaining
  role is historical until Phase 5 lands; the new code does not read it.

## Execution phases

### Phase 1 — Expand (schema + per-country values ONLY) — DONE, merged into develop (#5217)

**Structure only — NO producer change, NO behavior change.** The four producers keep using the
global `ApplicationConfiguration.user_anonymizing_window` until Phase 5. This is the load-bearing
decision (engineer): because the producers do not resolve per country until the column is mandatory,
Phase 5 needs NO defensive nil handling — there is never a nil to guard against when the producers run.

1. Migration: add `countries.anonymizing_window_days` (integer, nullable).
2. Migration: add `companies.retention_jurisdiction_country_id` (bigint, nullable).
3. Migration: **simple** index on `retention_jurisdiction_country_id` (concurrently + `disable_ddl_transaction!`).
4. Migration: add the FK `validate: false`, then a separate `validate_foreign_key` migration.
5. Data migrations: **one migration per country** (`AddAnonymizingWindowDaysTo<Country>`), each
   `country = Country.find_by(acronym: '..'); return if country.nil?; country.update(...)` —
   matching the sibling `AddFlagTo<Country>` migrations. **Brazil (1855, 5y+1m), Mexico (3680,
   10y+1m), and Colombia (3680, 10y+1m) are seeded**; every other country (AR/CL/GT/PA/PE) stays
   NULL until the client/legal team confirms its window (the internet-sourced figures were NOT
   trusted for PII retention). Each confirmed value later lands as its own migration.
6. `Company belongs_to :retention_jurisdiction_country ... optional: true` (presence deferred to
   Phase 5); `Country has_many :retention_jurisdiction_companies ... dependent: :nullify`.
7. Association specs; changelog `### Added — Per-country retention window`.

**Completion criteria**: merged into develop via #5217, `/test` clean, seed values verified. **(met)**

### Phase 2 — Release + Deploy to production (BEFORE the backfill)

The Phase 1 columns and per-country values live on `develop` but **not in production yet**. The
backfill (Phase 4) mutates production accounts, so the schema and the seeded values must be live in
production first. This phase cuts a release off `develop` and deploys it.

1. Cut the release with **HubFlow** from `develop` — NEVER `git checkout -b release/*`:
   `git hf release start X.Y.Z`. Minor bump (last release is 3.50.0 → 3.51.0), version decided by the
   engineer at cut time — not fixed here, and tagging is engineer-authorized only.
2. On the release branch: version bump + CHANGELOG (the `## [Unreleased]` entries, including
   `### Added — Per-country retention window`, roll into `## [X.Y.Z] - DATE`). Commit, push, PR against `master`.
3. Finish via **HubFlow** (`git hf release finish X.Y.Z`) — tags `master`, back-merges into `develop`.
   Run from the **main working tree, never a worktree** (§ HubFlow Policy).
4. **Single normal deploy — NOT phased.** This change is structure only (nullable columns, concurrent
   index, `validate: false` FK, per-country value updates); none of it breaks an in-flight job
   contract, so a phased deploy is unnecessary (§ Deployment Strategy). The ephemeral migration task
   runs the migrations before the new code goes live.
5. Productive app stacks: **`shared-001` and `atento-001`**. **Check the Sidekiq queue depth before
   deploying each** (app/CLAUDE.md — hold if the queue is heavy). Trigger per DEPLOY-REFERENCE.md.
6. Verify in production (read-only): the two columns exist and BR/MX/CO carry their window values
   (AR/CL/GT/PA/PE NULL, by design).

**Completion criteria**: release tagged, both productive stacks on the new version, columns + seeded
values confirmed in production.

### Phase 3 — Write-path (creation/edit accept the country) + Release + Deploy

New accounts must be born with a country before the backfill runs (decision 9). This phase makes
account creation and edit accept `retention_jurisdiction_country_id`, ships it, and deploys it —
two PRs across two repos, deployed before Phase 4.

**Backend (`app`)** — Pattern Priming against sibling mutations before writing:
1. `CreateCompanyGraphqlMutation`: add the `retention_jurisdiction_country_id` argument and permit it.
2. `UpdateCompanyGraphqlMutation`: same.
3. Expose the field on `CompanyGraphqlType` so the edit form can read the current value.
4. Tests for the two mutations accepting/persisting the field; changelog `### Added`.

**Front (`app-webclient`)** — Pattern Priming against the existing company form fields before writing:
1. Company create form: a country selector bound to `retention_jurisdiction_country_id`, sourced
   from the countries list, with a **tooltip** explaining the field and asking for care in setting it.
2. Company update form: the same selector, pre-filled with the current value.
3. `company.model.ts` + the create/update services carry the field into the mutation payload.

**Release + deploy** — HubFlow release each repo per its deploy path (`app` via GitHub Actions,
`app-webclient` via Netlify — DEPLOY-REFERENCE.md); check the Sidekiq queue before the `app` deploy
to the productive stacks (`shared-001`, `atento-001`). The field is **not yet mandatory** —
creation still succeeds without it (Phase 5 enforces presence), so this deploy is backward-compatible.

**Completion criteria**: both repos released and deployed; a new account can be created/edited with a
chosen country in production.

### Phase 4 — Backfill (operational, in production)

Assign `retention_jurisdiction_country_id` on every existing company. Runs AFTER Phase 3, so the
write-path is already live and no new account is born NULL during the backfill window. Data operation
governed by SCRIPT-DISCIPLINE (distrust the input, three-script per bucket, variables-not-constants,
consolidated report). The source of each company's governing country is operational input — NOT
auto-inferable from `business_territories` (multi-valued) or `branch` (a different meaning).
**Confirm the assignment source with the engineer before running.** Only countries with a seeded
window (BR/MX/CO) can bind accounts that Phase 5 will anonymize; accounts of not-yet-priced countries
stay unbound or are handled per the engineer's call.

**Completion criteria**: zero companies with `retention_jurisdiction_country_id: nil` (or the agreed
subset bound).

### Phase 5 — Contract (Release + Deploy: mandatory column + activate per-country resolution)

By now every bound account has a country (Phase 4) and new accounts are born with one (Phase 3), so
the producers resolve per account with NO nil handling.

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
6. Tests: `Company#anonymizing_window` + the producer selection behavior. Changelog `### Changed` —
   behavior now per-country; **Brazil moves 2008 → 1855** (irreversible; takes effect on this deploy).
7. **Release + deploy this phase too** (same HubFlow + deploy flow as Phase 2) — this is where the
   per-country behavior actually goes live and the first cron run anonymizes on the new windows.

**Completion criteria**: column NOT NULL, presence validated, producers resolve per account, released and deployed.

## Risks

- **Brazil reduction is irreversible** (2008 → 1855). Anonymization cannot be undone (LGPD art. 12).
  Accepted by the engineer (all-at-once, aligning the system with the already-documented window).
  This takes effect in **Phase 5**, when the producers start resolving per country — the first
  `anonymization:company` run after that release anonymizes Brazilian accounts in the newly-exposed
  1855–2008-day band. Phases 1–4 (structure, deploy, write-path, backfill) have no such effect.
- **Colombia/Panama legal basis is the weakest** (SPIKE-v2 Finding 7). Colombia 20y is the largest
  *mandatory* figure but covers a subset (SG-SST); Panama 9y is a composite. If legal review later
  revises these, it is a one-row data change in `countries` (the whole point of Option B).
- **Backfill correctness** (Phase 4): a wrong country on an account applies the wrong retention and
  can anonymize early. The three-script pre-flight/verify pattern (SCRIPT-DISCIPLINE) guards this.
- **Index absence** on `disabled_at` remains — Phase 1 added a **simple** index on the FK
  (`retention_jurisdiction_country_id`), not on `disabled_at`. The per-account selection in Phase 5
  navigates by id (join decomposition), so `disabled_at` is not on a scanned hot path.

## Out of scope

- Per-user retention (explicitly excluded by the engineer).
- Auto-inference of an account's governing country (operational decision, Phase 4).

(The UI/admin surface to set `retention_jurisdiction_country_id` on account creation/edit, previously
noted here as a possible follow-up, is now IN scope as Phase 3 — the write-path that must ship before
the backfill.)
