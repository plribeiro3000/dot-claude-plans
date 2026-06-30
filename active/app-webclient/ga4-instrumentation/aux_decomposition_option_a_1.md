# Decomposition Option A — Monolithic PR

## Single Task: ImplementAnalyticsFoundation

All 11 PLAN Phase 1 steps in one commit + PR.

### Task grouping

| PLAN Step | Task 1 | Description |
|-----------|--------|-------------|
| 1 | ✓ | Create AnalyticsService |
| 2 | ✓ | Wire initialize() into app startup |
| 3 | ✓ | Wire setUser() into login |
| 4 | ✓ | Wire clearUser() into logout |
| 5 | ✓ | Fix page_path tracking |
| 6 | ✓ | Install + configure ngx-cookieconsent |
| 7 | ✓ | Wire consent accept callback |
| 8 | ✓ | Remove asset entries from angular.json (all 39 projects) |
| 9 | ✓ | Delete src/gtag.js |
| 10 | ✓ | Delete gtag_compiler.js + remove script from package.json |
| 11 | ✓ | Remove /gtag.js loader from main.ts |

### PR structure

**Commit message:**
```
feat(analytics): GA4 front-end instrumentation rebuild (Phase 1)

- Create AnalyticsService with Consent Mode v2 default-denied
- Wire user_id tracking on login/logout
- Install and configure ngx-cookieconsent with LGPD opt-in
- Fix page_path tracking via NavigationEnd events
- Remove legacy gtag.js compilation pipeline
```

**Changed files:**
- `src/app/core/analytics/analytics.service.ts` (new, ~350 lines)
- `src/app/core/index.ts` (export AnalyticsService)
- `src/app/app.module.ts` (add provider, import NgxCookieConsentModule)
- `src/app/core/authentication/authentication.service.ts` (wire setUser/clearUser, emit events)
- `src/app/app.component.ts` (replace dataLayer.push, inject AnalyticsService)
- `src/main.ts` (remove scriptGtagConfig)
- `angular.json` (remove 39× "src/gtag.js" entries)
- `package.json` (add ngx-cookieconsent, remove analytics:compile script)
- `src/gtag.js` (deleted)
- `gtag_compiler.js` (deleted)

### Trade-offs

**Pros:**
- ✓ Single review gate
- ✓ Atomic consent + tracking delivery (no gap where consent is set but tracking 404s)
- ✓ Simple narrative and cleanup

**Cons:**
- ✗ Large diff (350+ new lines, 39-project angular.json edit, deletions)
- ✗ Wide review surface (consent logic, user-id format, page tracking, cleanup)
- ✗ One blocking comment delays everything
- ✗ If consent logic needs revision, entire PR must rebase

### Risk

- **Consent Mode ordering:** Must verify in DevTools that `gtag('consent','default',...)` fires before `gtag('js', ...)` and `gtag('config', ...)`
- **PII leakage:** Diff review must confirm no `email`, `first_name`, `last_name`, `company_id` in event payloads
- **angular.json removal:** 39 projects × 1 removal opportunity = high precision required (use grep verification afterward)
- **Runtime 404:** If main.ts cleanup is incomplete, `/gtag.js` 404 happens on every page load in production

### Mitigation

- Review AnalyticsService consent logic against GA4 Consent Mode v2 spec (PLAN.md aux_web_research_2.md Source 7)
- Pair grep verification with angular.json edit
- Pair main.ts deletions with src/gtag.js deletion (both shipped in same commit)
