# Decomposition Option B — 2-Step (Recommended)

## Task 1: Create AnalyticsService and wire consent, user-id, page tracking

Steps 1–7 (service creation and all application wiring)

### Task grouping

| PLAN Step | Task 1 | Task 2 | Description |
|-----------|--------|--------|-------------|
| 1 | ✓ | | Create AnalyticsService |
| 2 | ✓ | | Wire initialize() into app startup |
| 3 | ✓ | | Wire setUser() into login |
| 4 | ✓ | | Wire clearUser() into logout |
| 5 | ✓ | | Fix page_path tracking |
| 6 | ✓ | | Install + configure ngx-cookieconsent |
| 7 | ✓ | | Wire consent accept callback |
| 8 | | ✓ | Remove asset entries from angular.json (all 39 projects) |
| 9 | | ✓ | Delete src/gtag.js |
| 10 | | ✓ | Delete gtag_compiler.js + remove script from package.json |
| 11 | | ✓ | Remove /gtag.js loader from main.ts |

### Task 1: PR structure

**Commit message:**
```
feat(analytics): GA4 instrumentation service and wiring (Phase 1, part 1)

- Create AnalyticsService with Consent Mode v2 default-denied initialization
- Wire user_id tracking on login/logout (slug_userId format)
- Wire page_path tracking on route changes
- Install and configure ngx-cookieconsent (LGPD opt-in)
```

**Changed files:**
- `src/app/core/analytics/analytics.service.ts` (new, ~350 lines)
- `src/app/core/index.ts` (export AnalyticsService)
- `src/app/app.module.ts` (add provider, import NgxCookieConsentModule)
- `src/app/core/authentication/authentication.service.ts` (wire setUser/clearUser, emit events)
- `src/app/app.component.ts` (replace dataLayer.push, inject AnalyticsService)
- `package.json` (add ngx-cookieconsent v8.0.0)

**Diff size:** ~300 lines added/modified

---

## Task 2: Cleanup gtag.js, angular.json assets, and main.ts loader

Steps 8–11 (file deletions and asset cleanup)

### Task grouping (continued from above)

(see table above)

### Task 2: PR structure

**Commit message:**
```
chore(analytics): remove legacy gtag.js pipeline (Phase 1, part 2)

- Remove legacy src/gtag.js compilation pipeline (now handled by AnalyticsService)
- Remove "src/gtag.js" asset entries from all 39 projects in angular.json
- Remove local /gtag.js script loader from src/main.ts
- Remove analytics:compile npm script from package.json
```

**Changed files:**
- `angular.json` (remove 39× "src/gtag.js" entries)
- `src/main.ts` (remove scriptGtagConfig creation and insertBefore call, keep scriptGtag)
- `package.json` (remove analytics:compile script)
- `src/gtag.js` (deleted)
- `gtag_compiler.js` (deleted)

**Diff size:** ~50 lines removed

### Sequencing

**Critical dependency:** Task 2 **must not merge until Task 1 is live in production.**

Reason: Task 1 wires AnalyticsService to own all gtag configuration. Task 2 deletes the old `/gtag.js` and its main.ts loader. If Task 2 ships before Task 1 is live, the app loads main.ts, tries to fetch `/gtag.js`, gets 404, and analytics fails entirely for all users.

**Recommended deployment timeline:**
1. Task 1 PR review + merge to `develop` (~2–4 hours)
2. Deploy Task 1 to production (verify AnalyticsService initialization in GA4 DebugView)
3. Task 2 PR review + merge to `develop` (~1 hour)
4. Deploy Task 2 to production (verify no 404 on /gtag.js in Network tab)

### Trade-offs

**Pros:**
- ✓ Smaller first PR (Task 1: ~300 lines focused on service and wiring)
- ✓ Task 2 is mechanical and low-risk (cleanup once Task 1 is live)
- ✓ Task 2 can merge once Task 1 is in production (no need to wait)
- ✓ If Task 1 review needs revision, Task 2 is still ready to go

**Cons:**
- ✗ Between Task 1 merge and Task 2 merge: users can consent to analytics but tracking still 404s on `/gtag.js` (small window, ~1–4 hours)
  - Users see consent banner, click "Accept"
  - AnalyticsService logs `grantConsent()`, sets analytics_storage to 'granted'
  - But main.ts still tries to load `/gtag.js` (which no longer exists after Task 1 ships)
  - Result: Network 404; no events collected until Task 2 ships and the loader is removed
- ✗ Two PRs instead of one (more ceremony, but low overhead)
- ✗ Task 2 critical dependency on Task 1 merge (cannot ship Task 2 before Task 1 is live)

### Risk

**Task 1:**
- Consent Mode ordering must be verified in DevTools
- PII leakage review (no email/name/company_id)

**Task 2:**
- If angular.json removal is incomplete, users see 404 on `/gtag.js`
- Mitigation: verify with `grep -r '"src/gtag.js"' angular.json` after edit

### Recommendation

Option B is recommended because:
- Task 1 review surface is half the size of Option A (no cleanup)
- Task 2 is purely mechanical, low-risk cleanup that can ship once production is confirmed
- Decouples consent logic review from cleanup verification
- Critical path is Task 1 + Task 2, but they can be reviewed/merged back-to-back in ~2–4 hours total
