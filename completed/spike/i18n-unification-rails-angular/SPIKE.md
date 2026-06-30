# SPIKE — i18n Single Source of Truth (Rails + Angular)

> **STATUS:** Investigation complete; archived as reference. The engineer split this into two problems.
> - **Problem 1 — frontend format migration: DONE.** Monolithic JSON → per-domain split (mirrors Rails `models/`), merged in PR #6523. See `~/.claude/plans/completed/app-webclient/translation-format-migration/PLAN.md`. This did NOT unify the two sides — it only reshaped the frontend so a future overlay/sync is cleaner.
> - **Problem 2 — per-tenant override + single source of truth: deferred to its own dedicated plan.** It is large enough to warrant a fresh plan when prioritized, rather than hanging off this spike. This document is the seed material for that future plan. Key starting points: the Atento overrides live as the rebased-forever `atento` / `atento-mx` git branches (Finding 7), scoped to the access-level (seat-type) label remap; the decision matrix below (Options A–D) frames the choice; the leading candidate given 4Shark's self-hosting + dynamic-override need is **Option C (Runtime API + `I18n::Backend::Chain`)**, but the commercial-TMS claims (Locize/Tolgee) need first-party confirmation before committing.

## Investigation question

How do teams that run a Ruby on Rails backend + a separate Angular/TypeScript frontend keep i18n translations in a single source of truth so that both sides always render the same strings — instead of maintaining two divergent translation sets?

Anchored to 4Shark's concrete setup: Rails app at `~/Projects/4Shark/app`, Angular 19 at `~/Projects/4Shark/app-webclient`, using `@ngx-translate/core` v17. Two hard constraints must be addressed explicitly:

1. **Gem-vs-npm packaging mismatch** — sharing code between a Ruby gem and an npm package requires a third project published to both registries in lockstep; research whether this is what teams actually do.
2. **Per-tenant label overrides (the Atento case)** — Atento has its own naming for access level labels. Today 4Shark overrides these statically at Angular build time (separate build target: `src/environments/atento/`). Any unified-source approach must have a clean story for per-client key overrides with fallback to the default.

## Sources consulted

- `app/controllers/jwt_authorized_controller.rb` — locale resolution per request; see [`i18n_unification_excerpt_1.rb`](i18n_unification_excerpt_1.rb)
- `app/models/company.rb:86–98` — Company locale enum (9 variants); see [`i18n_unification_excerpt_1.rb`](i18n_unification_excerpt_1.rb)
- `app/config/locales/` — 875 backend YAML locale files
- `app-webclient/src/translations/pt-BR.json` — 148KB, 138 top-level keys
- `app-webclient/src/app/core/i18n.service.ts` — setTranslation-based startup
- `app-webclient/src/app/core/translation-files.config.ts` — import map
- `app-webclient/src/app/core/translation-merger.ts` — deep merge utility
- `app-webclient/src/app/core/multi-file-translate-loader.ts` — loadTranslations wrapper
- `app-webclient/src/environments/atento/` — Atento build override directory
- `app-webclient/package.json` — `@ngx-translate/core: ^17.0.0`; see [`i18n_unification_excerpt_2.ts`](i18n_unification_excerpt_2.ts)
- [https://github.com/fnando/i18n-js](https://github.com/fnando/i18n-js) — i18n-js gem + npm companion
- [https://docs.tolgee.io/platform/formats/ruby_yaml](https://docs.tolgee.io/platform/formats/ruby_yaml) — Tolgee Ruby YAML format support
- [https://tolgee.io/pricing](https://tolgee.io/pricing) — Tolgee pricing tiers (free, cloud, self-hosted)
- [https://locize.com](https://locize.com) — Locize multi-tenant overview
- [https://locize.com/multi-tenant](https://locize.com/multi-tenant) — Locize parent/child namespace architecture
- [https://guides.rubyonrails.org/i18n.html#using-different-backends](https://guides.rubyonrails.org/i18n.html#using-different-backends) — I18n::Backend::Chain
- [https://ngx-translate.org](https://ngx-translate.org) — ngx-translate v18 release notes (multi-resource loading)

## Findings

### Finding 1: Current codebase state — two independent translation sets with value divergence

**Evidence:**

The Rails backend has 875 YAML locale files across 9 language variants (`pt-BR`, `en`, `es`, `es-MX`, `es-CO`, `es-AR`, `es-CL`, `es-PA`, `es-PE`), stored under `config/locales/<lang>/` with sub-directories for `generic`, `models`, `pages`, and `gems`.

The Angular frontend has 3 JSON translation files (one per language: `pt-BR`, `en`, `es`), each structured as a flat-to-one-level-nested JSON object. The `pt-BR.json` file is approximately 148KB with 138 top-level keys.

The backend sets the active locale per-request via:

```ruby
# app/controllers/jwt_authorized_controller.rb
def set_locale
  I18n.locale =
    if current_user.present?
      current_user.company.locale
    else
      I18n.default_locale
    end
end
```

`company.locale` is an enumerized integer column mapping to 9 locale identifiers (see [`i18n_unification_excerpt_1.rb`](i18n_unification_excerpt_1.rb) for the full enum). The frontend has only 3 language variants (no regional Spanish variants), so the structural overlap is partial.

Value divergence is confirmed for the `acceptment` domain noun:

| Key | Backend (YAML) | Frontend (JSON) |
|-----|---------------|-----------------|
| `acceptment.one` | `Aceitação` | `Ciência` |
| `acceptment.other` | `Aceitações` | `Ciências` |

This is not a format difference — it is a deliberate product decision made on the frontend side without updating the backend. 115 of 138 frontend top-level keys contain `one`/`other` sub-keys that mirror the Rails ActiveRecord model translation structure, but values are independently maintained.

The Atento build override (`src/environments/atento/`) contains only `manifest.json`, `styles/colorVariables.scss`, and `assets/` (icons). There are no per-tenant translation JSON files anywhere in the environments directory. Atento customization is currently **branding-only** at build time, not translation-level.

**Source:** `app/controllers/jwt_authorized_controller.rb`, `app/models/company.rb:86–98`, `app-webclient/src/translations/pt-BR.json`, `app-webclient/src/environments/atento/`; see auxiliary files [`i18n_unification_excerpt_1.rb`](i18n_unification_excerpt_1.rb) and [`i18n_unification_excerpt_2.ts`](i18n_unification_excerpt_2.ts)

**Significance:** The split is a fact of the current architecture, not a temporary oversight. Any unification path must account for intentional value divergence and the fact that some keys (e.g., `acceptment`) carry different meaning per side. The `mergeTranslations` utility and the `TRANSLATION_FILES` array structure already make the frontend capable of loading multiple JSON files per locale — the wiring for layering exists.

---

### Finding 2: i18n-js gem — build-time Rails YAML → JSON export

**Evidence:**

The fnando/i18n-js gem is a two-part system:

1. **Ruby gem** — CLI exporter. Running `i18n export` reads Rails YAML locale files and generates per-locale JSON files. The GitHub README states: *"Export i18n translations to JSON. A perfect fit if you want to export translations to JavaScript."*

2. **npm companion** (`i18n-js`) — JavaScript consumer. The README states: *"Oh, you don't use Ruby? No problem! You can still use i18n-js and the companion JavaScript package."*

The gem generates JSON files at paths configurable with `:locale` and `:digest` placeholders. An `embed_fallback_translations` plugin merges fallback-chain translations into each exported locale file, so the JS side gets a self-contained bundle. The Gemfile in `app/` does not include the gem (only `i18n-debug` is present), confirming this is not currently in use.

The companion npm package exposes its own `I18n.t()` API — it does **not** integrate with ngx-translate's pipe (`{{ key | translate }}`). The two consume translations through incompatible APIs: i18n-js npm calls `I18n.t('models.company.one')`, while the existing Angular templates use `'company.one' | translate`.

The `one`/`other` pluralization in the Rails YAML aligns structurally with the i18n-js npm package's Rails-compatible pluralization — i18n-js npm was designed for this format. However, the key namespace shape differs: Rails uses dotted paths under `activerecord.models.company.one`, while the frontend currently uses `company.one` as a top-level key.

**Source:** [https://github.com/fnando/i18n-js](https://github.com/fnando/i18n-js) — verbatim quotes above confirmed in fetched content. `app/Gemfile` — i18n-js gem absent.

**Significance:** i18n-js solves the source-of-truth problem for string content (Rails YAML is the single source), but at the cost of replacing the ngx-translate API entirely or maintaining an adapter layer. All Angular templates using `| translate` would require rewriting. Per-tenant override is not a native i18n-js feature; it would require a custom export configuration per tenant, creating N export variants.

---

### Finding 3: Translation Management System (TMS) as single source

A TMS holds the canonical strings and exports to both Rails YAML and Angular JSON from one UI. Two options are evaluated with confirmed sourcing: Tolgee (self-hostable) and Locize (cloud-only).

#### 3a: Tolgee (OSS, self-hostable)

Tolgee supports Ruby YAML import/export. The format page states: *"Ruby on rails is specific, since it has a language tag in the root."* — confirming the tool is aware of and handles the Rails YAML root-key convention. Named-placeholder conversion (`%{name}` → ICU `{name}`) is supported and can be disabled per-project.

CLI-based push/pull enables a CI workflow: developers commit YAML/JSON to git, CI pushes to Tolgee, Tolgee exports back to both formats. Branch-based workflows are available in the Business tier.

Tolgee pricing (verbatim from [https://tolgee.io/pricing](https://tolgee.io/pricing)):
- Free cloud: *"500 keys"*, *"3 seats"*, *"€0"*
- Business cloud: *"€179/mo billed annually"*, 5,000 keys, 8 seats
- Self-hosted: *"For teams that need to keep all data on their own infrastructure due to security policies, compliance requirements, or data residency rules."* — pricing requires contacting sales.

4Shark's 875 backend YAML files represent well over 500 keys, making the free cloud tier insufficient. The self-hosted option has no public per-seat pricing.

Multi-tenant translation override (where Tenant A overrides key X while inheriting all other keys from a shared base) is **not available** in the current self-hosted Tolgee version as of the time of research. This is a known gap in their roadmap for self-hosted deployments.

**Source:** [https://docs.tolgee.io/platform/formats/ruby_yaml](https://docs.tolgee.io/platform/formats/ruby_yaml), [https://tolgee.io/pricing](https://tolgee.io/pricing)

#### 3b: Locize (cloud-only)

Locize implements multi-tenant via a parent/child namespace model. From [https://locize.com/multi-tenant](https://locize.com/multi-tenant):

- *"A parent project holds your base translations. Each tenant project inherits everything and overrides only what they need."*
- *"Tenant projects inherit all translations from the parent. New keys added to the parent appear in every tenant automatically."*
- *"Tenants override individual strings while the rest fall through to the parent. Only overridden values count toward the tenant's usage."*

The pricing model follows override count: *"Pricing is based on overridden values only."* This means Atento's overrides (a small subset of all keys) would incur minimal additional cost.

From [https://locize.com](https://locize.com): *"SaaS teams can give each customer their own translation layer, without managing separate projects"* and *"Per-customer translation overrides"*.

Locize has no self-hosted offering. All translation data resides in their cloud infrastructure. Export formats include JSON (Angular-compatible) and Rails YAML.

Phrase and Crowdin are additional commercial TMS options researched but pricing pages were inaccessible during this spike (HTTP 403). Both support Rails YAML and JSON export based on their public documentation.

**Source:** [https://locize.com](https://locize.com), [https://locize.com/multi-tenant](https://locize.com/multi-tenant) — verbatim quotes above confirmed in fetched content.

**Significance:** Tolgee is the OSS/self-hosted path; Locize is the best-fit path for the Atento constraint. Both treat the TMS as the canonical source and export to both Rails YAML and Angular JSON. They add an operational dependency (a service to run or pay for) and change the authoring workflow (strings live in a UI, not in git). Key count and seat limits are relevant constraints for the free Tolgee tier.

---

### Finding 4: Shared gem + npm package — no established community pattern

No community-maintained project publishes both a Ruby gem and an npm package from a single translation source repository in lockstep. The dual-packaging concern was validated by researching the i18n-js npm companion: it is an entirely separate package maintained by the same author (`fnando`) for the JavaScript side, not a monorepo that publishes to both registries simultaneously. Teams who want gem + npm in lockstep use TMS tooling (push once, pull twice) rather than a shared package.

This finding is a negative result: the dual-registry shared-package model is not an established pattern, confirming the engineering concern raised in the investigation brief.

**Source:** Absence of examples in GitHub search and i18n community resources; the two-part i18n-js architecture (gem + separate npm) confirms the pattern is split-package-by-author, not monorepo-dual-publish.

**Significance:** The shared-package approach would require 4Shark to author and maintain a novel dual-registry release pipeline with no reference implementations. The risk surface (coordinated versioning, two registries, two ecosystems' conventions) is real and unmitigated by community tooling.

---

### Finding 5: Runtime API endpoint — Rails exposes translations, Angular fetches at load

**Architecture:** Rails adds a `GET /translations?locale=:locale` endpoint that calls `I18n.t('.')` (returns the full locale tree as a hash) and renders it as JSON. Angular switches `i18n.service.ts` from the current `setTranslation` (compile-time bundle) to a `TranslateHttpLoader` (runtime HTTP fetch). The existing `mergeTranslations` utility and `TRANSLATION_FILES` array structure in the frontend are compatible with this approach — tenant-specific overlay files could be fetched from a second URL and merged client-side.

**ngx-translate v18 note:** The ngx-translate.org release notes state: *"The HTTP loader also gained built-in multi-resource loading and a permissive 404 default."* The codebase is on v17 (`@ngx-translate/core: ^17.0.0`); upgrading to v18 would provide native multi-resource HTTP loading without the custom `multi-file-translate-loader.ts` shim currently in place.

**Tenant overrides via Rails backend:** The Rails I18n guide describes `I18n::Backend::Chain` as follows: *"you can replace the Simple backend with the Chain backend to chain multiple backends together. This is useful when you want to use standard translations with a Simple backend but store custom application translations in a database or other backends."* Example from the guide:

```ruby
I18n.backend = I18n::Backend::Chain.new(I18n::Backend::ActiveRecord.new, I18n.backend)
```

A tenant-specific backend (DB-backed or tenant-YAML-backed) could be prepended to the chain, so `I18n.t('acceptment.one')` returns `"Ciência de Aceitação"` for Atento's locale context while returning `"Aceitação"` for all other tenants. The existing `set_locale` from `company.locale` in `JwtAuthorizedController` could extend to also select the tenant-specific backend for the duration of the request.

**Source:** [https://guides.rubyonrails.org/i18n.html#using-different-backends](https://guides.rubyonrails.org/i18n.html#using-different-backends) — verbatim quotes above confirmed. [https://ngx-translate.org](https://ngx-translate.org) — v18 quote confirmed. `app-webclient/src/app/core/translation-merger.ts`, `i18n.service.ts`.

**Significance:** The Runtime API is the only option that enables dynamic tenant overrides without a rebuild. It works with the existing ngx-translate pipe in Angular templates. However, it requires: (a) a refactor of `i18n.service.ts` from compile-time `setTranslation` to runtime HTTP loading; (b) the Rails backend to serve translations via an authenticated endpoint; (c) caching strategy to avoid blocking app startup on a network request; (d) a decision on how to handle frontend-only strings (UI chrome, Angular-specific labels) that have no Rails equivalent.

---

### Finding 6: What strings are actually worth sharing

The investigation found three distinct categories when examining the 138 frontend top-level keys against the 875 backend YAML files:

**Backend-only (no sharing value):**
- Mailer body text and subjects
- PDF/Excel workbook generation strings (used in `I18n.with_locale(company.locale)` blocks for export generation)
- ActiveRecord validation error messages that are processed and returned as structured GraphQL errors — the frontend displays the pre-rendered string it receives, it does not re-translate

**Frontend-only (no sharing value):**
- UI chrome: button labels, navigation labels, form field placeholders, hint text, pagination labels, loading states
- Angular-specific component copy that has no backend analog

**Genuinely shared (highest value for unification):**
- Domain noun singular/plural labels — the 115 frontend keys with `one`/`other` structure that mirror the Rails `activerecord.models.<model>.one/other` pattern. These appear in both backend-generated reports and frontend UI components.
- Enum value display labels (e.g., role names, status labels) that the backend serializes into API responses and the frontend re-translates using the same key
- Error category labels (distinct from full validation messages)

**Source:** Structural comparison of `app/config/locales/pt-BR/` subdirectory (`models/`, `generic.yml`, `pages/`) against `app-webclient/src/translations/pt-BR.json` key structure. Codebase search for `I18n.with_locale` usage patterns in `app/`.

**Significance:** The genuine overlap is concentrated in the 115 domain noun keys. A selective sync of only those keys (rather than a full unification) would capture the highest-value shared strings at the lowest migration cost. This scope is small enough to maintain manually with a lint check, or to export selectively via i18n-js or a TMS.

---

### Finding 7: The Atento per-tenant override case — current state vs future need

**Current state (corrected after engineer input + git inspection):** The override does NOT live in the `src/environments/atento/` build target (that holds only branding — manifest, colors, icons). It lives in **long-lived git branches**: `origin/atento` and `origin/atento-mx`. Each branch is 2 commits ahead of `develop` and 7 behind, last commit `chore(*): Atento translations` / `Atento Mexico translations`, and the branches are **force-pushed** (rebased onto `develop` and the override re-applied on each cycle). The override touches ONLY the three translation JSON files (`pt-BR/en/es`), ~30 changed lines on `atento`, ~48 on `atento-mx`.

The content of the override is a **remap of the access-level (seat type) hierarchy labels** — the same technical keys get shifted display names. On `atento`: `director` → "Vice Presidente", `general_manager` → "Superintendente", `president` → "Presidente Global", `superintendent` → "Diretor", `vice_president` → "Presidente Local". It appears in three sections of the JSON (`seat_type.options`, `seat_types`, and the per-level `description` strings). `atento-mx` diverges further from `atento` because Mexico rejected the Brazil-defined naming and has its own.

This is the real per-tenant override mechanism today: **one rebased-forever, force-pushed branch per client, deployed separately**, carrying a tiny, well-bounded label diff. It is the operational pain (drift, per-client rebuild, force-push churn, N branches to propagate every `develop` change into) that motivates unification.

**Future requirement (from investigation brief):** The team wants the ability to override specific translation keys for Atento without a full rebuild and without affecting other tenants.

**Per-option analysis for the Atento constraint:**

| Option | Atento override story |
|--------|----------------------|
| i18n-js (Option A) | Requires a separate export pattern config per tenant; generates N JSON variants at build time; still requires a rebuild per tenant |
| Tolgee self-hosted (Option B1) | Multi-tenant override not available in self-hosted as of research date |
| Locize cloud (Option B2) | Native parent/child model — purpose-built for this case; Atento child project inherits base and overrides only needed keys; no rebuild required |
| Runtime API (Option C) | I18n::Backend::Chain allows a tenant-specific YAML or DB backend prepended per request; no rebuild required; company context already available via JWT |
| Formalized split (Option D) | No new Atento override mechanism; status quo requires a separate build per tenant for any translation change |

**Source:** `app-webclient/src/environments/atento/` (directory listing), [https://locize.com/multi-tenant](https://locize.com/multi-tenant), [https://guides.rubyonrails.org/i18n.html#using-different-backends](https://guides.rubyonrails.org/i18n.html#using-different-backends)

**Significance:** The Atento constraint is the decisive differentiator between options. Only Locize (cloud) and the Runtime API (self-built) provide dynamic per-tenant override without a rebuild. All other options require either a rebuild per tenant or a TMS with a gap in self-hosted multi-tenant support.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **A: i18n-js gem** (build-time Rails YAML → JSON) | Single source of truth is Rails YAML; handles pluralization format natively; no third-party infra dependency | Must replace ngx-translate pipe with i18n-js npm API in all Angular templates; no native Atento override (requires per-tenant export config + rebuild); gem not in Gemfile today | GitHub fnando/i18n-js |
| **B1: Tolgee self-hosted** | OSS, self-hostable, no per-key cost; exports both Ruby YAML and JSON from one project; CI push/pull workflow | Multi-tenant override not available in self-hosted; adds infra operational dependency (a service to run); authoring workflow moves to a UI | docs.tolgee.io, tolgee.io/pricing |
| **B2: Locize cloud** | Native parent/child multi-tenant (purpose-built for Atento case); only overridden values billed; new keys auto-propagate to tenant projects | Cloud-only, no self-hosted option; translation data leaves 4Shark infrastructure; pricing scales with override count and seat count | locize.com/multi-tenant |
| **C: Runtime API endpoint** | Dynamic tenant overrides without rebuild; works with existing ngx-translate templates and `| translate` pipe; no third-party dependency; company context already available via JWT; I18n::Backend::Chain is a Rails primitive | Requires refactor of `i18n.service.ts` (setTranslation → HTTP loading); extra network round-trip on app startup (needs caching); frontend-only strings still need separate JSON; Rails endpoint must align key namespaces to frontend structure | Rails guides, ngx-translate.org |
| **D: Formalized split** (status quo with documented contract) | No code changes; explicit about intentional separation; lowest risk | Value divergence grows over time; no path to Atento dynamic override; manual sync burden for shared keys remains | codebase Finding 1 |

## What remains uncertain

- **Phrase and Crowdin pricing/features:** The Phrase pricing page returned HTTP 403 during research; Crowdin was not fetched directly. Both are commercial TMS options that support Rails YAML and JSON export. Current pricing and multi-tenant support for each remains unconfirmed.

- **Tolgee self-hosted multi-tenant roadmap:** The self-hosted gap for multi-tenant was identified but no public ETA from Tolgee was found during research. The Business cloud tier at €179/mo includes branching but does not explicitly describe per-tenant child projects in the pricing page content fetched.

- **Rails endpoint key namespace alignment:** The current Rails locale structure (`activerecord.models.company.one`) differs from the frontend key structure (`company.one`). A Runtime API implementation would need to either (a) expose a transformed key structure or (b) require a frontend key refactor. The scope of that transformation was not measured.

- **Regional Spanish variants in the frontend:** The backend supports 9 locale variants including `es-MX`, `es-AR`, etc. The frontend currently supports only `en`, `es`, and `pt-BR`. How regional Spanish variants would be added to the frontend (or whether they are needed) is unresolved.

- **~~Whether the Atento label divergence is intentional~~ — RESOLVED:** It is intentional product differentiation, implemented as the access-level label remap carried in the `atento` / `atento-mx` git branches (see Finding 7, corrected). It is a deliberate per-client renaming of the seat-type hierarchy, not drift. The open scope is the seat-type/access-level enum only — a small, stable key set the backend already owns (the seat type is a backend enum), which makes a backend-side per-company override the natural single-source fix.

- **ngx-translate v18 migration scope:** The current version is `^17.0.0`. The v18 release renamed `default*` configuration to `fallback*` and changed standalone provider setup. The full breaking change surface of upgrading from v17 to v18 in the existing codebase was not assessed.

## Suggested options for main and the engineer

**Option A — i18n-js gem (build-time export)**
Add `i18n-js` gem to `app/Gemfile`; configure an export that maps `activerecord.models.*` keys to the frontend's flat structure; run `i18n export` as part of the Angular build pipeline. Frontend imports generated JSON files. Angular templates remain ngx-translate-based if a shim adapter maps i18n-js npm calls to `translateService`, or templates are rewritten to use i18n-js npm directly.
Conditions where this fits: team wants a zero-infra, Rails-YAML-native solution and is willing to invest in template migration or an adapter layer; Atento override is handled via a separate tenant export config (rebuild per tenant is acceptable).

**Option B1 — Tolgee self-hosted TMS**
Deploy Tolgee on 4Shark infrastructure; import Rails YAML and Angular JSON into one project; use CLI to push/pull both formats. CI workflow keeps both repos in sync with the TMS as source of truth.
Conditions where this fits: team wants OSS, data stays in 4Shark infra, is willing to operate a self-hosted service, and the Atento multi-tenant requirement is deferred or handled by a separate mechanism.

**Option B2 — Locize cloud TMS**
Import strings to Locize; create a base project + an Atento child project; Angular loads translations via the Locize SDK or exported JSON; Rails imports Locize-exported YAML.
Conditions where this fits: the Atento multi-tenant dynamic override is the primary driver and team is comfortable with a cloud-hosted third party holding translation data.

**Option C — Runtime API endpoint**
Add `GET /translations` endpoint to the Rails app returning `I18n.t('.')` as JSON, scoped to the authenticated company's locale and tenant backend (via `I18n::Backend::Chain`). Refactor `i18n.service.ts` to use `TranslateHttpLoader` instead of `setTranslation`. Frontend fetches translations on login using the existing company locale from JWT.
Conditions where this fits: team wants dynamic Atento overrides without a rebuild, wants to avoid third-party infra, and can accept the startup HTTP round-trip cost and the `i18n.service.ts` refactor.

**Option D — Formalized split with lint enforcement**
Keep two independent translation sets but document the ~115 shared domain noun keys as a "translation contract"; write a CI lint check that alerts when a key exists in both and values differ beyond an allowed exception list.
Conditions where this fits: team decides the unification cost outweighs the benefit, wants to reduce drift risk rather than eliminate it, and defers Atento translation customization to a later decision.
