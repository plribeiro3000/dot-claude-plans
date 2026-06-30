# PLAN — GA4 Front-End Instrumentation Rebuild (app-webclient)

> Reference: derived from PLAN-SPIKE.md; auxiliary files: aux_codebase_bugs_1.md, aux_web_research_2.md

## Status

**Phase 1 — LIVE in production (released 2026-06-28).** Shipped in `app-webclient` release `1.273.0` (PRs #6525, #6527 merged; deployed via Netlify). The LGPD cookie-consent banner (Consent Mode v2, default-denied) is **live** across the Brazilian fronts: the banner renders only where `PRIVACY_POLICY_URL` is set, which is the 16 BR Netlify sites (the "learn more" link requires a published Portuguese policy; non-BR fronts intentionally have no banner until their jurisdiction's policy exists). `AnalyticsService`, the page_path fix, user_id on login/logout, and the `login`/`logout` events all shipped in the same release.

Phase 2 (feature events) and Phase 3 (Electron) remain deferred per the gates below.

## Objective

Rebuild the Google Analytics 4 front-end instrumentation in `app-webclient` so that all 39 client Angular builds correctly track authenticated B2B SaaS usage. The current implementation has three confirmed bugs (measurement ID never injected into `src/gtag.js`, page_path tracking silently broken, and no Consent Mode) and two missing features (user_id never set, no consent banner). The rebuild consolidates all gtag configuration into a new Angular `AnalyticsService`, adds LGPD-compliant Consent Mode v2 (default-denied), sets the established `{slug}_{userId}` user_id on login/logout, and fixes the broken page_path tracking. Electron analytics and the full feature-level event taxonomy are deferred to later phases.

---

## Scope

### In scope — Phase 1 (implement now)

- Create `AnalyticsService` (`@Injectable({providedIn:'root'})`) consolidating all gtag configuration
- Wire Consent Mode v2 default (all signals denied) before any `gtag('config', ...)` call
- Fix page_path tracking bug (`app.component.ts:45`)
- Implement user_id set on login (`authentication.service.ts:39`), clear on logout (`authentication.service.ts:68-69`)
- Add consent banner via `ngx-cookieconsent` (B1); wire accept callback to `gtag('consent','update',{analytics_storage:'granted'})`
- Send `login` (GA4 recommended event) and `logout` (custom event)
- Add `emitEvent(eventName, params)` method stub on `AnalyticsService` (Phase 2 infrastructure)
- Delete `src/gtag.js` from all 39 `angular.json` asset entries and from the repository
- Delete `gtag_compiler.js` and remove the `analytics:compile` npm script from `package.json`

### Deferred — Phase 2 (feature events)

C3 feature-level event taxonomy: the `emitEvent` method is established in Phase 1's infrastructure, but the specific event list and the required PII audit of every event parameter are deferred pending the engineer-provided event list.

### Deferred — Phase 3 (Electron)

D2 — a separate GA4 property for the Electron desktop build, pending a defined LGPD consent mechanism for the desktop environment and creation of the dedicated property in `google-analytics-manager`. The existing `if (env.ANALYTICS_ID)` guard in `src/main.ts:35-45` silently disables analytics in Electron builds with no code change required.

### Out of scope (all phases)

- BigQuery export setup (data retention beyond 14 months — separate concern)
- GA4 property configuration in `google-analytics-manager` (separate repo, already in progress)
- Google Signals activation/deactivation (property-level setting, not front-end code)
- Per-client or per-region consent parameterization

---

## Chosen approach

**Direction:** A2 + B1 — new Angular `AnalyticsService` replacing the `src/gtag.js` / `gtag_compiler.js` static-file pipeline, with `ngx-cookieconsent` for the consent banner.

**Rationale (from engineer):** A2 is required because of the Consent Mode ordering constraint: `gtag('consent','default',...)` must fire before `gtag('js', new Date())` and before any `gtag('config', ...)` call. The old `window.onload` path in `src/gtag.js` fires after page load and cannot guarantee this ordering — making A1 non-compliant with LGPD. Moving config into an Angular service initialized from the bootstrap path guarantees the correct sequence. B1 is chosen as the Angular-native, MIT-licensed, zero-SaaS-cost option; the `gtag('consent','update',...)` call is wired manually in the accept callback.

**Source patterns referenced:**
- `src/app/rollbar.ts` + `src/app/app.module.ts:283-284` — `@Injectable` / factory registration pattern for singleton services
- `src/main.ts:35-45` — GA4 library injection (already correct; kept unchanged)
- Consent Mode ordering rule: `aux_web_research_2.md` § Source 7

---

## Technical decisions

| Decision | Choice | Rationale (from engineer) |
|---|---|---|
| Measurement ID delivery (A) | A2 — Angular `AnalyticsService`, delete `src/gtag.js` and `gtag_compiler.js` | Only path that guarantees `gtag('consent','default',...)` fires before `gtag('config',...)` — the Consent Mode ordering constraint is the deciding factor; A1 cannot satisfy it |
| Consent banner / CMP (B) | B1 — `ngx-cookieconsent` v8.0.0 (Angular 19+, MIT) | Zero SaaS cost, Angular-native DI integration, version-controlled configuration; engineer manually wires the `gtag('consent','update',...)` call in the accept callback |
| Consent regulation scope | Conservative opt-in (default-denied) for ALL fronts, no per-client parameterization | Covers LGPD + LATAM + GDPR uniformly across all current deployments |
| Phase 1 event taxonomy | `login` (GA4 recommended event) + `logout` (custom event) + page_path fix | Minimum viable user-identification and session boundary tracking; safe and immediately actionable |
| Phase 2 event taxonomy | Deferred — `emitEvent` method on `AnalyticsService` is ready; specific events pending engineer-provided list + PII audit per parameter | C3 feature events require a product decision and PII hygiene verification for every parameter before shipping |
| User-ID format | `{slug}_{userId}` where `slug = env.GRAPHQL_API_SERVER.split('.')[0]` and `userId = credentialsService.credentials.user.id` (`string`); sent raw, no hashing | Pre-established decision; `slug` is the first host label of `GRAPHQL_API_SERVER` (e.g. `shared001`, `atento001`, `demo001`, `beta001`), confirmed 1:1 with the backend across all fronts |
| User-ID PII boundary | NEVER send `email`, `first_name`, `last_name`, `company_id` — they live on the same `UserCredentials` object | Pre-established; GA4 ToS prohibition + LGPD data minimization |
| Electron (D) | D2 — separate GA4 property, deferred to Phase 3 | Blocked on: (1) defined LGPD consent mechanism for desktop; (2) property created in `google-analytics-manager` |
| Privacy policy URL | Single shared 4Shark URL for the banner's "learn more" link | Engineer provides the concrete URL at implementation time — open item |

---

## Execution phases

### Phase 1: Foundation

**Objective:** Fix all three bugs, add user_id tracking, add LGPD-compliant Consent Mode v2 with a consent banner, and deliver correct page tracking across all 39 Netlify fronts.

**Load-bearing ordering constraint:** `gtag('consent','default',{analytics_storage:'denied', ad_storage:'denied', ad_user_data:'denied', ad_personalization:'denied'})` MUST fire before `gtag('js', new Date())` and before any `gtag('config', ...)` call. This ordering is guaranteed by `AnalyticsService.initialize()` running synchronously in the Angular bootstrap path, and is the reason A1 was not chosen.

#### Components

**1. Create `AnalyticsService`**

New file: `src/app/core/analytics/analytics.service.ts`

Decoration: `@Injectable({providedIn:'root'})` — simpler than the InjectionToken/factory pattern used by Rollbar since no DI tree isolation is needed here.

Pattern reference: `src/app/rollbar.ts` (structure); `src/app/app.module.ts:283-284` (registration style).

Methods:

| Method | Behavior |
|---|---|
| `initialize()` | Guards on `if (!measurementId) return`. Sets consent default (all four signals denied) → calls `gtag('js', new Date())` → calls `gtag('config', measurementId)`. The consent default fires first — this is the ordering constraint. |
| `trackPageView(pagePath: string)` | Calls `gtag('config', measurementId, { page_path: pagePath })`. Guards on `if (!measurementId) return`. |
| `setUser(userId: string)` | Calls `gtag('set', { user_id: userId })`. |
| `clearUser()` | Calls `gtag('set', { user_id: null })`. |
| `grantConsent()` | Calls `gtag('consent', 'update', { analytics_storage: 'granted' })`. |
| `emitEvent(eventName: string, params?: object)` | Calls `gtag('event', eventName, params)`. Phase 2 infrastructure — method is present in Phase 1 but no feature events are wired until Phase 2. |

A `declare let gtag: Function` global declaration is required (one line in a `.d.ts` file or inline in the service file).

**2. Wire `initialize()` into app startup**

Register in `src/app/app.module.ts` providers using the factory/provider pattern at lines 283-284 (existing Rollbar registration pattern), or call from `AppComponent` constructor — whichever matches the codebase's convention at implementation time.

**3. Wire `setUser()` into login**

File: `src/app/core/authentication/authentication.service.ts:39`

After `this.credentialsService.setCredentials(response.body, formData.remember)`:

```typescript
const slug = env.GRAPHQL_API_SERVER.split('.')[0];
const userId = `${slug}_${this.credentialsService.credentials.user.id}`;
this.analyticsService.setUser(userId);
this.analyticsService.emitEvent('login', { method: 'password' });
```

User id path: `credentials.model.ts:18` (`user: UserCredentials`) → `user-credential.model.ts:17` (`id: string`).

**4. Wire `clearUser()` into logout**

File: `src/app/core/authentication/authentication.service.ts:68-69`

Before `destroyCredentials()` / the navigation call:

```typescript
this.analyticsService.emitEvent('logout');
this.analyticsService.clearUser();
// existing: this.credentialsService.destroyCredentials() / navigate to /login
```

**5. Fix page_path tracking**

File: `src/app/app.component.ts:45`

Replace the broken call:
```typescript
// REMOVE: (window as any).dataLayer.push('config', env.ANALYTICS_ID, { page_path: event.urlAfterRedirects });
// ADD:
this.analyticsService.trackPageView(event.urlAfterRedirects);
```

**6. Install `ngx-cookieconsent` and configure**

Install `ngx-cookieconsent` v8.0.0 (MIT). Configure with:
- `type: 'opt-in'` — LGPD requires affirmative consent; opt-out is not valid
- `cookie.domain: window.location.hostname`
- Portuguese copy for the banner text
- The "learn more" link points to the shared 4Shark privacy policy URL (engineer provides the concrete URL at implementation time — see Phase 1 open items)

**7. Wire consent banner accept callback**

Subscribe to `ngcCookieConsentService.statusChange$` in `AppComponent` or `AnalyticsService`. On `status === 'allow'`: call `this.analyticsService.grantConsent()`.

**8. Remove `src/gtag.js` asset entries from `angular.json`**

Delete the plain string asset entry `"src/gtag.js"` from every project's assets array across all 39 projects. The entry appears as a plain string (not an object-format block) at lines 29, 152, and equivalent positions in each project's `assets` array.

Note: the aux file's code excerpt showed an object-format `{ "glob": "**/*", "input": "src/gtag.js", "output": "/" }` — that quote was incorrect. The actual entries are plain strings per the engineer's verified wiring points.

**9. Delete `src/gtag.js`** from the repository.

**10. Delete `gtag_compiler.js`** and remove the `analytics:compile` script from `package.json`.

**11. Remove the local `/gtag.js` loader from `src/main.ts`**

`src/main.ts:35-45` has TWO script loaders inside the `if (env.ANALYTICS_ID)` guard:
- `scriptGtag` (lines 36-38) — loads the GA4 library from `www.googletagmanager.com/gtag/js?id=…`. **Keep this.**
- `scriptGtagConfig` (lines 40-41) — loads the LOCAL `/gtag.js` file (the `src/gtag.js` deleted in steps 8-9). **Remove this**, including its `document.body.insertBefore(scriptGtagConfig, …)` at line 43.

Without this step, deleting `src/gtag.js` (steps 8-9) causes a runtime **404 on `/gtag.js`** on every page load where `ANALYTICS_ID` is set. After removal, `main.ts` loads only the GA4 library; the consent/`js`/`config`/`page_path` calls that the old `/gtag.js` used to do are now owned by `AnalyticsService`. Keep the `if (env.ANALYTICS_ID)` guard (Phase 3 / Electron relies on it).

#### Dependencies

- `ngx-cookieconsent` v8.0.0 added to `package.json`
- `src/main.ts:35-45` — keep the GA4 library loader (`scriptGtag`) and the `if (env.ANALYTICS_ID)` guard; remove the local `/gtag.js` loader (`scriptGtagConfig`, lines 40-41 and 43) per Phase 1 step 11
- `netlify.toml` CSP — already covers all GA4 domains (`www.googletagmanager.com`, `www.google-analytics.com`, `analytics.google.com`, `stats.g.doubleclick.net`); no changes needed

#### Success criteria

- [ ] Browser DevTools confirms `gtag('consent','default',{analytics_storage:'denied',...})` fires before `gtag('js', new Date())` in the initialization sequence
- [ ] `src/gtag.js` is absent from the repository and from all 39 `angular.json` assets arrays (`grep -r '"src/gtag.js"' angular.json` returns empty)
- [ ] `gtag_compiler.js` is deleted; `analytics:compile` is absent from `package.json`
- [ ] `src/main.ts` no longer loads `/gtag.js` (the `scriptGtagConfig` lines removed); the Network tab shows NO 404 for `/gtag.js` on page load
- [ ] GA4 DebugView confirms `page_view` events carry the correct `page_path` value (NavigationEnd URL) on route change
- [ ] GA4 DebugView confirms `login` event fires after authentication with `user_id` set to `{slug}_{userId}` format
- [ ] GA4 DebugView confirms `logout` event fires and `user_id` is subsequently null in GA4 session
- [ ] Consent banner renders on first visit; accepting updates `analytics_storage` to `'granted'`; subsequent visits do not re-show the banner (ngx-cookieconsent localStorage persistence)
- [ ] `email`, `first_name`, `last_name`, `company_id` are absent from all GA4 event payloads (verify in DevTools Network tab → collect requests)
- [ ] Electron build remains analytics-disabled (no changes made; `if (env.ANALYTICS_ID)` guard in `src/main.ts:35-45` continues to handle it)

---

### Phase 2: Feature events (deferred)

**Objective:** Implement the C3 feature-level event taxonomy using `AnalyticsService.emitEvent()`.

**Pending before this phase begins:**
- Engineer-provided event list (event names, parameter names and types for each feature interaction)
- PII audit of every event parameter — no `email`, CPF, name, phone, or other LGPD-covered data may appear in any parameter; this audit must be completed and signed off before Phase 2 ships

**Infrastructure in place from Phase 1:** `AnalyticsService.emitEvent(eventName, params)` is already present. No architectural changes are required in Phase 2 — only event wiring at the feature level.

---

### Phase 3: Electron (deferred)

**Objective:** Implement D2 — track Electron desktop usage via a dedicated GA4 property.

**Pending before this phase begins:**
- A defined LGPD consent mechanism for the Electron desktop environment (no browser-native consent storage pattern applies cleanly to a desktop app)
- Creation of the dedicated Electron GA4 property in `google-analytics-manager`
- The resulting measurement ID for the Electron build environment

**Current state (no action needed):** Electron builds have `ANALYTICS_ID: null` (or the sample placeholder). `src/main.ts:35-45` guards on `if (env.ANALYTICS_ID)` — analytics is silently disabled with no code change required to maintain this state.

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Consent Mode ordering regression | If `gtag('consent','default',...)` fires after `gtag('js',...)`, GA4 collects data before consent is set — LGPD violation | A2 path (Angular service) guarantees correct ordering; verify in DevTools on first deploy before rolling out to production |
| `angular.json` removal is incomplete | One or more of the 39 projects retain the `src/gtag.js` asset entry; build may reference a deleted file | Automate removal with a targeted sed/jq pass across the full `angular.json`; post-removal verify with `grep -r '"src/gtag.js"' angular.json` |
| ngx-cookieconsent consent state not persisted across visits | User sees banner on every visit; perceived as broken | Verify localStorage persistence in a non-incognito browser session before signing off; check the library's built-in expiry behavior |
| PII in Phase 2 event parameters | GA4 ToS violation; Google can terminate the property without warning | Phase 2 requires a completed PII audit of every event parameter before any feature events are shipped — this is a Phase 2 gate |
| `credentials.user.id` availability at login hook | If `credentialsService.credentials.user.id` is not populated immediately after `setCredentials` at `authentication.service.ts:39`, `setUser` would send an undefined id | Confirm at Phase 1 implementation time that `credentialsService.credentials.user.id` is populated before calling `setUser` (see Phase 1 open items) |
| Electron LGPD consent undefined | If Phase 3 proceeds without a defined desktop consent mechanism, Electron users would have analytics collected without valid LGPD consent | Phase 3 must not begin until the consent mechanism is defined and documented — the deferred gate is load-bearing |

---

## Assumptions

- `src/main.ts:35-45` loads the GA4 library correctly (`scriptGtag`), but ALSO loads the local `/gtag.js` (`scriptGtagConfig`) — the latter must be removed in Phase 1 step 11 since `src/gtag.js` is deleted; otherwise a runtime 404 occurs. The `if (env.ANALYTICS_ID)` guard stays
- All 39 Netlify fronts have their own `ANALYTICS_ID` env var set in Netlify (established; managed in `google-analytics-manager`)
- `env.GRAPHQL_API_SERVER.split('.')[0]` produces a 1:1-with-backend slug across all fronts (engineer-confirmed; examples: `shared001`, `atento001`, `demo001`, `beta001`)
- `ngx-cookieconsent` v8.0.0 is compatible with the Angular version currently in use in the monorepo
- The `src/gtag.js` entries in `angular.json` are plain strings (not object-format blocks) — engineer-verified wiring point, correcting the aux file's object-format code excerpt
- `netlify.toml` CSP already covers all GA4 domains; no CSP changes are required (verified in `aux_codebase_bugs_1.md` § CSP section)
- Conservative opt-in (default-denied) is appropriate for all current deployments — no evidence of non-Brazilian clients requiring different consent handling
- The `analytics:compile` npm script is the only consumer of `gtag_compiler.js`; both can be removed together

---

## Phase 1 open items

These two items do not block the architecture but must be resolved at implementation time:

1. **Privacy policy URL** — RESOLVED: the banner's "learn more" link points to the current published version in the `4shark-legal` S3 bucket (sa-east-1):
   `https://4shark-legal.s3.sa-east-1.amazonaws.com/4shark_politica_de_privacidade_brasil_v2.pdf`
   The URL is **versioned by design** (v1/v2 are separate documents) — this is deliberate and keeps the per-version acceptance traceability the platform already has (the `pending_legal_documents_acceptance` re-acceptance flow). It should be wired as an env var (e.g. `PRIVACY_POLICY_URL`, like `ANALYTICS_ID`/`GRAPHQL_API_SERVER`) so the value can be updated per Netlify site without a code rebuild. See "Consent versioning & follow-up documentation" below.

2. **`credentials.user.id` availability at the login hook point** — confirm at implementation that `credentialsService.credentials.user.id` is populated immediately after `this.credentialsService.setCredentials(response.body, formData.remember)` at `authentication.service.ts:39`, before `setUser(...)` is called. Path: `credentials.model.ts:18` (`user: UserCredentials`) → `user-credential.model.ts:17` (`id: string`). If the id is not available at that call site, the hook placement must be adjusted.

---

## Consent versioning & follow-up documentation

**The versioned-policy model is intentional and stays as-is.** The published privacy policy lives as separate, versioned PDFs in `4shark-legal` (`..._v1.pdf`, `..._v2.pdf`, …). This is more rigorous than the common single-URL approach: it preserves which exact version each user accepted (the `pending_legal_documents_acceptance` re-acceptance flow re-collects consent when a new version is published). LGPD is satisfied by that flow — no "latest" alias, no backend remodeling, no change to this model.

**The one operational rule:** the banner's privacy-policy URL points to the *current* version. When the compliance team publishes a new version (`_v3`, …), update the `PRIVACY_POLICY_URL` env var on the Netlify sites to the new file. The re-acceptance flow handles re-collecting consent; the env var keeps the banner's "learn more" link pointing at the current document.

**Follow-up (end of this front, separate small PR to `dot-claude`):** document this whole consent mechanism — the GA4 Consent Mode v2 + cookie banner, the versioned policy in `4shark-legal`, and the operational rule above (update `PRIVACY_POLICY_URL` on each new policy version) — as a reference doc/runbook in `dot-claude`, so the next person touching this is reminded of the version-update step without rediscovering it.
