# PLAN — Per-country anonymization retention window

## Context

Today the app anonymizes a deactivated client's user data after a single global window —
`ENV.fetch('USER_ANONYMIZING_WINDOW', 2008).days.ago` (`lib/application_configuration.rb:439-442`),
2008 days for every account regardless of country. Different countries mandate different legal
retention periods for employee data. This plan makes the retention window resolvable **per
account**, driven by the country that legally governs each account's data retention.

Research backing this plan (do not re-run — decisions below are already settled):
- `~/Projects/4Shark/dot-claude-plans/active/spike/anonimizacao-por-pais/SPIKE.md` (v1) — the
  anonymization pipeline map and the Brazil/Mexico legal basis
- `~/Projects/4Shark/dot-claude-plans/active/spike/anonimizacao-por-pais/SPIKE-v2.md` (v2) — the
  per-account premise, per-country legal research, and the naming/domain analysis
- `~/Projects/4Shark/dot-claude-plans/active/spike/anonimizacao-por-pais/anonimizacao-por-pais_legal_sources_v2_country_retention.md`
  — every legal source per country, with URLs and verification status
- `~/Projects/4Shark/dot-claude-plans/completed/spike/anonymization-producer-gating/SPIKE.md` — the
  unbounded-daily-re-scan question that produced the terminal flag (Phase 5, items 5–8). **Read its
  "Outcome" section first**: the option analysis in the body mischaracterized the terminal flag as
  the highest-cost option, and the Outcome records what actually shipped and why it is cheap.

## RESUME HERE — 2026-07-15

**Phases 1–4 are done. Phase 5's code is merged into `develop`. Only the release + deploy (item 11) is
left, and the release is already cut and waiting.**

`release/3.54.0` is cut from `develop` and pushed; **PR #5232 — `[3.54.0] - 2026-07-15` → `master`** is
open. `config/version.rb` is at `3.54.0` and the CHANGELOG's `## [Unreleased]` rolled into
`## [3.54.0] - 2026-07-15` (dated tomorrow deliberately — the engineer merges it first thing).

Tomorrow, in order:

1. **Merge PR #5232** — engineer only; the merge is never the agent's call.
2. **Run `/merge-cleanup`** from the **main working tree** of `app` (never a worktree — `git hf` checks
   out `master` and `develop`, impossible from a linked worktree). It detects the `release/*` branch and
   runs `bash ~/.claude/scripts/hubflow.sh release finish 3.54.0 "<tag-message>"`, which tags `master`
   at the `chore(release): 3.54.0` commit, back-merges into `develop`, and deletes the branch. Match the
   tag-message convention from the previous tag first (`git tag -n1 3.53.0`). Invoking `/merge-cleanup`
   on a release branch IS the tag authorization — it does not ask again.
3. **Deploy** `shared-001`, then `atento-001` (DEPLOY-REFERENCE.md). **Check the Sidekiq queue depth
   before each** — hold if it is heavy (app/CLAUDE.md). Single normal deploy; nothing here needs phasing.
4. **Watch the first `anonymization:company` cron run after the deploy.** That run is the go-live. Two
   consequences, both intended and already accepted:
   - **Brazil 2008 → 1855 fires as one irreversible batch** — every Brazilian account disabled in the
     newly-exposed 1855–2008-day band becomes eligible on that first run (LGPD art. 12: cannot be undone).
   - **The terminal flag self-backfills on the same run** — every already-anonymized company is selected,
     observed complete, and self-marks. That first run IS the backfill, by design.

After that run, the feature is live and Phase 5 is complete — and **that is the trigger for Phase 6**:
closing the silent-retention gap (an account whose country has a NULL window is never anonymized, and
nothing says so). That is the agreed next thing to look at once today's plan is finished; its shape is
still undecided and is the engineer's call. Everything else is in § Open follow-ups — none of it blocks
the release.

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

- **~~Resolution is direct, per account — NO iteration over countries.~~ SUPERSEDED (engineer review
  of PR #5223 → Phase 5 item 4): resolution is database-side, iterating the countries that have a
  window and comparing `disabled_at` in SQL per country. No `Company#anonymizing_window` method.**
  The original text follows for history: each company resolved its own country and window
  (`company.retention_jurisdiction_country.anonymizing_window_days`); the cutoff lived on `Company`
  as `Company#anonymizing_window` (a `Time`, mirroring the `ApplicationConfiguration.user_anonymizing_window`
  it replaced).
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
- **Terminal flag on `companies.anonymized`, marked by a fourth leg that OBSERVES the other three —
  no `Computation`, no cross-leg coordination, no backfill (engineer decision, PR #5229).** The
  daily cron re-derives its eligible-company population from scratch forever, so a company
  anonymized years ago is re-scanned every day for the life of the platform. The gate is a boolean
  `anonymized` column (default false); the three "disabled company" producers add
  `.without_anonymization` to their scan, and a fourth leg (`Company::Anonymizer::Producer` →
  `Consumer` → `Finalizer`) marks the flag once the company is genuinely done.
  - **Why not a gate on "company still has a non-anonymized user"** (the first proposal): the three
    legs run in parallel with no ordering. If the user leg finishes while document redaction is
    still incomplete, a user-based gate stops re-visiting the company from that day forward and the
    un-redacted documents are never found again. The user leg never touches `Document` — see the
    gating spike, Finding 4.
  - **Why no `Computation`**: completion here is **observed, not coordinated**. The Consumer asks
    each of the three legs "is there pending work?" — `User.exists?(anonymized: false)`,
    `Document...without_status(:redacted).exists?`, `UserIdentifierAction.exists?(anonymized: false)` —
    and only chains to the `Finalizer` when all three answer no. Every check reads **durable data
    state, not job state**, so there is no race with the legs' own jobs and nothing to synchronize:
    a leg that has not run yet, or was interrupted mid-run, still has its rows pending, so the flag
    is simply not set and the company is re-scanned tomorrow. This is what makes the terminal flag
    cheap instead of the "highest cost" option the spike first characterized it as.
  - **Why no backfill**: the flag defaults to false, so on the first cron run after deploy every
    already-anonymized company is selected, observed as complete, and self-marks. The backfill is
    the first run.
  - **Re-enable clears it**: `Company#enable` sets `anonymized: false` alongside `disabled_at`/
    `disabler_id`, so a company that is re-enabled and later disabled again starts a fresh cycle
    rather than being suppressed by a stale flag.
  - **`User::Anonymizer::Producer` (the fourth producer) is deliberately NOT gated** — it scans
    `Company.enabled` for individually-disabled users, and an enabled company never reaches a
    terminal state (new users can be disabled at any time for the life of the account). There is
    nothing to permanently exclude.

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

### Phase 2 — Release + Deploy to production (BEFORE the backfill) — DONE (release 3.51.0, deployed to shared-001 + atento-001)

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
values confirmed in production. **(met)** — 3.51.0 tagged and back-merged; both productive stacks
deployed; BR/MX/CO windows confirmed live.

### Phase 3 — Write-path (creation/edit accept the country) + Release + Deploy — DONE (app #5221 write-path + #5222 presence; app-webclient #6590; deployed)

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
chosen country in production. **(met)** — backend #5221 (mutations accept + persist the field) and
front #6590 (user-chosen country selector + tooltip, required on create/edit). **Presence brought
forward from Phase 5 at the engineer's call (#5222):** the model-level
`validates :retention_jurisdiction_country_id, presence: true` shipped here, ahead of the backfill.
Trade-off accepted knowingly: between the #5222 deploy and Phase 4 completion, any existing NULL
account failed every `.save`/`.update` (the write-block — Finding C2 of the business-territory
spike); Phase 4 then filled every account, satisfying it.

### Phase 4 — Backfill (operational, in production) — DONE (beta 54, demo 157, shared 78, atento 8; all verified)

Assign `retention_jurisdiction_country_id` on every existing company. Runs AFTER Phase 3, so the
write-path is already live and no new account is born NULL during the backfill window. Data operation
governed by SCRIPT-DISCIPLINE (distrust the input, three-script per bucket, variables-not-constants,
consolidated report). The source of each company's governing country is operational input — NOT
auto-inferable from `business_territories` (multi-valued) or `branch` (a different meaning).
**Confirm the assignment source with the engineer before running.** Only countries with a seeded
window (BR/MX/CO) can bind accounts that Phase 5 will anonymize; accounts of not-yet-priced countries
stay unbound or are handled per the engineer's call.

**Completion criteria**: zero companies with `retention_jurisdiction_country_id: nil` (or the agreed
subset bound). **(met)** — every company in all four environments now has a country.

**Executed approach (engineer decision at run time, refining decision 1 / this phase's original
premise).** Decision 1 and this phase originally said the country was NOT auto-inferable from
`business_territories`. At run time the engineer decided the opposite where it is unambiguous: for
the backfill the governing country WAS derived from the account's **single** `business_territory`.
A spike (`active/spike/business-territory-retention-jurisdiction/SPIKE.md`) first confirmed the
premise change was safe and that **nothing consumes `retention_jurisdiction_country_id` yet** (the
anonymization workers still run the single global window — so the backfill's live purpose today is
only to unblock the presence write-block, not to change anonymization). Rule applied per
environment via the three-script pattern (pre-flight → mutation → verification): `retention =
single territory country`, with no-window countries (GT/CL/PE/AR) tied to their own country all the
same. Two demo multi-territory accounts were handled specially:
- **#633 (Atento Mexico API)** carried an erroneous `BR` territory (added 2025-12-04, three months
  before its `MX` territory on 2026-03-02; zero subsidiaries → removal safe). The `BR` territory row
  was removed, leaving `MX` → retention `MX`.
- **#488 (Conta Global)** is a legitimate `Holding` with 8 per-country child CallCenters (which
  backfilled per-country on their own via the single-territory rule). The aggregator record got a
  **representative country (BR)**; its business_territory/branch divergence (holding territory
  `[AR,BR,CO,MX,PE]` vs 8 branch countries `[AR,BR,CL,CO,GT,MX,PA,PE]`) is left as a separate
  follow-up, NOT corrected in this pass.

### Phase 5 — Contract (Release + Deploy: mandatory column + activate per-country resolution + terminal flag)

By now every bound account has a country (Phase 4) and new accounts are born with one (Phase 3), so
the producers resolve per account with NO nil handling.

**NEW GAP surfaced by the backfill — must be resolved before items 3–4 go live.** The backfill bound
production accounts to **AR, CL, GT, PA, PE** (the engineer's "amarra ao país mesmo" decision), but
those countries still have `anonymizing_window_days = NULL` (only BR/MX/CO are seeded — Phase 1
item 5). The country FK is now non-null everywhere, so the country-level "NO nil handling" premise
holds — but the **window** can still be NULL, and item 3's `Company#anonymizing_window`
(`retention_jurisdiction_country.anonymizing_window_days.days.ago`) would raise on a NULL window for
those accounts. **Engineer decision (resolved): option (b) — the producers exclude accounts whose
country window is still NULL.** AR/CL/GT/PA/PE accounts are simply not selected for anonymization
until their window is seeded later (a one-row `countries` update per country, once legal confirms).
Code-only; no dependency on legal confirmation to ship Phase 5. Item 4 below carries this filter.

**Note:** item 2 (`validates :retention_jurisdiction_country_id, presence: true`) already shipped
early in Phase 3 (#5222) — no work left on that item. For what is done and what remains across the
rest of the items, see the **Status** block at the end of this phase (only item 11, release + deploy,
is left).

1. Migration: `retention_jurisdiction_country_id` NOT NULL on `companies`.
2. `validates :retention_jurisdiction_country_id, presence: true` on `Company` — **already shipped in
   Phase 3 (#5222); nothing left on this item.**
3. **No `Company#anonymizing_window` method** — the eligibility comparison is done database-side in
   the producers (engineer review of PR #5223, superseding the earlier per-account-method approach).
4. Change the four producers (`Company::UserAnonymizer`, `Company::ActionAnonymizer::Producer`,
   `Company::DocumentRedactor::Producer`, `User::Anonymizer::Producer`) to select **database-side, per
   country**: iterate the countries that have an `anonymizing_window_days`, and for each, select the
   disabled companies (or, for `User::Anonymizer::Producer`, the disabled users of that country's
   enabled companies) whose `disabled_at` is past `anonymizing_window_days.days.ago` — the comparison
   runs in SQL, filtered by the indexed `retention_jurisdiction_country_id`, using the
   `Company.disabled` / `Company.enabled` scopes. This **supersedes the plan's earlier "NO iteration
   over countries" and per-account `Company#anonymizing_window` decisions** (engineer review of PR
   #5223). Countries with a NULL window are excluded by the `Country.where.not(anonymizing_window_days:
   nil)` at the top of each producer — which also resolves the AR/CL/GT/PA/PE gap without a separate
   filter.
5. Migration: `companies.anonymized` (boolean, `default: false`, `null: false`) — the terminal flag.
6. `Company.without_anonymization` scope (`where(anonymized: false)`); the three "disabled company"
   producers (`Company::UserAnonymizer`, `Company::ActionAnonymizer::Producer`,
   `Company::DocumentRedactor::Producer`) add it to their per-country scan.
   `User::Anonymizer::Producer` is deliberately NOT gated (enabled companies have no terminal state).
7. Fourth leg, fired from `Company::Anonymizer#perform` alongside the existing three:
   `Company::Anonymizer::Producer` (per-country scan of disabled + not-yet-flagged companies past
   their window) → `Company::Anonymizer::Consumer` (observes the three legs' pending work via
   `exists?`; returns early on any pending) → `Company::Anonymizer::Finalizer` (sets the flag).
8. `Company#enable` clears the flag — full reimplementation (no `super`), setting
   `anonymized: false` with `disabled_at`/`disabler_id` so a re-enabled account starts a fresh cycle.
9. Fix `app/docs/architecture/API_PATTERNS.md` § "Anonymization and the 5-year rule": remove the
   stale "2590 days / ~7 years" claim (production is 2008) and generalize to the per-account, per-country window.
10. Tests: the producer selection behavior + `Company#enable` clearing the flag. Changelog
    `### Changed` — behavior now per-country; **Brazil moves 2008 → 1855** (irreversible; takes
    effect on this deploy) — and `### Added` for the skip of already-anonymized accounts.
11. **Release + deploy this phase too** (same HubFlow + deploy flow as Phase 2) — this is where the
    per-country behavior actually goes live and the first cron run anonymizes on the new windows.

**Completion criteria**: both columns in place (`retention_jurisdiction_country_id` NOT NULL,
`anonymized` NOT NULL), presence validated, producers resolve per account and skip already-anonymized
accounts, released and deployed.

**Status:** **`feature/per-country-anonymization` is MERGED into `develop`** — PR #5223, rebased onto
develop at 3.53.0 immediately before the merge (the rebase linearized the branch, dropping the #5229
merge commit). The code landed in two PRs that were first merged into that feature branch:
- **#5223** — items 1, 3, 4, 9 (the NOT NULL migration, database-side per-country resolution in the
  four producers, and the API_PATTERNS fix). Item 2 was already shipped in #5222. Review-driven
  hardening included: `Country` `dependent: :nullify` → `:restrict_with_exception` (the NOT NULL made
  `:nullify` a latent `PG::NotNullViolation` on country destroy), and
  `validates :anonymizing_window_days, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true`
  (a `0` window would make every disabled account of that country immediately eligible — irreversible
  mass anonymization).
- **#5229** — items 5, 6, 7, 8: the `companies.anonymized` terminal flag, the
  `without_anonymization` gate on the three "disabled company" producers, the
  `Producer`/`Consumer`/`Finalizer` fourth leg, and `Company#enable` clearing the flag.
- Item 10 (tests + changelog) is covered across both.

**Item 11 (release + deploy) is the only one left, and it is IN PROGRESS** — `release/3.54.0` is cut
from `develop` and **PR #5232 (`[3.54.0] - 2026-07-15` → `master`) is open**, awaiting the engineer's
merge on 2026-07-15. **§ RESUME HERE carries the exact sequence** from that merge through go-live
(merge → `/merge-cleanup` runs `hubflow.sh release finish` → deploy `shared-001`/`atento-001` after the
queue check → watch the first cron run). Per the gate decision, the producers iterate only countries
with a seeded window, so AR/CL/GT/PA/PE accounts are not anonymized until their
`anonymizing_window_days` is seeded (a one-row `countries` update per country, once legal confirms).

**Deploy shape — still a single normal deploy, now for two reasons.** The per-country change only
alters the cron selection query (decision 8). The flag work adds a column and a NEW fan-out
(`Company::Anonymizer::Producer`/`Consumer`/`Finalizer`) but changes no existing job's argument
shape, introduces no non-idempotent step, and derives no `Computation` key — the three conditions
that would force expand/contract per DEPLOYMENT-STRATEGY. The ephemeral migration task adds the
`anonymized` column (default false, so existing rows are backfilled by Postgres, not by a data
migration) before the new code goes live; a worker still running old code during the rollover simply
does not fire the fourth leg that day.

### Phase 6 — Close the silent-retention gap (starts when Phase 5 is live)

**Trigger: the moment item 11 is done** — release merged, deployed, first `anonymization:company` run
observed. Everything planned for 2026-07-14 ends there; **this is the next thing to look at.**

**The gap.** Every producer iterates only `Country.where.not(anonymizing_window_days: nil)`. An account
whose retention jurisdiction country has a NULL window is therefore **never anonymized — and nothing
says so.** Today that is AR / CL / GT / PA / PE (Phase 1 item 5 left them unseeded on purpose, pending
legal). Before this feature the single global window guaranteed every disabled account was eventually
processed; that safety net is now gone **by design**, and nothing replaced it.

**Why it matters.** LGPD storage limitation makes the window a **maximum**, not an option — "we retain
it until someone remembers to seed the country" is not a defensible position. And the failure is
**silent**: no error, no job, no log line; it surfaces only at an LGPD verification, which is the worst
possible moment to discover it. Raised as a Medium finding by the PR #5223 review.

**Shape NOT decided — the engineer's call.** Options surfaced, none chosen:
- a periodic check that flags any country referenced by a disabled company but lacking a window;
- a guard at write/seed time — a country cannot be used as a retention jurisdiction until it has a window;
- accept it explicitly and track the unseeded countries out-of-band until legal confirms.

**Seeding the five countries does NOT close this.** Follow-up 1 removes today's *instance* of the gap;
the gap itself is structural — a country added tomorrow, or a jurisdiction pointed at an unseeded
country, reopens it. Phase 6 is about the class of problem, not the current five.

## Learnings (from execution — read before touching this feature again)

1. **`business_territory` is NOT the retention jurisdiction.** It is where the company *does business*,
   and it is legitimately multi-valued. For a **single**-territory account it is a sound proxy (one
   country of operation → that country's law governs), and that is exactly how the backfill used it.
   For multi-territory it breaks down and needs judgment — see the two demo accounts in Phase 4. The
   plan originally asserted the country was "NOT auto-inferable from `business_territories`" (decision
   1); the refinement is that it IS inferable precisely when the territory is unambiguous. Established
   by `active/spike/business-territory-retention-jurisdiction/SPIKE.md`.
2. **A `Holding`'s territory is not its branches, and `Company` has no `parent_id`.** The company-to-
   company hierarchy is `Holding` (an STI subtype) + `CompanyBranch`; **no code links
   `company_business_territories` to `company_branches`** — they are independently written. The demo
   "Conta Global" proved it: territory `[AR,BR,CO,MX,PE]` (5) vs 8 branch countries
   `[AR,BR,CL,CO,GT,MX,PA,PE]`. Do not infer one from the other.
3. **Until Phase 5, nothing read `retention_jurisdiction_country_id`.** The anonymization workers ran
   the single global `USER_ANONYMIZING_WINDOW` the whole time. So the backfill's *live* purpose was
   never "fix anonymization" — it was **unblocking writes**: the presence validation (#5222, brought
   forward from Phase 5) made every `.save`/`.update` on a NULL account fail. The DB had no `NOT NULL`
   until Phase 5, so a NULL never broke a read.
4. **`countries.anonymizing_window_days` is an Integer (a count of days); `companies.disabled_at` is a
   datetime.** They can never be compared directly — the integer must be converted to a cutoff
   (`anonymizing_window_days.days.ago`) and compared against `disabled_at`. This was a real bug caught
   in review. A `0` window would make `0.days.ago == now`, so every disabled account of that country
   would be instantly eligible — which is why the `greater_than: 0` validation now exists.
5. **`DocumentRedactor` vs `Anonymizer` is a real domain distinction, not a naming clash to
   standardize.** They are different operations: `Company::DocumentRedactor::Consumer` **redacts** —
   `attachment.destroy` + `document.redact!` (status `:redacted`), i.e. the file is removed;
   `User::Anonymizer::Consumer` **anonymizes** — replaces email/name/`unique_register_id` with
   `ANONYMIZED_VALUE` in place, the row stays. The LGPD domain language uses both verbs deliberately
   ("anonymizes users, redacts documents"). Renaming to one verb would erase a distinction the law and
   the code both make.
6. **This project does not unit-test workers.** There is no `spec/workers` and nothing exercises a
   Producer/Consumer/`perform`. The per-country selection therefore has **no unit test** — the coverage
   is the review plus the model-level specs. Do not "add worker specs" as a convention here without the
   engineer's call; do not treat the absence as an oversight to fix in passing.
7. **A rebase can silently corrupt the CHANGELOG — always diff it against the base afterwards.** When
   `feature/per-country-anonymization` was rebased onto develop at 3.53.0, git auto-merged the
   `### Changed` block **into the already-released `## [3.52.0]` section** and left the file with no
   `## [Unreleased]` at all. Nothing conflicted; nothing errored. `git diff origin/develop...HEAD --
   CHANGELOG.md` is what caught it — the diff must be *only* the new `## [Unreleased]` block.
8. **The schema.rb conflict on a rebase is mechanical: take the highest `version:`.** It is the max
   migration timestamp across the merged tree, and it conflicted on every replayed commit. The rest of
   the file auto-merged correctly both times.

## Open follow-ups (none block the release)

1. **Seed `anonymizing_window_days` for AR / CL / GT / PA / PE** — pending client/legal confirmation
   (the internet-sourced figures in § Per-country values were deliberately not trusted for PII
   retention). Until each is seeded, accounts bound to that country are **never anonymized**: the
   producers iterate only `Country.where.not(anonymizing_window_days: nil)`. Each confirmed value is a
   one-row `countries` update shipped as its own migration, matching Phase 1 item 5. **Feeds Phase 6
   but does not close it** — seeding these five removes today's instance of the silent-retention gap,
   not the gap itself.
2. **Demo "Conta Global" (#488) territory/branch divergence** — its `business_territory` (5 countries)
   does not match its 8 `company_branches`. It got a representative country (BR) in the backfill so it
   would not block; the divergence itself was deliberately left alone (learning 2 explains why the two
   are not derivable from each other). Demo-only, non-productive `holding_dashboard` feature.

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
- **The terminal flag's completeness check is a maintenance coupling — a new PII leg MUST be added to
  `Company::Anonymizer::Consumer` or accounts get flagged with residual PII.** The Consumer names the
  three concerns explicitly (`User` / `Document` / `UserIdentifierAction`); it is the only thing
  standing between a company and permanent exclusion from the daily scan. If a fourth PII surface is
  ever anonymized by a new leg fired from `Company::Anonymizer#perform` and its `exists?` check is
  not added to the Consumer, every company will be flagged while that leg still has pending rows, and
  no daily run will ever revisit them. The failure is **silent** (nothing errors; the data is simply
  never anonymized) and only surfaces at an LGPD verification. There is no mechanical guard for this
  — the coupling is by convention: **whoever adds a leg to `Company::Anonymizer#perform` adds its
  pending-work check to `Company::Anonymizer::Consumer` in the same PR.**
- **Un-flagging is not a recovery path for a wrongly-flagged account.** The flag suppresses the scan;
  it does not delete anything. If an account is flagged in error, clearing `anonymized` back to false
  puts it back in the next daily run and the legs resume — nothing is lost. The irreversible half is
  the anonymization itself (LGPD art. 12), which the flag never triggers on its own.

## Out of scope

- Per-user retention (explicitly excluded by the engineer).
- Auto-inference of an account's governing country (operational decision, Phase 4).

(The UI/admin surface to set `retention_jurisdiction_country_id` on account creation/edit, previously
noted here as a possible follow-up, is now IN scope as Phase 3 — the write-path that must ship before
the backfill.)
