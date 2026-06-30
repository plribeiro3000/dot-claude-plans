# SPIKE — Migrate off the `elasticsearch` gem to `opensearch-ruby`

**Status:** decision recorded — execution design pending.
**Project:** `app` (Ruby on Rails).
**Trigger date:** 2026-06-22.
**Supersedes the deferred follow-up:** `completed/app/elasticsearch-bulk-refresh-and-upgrade/PLAN-SPIKE.md` § Track 3/4 (which left the adapter choice to the engineer and parked it as "independent technical debt").

---

## Decision

Migrate the app's search client from the `elasticsearch` gem family (`elasticsearch`, `elasticsearch-persistence`, `elasticsearch-model`) to the **official `opensearch-ruby`** gem, and **build a thin in-app Repository shim** on top of it so that `ApplicationElasticIndex` / `DealElasticIndex` and their callers keep their current interface.

- Keep the application code and the `Deal` (ActiveRecord) × `DealElasticIndex` (isolated index) separation.
- Keep the per-tenant client swap (`DealElasticIndex.client = ...`).
- Swap **only** the adapter; reimplement whatever the official gem does not provide (it has no persistence/Repository layer — we supply it).

This was "Option B" in the prior PLAN-SPIKE. The community fork `opensearch-rails` (the "Option A" that ships a ready Repository) was **rejected** — see Rationale.

---

## Why we are here (the trigger)

CI's `Bundler Audit` flagged **`faraday` 1.10.5 / CVE-2026-54297** (High — uncontrolled recursion / stack-exhaustion DoS), fix = `update to '>= 2.14.3'`. faraday cannot move to 2.x because of the Elasticsearch client stack:

```mermaid
flowchart LR
  A["gem 'elasticsearch', '< 7.14.0'"] --> B[elasticsearch-transport 7.13.3]
  B -->|requires| C["faraday (~> 1)"]
  C -.blocks.-> D["faraday >= 2.14.3 (CVE fix)"]
```

The app pins `elasticsearch < 7.14.0` because `elasticsearch-ruby >= 7.14` refuses to talk to OpenSearch (product-verification via the `x-elastic-product` header), and the platform runs on **OpenSearch** (cluster `app-shared-001` is on **OpenSearch 3.5**). So upgrading the ES gem is a closed path. The only way to free faraday — and fix the CVE at the root — is to replace the Elasticsearch client gem with an OpenSearch-native one.

**Confirmed (2026-06-22):** `opensearch-ruby` 3.4.0 depends on `faraday >= 1.0, < 3` (via `opensearch-transport`). Adopting it lets the resolver pick faraday `>= 2.14.3` → **resolves CVE-2026-54297**.

> Note: the CVE does **not** block the unrelated style-rename PR #5151 — `Bundler Audit` is not a required check on `develop` (only `Verify Minimum Age` is). This migration is the legitimate root-cause fix, not a gate for that PR.

---

## Options considered

Full analysis in the prior spike (`completed/app/elasticsearch-bulk-refresh-and-upgrade/PLAN-SPIKE.md` § Track 4). Summary:

| Option | What | Verdict |
|---|---|---|
| `opensearch-rails` fork via `github:` | Community fork of `elasticsearch-rails`; ships `OpenSearch::Persistence::Repository` (closest drop-in) | **Rejected** — unmaintained + supply-chain (see Rationale) |
| **`opensearch-ruby` + Repository shim** | Official OpenSearch client; no persistence layer → we build a thin shim | **Chosen** |
| `esse` gem | Supports ES+OS; different architecture (`Esse::Index`) | Rejected — low adoption; full rewrite |
| `searchkick` | OpenSearch-endorsed; search lives in the AR model | Rejected — eliminates the Deal/DealElasticIndex separation; per-tenant client swap is global (needs a hack) |

---

## Rationale — why `opensearch-ruby` and NOT the `opensearch-rails` fork

The fork is the cheaper drop-in (ready Repository, smaller change). It was rejected on two grounds confirmed by research on 2026-06-22:

### 1. It is unmaintained — effectively a dead library

GitHub API, all three forks in the chain share the **same last commit, `2024-02-09` ("Update the opensearch-rails gem (RM-2427)")** — frozen for ~2.5 years:

| Fork | Last commit | Notes |
|---|---|---|
| `TheRealReal/opensearch-rails` (origin) | 2024-02-09 | 1 star; forum reports it "looks abandoned" |
| `compliance-innovations/opensearch-rails` | 2024-02-09 | de-facto single author (M. Bolhuis); tags `v1.0.0`, `v1.1.0.a`, `v1.1.0.b` (irregular) |
| `Prolegis/opensearch-rails` | 2024-02-09 | re-forked "for stable release, preventing issues from changes to remote which doesn't follow typical versioning" |

- The "30 contributors" on the fork are **inherited from the `elasticsearch-rails` git history** — not active OpenSearch maintainers.
- Main branch is "compatible with version 2.x of the OpenSearch stack" — the cluster runs **OpenSearch 3.5**; 3.x support is not guaranteed.

### 2. It is unpublished by deliberate ecosystem choice, not oversight

The OpenSearch project decided **not** to own/publish an official `opensearch-rails`, pushing users to `searchkick` or to build over `opensearch-ruby` directly (issue `opensearch-project/opensearch-ruby#50`):

- mcoms (2022-11-12): "When I first raised this issue in January, it seemed as though forgetting about an `opensearch-rails` gem was a simple oversight rather than a conscious choice" — i.e. it was a conscious non-decision.
- simi (rubygems.org maintainer, 2022-11-12): "Initially I was about to go with 1. [fork and donate it], but then I realized I don't want to spend my time contributing to billion dollar company projects."
- dblock (Amazon/OpenSearch, 2022-11-15): "don't let anyone stop you from forking and maintaining opensearch-rails outside of this org - we can always move it here later."
- wbeckler (OpenSearch, 2022-11-17): "I don't want to encourage that as a solution over adding whatever is missing from searchkick."

So `opensearch-rails` is github-only company forks — outside Renovate/Dependabot/min-age and outside the 4Shark supply-chain policy.

### 3. The chosen base is the opposite on every axis

`opensearch-ruby` is the **official OpenSearch-project client**, published and versioned on rubygems (3.4.0), faraday `>= 1.0, < 3` (fixes the CVE), works with Renovate/Dependabot. At least one team in issue #50's own thread did exactly this — reimplemented the useful pieces over `opensearch-ruby` directly.

The cost of the shim (the fork's one advantage) is a one-time, self-owned implementation we control — preferable to importing a dead dependency into the critical search path.

---

## What stays vs. what changes

**Stays:** application code, the `Deal`/`DealElasticIndex` separation, the per-tenant client swap, the public surface used by callers (`save_document!`, `delete_document!`, `fetch_ids_by`, `search(...).raw_response` + `scroll`, `create_index!`, `index_exists?`).

**Changes:** the `Gemfile` (remove `elasticsearch`, `elasticsearch-persistence`, `elasticsearch-model`; add `opensearch-ruby`); the includes/aliases inside `ApplicationElasticIndex`; the `settings`/`mappings` DSL surface in `DealElasticIndex`; the error-class namespaces (`Elasticsearch::Transport::...` → `OpenSearch::Transport::...`). All of it absorbed behind the shim so callers are untouched.

**Code surface to map in the execution phase** (from the prior spike's sources):
- `app/elastic_indexes/application_elastic_index.rb` (Repository + DSL includes, `save_document!`)
- `app/elastic_indexes/deal_elastic_index.rb` (`settings`/`mappings` DSL)
- `app/middlewares/elastic_index_connection.rb` + `app/config/initializers/elastic_indexes.rb` (per-tenant `client =`)
- `app/adapters/metric/total_adapter.rb`, `app/adapters/metric/quantity_adapter.rb`, `app/workers/deal_eligibility/grower.rb` (`fetch_ids_by`)
- `app/workers/deal_elastic_index/expirator.rb` (`raw_response` + `scroll`)
- `app/workers/deal_elastic_index/{consumer,grower,destroyer}.rb` (`save_document!` / `delete_document!`)

---

## Open — to design in the execution phase (next step)

Not decided here; this SPIKE records the adapter decision + rationale only.

1. **Repository shim API** — exact methods to expose (`save`/`update`/`delete`/`search`/`find`/`create_index!`/`delete_index!`/`refresh_index!`/`index_exists?` + `settings`/`mappings` DSL) and how `bulk` maps to `OpenSearch::Client#bulk`.
2. **Query equivalence** — `fetch_ids_by` (bool/must/range/match) and the `scroll` in `expirator.rb` must return byte-for-byte identical results; define the equivalence tests.
3. **faraday pin sweep** — confirm no other gem in `Gemfile.lock` pins `faraday (~> 1)` after `elasticsearch-transport` is removed (so the resolver actually reaches `>= 2.14.3`).
4. **Test strategy** — are there integration tests against OpenSearch in CI, or only mocked unit tests?
5. **Reindex / rollout** — staging validation before production; whether existing indexed data needs a reindex.
6. **PR scoping** — this migration as its own PR, independent of any other work.

---

## Sources

- `app/Gemfile.lock` — `nokogiri`/`faraday` resolution; `elasticsearch-transport (7.13.3) → faraday (~> 1)`.
- Bundler Audit (CI, 2026-06-22) — `faraday 1.10.5 / CVE-2026-54297`, "update to '>= 2.14.3'".
- rubygems.org API (2026-06-22) — `opensearch-ruby` 3.4.0 → `faraday >= 1.0, < 3`, `multi_json >= 1.0`.
- GitHub API (2026-06-22) — last commit `2024-02-09` on `TheRealReal/`, `compliance-innovations/`, `Prolegis/` `opensearch-rails`.
- [opensearch-project/opensearch-ruby#50](https://github.com/opensearch-project/opensearch-ruby/issues/50) — verbatim quotes (mcoms 2022-11-12, simi 2022-11-12, dblock 2022-11-15, wbeckler 2022-11-17); issue closed 2023-02-07.
- [forum.opensearch.org — Request for Elasticsearch-rails fork](https://forum.opensearch.org/t/request-for-elasticsearch-rails-fork/6860).
- Prior study: `completed/app/elasticsearch-bulk-refresh-and-upgrade/PLAN-SPIKE.md` § Track 3/4 (option analysis, code-surface sources).
- `completed/app/elasticsearch-bulk-refresh-and-upgrade/REVISIT-CONTEXT.md` — cluster `app-shared-001` on `OpenSearch_3.5`.
