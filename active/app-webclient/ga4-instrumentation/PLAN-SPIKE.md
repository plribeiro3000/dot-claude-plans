# PLAN-SPIKE — GA4 Front-End Instrumentation Rebuild (app-webclient)

> Reference: `~/.claude/plans/active/spike/ga4-config-best-practices/SPIKE.md`
> Auxiliary files: `aux_codebase_bugs_1.md`, `aux_web_research_2.md`

---

## Objective

Rebuild the Google Analytics 4 front-end instrumentation in `app-webclient` so that all 39 client builds correctly track authenticated B2B SaaS usage. The current implementation has three confirmed bugs and two missing features; basic auto-collection from GA4 library init partially works but all explicit tracking (page_path, user_id, consent) is broken or absent. The rebuild must comply with LGPD (default-denied consent), send the established `{GRAPHQL_API_SERVER}_{user.id}` user_id format, and handle the Electron build path without breaking Netlify deploys.

---

## Already-established decisions (not open, not re-surfaced)

| Decision | Value | Source |
|---|---|---|
| GA4 property management | Done; one property per client, managed as code in `google-analytics-manager` | Parent task brief |
| Measurement ID delivery | `ANALYTICS_ID` Netlify env var → `ngx-scripts env` → `env.ANALYTICS_ID` in app | Parent task brief |
| User-ID format | `{GRAPHQL_API_SERVER}_{user.id}` (`env.GRAPHQL_API_SERVER` + `credentialsService.credentials.user.id`) | Parent task brief |
| Primary privacy regime | LGPD (Brazilian law); GDPR relevant for non-BR clients | SPIKE.md Finding 3 |
| PII prohibition | email, CPF, name, phone MUST NEVER be sent as user_id or any event param | SPIKE.md Finding 2 |

---

## Scope

### In scope

- Fix Bug 1: `gtag_compiler.js` + `src/gtag.js` — the measurement ID injection failure
- Fix Bug 2: `app.component.ts` — the wrong dataLayer push API for page_path tracking
- Add User-ID: set `user_id` after login, null on logout
- Add Consent Mode v2: `analytics_storage` (and the three ad_* signals) default to `'denied'`; update to `'granted'` on user consent
- Add a consent banner component or integrate a CMP library
- Decide and implement the event taxonomy (login, page_view, optionally others)
- Handle Electron build path (analytics disabled or separate ID)

### Out of scope (open question)

- BigQuery export setup (data retention beyond 14 months — separate concern per SPIKE.md Finding 4)
- GA4 property configuration in `google-analytics-manager` (separate repo, already in progress)
- Google Signals activation/deactivation (property-level setting, not front-end code)
- Non-LGPD clients (no evidence of non-Brazilian deployments yet; parameterization deferred)

---

## Confirmed bugs and gaps (codebase findings)

### Bug 1 — Measurement ID never injected into `src/gtag.js`

`gtag_compiler.js` (`app-webclient/gtag_compiler.js`) replaces the token `GTAG_ID`:

```js
let formatted = data.replace(/GTAG_ID/g, process.env.ANALYTICS_ID);
```

But `src/gtag.js` contains `'xx-xxxxxxxxx-x'` (a Universal Analytics placeholder), never `GTAG_ID`:

```js
gtag('config', 'xx-xxxxxxxxx-x');
```

Result: `analytics:compile` runs, replaces nothing, and `src/gtag.js` is deployed with the UA placeholder.
The GA4 library IS loaded correctly from `main.ts` with `env.ANALYTICS_ID` — that part works.
See: `aux_codebase_bugs_1.md` § Bug 1

### Bug 2 — Page-path tracking silently broken

`app.component.ts` (line 45):

```typescript
(window as any).dataLayer.push('config', env.ANALYTICS_ID, { page_path: event.urlAfterRedirects });
```

`dataLayer.push()` takes a single object. Passing three separate arguments pushes three primitives onto the array and is ignored by the GA4 runtime. Correct form is `gtag('config', env.ANALYTICS_ID, { page_path: ... })`.
See: `aux_codebase_bugs_1.md` § Bug 2

### Missing feature 1 — User-ID never set

No `gtag('config', ..., { user_id: ... })` or `gtag('set', { user_id: ... })` exists anywhere in the codebase.
The user's internal ID is available at `credentialsService.credentials.user.id` (type `string`).
See: `aux_codebase_bugs_1.md` § Missing feature

### Missing feature 2 — No Consent Mode / No consent banner

Zero CMP code, zero `gtag('consent', ...)` calls, zero consent banner exist.
Under LGPD, collecting analytics data without affirmative user consent is unlawful.
See: `aux_codebase_bugs_1.md` § Missing feature (consent)

---

## Candidate approaches

There are three orthogonal decisions that produce separate option sets. Each is surfaced independently so the engineer can mix and match.

---

### Decision A — How to fix the measurement ID delivery (`src/gtag.js` and `gtag_compiler.js`)

The root problem: the local `src/gtag.js` file carries both the GA config call and a hardcoded non-GA4 placeholder. Two approaches fix this.

---

#### Option A1: Fix the token in `src/gtag.js` + fix the regex in `gtag_compiler.js`

Change `src/gtag.js` to use `GTAG_ID` as the placeholder (matching what `gtag_compiler.js` already replaces):

```js
window.onload = function () {
  window.dataLayer = window.dataLayer || [];
  function gtag() { dataLayer.push(arguments); }
  gtag('js', new Date());
  gtag('config', 'GTAG_ID');
};
```

The compiler already has `data.replace(/GTAG_ID/g, process.env.ANALYTICS_ID)` — this would now work correctly.

**Pros:**
- Minimal change — two files, one token rename
- Preserves the existing two-script architecture (`main.ts` injects the library, `src/gtag.js` holds config)
- `gtag_compiler.js` step is already in the build pipeline (`analytics:compile` script in `package.json`)
- No new dependencies

**Cons:**
- `gtag_compiler.js` destructively overwrites `src/gtag.js` (not a copy/output step) — if the build is re-run, the placeholder is gone and a re-run replaces an already-replaced value. Fragile: running `analytics:compile` twice produces `G-XXXXXXX` in the source file permanently
- `src/gtag.js` loaded via `window.onload` — fires after all DOM/script loads, introducing a timing gap where the GA4 library has already initialized but the config call has not run yet
- The `gtag_compiler.js` node script is a bespoke one-off with no error handling (it silently succeeds with no replacement if the token is wrong again)
- Consent Mode signals cannot be set before `gtag('config', ...)` with this architecture — `window.onload` is too late

**Cost/effort:** ~30 min (change two files)
**Risk:** Low for the immediate fix; medium for Consent Mode v2 compliance (ordering problem)

---

#### Option A2: Eliminate `src/gtag.js` and `gtag_compiler.js`; move all gtag config into an Angular service

Delete `src/gtag.js` from all `angular.json` assets arrays. Delete or no-op `gtag_compiler.js`. Move all gtag initialization into a new `AnalyticsService` in the Angular app.

`main.ts` already injects the GA4 library script correctly. The new service handles the rest:

```typescript
// sketch of AnalyticsService — NOT a final implementation
@Injectable({ providedIn: 'root' })
export class AnalyticsService {
  private readonly measurementId = env.ANALYTICS_ID;

  initialize(): void {
    if (!this.measurementId) return;
    // Set consent default BEFORE config (see SPIKE.md Finding 3 + aux_web_research_2.md § Source 7)
    gtag('consent', 'default', {
      analytics_storage: 'denied',
      ad_storage: 'denied',
      ad_user_data: 'denied',
      ad_personalization: 'denied'
    });
    gtag('js', new Date());
    gtag('config', this.measurementId);
  }

  setUser(userId: string): void {
    gtag('set', { user_id: userId });
  }

  clearUser(): void {
    gtag('set', { user_id: null });
  }

  trackPageView(pagePath: string): void {
    if (!this.measurementId) return;
    gtag('config', this.measurementId, { page_path: pagePath });
  }

  grantConsent(): void {
    gtag('consent', 'update', { analytics_storage: 'granted' });
  }
}
```

The service is called from:
- `AppModule` providers (factory or constructor call on app init) for `initialize()`
- `AuthenticationService.login()` (after `setCredentials`) for `setUser()`
- `AuthenticationService.logout()` (before `destroyCredentials`) for `clearUser()`
- `AppComponent` router subscription (replacing the broken `dataLayer.push`) for `trackPageView()`

Pattern reference: `src/app/rollbar.ts` (InjectionToken + factory) or `@Injectable({ providedIn: 'root' })` (simpler, since no Angular DI tree isolation needed).
See: `aux_codebase_bugs_1.md` § Rollbar integration pattern

**Pros:**
- Consent Mode v2 signals can be set before any config call — correct ordering guaranteed
- No build-time file overwrite; no fragile compiler step; `gtag_compiler.js` is deleted entirely
- Strongly typed; testable (mockable service); all analytics logic in one place
- Consent Mode `update` call can be triggered from the same service when user grants consent (no need for external bridge script)
- Removes the `window.onload` timing gap
- Eliminates a bespoke Node.js script that was already broken

**Cons:**
- More files to change (remove `src/gtag.js` from 39 entries in `angular.json`, add service file, update `AppComponent`, `AuthenticationService`, `AppModule`)
- Requires the `declare let gtag: Function` global or a typed wrapper — needs `gtag.js` global to be available (still loaded by `main.ts`, which is correct)
- Angular 19 uses standalone APIs by preference; the current codebase uses NgModule — the service registration pattern must match what's already there

**Cost/effort:** ~3–4 hours (new service, wire into existing components, remove old files)
**Risk:** Low; no new runtime dependencies. Removes more surface area than it adds.

---

### Decision B — Consent Mode v2 / consent banner

Two sub-options for the consent UI and signal wiring.

---

#### Option B1: ngx-cookieconsent (Angular-native library, no SaaS)

Install `ngx-cookieconsent` (v8.0.0, supports Angular 19+, MIT license). Configure it to match LGPD requirements: opt-in mode, denied by default. On the user's accept callback, call `gtag('consent', 'update', { analytics_storage: 'granted' })`.

Angular provider registration:

```typescript
// app.module.ts additions
import { NgcCookieConsentModule, NgcCookieConsentConfig } from 'ngx-cookieconsent';

const cookieConfig: NgcCookieConsentConfig = {
  cookie: { domain: window.location.hostname },
  position: 'bottom',
  theme: 'classic',
  palette: { popup: { background: '#1F4B7B' }, button: { background: '#f1d600' } },
  type: 'opt-in',    // LGPD requires opt-in (not opt-out)
  content: {
    message: 'Usamos cookies para análise de uso da plataforma.',
    deny: 'Recusar',
    allow: 'Aceitar',
    link: 'Saiba mais',
    href: '/politica-de-privacidade',
  }
};
```

The consent update call is added in the `statusChange$` subscription in `AppComponent` or in `AnalyticsService`:

```typescript
// on status === 'allow':
this.analyticsService.grantConsent();
```

See: `aux_web_research_2.md` § Source 4 for library details.

**Pros:**
- No SaaS dependency, no per-domain cost, no external service
- Angular-native, v19-compatible, translatable via ngx-translate (already in the project)
- Consent logic fully in-code — version-controlled, auditable, customizable per client if needed
- One npm dependency vs an external script tag

**Cons:**
- No built-in Consent Mode v2 bridge — engineer must write the `gtag('consent', 'update', ...)` call manually in the status callback (not hard, but not automated)
- No LGPD-specific template out of the box — engineer writes the Portuguese copy
- Banner UI customization is limited to the Osano Cookie Consent widget's theme options
- If banner logic needs to vary per client (e.g., some clients have non-Brazilian users), parameterization must be added by the engineer

**Cost/effort:** ~2–3 hours (install, configure, wire consent update to `AnalyticsService`)
**Risk:** Low; well-maintained library (v8 released for Angular 19)

---

#### Option B2: Custom consent banner component

Build a small Angular standalone component that renders a bottom bar with "Aceitar / Recusar" buttons. On accept, persist the choice to `localStorage` and call `gtag('consent', 'update', { analytics_storage: 'granted' })`. `AnalyticsService.initialize()` reads the stored choice on app start to restore consent state.

**Pros:**
- Zero new npm dependencies
- Full control over UX, copy, and per-client customization
- Can easily add per-client opt-out URL pointing to a per-client privacy policy page

**Cons:**
- More code to write and maintain (banner component, consent state persistence in localStorage, initialization logic reading stored state)
- Consent persistence across sessions must be handled manually (localStorage key, expiry if needed)
- Risk of subtle timing bugs (e.g., reading localStorage before gtag is initialized)

**Cost/effort:** ~4–6 hours
**Risk:** Medium (custom persistence logic is a common source of consent-timing bugs)

---

#### Option B3: Third-party CMP (CookieHub, Cookiebot, OneTrust)

Integrate a certified Google CMP partner via their embed script. The CMP handles the banner UI, consent storage, and Consent Mode v2 signal delivery automatically.

Example: CookieHub. Per-site setup in CookieHub dashboard, then one `<script>` tag per site (or per `ANALYTICS_ID` if all sites share a container).

**Pros:**
- Built-in Consent Mode v2 integration — no manual `gtag('consent', ...)` calls needed
- LGPD-compliant templates available
- TCF v2.3 support (relevant if clients have EU users)
- Consent audit log available (useful for compliance reporting)

**Cons:**
- SaaS cost: ~$10–20/month per domain × 50 domains = $500–1000/month
- External JS dependency loaded at runtime — adds latency, introduces a third-party uptime dependency
- Each site requires setup in the CMP's dashboard — operational overhead for 50 domains
- Consent configuration lives outside the version-controlled codebase

See: `aux_web_research_2.md` § Source 5 for CookieHub details.

**Cost/effort:** ~2 hours of dev integration + ongoing SaaS cost
**Risk:** Low for compliance; medium for operational dependency on an external SaaS

---

### Decision C — Event taxonomy

What explicit events to send beyond the auto-collected ones (session_start, first_visit, page_view via enhanced measurement, scroll, outbound clicks).

---

#### Option C1: Minimal — login + page_path fix only

Fix the `page_path` tracking (Bug 2), send the `login` recommended event on authentication, send `null` on logout.

Events sent:
- Auto-collected: `page_view`, `session_start`, `first_visit`, `scroll`, `outbound_click` (via GA4 enhanced measurement)
- Manual: `login` (with `user_id` set), explicit `page_path` via `gtag('config', ..., { page_path })` on NavigationEnd

**Pros:** Smallest implementation, lowest risk of instrumentation errors, covers the critical user-identification use case.
**Cons:** No visibility into feature-level engagement (which screens users navigate to, which features are used).

**Cost/effort:** Included in Decision A work (no additional events beyond `login`)
**Risk:** Lowest

---

#### Option C2: Standard B2B SaaS — login + page_path + logout + search

Add `logout` (custom event) and `search` (recommended event, already has a GA4 schema) if the app has an internal search feature.

Events sent (in addition to C1):
- `logout` (custom event, no predefined GA4 schema)
- `search` with `search_term` parameter (GA4 recommended event — unlocks Search Terms report)

**Pros:** Identifies when sessions end explicitly (useful for session duration analysis) and captures search behavior.
**Cons:** `logout` is a custom event with no dedicated GA4 report; it appears in raw event counts only unless a custom report is built.

**Cost/effort:** +1 hour above C1
**Risk:** Low

---

#### Option C3: Enhanced — C2 + key feature events

Add custom events for high-value feature interactions: report_viewed, export_triggered, goal_reviewed, dashboard_accessed. Parameters: `feature_name` (string), `client_id` (string from `env.COMPANY_ID` — already in env, not PII).

Note: `env.COMPANY_ID` is a configuration value assigned by 4Shark to identify the client company; it is not a user identifier and is not PII.

**Pros:** Enables feature usage analysis per client; supports product-led growth decisions.
**Cons:** Higher implementation and maintenance cost; event names and parameters must be agreed upfront; incorrect implementation risks sending PII (must audit every event parameter).

**Cost/effort:** +4–8 hours depending on number of events; requires product-level decision on what to track
**Risk:** Medium (PII hygiene audit required for every custom event parameter)

---

### Decision D — Electron build handling

The `electron:build` script (`ng build --configuration production --base-href ./dist.electron --output-path dist.electron`) does not use Netlify env vars. `env.ANALYTICS_ID` will be null or the sample placeholder.

Currently `main.ts` guards on `if (env.ANALYTICS_ID)` — if `ANALYTICS_ID` is null, no GA scripts are injected. This effectively disables analytics in the Electron build without any change.

Three options:

---

#### Option D1: Accept analytics-disabled in Electron (no change needed)

Leave the `if (env.ANALYTICS_ID)` guard in `main.ts`. The Electron build has `ANALYTICS_ID: null` (from the sample `.env.ts`), so analytics is silently disabled.

**Pros:** Zero additional work; the guard already does the right thing.
**Cons:** No analytics data from Electron users; if Electron usage is significant, this is a blind spot.

**Cost/effort:** Zero
**Risk:** Zero

---

#### Option D2: Provide a separate Electron GA4 property ID at build time

Set `ANALYTICS_ID` in the Electron build environment (e.g., via a `.env.electron` file that is not committed, or via the `electron:build` script reading a local env var). This would require a separate GA4 property in `google-analytics-manager` for Electron.

**Pros:** Electron usage is tracked in GA4.
**Cons:** Requires a separate GA4 property for Electron; LGPD consent handling for a desktop app is undefined territory (no browser-native consent storage pattern applies cleanly); build process for Electron must be updated.

**Cost/effort:** ~2 hours + property setup in `google-analytics-manager`
**Risk:** Medium (LGPD consent for desktop apps is not established in this codebase)

---

#### Option D3: Disable analytics in Electron via build configuration

Add an `electron` Angular build configuration that sets `ANALYTICS_ID` to a known sentinel value (e.g., `'ELECTRON'`) and guard against it explicitly. This makes the intent explicit rather than relying on null.

**Pros:** Explicit and readable; can be extended later to add Electron-specific tracking.
**Cons:** More configuration change than D1 for the same outcome (analytics disabled).

**Cost/effort:** ~1 hour
**Risk:** Low

---

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|---|---|---|---|
| A — Measurement ID delivery | A1 (fix token in src/gtag.js) / A2 (Angular service, delete src/gtag.js) | A1 is faster (30 min) but has Consent Mode ordering risk; A2 is cleaner, enables correct consent timing, removes the broken compiler step | □ |
| B — Consent banner / CMP | B1 (ngx-cookieconsent) / B2 (custom component) / B3 (SaaS CMP) | B1 is lowest-cost Angular-native; B2 gives full control with more code; B3 has ongoing SaaS cost but delivers built-in compliance features | □ |
| C — Event taxonomy | C1 (minimal: login + page_path) / C2 (+logout +search) / C3 (+feature events) | C1 is safe and sufficient for user-identification analytics; C3 requires product decisions on what to track and a PII audit of every parameter | □ |
| D — Electron | D1 (accept disabled, no change) / D2 (separate GA4 property) / D3 (explicit config guard) | D1 requires zero work; D2 adds tracking but LGPD consent for desktop is unsolved | □ |

---

## Execution order (for whichever options are chosen)

The order below is constraint-driven, not preference-based.

**If A2 + B1 or B2 are chosen (Angular service + any non-SaaS consent banner):**

1. Create `AnalyticsService` (contains `initialize()`, `setUser()`, `clearUser()`, `trackPageView()`, `grantConsent()`)
2. Add `gtag` global type declaration (one line in a `.d.ts` file or inline `declare let gtag`)
3. Wire `initialize()` into app startup (from `AppModule` providers factory or `AppComponent` constructor — pattern matches Rollbar registration in `app.module.ts` lines 283–284)
4. Wire `setUser()` into `AuthenticationService.login()` after line 39 (`setCredentials` call)
5. Wire `clearUser()` into `AuthenticationService.logout()` before line 68 (`navigateByUrl('/login')`)
6. Replace the broken `dataLayer.push` in `AppComponent` constructor (lines 40–48) with `analyticsService.trackPageView()`
7. Add consent banner (B1 or B2); wire banner's "accept" callback to `analyticsService.grantConsent()`
8. Remove `src/gtag.js` from all `angular.json` assets entries
9. Delete or no-op `gtag_compiler.js` (or remove the `analytics:compile` script from `package.json`)
10. Deploy and verify: confirm `gtag('consent', 'default', ...)` fires before `gtag('config', ...)` in browser DevTools Network tab

**If A1 is chosen (minimal token fix):**

1. Change `src/gtag.js` to use `GTAG_ID` token
2. Add `gtag('consent', 'default', { analytics_storage: 'denied', ... })` BEFORE the `gtag('config', 'GTAG_ID')` call in `src/gtag.js` — but note this fires in `window.onload`, after the library has already fired; this is a timing risk that A1 does not resolve
3. Add a separate `AnalyticsService` (simpler version — just `setUser`, `clearUser`, `trackPageView`, `grantConsent`)
4. Wire service into `AuthenticationService` and `AppComponent`
5. Add consent banner
6. Wire banner accept to `gtag('consent', 'update', ...)`

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| Consent Mode timing (A1 path): `gtag('consent', 'default', ...)` may fire after `gtag('js', ...)` in `window.onload` | GA4 collects data before consent is set; LGPD violation | Use A2 (Angular service) which fires consent default synchronously before any config call |
| PII in event parameters (C3) | GA4 ToS violation, property deletion without warning | Audit every custom event parameter before shipping; no email, CPF, name, phone anywhere |
| ngx-cookieconsent consent state not restored across sessions | On return visit, user sees banner again; consent setting is lost | Verify the library's localStorage persistence behavior on re-visit; add an explicit check in `AnalyticsService.initialize()` for stored consent |
| `angular.json` edit scope | 39 projects × 1 asset entry each — mechanical but error-prone if done by hand | A search-and-replace or jq transformation covers all 39 in one step |
| Electron LGPD consent undefined | If D2 is chosen, desktop analytics collection may lack valid consent | Do not enable Electron analytics (D1 or D3) until a consent mechanism for the desktop build is defined |
| `user.id` leakage | If `credentialsService.credentials.user.id` is a sequential integer, it may be combined with other signals to re-identify users | User-ID format `{GRAPHQL_API_SERVER}_{user.id}` was pre-decided; engineer should assess whether a hash is needed for production |

---

## Open questions for the engineer

1. **Decision A**: Fix the existing `src/gtag.js` + `gtag_compiler.js` (A1) or replace with an Angular service and delete the static file (A2)? Note: A2 is required for correct Consent Mode ordering.

2. **Decision B**: ngx-cookieconsent (B1), custom Angular component (B2), or a SaaS CMP like CookieHub (B3)? The cost split: B1 is ~$0 + 3h, B2 is ~$0 + 5h, B3 is ~$500/month + 2h.

3. **Decision C**: Minimal event set (C1) or add business-level events (C2/C3)? If C3, which feature interactions should generate events — and is there a product roadmap document that covers this?

4. **Decision D**: Accept analytics disabled in Electron (D1) or invest in Electron analytics (D2/D3)?

5. **User-ID opaque check**: Is `credentials.user.id` a sequential integer or a UUID? If sequential, should it be hashed (SHA-256) before sending to GA4 to reduce re-identification risk?

6. **Consent per-client parameterization**: Some clients may have non-Brazilian users who are subject to GDPR, not LGPD. Should the consent banner copy and opt-in/opt-out mode be parameterizable per client (via a new env var like `CONSENT_REGULATION=LGPD|GDPR`)? Or is LGPD sufficient for all current deployments?

7. **Privacy policy URL**: The consent banner (B1 or B2) needs a "learn more" link. Does each client have its own privacy policy URL, or is there a shared 4Shark privacy policy? If per-client, it needs a new Netlify env var.

---

## Sources

### Codebase (all verbatim — see `aux_codebase_bugs_1.md` for extended excerpts)

- `app-webclient/gtag_compiler.js:3` — `data.replace(/GTAG_ID/g, process.env.ANALYTICS_ID)` (wrong token)
- `app-webclient/src/gtag.js:6` — `gtag('config', 'xx-xxxxxxxxx-x')` (UA placeholder, never replaced)
- `app-webclient/src/main.ts:5-12` — correct GA4 library injection from `env.ANALYTICS_ID`
- `app-webclient/src/app/app.component.ts:45` — `dataLayer.push('config', env.ANALYTICS_ID, { page_path: ... })` (wrong API)
- `app-webclient/src/app/core/authentication/authentication.service.ts:39` — `credentialsService.setCredentials(response.body, ...)` (login hook)
- `app-webclient/src/app/core/authentication/authentication.service.ts:68-69` — `destroyCredentials()` (logout hook)
- `app-webclient/src/app/core/authentication/user-credential.model.ts:4` — `id: string` (internal user ID)
- `app-webclient/src/app/rollbar.ts:29,40-42` — InjectionToken + factory pattern for third-party service
- `app-webclient/src/app/app.module.ts:283-284` — Rollbar provider registration pattern
- `app-webclient/package.json:20` — `ngx-scripts env` var list including `ANALYTICS_ID`, `GRAPHQL_API_SERVER`
- `app-webclient/angular.json:29,152,...` — `src/gtag.js` asset entry repeated for all 39 projects
- `app-webclient/netlify.toml` — CSP already covers GA4 domains (no changes needed)

### Web references

- [GA4 User-ID implementation guide](https://developers.google.com/analytics/devguides/collection/ga4/user-id) — official gtag `set`/`config` commands for user_id, null-on-logout requirement
- [GA4 Consent Mode guide](https://developers.google.com/tag-platform/security/guides/consent) — `gtag('consent', 'default', ...)` and `gtag('consent', 'update', ...)` commands
- [GA4 recommended events](https://developers.google.com/analytics/devguides/collection/ga4/reference/events) — `login` event with `method` param; `search` event with `search_term` param
- [SPIKE.md Finding 3](~/.claude/plans/active/spike/ga4-config-best-practices/SPIKE.md) — LGPD requires affirmative consent; default denied; `secureprivacy.ai` timing quote
- [SPIKE.md Finding 2](~/.claude/plans/active/spike/ga4-config-best-practices/SPIKE.md) — PII prohibition, Google ToS, email/CPF/name/phone prohibited
- [ngx-cookieconsent](https://github.com/tinesoft/ngx-cookieconsent) — Angular v19-compatible consent library, MIT license
- [CookieHub Consent Mode v2](https://www.cookiehub.com/google-consent-mode-v2) — certified CMP, LGPD templates, SaaS pricing

### See auxiliary files

- `aux_codebase_bugs_1.md` — full code excerpts for all five findings, build pipeline details, authentication hook points
- `aux_web_research_2.md` — verbatim extracts from Google docs, ngx-cookieconsent, CookieHub, consent timing requirement
