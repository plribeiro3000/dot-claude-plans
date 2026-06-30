# Auxiliary Files Index — TASKS-SPIKE Phase 1 Decomposition

This document lists all auxiliary files supporting `TASKS-SPIKE.md` and directs the engineer to the information they need.

---

## Files in this directory

### Main deliverable
- **`TASKS-SPIKE.md`** — primary decomposition document
  - 3 options (A, B, C) with trade-offs
  - Task 1 and Task 2 specifications (assuming Option B)
  - Cross-cutting concerns, open decisions, pattern references

### Auxiliary files (supporting materials)

| File | Content | Use when |
|------|---------|----------|
| `aux_decomposition_option_a_1.md` | Monolithic PR approach (all 11 steps in one commit) | Engineer is considering Option A (single PR, fastest) |
| `aux_decomposition_option_b_2.md` | 2-step approach (Task 1: service + wiring; Task 2: cleanup) | Engineer is considering Option B (recommended, balanced) |
| `aux_decomposition_option_c_3.md` | 5-step approach (incremental tasks, safest path) | Engineer is considering Option C (most conservative) |
| `aux_angular_json_cleanup_4.md` | Implementation notes for 39-project angular.json asset removal | Implementing the `"src/gtag.js"` string removal from all projects |

---

## How to use these files

### Engineer decision flow

1. **Start here:** Read `TASKS-SPIKE.md` § "Decomposition options" (top of doc)
   - Get a 1-minute overview of A, B, C

2. **Pick a direction:**
   - Option A (monolithic) → Read `aux_decomposition_option_a_1.md`
   - Option B (recommended) → Read `aux_decomposition_option_b_2.md`
   - Option C (incremental) → Read `aux_decomposition_option_c_3.md`

3. **If planning Task 2 cleanup:**
   - Read `aux_angular_json_cleanup_4.md` for implementation strategies

4. **Review full spec:** Back to `TASKS-SPIKE.md` § "Tasks" for complete acceptance criteria

---

## Key decision points

### 1. Decomposition choice (affects all tasks)

| Option | PR structure | Timeline | Risk | Review surface |
|--------|---|---|---|---|
| **A** (monolithic) | 1 PR, all 11 steps | ~4 hours total | Highest | Widest (consent + user-id + page tracking + cleanup) |
| **B** (2-step) | 2 PRs (service+wiring, cleanup) | ~4–6 hours (sequential) | Medium | Balanced (Task 1 is focused, Task 2 is mechanical) |
| **C** (5-step) | 5 PRs (incremental) | ~8–12 hours (sequential) | Lowest | Narrowest (each PR single-purpose) |

**Recommended:** Option B (balanced trade-off)

### 2. Angular.json cleanup approach (for Task 2 or Task 5)

| Approach | Speed | Safety | Audibility |
|----------|-------|--------|-----------|
| Manual removal | Slow | High | High (every change visible) |
| sed/awk script | Fast | Medium (requires grep verification) | Low (changes are bulk) |
| Node.js script | Medium | Highest | Low (bulk changes) |

**Recommended:** sed + grep verification (fast + safe + verification built-in)

### 3. Privacy policy URL (Task 1 open item)

**Action:** Engineer provides the shared 4Shark privacy policy URL before Task 1 implementation.

**Where used:** `ngx-cookieconsent` banner configuration (the "learn more" link).

### 4. `credentials.user.id` availability (Task 1 open item)

**Action:** Confirm at implementation that `credentialsService.credentials.user.id` is populated immediately after `setCredentials()` at `authentication.service.ts:39`.

**Where used:** `setUser()` hook placement in the login flow.

---

## Reference summary

### Codebase wiring points (from PLAN.md + codebase analysis)

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| Provider registration | `src/app/app.module.ts` | 283–284 | Pattern for AnalyticsService provider registration |
| Rollbar factory | `src/app/rollbar.ts` | 40–42 | Pattern for factory-based singleton service |
| GA4 library loader | `src/main.ts` | 36–38 | Keep this (scriptGtag) |
| GA4 config loader (DELETE) | `src/main.ts` | 40–41, 43 | Remove this (scriptGtagConfig) in Task 2 |
| Page tracking (broken) | `src/app/app.component.ts` | 40–48 | Fix line 45 in Task 1 |
| Login hook | `src/app/core/authentication/authentication.service.ts` | 39 | Wire setUser() + login event here |
| Logout hook | `src/app/core/authentication/authentication.service.ts` | 68–69 | Wire clearUser() + logout event here |
| Legacy gtag.js | `src/gtag.js` | — | Delete in Task 2 |
| Legacy gtag compiler | `gtag_compiler.js` | — | Delete in Task 2 |
| Angular.json assets | `angular.json` | (39 projects) | Remove "src/gtag.js" entries in Task 2 |

---

## Phase 1 scope reminder

This TASKS-SPIKE decomposes **Phase 1 (Foundation)** only.

- **Phase 2 (Feature events)** — deferred pending engineer-provided event list + PII audit
- **Phase 3 (Electron)** — deferred pending desktop consent mechanism + dedicated GA4 property

Phases 2 and 3 are not decomposed here; they are represented as blocked task groups in `TASKS-SPIKE.md` under "Phases 2 and 3 (deferred)."

---

## Success criteria summary

All options converge on the same end state:

- ✓ `AnalyticsService` created with all 6 methods
- ✓ Consent Mode v2 default-denied fires before gtag js/config
- ✓ User-id set on login, cleared on logout (format: `{slug}_{userId}`)
- ✓ Page tracking fixed (NavigationEnd → trackPageView)
- ✓ Consent banner renders (ngx-cookieconsent opt-in)
- ✓ Legacy pipeline deleted (src/gtag.js, gtag_compiler.js, /gtag.js loader removed)
- ✓ No 404 on /gtag.js (main.ts scriptGtagConfig removed)
- ✓ No PII in GA4 payloads
- ✓ All 39 projects build successfully

The choice of A, B, or C affects **how** we get there (sequencing, review gates, deployment timeline), not **what** we deliver.

---

## Next steps

1. Engineer reviews `TASKS-SPIKE.md` and this index
2. Engineer chooses Option A, B, or C
3. Engineer decides on angular.json cleanup approach (if applicable)
4. Engineer provides privacy policy URL
5. Engineer confirms credentials.user.id availability
6. I (task-researcher) provide additional context or clarifications as needed
7. Main spawns `@agent-task-composer` with the engineer's chosen option
8. `@agent-task-composer` writes canonical `TASKS.md` from the validated draft + engineer's choice

---

## Questions for the engineer?

If any aspect of the decomposition is unclear, the engineer can ask for:
- More detail on a specific option's trade-offs
- Concrete PR size estimates for each option
- Timeline estimates including review waiting time
- Risk mitigation strategies for a specific option
