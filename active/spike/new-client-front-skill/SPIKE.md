# SPIKE — Automating "create a new client front" as a dot-claude skill

> Question: today a new client front (an `app-webclient` Netlify site) is created by hand through several UIs. Can the whole process be automated as a dot-claude skill that asks the jurisdiction questions, applies the `JURISDICTION.md` naming convention, and drives the creation end to end? This spike maps the process, what is API-able vs manual, and the phases — to decide whether to build it.

## The end-to-end process (what a new front needs)

A front spans four systems. The backend (the app environment + the client COMPANY) is assumed to already exist — the front only points at it. Verified facts in brackets.

1. **Code — `app-webclient` repo (a PR).**
   - `src/environments/<slug>/manifest.json` (client name, theme colors, icon refs), `styles/colorVariables.scss` (`$primary`/`$secondary`/`*-hover` brand colors), `assets/` (favicons + PWA icons in several sizes). [verified anatomy on `atento`]
   - A new project entry in `angular.json` (build/serve: `assets`, `stylePreprocessorOptions.includePaths` → `src/environments/<slug>/styles`, build command `yarn build <slug>`, `scripts`/`styles`). [verified shape; today 39 projects]
   - Merged to `master` **before** Netlify can build it (`yarn build <slug>` must resolve).

2. **Netlify — the site (API).** [verified: `createSite`, `updateSite`, `createEnvVars`, `createSiteBuildHook`, `createSiteDeploy` all exist]
   - `createSite` connected to the GitHub repo (`repo_url=.../app-webclient`, `installation_id=2652638`, `repo_branch=master`, `allowed_branches=["master"]`, build cmd `yarn build <slug>`, `dir=dist/`). [installation_id seen in existing `build_settings`]
   - `createEnvVars` for the ~25 vars the `env` script reads: `GRAPHQL_API_SERVER` (chosen backend), `CLIENT_NAME`, `COMPANY_ID`, `APP_TITLE`, `LOGO_*`, `FAVICON_*`, `MANIFEST_PATH`, `CURRENCY_*`, `AUTH_*`, `MOBILE_CONFIGURATION_UUID`, `ROLLBAR_ACCESS_TOKEN`, and **conditionally `PRIVACY_POLICY_URL`** (the jurisdiction question). [createEnvVars format proven this session]
   - `custom_domain = <slug>.app4shark.com` via `updateSite`.
   - **Trap (now in `JURISDICTION.md`):** `env:get/set --site` is ignored when a project is linked — always use `netlify api …` with `accountId=5d9c939ac98c2406038d77f5` + `siteId`.

3. **DNS — Cloudflare (gap).** [verified: `app4shark.com` NS = `*.ns.cloudflare.com`; each front is a CNAME `<slug>.app4shark.com → fourshark-app-client-<slug>.netlify.app`]
   - A new CNAME in the Cloudflare `app4shark.com` zone. **No Cloudflare CLI/token found locally** (`wrangler`/`cloudflared` absent, no `CF_*` env). This is the one step not yet API-reachable from here.

4. **GA4 — already tooled (orchestrate, don't reinvent).** [verified: `google-analytics-manager/property-setup`]
   - GA4-as-code: `apps.yml` (monitored/excluded) + `plan`/`apply` create the property + web stream + standardized settings and **set `ANALYTICS_ID` on the Netlify site + deploy**. One **manual UI step** per new property (granular-location toggle — no Admin API). Each client gets its **own** property (this corrected the earlier wrong "single shared property" reading).
   - Runs after the Netlify site exists (it syncs onto the site).

## Automatable vs manual

| Step | How | Status |
|---|---|---|
| Env folder + `angular.json` project | generate files (a PR) | ✅ automatable (code) |
| **Brand assets** (icons/favicons) | images | ⛔ engineer provides (cannot generate) |
| Netlify site + build settings | `netlify api createSite` | ✅ API |
| Netlify env vars (incl. conditional policy) | `netlify api createEnvVars` | ✅ API |
| Netlify custom domain | `netlify api updateSite` | ✅ API |
| **DNS CNAME** (Cloudflare) | Cloudflare API | ⚠ needs a token, or manual |
| GA4 property + `ANALYTICS_ID` sync | `property-setup` `apply` | ✅ existing tool |
| **GA4 granular-location toggle** | GA Admin UI | ⛔ manual (no API) |
| Backend + client COMPANY | app/onboarding/setup | ◻ out of scope (pre-exists) |

## Proposed two-phase shape (matches the engineer's intuition)

The Netlify build needs the `angular.json` project in `master`, so code must land first.

**Phase 1 — Code PR.** Ask the engineer the jurisdiction questions (policy needed? which country?), apply `JURISDICTION.md` to derive the **name** (dedicated → canonical client name; shared → role; suffix per country) and whether `PRIVACY_POLICY_URL` applies; collect brand colors + the asset images; generate `src/environments/<slug>/` + the `angular.json` project; open the PR. Engineer reviews/merges.

**Phase 2 — Infra (after merge).** `createSite` (repo + build cmd `yarn build <slug>`) → `createEnvVars` (the var set, incl. conditional policy) → `updateSite custom_domain` → DNS CNAME (Cloudflare token or hand-off) → add app to `property-setup/apps.yml` + `plan`/`apply` → trigger first build → hand off the two manual residuals (GA4 granular-location toggle; DNS if no token). Verify via `getEnvVars` (the trap).

## Skill interaction (the engineer's described UX)

Ask → propose → confirm, step by step: (1) which client + dedicated/shared/global; (2) jurisdiction → policy yes/no; (3) the skill states the resulting **name + convention** from `JURISDICTION.md` and the var set; (4) engineer "pode seguir"; (5) Phase 1 generates the PR; after merge, (6) Phase 2 runs the infra. Reads current patterns first (like `/create-integrator`), never hardcodes.

## Resolved decisions (engineer)

1. **DNS — via Terraform, not raw API.** `app4shark.com` is a Cloudflare zone managed in the terraform `dns/` stack (`public_dns_app4shark_com.tf`, `cloudflare_zone_ids`, redirect rulesets like `atento-br → atentoprime-br`); credentials are in `dns/.envrc`. The new front's CNAME (`<slug>.app4shark.com → fourshark-app-client-<slug>.netlify.app`) is a Terraform change in that stack — `direnv exec ~/Projects/4Shark/terraform/dns terraform …` plan → apply (apply-before-merge, per Terraform policy) → PR. No raw Cloudflare call, no manual DNS. DNS gap CLOSED.
2. **Iterative skill; assets in S3.** The skill is iterative — the engineer triggers it and it asks for each gap as it goes. Brand images live in the expected S3 bucket (`4shark-assets`, the host in the `LOGO_*`/`FAVICON_*` URLs); if the engineer has them locally, the skill uploads each to S3 with the proper per-file policy/ACL. (The repo env-folder PWA icons under `src/environments/<slug>/assets/` are the in-repo part; the S3 logos/favicons are the env-var-referenced part.)
3. **Frontend-only — backend is out of scope.** The skill asks which existing backend (`GRAPHQL_API_SERVER`) the front points at; it never creates a backend or a client COMPANY. Initial front setup only.
4. **GA4 via `property-setup`.** Orchestrate the existing tool (add the app to `apps.yml` monitored → `plan`/`apply`, which creates the property + stream and syncs `ANALYTICS_ID` on the site) and surface the one manual UI step (granular-location toggle). Do not call the GA Admin API directly.
5. **Skill `create-front`** — dot-claude folder skill (like `/create-integrator`), main-session-driven, reads current patterns each run, never hardcodes.

## Build shape (locked)

`skills/create-front/SKILL.md`, iterative. Reads current patterns first (an existing front's `src/environments/<base>/` + its `angular.json` project, an existing Netlify site's `build_settings` via the API, the `dns/` stack records, `property-setup/apps.yml`, the env var list). Then:

- **Phase 1 (code PR):** ask client + dedicated/shared/global + jurisdiction (policy? country?) → derive name + var set per `JURISDICTION.md` → collect brand colors + assets (S3 path, or local → upload to `4shark-assets` with policy) → generate `src/environments/<slug>/` + the `angular.json` project + (if BR + policy) note `PRIVACY_POLICY_URL` → open the `app-webclient` PR → engineer merges.
- **Phase 2 (infra, after merge):** `netlify api createSite` (repo + `yarn build <slug>` + branch master) → `createEnvVars` (the var set, incl. conditional `PRIVACY_POLICY_URL`) → `updateSite custom_domain` → Terraform `dns/` CNAME (plan → apply → PR) → `property-setup` add-to-`apps.yml` + `plan`/`apply` → trigger first build → verify env via `getEnvVars` (the `--site` trap) → hand off the GA4 granular-location toggle.

## Recommendation

Feasible and worth building. The hard parts are already solved or API-able: Netlify (API), GA4 (`property-setup`), code generation (templated from an existing front). The only true gaps are **brand assets** (inherently engineer-input) and **two manual residuals** (Cloudflare DNS without a token; the GA4 granular-location toggle) — both are clean hand-offs, not blockers. Build it as a two-phase skill (code PR → infra), orchestrating the existing tools, with `JURISDICTION.md` driving the naming/policy questions.
