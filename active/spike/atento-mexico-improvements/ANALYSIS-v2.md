# ANALYSIS v2 — Atento México Improvements

> **Phase:** Analysis complete. All 17 requests triaged — decisions finalized.
> **Next step:** See `STATEMENT-OF-WORK.md` for delivery planning, `ANALYSIS.md` for technical details.

## Context

- **Client:** Atento México
- **Source:** 17 improvement requests analyzed in spike (2026-01-27), clarification meeting held (2026-02-26)
- **Reference:** `KNOWLEDGE.md` (this directory)
- **Impacted projects:** app (backend), app-webclient (frontend), potentially integrator
- **Scale:** Atento México operates 130 compensation plans monthly, ~10,000 employees

## Triage Summary

| Decision | Count | Items |
|----------|-------|-------|
| Implement | 9 | #1, #2, #3, #4, #6, #7, #9, #12, #14 — note: #3 delivers as two separate features (Strategy 1: Validation Rules + Strategy 2: Sábana Report), each with a different charge model |
| Will NOT implement | 4 | #8, #10, #11, #13 |
| Operational fix | 2 | #15 (permissions), #16 (bug) |
| Training | 2 | #5, #17 |
| Keycloak configuration (conditional) | 1 | #18 (access audit) — no development, conditional on SSO migration |

---

## Items Breakdown

### GROUP A — Will Implement

#### A1. Monthly Usage: User Registration Date (#1)

**Problem:** Admins cannot see when users registered on the platform from the Monthly Usage drill-down.

**Proposed approach:**
- Add `created_at` column to the Monthly Usage drill-down (second level) API response
- Add column to the frontend table

**Complexity:** Low
**Projects:** app, app-webclient

---

#### A2. Simplified Report — Payment Summary per Employee (#2)

**Problem:** When employees are promoted/transferred or during audits, HR needs a summary of all approved payments per employee over a date range. Today this requires manually downloading and consolidating data from multiple places.

**Proposed approach:**
- New report endpoint that aggregates approved payment data per employee, per payment type, over a configurable date range
- Filters: date range (start/end), employee selection (specific users or full base)
- Accessible by admins and managers (hierarchy-filtered)
- Excel export
- Data source: only finalized + approved payments

**Complexity:** Medium
**Projects:** app, app-webclient

---

#### A3. Complete Report (Sabana) — Consolidated Control Spreadsheet (#3)

**Problem:** Atento México manually maintains a 120-column Excel spreadsheet consolidating all operational indicators and bonus calculation results across 130 plans for financial control and auditing. They need this inside ForShark to validate data before approving payments.

**Proposed approach — two complementary strategies:**

**Strategy 1 — Input validation (preventive):**
- Add configurable validation rules to incentive definitions (e.g., min/max values, data type constraints)
- Validate indicator values at upload time (e.g., quality score cannot exceed 100%)
- Reject or flag invalid data before it reaches calculation
- This addresses the root cause: catching errors at entry rather than at report time

**Strategy 2 — Consolidated report (detective):**
- New report per calendar that consolidates all plans into a single table
- One row per employee, columns: employee general data + all indicators + calculation results per payment type
- Status column indicating payment state (paid approved / not paid approved)
- Available at any point in the process (from partial through to payment)
- Excel export
- Dynamically grows as new indicators/payment types are created

**Open questions to resolve before implementation:**
1. Column mapping: which of their ~120 columns can ForShark provide today vs. needs development?
2. Performance: consolidating ~10,000 employees × 120+ columns — batch processing or real-time?
3. Should Strategy 1 be delivered first (quick wins, prevents errors) before the full report?

**Complexity:** High
**Projects:** app, app-webclient
**Recommendation:** Deliver Strategy 1 (input validation) first as it has higher impact for lower effort, then plan Strategy 2 as a separate feature.

---

#### A4. Bulk User Update via Upload (#4)

**Problem:** User upload currently only supports creation. When a user already exists, the upload rejects the record. Atento México needs to correct ~20 users per fortnight (name typos, extra spaces, status changes) and must do it one by one.

**Proposed approach:**
- Extend the existing user upload (UserDocument) to support update mode
- If user already exists (matched by unique identifier), update their data instead of rejecting
- Maintain creation behavior for new users
- Password reset: already exists as a separate feature — include in training, not development

**Note:** Future payroll integration will automate most user data updates, but this manual upload improvement is needed in the interim.

**Complexity:** Medium
**Projects:** app, app-webclient

---

#### A5. Bulk Import of Groups (#6)

**Problem:** Atento México creates ~130 new groups monthly (one per plan) to avoid maintaining group membership. Currently, groups must be created one by one through the UI.

**Proposed approach:**
- New GroupDocument type for bulk group creation via file upload
- Layout fields: group name, description, and optionally initial member list
- Currently only GroupDocument for Groupification (user-to-group association) exists — need a new document type for group creation

**Complexity:** Medium
**Projects:** app, app-webclient

---

#### A6. Bulk Import of Plans (#7)

**Problem:** Creating 130 plans monthly by hand is extremely time-consuming. Each plan requires selecting calendar, group, incentives, and payment types manually.

**Proposed approach:**
- New PlanDocument type for bulk plan creation via file upload
- Layout fields: name, calendar (ID), group (ID), incentives (by ID), payment types (by external ID), approvers, description, etc.
- All-or-nothing validation: reject entire file if any row has errors, with detailed error messages (line number + error description)
- **Prerequisite:** Add `external_id` to Incentive model — users need to reference incentives without exposing 4Shark's internal calculation rules via export

**Dependencies:**
- A5 (Bulk Groups) should be delivered first — groups must exist before creating plans
- Incentive `external_id` must be available so users can map incentive names to IDs in their layouts

**Complexity:** High
**Projects:** app, app-webclient

---

#### A7. Additional Columns in Partials Listing (#9)

**Problem:** To validate partials, admins must open each plan individually to see the calculated amount. With 130 plans, this takes significant time.

**Proposed approach:**
- Add columns to the Partials listing: group name, number of collaborators, final generated amount
- Group name: simple join — no performance concern
- Collaborator count and final amount: dynamic per hierarchy (hierarchy-aware calculation at runtime)
- Performance analysis needed: with 130 plans and potentially large result sets, runtime calculation may cause timeouts

**Risk:** Performance impact on the listing page for clients with many plans or deep hierarchies.

**Complexity:** Medium-High
**Projects:** app, app-webclient

---

#### A8. Plan Summary in Partial Result (#12)

**Problem:** When viewing a partial result, users cannot see the plan's general configuration data without navigating away.

**Proposed approach:**
- Display plan metadata on the Partial result screen: ID, Name, Type, Description, Calendar, Group, Status, Goal, Participation, Shared Goal, Created at, Ended at, Updated at
- This data already exists — just needs to be included in the API response and displayed in the frontend

**Complexity:** Low
**Projects:** app, app-webclient

---

#### A9. Additional Columns in Compensations Listing (#14)

**Problem:** Same as A7 but for the Compensations listing. The listing only shows ID, Plan, Calendar, and Status. Admins need to see group name, number of collaborators, and final generated amount without opening each compensation individually.

**Proposed approach:**
- Add 3 columns to the Compensations listing: group name, number of collaborators, final generated amount
- Same hierarchy-aware dynamic calculation as A7 (Partials listing)
- Same performance considerations apply

**Complexity:** Medium-High
**Projects:** app, app-webclient

---

### GROUP B — Will NOT Implement

| # | Request | Reason |
|---|---------|--------|
| 8 | Calendar sorting in dropdown | Current alphabetical sorting is the platform standard for years. Changing it for one client's non-standard naming convention would break UX for all other clients. |
| 10 | Batch Partials + remove 24h lock | Partials are generated automatically every night. Use compensations for closing workflow. |
| 11 | Automatic reports for Partials | Partials are monitoring-only. Reports are for compensations. |
| 13 | Selective Compensations + remove 24h lock | Lock exists for performance. Batch processing already handles this intelligently. |

---

### GROUP B2 — Keycloak Configuration (conditional, no development)

#### #18 — Access Audit / Session Monitoring

**Problem:** Atento México needs evidence that employees accessed the platform and saw their declarations. Employees claim they did not know about a declaration. The client needs to audit: who logged in, when, how many times, and whether the declaration was already available at that moment.

**Decision:** Implement via Keycloak configuration — no development. Conditional on SSO migration.

**Approach:**
- Enable Keycloak event logging (`LOGIN`, `LOGOUT`, `LOGIN_ERROR`) in the `atento-mexico` realm
- Configure 90-day retention
- Create a read-only admin user in the realm with `view-events` + `view-users` roles (cannot see other realms, cannot modify anything)
- Export: available via Keycloak Admin REST API using the read-only user's token

**Prerequisite:** Client must migrate to SSO as the only authentication channel. Direct login in the app is not captured by Keycloak. Recommendation: SSO migration also eliminates password reset support burden.

**Limitation:** Pages accessed within the app are not tracked by Keycloak — this would require frontend instrumentation and is out of scope.

**Complexity:** Trivial (configuration only)
**Charge model:** No charge — pure infrastructure configuration

---

### GROUP C — Operational Fixes (permission + bug)

| # | Request | Action |
|---|---------|--------|
| 15 | Automatic report generation for Compensations | Enable permissions for all admins — feature exists but was not accessible. |
| 16 | Batch reports loading issue | Fix page loading bug — user could not access the feature at all. |

---

### GROUP D — Training

| # | Request | Action |
|---|---------|--------|
| 5 | Explain Identifications | Training session — explain multi-identifier system, relevance for payroll integration |
| 17 | Explain 12 unknown modules | Training session — cover all 12 modules listed in the original request |

**Recommendation:** Combine both into a single comprehensive training session. Include password reset bulk functionality demo. Consider inviting all Atento countries if content is shareable.

---

## Open Items

1. **Column mapping session** for #3 (Sabana) — define which columns ForShark can provide vs. needs development
2. **Santiago** to email Jessica about Atento Colombia decimal points request
3. **Schedule training session** for #5 and #17 — confirm participants and date
