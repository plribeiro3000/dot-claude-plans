# Decomposition Option C — 5-Step (Safest)

## Five Tasks: Incremental service development

Each concern gets its own task and PR; cleanup is combined.

### Task grouping

| PLAN Step | Task 1 | Task 2 | Task 3 | Task 4 | Task 5 | Description |
|-----------|--------|--------|--------|--------|--------|-------------|
| 1 | ✓ | | | | | Create AnalyticsService |
| 2 | | ✓ | | | | Wire initialize() into app startup |
| 3 | | | ✓ | | | Wire setUser() into login |
| 4 | | | ✓ | | | Wire clearUser() into logout |
| 5 | | | | ✓ | | Fix page_path tracking |
| 6 | | | | ✓ | | Install + configure ngx-cookieconsent |
| 7 | | | | ✓ | | Wire consent accept callback |
| 8 | | | | | ✓ | Remove asset entries from angular.json |
| 9 | | | | | ✓ | Delete src/gtag.js |
| 10 | | | | | ✓ | Delete gtag_compiler.js + remove script |
| 11 | | | | | ✓ | Remove /gtag.js loader from main.ts |

### Task 1: Create AnalyticsService

**Commit:** "feat(analytics): create AnalyticsService with Consent Mode v2"

**Changed files:**
- `src/app/core/analytics/analytics.service.ts` (new, ~350 lines)
- `src/app/core/index.ts` (export)

**Diff size:** ~350 lines added

**Acceptance:** Service methods exist; no initialization wiring yet.

---

### Task 2: Wire AnalyticsService initialization in app bootstrap

**Commit:** "feat(analytics): initialize AnalyticsService from app bootstrap"

**Changed files:**
- `src/app/app.module.ts` (add provider/factory)

**Diff size:** ~10 lines added

**Acceptance:** `initialize()` fires on app startup; DevTools shows gtag('consent','default',...) before gtag('js',...).

**Dependency:** Requires Task 1 ✓

---

### Task 3: Wire user-id tracking on login/logout

**Commit:** "feat(analytics): track user_id on login/logout events"

**Changed files:**
- `src/app/core/authentication/authentication.service.ts` (inject AnalyticsService, wire hooks at lines 39, 68)

**Diff size:** ~15 lines added

**Acceptance:** GA4 DebugView shows `login`/`logout` events with correct user_id format.

**Dependency:** Requires Task 2 ✓ (so AnalyticsService is initialized before login)

---

### Task 4: Wire page tracking and add consent banner

**Commit:** "feat(analytics): add page tracking and consent banner"

**Changed files:**
- `src/app/app.component.ts` (replace dataLayer.push at line 45, inject AnalyticsService)
- `package.json` (add ngx-cookieconsent)
- `src/app/app.module.ts` (import NgxCookieConsentModule, wire statusChange$ subscription)

**Diff size:** ~50 lines added/modified

**Acceptance:** 
- GA4 DebugView shows `page_view` events with correct `page_path`
- Consent banner renders
- Accepting updates analytics_storage to 'granted'

**Dependency:** Requires Task 3 ✓

---

### Task 5: Cleanup legacy gtag.js pipeline

**Commit:** "chore(analytics): remove legacy gtag.js pipeline"

**Changed files:**
- `angular.json` (remove 39× "src/gtag.js")
- `src/main.ts` (remove scriptGtagConfig)
- `package.json` (remove analytics:compile script)
- `src/gtag.js` (deleted)
- `gtag_compiler.js` (deleted)

**Diff size:** ~50 lines removed

**Acceptance:**
- Build succeeds
- No 404 on /gtag.js
- `grep -r '"src/gtag.js"' angular.json` returns empty

**Dependency:** Requires Task 4 ✓ (AnalyticsService owns all gtag config; old pipeline is no longer used)

---

### Sequencing and critical path

```
Task 1 (service)
  ↓
Task 2 (initialization)
  ↓
Task 3 (user-id tracking)
  ↓
Task 4 (page tracking + consent banner)
  ↓
Task 5 (cleanup)
```

**Critical path:** All tasks are sequential; each blocks the next.

**Timeline:** ~5 PRs × 1–2 hours each = ~5–10 hours total (2.5–5 hours of actual work + 2.5–5 hours of review + merge waiting).

### Trade-offs

**Pros:**
- ✓ Finest grain of review: each PR has a single, clear purpose
- ✓ Safest for incremental testing and debugging
- ✓ Can parallelize reviews once a task ships (Task 2 can be reviewed while Task 1 is being merged)
- ✓ Each task is easy to understand and explain
- ✓ Easiest to bisect/revert if something breaks

**Cons:**
- ✗ 5 PRs = 5 review cycles + 5 merges = high overhead for the engineer
- ✗ Long critical path: tasks are sequential; no parallelism
- ✗ Long wait-for-approval cycles between merges
- ✗ Between each task merge, instrumentation is incomplete:
  - After Task 1: service exists but does nothing (not initialized)
  - After Task 2: service initializes but no user-id (login hook not wired)
  - After Task 3: user-id wired but no page tracking or consent banner
  - After Task 4: consent banner exists but cleanup not done (404s on /gtag.js)
  - After Task 5: complete
- ✗ Higher risk of conflicts if other branches touch `authentication.service.ts` or `app.component.ts`

### Recommendation

Option C is recommended if:
- ✓ You have very limited review bandwidth (small diffs are easier to review)
- ✓ You want the safest possible path with maximum testability between steps
- ✓ You expect many revisions and want to minimize rebase overhead

Option C is **NOT** recommended if:
- ✗ You need the feature shipped quickly (critical path is longest)
- ✗ You want analytics to work end-to-end as soon as possible (each intermediate merge leaves gaps)
- ✗ Your team has limited merge/CI capacity (5 merges = 5 CI runs)
