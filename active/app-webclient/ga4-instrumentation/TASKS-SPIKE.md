# TASKS-SPIKE — GA4 Front-End Instrumentation (Phase 1: Foundation)

> Reference: PLAN.md (engineer-approved); input: app-webclient codebase analysis

---

## Decomposition options (multiple valid breakdowns exist)

The 11 Phase 1 steps cluster naturally into logical groups. Three options are presented below; the engineer chooses the decomposition that best fits their review/release strategy.

### Option A: Monolithic — single PR for all Phase 1 (11 steps in one task)

**Single task:** ImplementAnalyticsFoundation

**Grouping:** All 11 PLAN steps (service creation, user-id wiring, consent banner, cleanup) in one commit + PR.

**Pros:**
- Single review gate; all changes are reviewed together for internal consistency
- Guaranteed atomic delivery — consent banner and default-denied state ship together; no window where tracking happens without consent
- Simpler PR narrative: "GA4 instrumentation rebuild, Phase 1"

**Cons:**
- Large diff (~450 lines service + 20+ line modifications + 39-project angular.json edit + 3 file deletions)
- Review surface is wide (consent logic, user-id format, page tracking, package deps, cleanup)
- Risk: a single blocking comment on any subsection delays the entire Phase 1
- If consent logic needs revision, the whole PR must rebase

---

### Option B: Split 2-step (service + wiring vs cleanup)

**Task 1:** Create AnalyticsService + wire consent, user-id, page tracking  
**Task 2:** Cleanup (angular.json, gtag.js, main.ts, package.json)

**Grouping:**
- Task 1: Steps 1–7 (service creation, all wiring, consent banner)
- Task 2: Steps 8–11 (asset cleanup + file deletions)

**Pros:**
- Smaller first PR (~350 lines service + wiring); easier to reason about
- Task 2 (cleanup) is mechanical and can ship once Task 1 is merged — decouples the two concern domains
- If Task 1 needs revision, Task 2 is ready and can merge independently

**Cons:**
- Between Task 1 merge and Task 2 merge, users can consent but analytics does not fire yet (the `/gtag.js` 404 still blocks it). Window of "consent is set but tracking is 404ing". Small window, but observable in logs
- Two reviews instead of one; slightly more ceremony
- Task 2 must wait for Task 1 to merge, so critical path is Task 1 + Task 2 (not parallel)

---

### Option C: Split 5-step (service-first, then wire by concern, then cleanup)

**Task 1:** Create AnalyticsService (step 1 only)  
**Task 2:** Wire AnalyticsService initialization in app startup (step 2)  
**Task 3:** Wire user-id tracking (steps 3–4: login/logout)  
**Task 4:** Add consent banner + page tracking fix (steps 5–7)  
**Task 5:** Cleanup (steps 8–11)

**Grouping:** One step per task, except cleanup is combined (cleanup is atomic).

**Pros:**
- Finest grain of review; each task has a single clear purpose
- Can parallelize reviews (Task 2, 3, 4 can review in parallel once Task 1 ships)
- Safest for incremental testing: Task 1 ships service, Task 2 proves initialization, Task 3 proves user-id, Task 4 proves consent, Task 5 proves cleanup

**Cons:**
- 5 PRs = 5 review cycles, more overhead for the engineer
- Long critical path: each task blocks the next (Task 1 → Task 2 → Task 3 → Task 4 → Task 5)
- Gaps between merges: after Task 1, analytics is initialized but does nothing; after Task 2, consent and user-id not yet wired; after Task 3, consent not yet in UI; etc. — each merge leaves incomplete instrumentation
- Higher risk of conflicts if other branches touch authentication.service.ts or app.component.ts

---

## Recommended option (engineer decides)

**The engineer chooses based on:**
- **Risk tolerance:** Option A is riskiest (large diff) but fastest; Option C is safest but slowest
- **Review bandwidth:** Option A (1 PR) vs Option C (5 PRs)
- **LGPD compliance window:** Options B and C leave time windows where consent default is set but tracking is offline (small, but observable). Option A ships consent + tracking together atomically

**Suggested trade-off:** Option B (2-step) balances review surface with completeness — Task 1 is ~300 lines of focused change (service, wiring, consent), Task 2 is mechanical and low-risk (cleanup). Tasks ship ~2–4 hours apart (time for review/merge/deploy).

---

## Tasks (assuming Option B — engineer will confirm at review)

### Task 1: Create AnalyticsService and wire initialization, user tracking, and consent banner

**Phase (from PLAN.md):** Phase 1, steps 1–7

**Description:** 
Create `AnalyticsService` (`@Injectable({providedIn:'root'})`) with methods for consent default, page tracking, user ID management, and event emission. Wire `initialize()` into the app bootstrap path to guarantee Consent Mode v2 ordering (consent-default before gtag js/config). Wire `setUser()`/`clearUser()` into `authentication.service.ts` login/logout hooks. Replace broken dataLayer.push at `app.component.ts:45` with `trackPageView()`. Install `ngx-cookieconsent` and wire accept callback to `grantConsent()`.

**Deliverables:**
- New file: `src/app/core/analytics/analytics.service.ts` (~350 lines)
- Export from `src/app/core/index.ts`
- Modified: `src/app/app.module.ts` — add AnalyticsService provider (factory or `@Injectable`)
- Modified: `src/app/core/authentication/authentication.service.ts` — inject AnalyticsService, wire `setUser()` at line 39, wire `emitEvent('login')`, wire `clearUser()`/`emitEvent('logout')` at line 68
- Modified: `src/app/app.component.ts` — inject AnalyticsService, replace line 45 dataLayer.push with `trackPageView()`
- Modified: `package.json` — add `ngx-cookieconsent` v8.0.0
- Modified: `src/app/app.module.ts` — import `NgxCookieConsentModule`
- Modified: `AppComponent` or `AnalyticsService` — subscribe to `statusChange$` and wire accept callback

**Dependencies:** None (Task 1 is foundational)

**Acceptance criteria:**
- [ ] `AnalyticsService` exists at `src/app/core/analytics/analytics.service.ts` with all six methods (`initialize`, `trackPageView`, `setUser`, `clearUser`, `grantConsent`, `emitEvent`)
- [ ] `initialize()` calls `gtag('consent', 'default', {...all_denied...})` BEFORE `gtag('js', ...)` and `gtag('config', ...)` — verify in DevTools console on first page load
- [ ] `setUser()` sends user_id in format `{slug}_{userId}` (slug from `env.GRAPHQL_API_SERVER.split('.')[0]`)
- [ ] `clearUser()` sets user_id to null in gtag
- [ ] `grantConsent()` calls `gtag('consent', 'update', {analytics_storage:'granted'})`
- [ ] `emitEvent(eventName, params)` calls `gtag('event', eventName, params)`
- [ ] Login flow: `authentication.service.ts:39` calls `setUser()` + `emitEvent('login')` after `setCredentials()`; GA4 DebugView shows `login` event with correct user_id
- [ ] Logout flow: `authentication.service.ts:68` calls `emitEvent('logout')` + `clearUser()` before `destroyCredentials()`; GA4 DebugView shows `logout` event and user_id becomes null
- [ ] App startup: `initialize()` is called from app bootstrap (app.module.ts provider factory, verified by DevTools Network showing gtag js/config calls in order)
- [ ] Page tracking: route changes trigger `trackPageView(event.urlAfterRedirects)` in `app.component.ts`; GA4 DebugView shows `page_view` events with correct `page_path` values
- [ ] Consent banner renders on first visit (ngx-cookieconsent in opt-in mode, PT copy visible)
- [ ] Accepting banner calls `grantConsent()` → GA4 DevTools shows `gtag('consent', 'update', {analytics_storage:'granted'})`
- [ ] Banner state persisted: second visit does not re-show banner (localStorage check)
- [ ] No PII fields (`email`, `first_name`, `last_name`, `company_id`) appear in any gtag payload (DevTools Network inspect)

**Pattern reference:** 
- `src/app/rollbar.ts:40-42` — factory function pattern for injectable singleton
- `src/app/app.module.ts:283-284` — provider registration pattern (ErrorHandler + RollbarService)
- `src/main.ts:35-45` — gtag library injection (scriptGtag loader, `if (env.ANALYTICS_ID)` guard)

**Open questions:**
1. **Privacy policy URL** — the "learn more" link in ngx-cookieconsent banner must point to a real URL. Engineer provides the shared 4Shark privacy policy URL before finalizing banner config.
2. **`credentials.user.id` availability** — confirm at implementation that `credentialsService.credentials.user.id` is populated immediately after `this.credentialsService.setCredentials(response.body, formData.remember)` at `authentication.service.ts:39`, before `setUser(...)` is called. If not available at that hook, adjust hook placement or async timing.

---

### Task 2: Cleanup gtag.js, angular.json assets, and main.ts loader

**Phase (from PLAN.md):** Phase 1, steps 8–11

**Description:**
Remove the legacy gtag.js compilation pipeline and ensure no runtime 404s on the now-deleted `/gtag.js` file. Delete `src/gtag.js` and `gtag_compiler.js` from the repository. Remove the `"src/gtag.js"` plain-string asset entry from all 39 projects' `angular.json` assets arrays. Remove the local `/gtag.js` script loader (`scriptGtagConfig`, lines 40–41 and line 43 insertBefore) from `src/main.ts`, keeping the GA4 library loader (`scriptGtag`, lines 36–38) and the `if (env.ANALYTICS_ID)` guard.

**Dependencies:** Task 1 must be merged first (consent + tracking are now owned by AnalyticsService, not the deleted `/gtag.js`). This task cannot ship before Task 1 is live in production.

**Deliverables:**
- Deleted: `src/gtag.js`
- Deleted: `gtag_compiler.js`
- Deleted from `package.json`: the `"analytics:compile"` npm script entry
- Modified: `angular.json` — remove 39 instances of `"src/gtag.js"` from assets arrays
- Modified: `src/main.ts` — remove lines 40–41 (scriptGtagConfig creation) and line 43 (insertBefore call); keep scriptGtag and the `if (env.ANALYTICS_ID)` guard intact

**Acceptance criteria:**
- [ ] `src/gtag.js` does not exist in the repository
- [ ] `gtag_compiler.js` does not exist in the repository
- [ ] `package.json` does not contain `"analytics:compile"` script
- [ ] `grep -r '"src/gtag.js"' angular.json` returns empty (all 39 entries removed)
- [ ] `src/main.ts` lines 40–41 and 43 removed; scriptGtag loader (lines 36–38) remains; `if (env.ANALYTICS_ID)` guard remains
- [ ] Build succeeds for all 39 projects: `npm run build` or equivalent CI command
- [ ] Network tab on first page load shows NO 404 for `/gtag.js` (Electron builds with `ANALYTICS_ID=null` also show no gtag calls, as expected)
- [ ] GA4 DebugView continues to show page_view, login, logout, and consent events (AnalyticsService is now the source; `/gtag.js` load was the old source)

**Pattern reference:**
- `scripts/validate-bash-command.sh` pattern for angular.json edits: a targeted sed/jq pass is recommended to avoid manual error across 39 projects. Example command (for the engineer's review, not auto-executed):
  ```bash
  # Pseudo-command — engineer adjusts for their environment
  # Find all angular.json files, locate "src/gtag.js" in each assets array, remove it
  # Verify: grep -r '"src/gtag.js"' angular.json (should be empty)
  ```

**Risk (from PLAN.md):** If removal is incomplete, one or more projects retain the asset entry. Build may succeed but users will see a 404 on `/gtag.js` on every page load. Mitigation: post-removal verify with grep (see acceptance criteria).

---

## Cross-cutting concerns

### Testing strategy
- **Unit tests (AnalyticsService):** Verify that `initialize()` calls gtag in the correct order; `setUser()` formats user_id correctly; `trackPageView()` passes page_path; `grantConsent()` updates consent state.
- **Integration tests (authentication flow):** Verify that login triggers `setUser()` + `login` event; logout triggers `clearUser()` + `logout` event.
- **E2E / Manual validation:** DevTools DevMode inspection in GA4 is the primary validation (DebugView shows events in real-time).

### Error handling
- `initialize()` guards on `if (!measurementId) return` — no gtag calls if ANALYTICS_ID is not set (Electron builds, local dev with no env).
- All gtag calls wrapped in try-catch or guarded to prevent uncaught errors if gtag is undefined.
- Consent banner accepts/rejects gracefully; no blocking errors if localStorage is unavailable.

### LGPD compliance (from PLAN.md)
- Consent default (all signals denied) fires BEFORE tracking begins.
- User must affirmatively accept before `analytics_storage` is set to `'granted'`.
- No PII fields sent in event parameters: `email`, `first_name`, `last_name`, `company_id` must not appear.
- Phase 2 gates on PII audit before any feature events ship.

### Observability
- Browser DevTools Console: verify gtag calls and consent state on first page load.
- DevTools Network tab: watch gtag/collect requests; filter by analytics.google.com.
- GA4 DebugView: real-time event stream (with measurement ID + debug token).
- Error logs in Rollbar: if gtag throws, errors are captured.

---

## Open decisions for the engineer

1. **Decomposition choice:** Which option (A, B, or C) best fits your review/release workflow?  
   - **Option A** (single PR, all 11 steps) — fastest, highest risk  
   - **Option B** (Task 1 + Task 2) — recommended, balanced  
   - **Option C** (5 tasks) — safest, slowest  

2. **angular.json cleanup approach (Task 2):**  
   - Manual removal across 39 projects (safe, auditable, tedious)  
   - Automated sed/jq script (fast, must verify with grep afterward)  
   - Custom Node script to parse/modify JSON (safest, takes development time)  

3. **Privacy policy URL (Task 1 open item):**  
   - What is the shared 4Shark privacy policy URL for the banner's "learn more" link?  

4. **`credentials.user.id` availability (Task 1 open item):**  
   - Confirm at implementation that `credentialsService.credentials.user.id` is populated immediately after line 39's `setCredentials()` call in `authentication.service.ts`.  

---

## Sources and pattern references

- **AnalyticsService structure:** `src/app/rollbar.ts:40-42` (factory pattern), `src/app/app.module.ts:283-284` (provider registration)
- **gtag library loader:** `src/main.ts:35-45` (existing correct GA4 library injection)
- **Page tracking hook:** `src/app/app.component.ts:40-48` (existing router subscription, currently broken at line 45)
- **Authentication wiring points:** `src/app/core/authentication/authentication.service.ts:39` (login), `68-69` (logout)
- **Consent Mode ordering rule:** PLAN.md § Execution phases, Phase 1; `aux_web_research_2.md` § Source 7 (Consent Mode v2 specification from Google)
