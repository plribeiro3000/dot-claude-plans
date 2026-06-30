# SPIKE — GA4 as Terraform Infrastructure-as-Code

## Investigation question

Can Google Analytics 4 (GA4) properties, data streams, and configuration be managed declaratively via Terraform — so 4Shark's 40–50 front-end GA configurations live in a Terraform stack and are controlled at scale?

## Executive answer

**No usable Terraform provider for GA4 configuration exists today — neither official nor community.**

- The **official `hashicorp/google`** provider covers GCP services but does NOT include any GA4 Admin API resources. Two GitHub issues (Jan 2024 closed unresolved, Aug 2022 open unresolved) confirm the gap.
- **No community/third-party Terraform provider** wrapping the GA Admin API has been published on the Terraform Registry or GitHub.
- The **Google Analytics Admin API v1** (the API that would power any provider) is fully capable — it exposes CRUD for properties, data streams, custom dimensions, conversion events, and more. The gap is entirely at the Terraform provider layer, not at the API layer.
- A custom Terraform provider is technically feasible. Building one is a non-trivial engineering investment with an ongoing maintenance burden.

---

## Sources consulted

- `https://developers.google.com/analytics/devguides/config/admin/v1` — GA4 Admin API overview: scope of what the API manages
- `https://developers.google.com/analytics/devguides/config/admin/v1/rest` — REST resource reference
- `https://developers.google.com/analytics/devguides/config/admin/v1/quickstart` — Admin API auth and quickstart
- `https://developers.google.com/identity/protocols/oauth2/scopes#analytics` — OAuth scopes for Analytics APIs
- `https://github.com/hashicorp/terraform-provider-google/issues/16898` — Enhancement request for `google_analytics_property` (Jan 2024, closed, no implementation)
- `https://github.com/hashicorp/terraform-provider-google/issues/12439` — Enhancement request for GTM resources including GA4 tags (Aug 2022, open, no implementation)
- `https://registry.terraform.io/providers/hashicorp/google/latest/docs` — Official provider docs (searched for `google_analytics_*` resources; none found)
- `https://www.oscargallegoruiz.com/en/blog/ga4-manager-automate-google-analytics/` — GA4 Manager: Go CLI using Admin API (not Terraform)
- `https://github.com/google/google-analytics-utilities` — Google GA4 management tool (App Script, not Terraform)
- `https://gist.github.com/salrashid123/e6366a551ce952b603036dbd996b7768` — 2020 gist attempting HTTP-based GA tracking via Terraform (non-functional, wrong direction)
- See auxiliary: `ga4terraform_doc_1.txt` — Raw Admin API overview, REST resources, auth, OAuth scopes
- See auxiliary: `ga4terraform_doc_2.txt` — GitHub issue evidence and alternative-tool details

---

## Findings

### Finding 1: Official `hashicorp/google` provider — no GA4 Admin API resources

**Evidence:** Multiple searches of the Terraform Registry for `google_analytics_*` resources in `hashicorp/google` returned only unrelated resources (`google_bigquery_analytics_hub_*`, `google_scc_management_*`). No `google_analytics_property`, `google_analytics_data_stream`, or similar resource exists.

GitHub issue #16898 (`https://github.com/hashicorp/terraform-provider-google/issues/16898`), opened January 4, 2024, explicitly states: "there is no way to create a Google Analytics property under a known Google Analytics account ID." The issue was closed with no linked PRs and no maintainer response.

**Source:** `https://registry.terraform.io/providers/hashicorp/google/latest/docs` (provider resource index); `https://github.com/hashicorp/terraform-provider-google/issues/16898`

**Significance:** The `hashicorp/google` provider scopes itself to GCP services (Compute, BigQuery, Firebase, Cloud Run, etc.). Google Analytics 4 is a separate product under Google Marketing Platform and is not covered. The two providers share the `google.*` namespace but GA4 is a distinct API surface.

Verbatim quote confirmed: "there is no way to create a Google Analytics property" — in issue #16898 body at `https://github.com/hashicorp/terraform-provider-google/issues/16898`.

---

### Finding 2: Third-party / community Terraform providers — none found

**Evidence:** Exhaustive searches of the Terraform Registry and GitHub found no published Terraform provider wrapping the Google Analytics Admin API v1. The closest artifacts found:

1. A 2020 GitHub gist (`https://gist.github.com/salrashid123/e6366a551ce952b603036dbd996b7768`, last active July 27, 2020) attempting to use Terraform's `http` data source to send UA tracking events — documented as non-functional (wrong content-type returned by GA), last active 2020, and concerns the wrong problem (pushing hits, not managing GA4 config).
2. The `airbytehq/airbyte` Registry provider has `airbyte_source_google_analytics_data_api` — this is an Airbyte data extraction connector, not GA4 Admin API configuration management.

**Source:** Terraform Registry search `https://registry.terraform.io/search/providers?q=google+analytics` (Registry page returned only header, no providers; confirmed empty via search engine results that showed no GA4 admin provider); GitHub searches with terms `"terraform-provider" "google-analytics" admin API`.

**Significance:** No drop-in community provider exists. The community has not filled this gap despite the 2022–2024 GitHub issues. This is an open engineering gap.

UNVERIFIED: The Terraform Registry search pages are JavaScript-rendered and returned only a header to the fetch tool — the provider absence is inferred from search engine result sets (which showed no GA4 admin provider under any namespace) rather than a direct page-by-page scrape.

---

### Finding 3: GA4 Admin API scope — the ceiling of what any provider could manage

**Evidence:** From the Admin API overview: "The Google Analytics Admin API allows for programmatic access to the Google Analytics configuration data and is only compatible with Google Analytics properties."

The Admin API v1 exposes full CRUD for:
- Accounts and account summaries
- Properties (`displayName`, `timeZone`, `currencyCode`, `industryCategory`, `propertyType` — all configurable; `serviceLevel` is output-only)
- Data streams (web, Android app, iOS app): create, get, list, patch, delete
- Measurement Protocol secrets
- Custom dimensions and custom metrics (with archive)
- Key events (formerly conversion events)
- Event create/edit rules (v1alpha)
- Firebase links, Google Ads links, BigQuery links, SA360 links, DV360 links
- Data retention settings, Google Signals settings
- Audiences and channel groups (v1alpha)
- User access bindings

**Source:** `https://developers.google.com/analytics/devguides/config/admin/v1` (overview); `https://developers.google.com/analytics/devguides/config/admin/v1/rest` (REST reference). See `ga4terraform_doc_1.txt` for full resource list.

**Significance:** The API ceiling is high — nearly everything a GA4 administrator does in the UI is programmable. A Terraform provider built on this API could, in theory, declaratively manage the full server-side GA4 configuration for all 40–50 properties from a single stack.

Verbatim quote confirmed: "The Google Analytics Admin API allows for programmatic access to the Google Analytics configuration data" — at `https://developers.google.com/analytics/devguides/config/admin/v1` overview text.

---

### Finding 4: The critical split — server-side config vs client-side tag

**Evidence:**

The GA4 Admin API overview page makes **no mention of gtag.js, GTM snippets, or client-side JavaScript**. The API covers server-side configuration only.

The `measurementId` field on a web data stream is **output-only**: per the REST docs for `properties.dataStreams`, the measurement ID "is not editable" and is "the unique Google-assigned identifier of a web stream (e.g. G-1234567)." It is assigned by Google when a web data stream is created via the API, not specified by the caller.

The **client-side tag** — the `<script>` block with `gtag('config', 'G-XXXXXXXXXX')` embedded in each front-end's HTML, or a Google Tag Manager container snippet — is application code. It lives in each front-end repository and is deployed as part of the front-end's own build/deploy process. The Admin API does not deploy, modify, or validate client-side code in any form.

**Source:** `https://developers.google.com/analytics/devguides/config/admin/v1` (no gtag.js mention); measurement ID output-only field confirmed via REST docs for `properties.dataStreams` and reiterated in the GA4 Admin API quickstart.

**Significance (for 4Shark's 40–50 front-ends):**

| Layer | Managed by Admin API / Terraform | Lives in |
|-------|----------------------------------|----------|
| GA4 account | Yes | Google's servers |
| GA4 property (display name, timezone, currency) | Yes | Google's servers |
| Web data stream (one per front-end) | Yes | Google's servers |
| Measurement ID (`G-XXXXXXXXXX`) | Assigned by API, output-only | Google's servers |
| Custom dimensions, metrics, conversions | Yes | Google's servers |
| `<script gtag.js ...>` tag in HTML | **No** | Each front-end repo |
| GTM container snippet | **No** | Each front-end repo |

Terraform (if a provider existed) can own the left column. The right column stays as front-end application code. The measurement ID, once created by Terraform/API, can be consumed as a Terraform output and injected into each front-end's config — but that injection step is a separate front-end deployment concern.

---

### Finding 5: Authentication to the GA Admin API

**Evidence:** From the Admin API quickstart (`https://developers.google.com/analytics/devguides/config/admin/v1/quickstart`): service accounts are supported for server-to-server flows. Required OAuth scopes:

- `https://www.googleapis.com/auth/analytics.edit` — "Edit Google Analytics management entities"
- `https://www.googleapis.com/auth/analytics.readonly` — for read-only operations

Service accounts "must themselves be granted a GA4 role (e.g., Administrator) at the target account or property." This means the service account needs to be added as an Editor or Administrator in the GA4 UI (or via the Admin API's own access bindings endpoint).

Go client library: `google.golang.org/api/analyticsadmin/v1beta` (`https://pkg.go.dev/google.golang.org/api/analyticsadmin/v1beta`).

**Source:** `https://developers.google.com/identity/protocols/oauth2/scopes#analytics` (scope descriptions); `https://developers.google.com/analytics/devguides/config/admin/v1/quickstart`

**Significance:** Standard GCP service account authentication applies. A Terraform provider would authenticate identically to any other GCP provider: a service account key or Workload Identity, granted `analytics.edit` scope, with the service account added as a GA4 Editor/Administrator. No special auth mechanism is needed beyond standard GCP patterns already in use at 4Shark.

Verbatim quote confirmed: the `analytics.edit` scope is described as "Edit Google Analytics management entities" — at `https://developers.google.com/identity/protocols/oauth2/scopes#analytics` in the Analytics section.

---

### Finding 6: Pattern for N properties — what exists, and realistic alternatives today

**Evidence:** No GA4 Terraform provider exists, so the `for_each` pattern cannot be applied today. If a provider existed, the standard Terraform shape for 40–50 properties would be a module with `for_each = var.front_ends` over a map of `{ site-name = { display_name, time_zone, ... } }` producing one property + one data stream per front-end — standard Terraform idiom.

**Realistic alternatives that exist today:**

1. **GA4 Manager (Go CLI / MCP server)** — `https://www.oscargallegoruiz.com/en/blog/ga4-manager-automate-google-analytics/`: "GA4 Manager is an open-source CLI tool and MCP server that automates Google Analytics 4 and Search Console configuration." Uses Admin API v1alpha, YAML-declarative, manages properties, custom dimensions, metrics, data retention, conversions. Limitation noted: audience creation is not fully automated — the tool generates documentation for manual UI completion. Not Terraform; does not integrate with Terraform state.

2. **Google Analytics Utilities (Google Sheets App Script)** — `https://github.com/google/google-analytics-utilities`: "This repository contains an App Script tool designed to work with Google Sheets, enabling bulk management of Google Analytics 4 settings." Note: "This is not an officially supported Google product." Last release Oct 28, 2024; 247 stars. Spreadsheet-based; not IaC.

3. **Custom Terraform provider** — building one from scratch using the Terraform Plugin Framework (Go), wrapping `google.golang.org/api/analyticsadmin/v1beta`. Technically feasible; Admin API has full CRUD; Go client library is published by Google. Maintenance burden falls on 4Shark.

4. **Direct Admin API script (Python/Go) in CI** — wraps the same API, runs on deploy or on schedule, compares desired vs actual state. No Terraform integration; drift detection must be written from scratch.

**Source:** alternatives cited from sources listed above. The for_each pattern is standard Terraform idiom (no specific citation needed — it is the language's built-in iteration mechanism).

---

## Trade-offs surfaced

| Option | Pros | Cons | Source |
|--------|------|------|--------|
| Wait for official `hashicorp/google` GA4 support | Zero maintenance; HashiCorp/Google own it | No timeline; issues open since 2022/2024 with no traction | github.com issues #12439, #16898 |
| Build a custom Terraform provider (Go, Plugin Framework) | Fits existing Terraform workflow; `for_each` across 50 properties; state in Terraform; drift detection built-in | Significant build effort; ongoing maintenance; must follow Terraform Plugin Framework conventions | developer.hashicorp.com/terraform/plugin |
| GA4 Manager CLI | Exists today; wraps same Admin API; YAML-declarative; open-source | Not Terraform; separate tool chain; no Terraform state; separate skill to operate | oscargallegoruiz.com/en/blog/ga4-manager-automate-google-analytics |
| Direct Admin API script (Python/Go) | Flexible; full API coverage; can run in CI | Not declarative in the Terraform sense; drift detection hand-rolled; no state | developers.google.com/analytics/devguides/config/admin/v1 |
| Google Tag Manager for client-side consolidation | Reduces per-repo GA4 tag embeds to one GTM snippet per site | GTM Terraform resources also do not exist officially (issue #12439 open since 2022); separate product with its own learning curve | github.com/hashicorp/terraform-provider-google/issues/12439 |

---

## What remains uncertain

- Whether HashiCorp has any internal roadmap to add `google_analytics_property` / `google_analytics_data_stream` resources (no public signal in issues or roadmap as of June 2026).
- Whether Google is building a standalone Terraform provider for Google Marketing Platform products (no announcement found).
- How 4Shark's 40–50 front-ends currently embed GA4 measurement IDs — hardcoded in HTML, via env var, via GTM, or another mechanism — which determines the complexity of the "inject measurement ID into front-end" step.
- Whether 4Shark already uses Google Tag Manager across its front-ends (GTM consolidation could reduce the per-front-end GA tag problem independently of any Terraform provider).

---

## What this means for 4Shark

**IaC-able today via Terraform:** Nothing — no provider (official or community) exists.

**Server-side config manageable via GA Admin API TODAY (any scripted approach):**
- Creating and naming GA4 accounts and properties (one per front-end or grouped)
- Creating web data streams and receiving measurement IDs
- Setting data retention, timezone, currency, industry
- Defining custom dimensions, custom metrics, key events
- Linking to BigQuery, Firebase, Google Ads
- Managing user access bindings at scale

**Not manageable by Admin API (ever) — stays as application code:**
- The `<script>` gtag.js snippet or GTM container snippet embedded in each front-end's HTML
- After the server-side property/stream is created (by Terraform or script), each front-end still needs its measurement ID injected — this is a front-end deployment step, separate from any GA admin tool

**Maturity / risk assessment:**
- Admin API itself: mature, stable, v1beta widely used
- Terraform provider for GA4: does not exist; building from scratch = medium-to-high effort with ongoing maintenance risk
- GA4 Manager CLI: exists, open-source, actively maintained, lower risk if team accepts non-Terraform toolchain

---

## Suggested options for main and the engineer

- **Option A: Build a custom Terraform provider** wrapping `analyticsadmin/v1beta` in Go using the Terraform Plugin Framework. Would enable declarative `for_each`-across-50-properties management in an existing Terraform stack; measurement IDs available as Terraform outputs for front-end consumption. Engineering cost: significant upfront; ongoing maintenance.

- **Option B: Adopt GA4 Manager CLI** as the declarative tool for GA4 config, parallel to Terraform. YAML-based, wraps the same Admin API, exists today, open-source. Does not integrate with Terraform state; measurement IDs must be distributed to front-ends through a separate mechanism.

- **Option C: Direct Admin API script (Python or Go) in CI.** Full API coverage; can run in CI/CD pipeline; drift detection must be written by the team. No Terraform state integration.

- **Option D: Wait for official provider support.** Two GitHub issues exist; no timeline. Low-effort now, but the GA4 management problem remains unresolved for an unknown duration.

(NO recommendation — options presented for engineer and main to evaluate.)
