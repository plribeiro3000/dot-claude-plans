# KNOWLEDGE — Atento México Improvements

## Background

This document consolidates the knowledge gathered from two phases:

1. **Phase 1 — Spike analysis** (completed 2026-01-27) — Initial analysis of 17 improvement requests from Atento México, based on two PowerPoint presentations. Original client text, screenshots, and PPT files are available as supporting files in this directory.
2. **Phase 2 — Clarification meeting** (2026-02-26) — Meeting with Atento México (Luis, Jessica) and 4Shark (Pablo, Santiago) to resolve all open questions from the phase 1 analysis.

**Supporting files:**
- `meeting-transcript-2026-02-26.md` — Full meeting transcript
- `meeting-summary-2026-02-26.md` — AI-generated meeting summary
- `Mejoras 4shark Atento México 1 de 2.pptx` — Original PPT with requests #1–#3
- `Mejoras 4shark Atento México 2 de 2.pptx` — Original PPT with requests #4–#17
- `images/` — Screenshots extracted from both PPTs
- `KNOWLEDGE.docx` — Original Word document from phase 1 analysis

---

## Phase 1 — Original Analysis Summary (2026-01-27)

Initial decisions before the clarification meeting. Several items had open questions pending client feedback.

| # | Request | Phase 1 Decision |
|---|---------|-----------------|
| 1 | Monthly Usage: add user registration date | ✅ Implement |
| 2 | Simplified report with payment types | ❓ Needs client feedback |
| 3 | Complete report (sabana) with payment types | ❓ Needs client feedback |
| 4 | Quick editing of employee data | ❓ Needs client feedback |
| 5 | Explain Identifications functionality | 🎓 Training |
| 6 | Bulk import of Groups | ✅ Implement |
| 7 | Bulk import of Plans | ❓ Needs client feedback |
| 8 | Calendar sorting in dropdown | ⚠️ Needs impact analysis |
| 9 | Additional columns in Partials listing | ✅ Implement |
| 10 | Batch creation of Partials + remove 24h lock | ❌ Will NOT implement |
| 11 | Automatic report generation for Partials | ❌ Will NOT implement |
| 12 | Plan summary in Partial result | ✅ Implement |
| 13 | Selective creation of Compensations + remove 24h lock | ❌ Will NOT implement |
| 14 | Additional columns in Compensations listing | ❓ Needs client feedback |
| 15 | Automatic report generation for Compensations | ✅ Enable (already exists) |
| 16 | Batch Compensation Reports limited functionality | ❓ Problem not clear |
| 17 | Explain 12 unknown modules | 🎓 Training |

**Phase 1 principle:** 4Shark is not a software house. Every request must be understood in terms of the real pain and the problem, not just what the client asks for as a solution.

---

## Detailed Knowledge per Request

### #1 — Monthly Usage: User Registration Date

**Decision:** Implement
**Spike conclusion confirmed in meeting.** Add a column with the user's registration date to the Monthly Usage drill-down screen.
**Complexity:** Low

---

### #2 — Simplified Report with Payment Types

**Decision:** Implement
**Questions resolved in meeting.**

**Pain:** When employees are promoted or transferred laterally, HR/management needs a summary of all compensations received over a specific period to determine salary expectations. Currently, this requires manually downloading history data, scrolling through excessive information, copying to Excel, and summing values. This is feasible for 10 employees but impractical for 1,000+ (e.g., bank audits).

**Requirements gathered:**
- **Purpose:** Summarize compensations paid per employee per payment type over a date range
- **Who generates it:** Administrators and managers
- **Data source:** Only finalized and approved payments (not pending awards or unapproved compensations)
- **Filters needed:** Date range (start/end), specific employees or full base
- **Format:** Single table, Excel export
- **Use cases:** Employee promotions, lateral transfers, salary benchmarking, audit responses

**Complexity:** Medium

---

### #3 — Complete Report (Sabana) with Payment Types

**Decision:** Implement — delivered as **two separate features** with different charge models (see ANALYSIS-v2.md for breakdown):
- **Strategy 1 — Validation Rules** (Platform Improvement, prioritization fee, delivered first)
- **Strategy 2 — Sábana Report** (Client-Specific, full charge, blocked pending column mapping session)

**Questions resolved in meeting, but implementation is complex.**

**Pain:** Atento México currently maintains a manual Excel spreadsheet ("TBL General" / "Sábana General") with ~120 homologated columns across their 130 compensation plans. This spreadsheet consolidates:
- Employee structure data (coordinator, manager, name, employee number, phone login, etc.)
- All operational indicators (quality score, number of calls, etc.)
- Bonus calculation results (bonus points, money conversion, bonus cap)

They use this for financial control and auditing:
- Verify no quality score exceeds 100%
- Verify bonus caps are being respected across all plans
- Cross-reference indicator data between operations and compensation areas
- Compare monthly payments to detect anomalies (e.g., 90% payment drop)

**Requirements gathered:**
- **Format:** Single unified table (one row per employee, all columns in one sheet)
- **Timing:** Available at any point in the process (not just after final payment) — for pre-payment validation
- **Status differentiation:** Needs a column indicating payment status: "paid approved" vs "not paid approved" (simplified — Luis confirmed two states is sufficient)
- **Columns:** Employee general data + all operational indicators + calculation results. Grows dynamically as new payment types and indicators are created.
- **Missing data:** Some columns in their current spreadsheet don't exist in ForShark (e.g., "centro", "login AC", "fecha de ingreso"). Options discussed: variables, department field mapping, or new development.
- **Scope:** Per calendar, across all plans (130 plans consolidated)

**Key insight from Pablo in meeting:** The real solution might not be just a spreadsheet export. Many of the validation needs (quality score ≤ 100%, bonus caps) could be solved with input validation rules/triggers on indicator upload, catching errors before they propagate to payment. The spreadsheet alone might be "too late" to fix problems (e.g., if compensation letter already sent).

**Open questions for internal planning:**
- Which columns can ForShark provide vs. which need new development?
- Should we implement input validation triggers as an alternative/complement to the report?
- Performance implications of consolidating ~10,000 employees × 120+ columns dynamically

**Complexity:** High

---

### #4 — Quick Editing of Employee Data (Bulk Update)

**Decision:** Implement
**Questions resolved in meeting — original spike misunderstood the request.**

**Pain:** NOT about the individual form being slow. The issue is needing to update ~20 employees per fortnight for minor corrections (typos in names, extra spaces, name changes due to legal reasons). Currently, the user upload only creates new users — if the user already exists, it rejects the record. They need the upload to also support updates.

**Requirements gathered:**
- **Scope:** Extend existing user upload to detect existing users and update them
- **Volume:** ~20 users per fortnight, occasionally more
- **Types of changes:** Name corrections, status changes (active/inactive), other demographic data
- **Password reset:** Already exists as a separate feature — needs training, not development
- **Future:** Integration with payroll system (book) will automate most user data updates

**Complexity:** Medium

---

### #5 — Explain Identifications Functionality

**Decision:** Training
User identifiers allow multiple IDs per user (book ID, ERP ID, CRM ID). The primary identifier is used across dashboards and exports. Critical for payroll integration. Training session to be scheduled.

---

### #6 — Bulk Import of Groups

**Decision:** Implement
**Spike conclusion confirmed.** Create new groups via file upload. Currently, GroupDocument only handles user-to-group association (Groupification), not group creation.

**Additional context from meeting:** Atento México creates new groups monthly (130 groups) to avoid group maintenance. They prefer creating fresh groups + fresh plans each month rather than updating existing group memberships. This makes bulk group creation essential for their workflow.

**Complexity:** Medium

---

### #7 — Bulk Import of Plans

**Decision:** Implement
**Questions resolved in meeting.**

**Pain:** Creating 130 plans monthly by hand is extremely time-consuming. Each plan requires selecting calendar, group, incentives (variables), and payment types. They currently copy-paste from control files, but the manual selection process is slow.

**Requirements gathered:**
- **Volume:** 130 plans per month
- **Layout fields:** Calendar, group, incentives (variables), payment types, approvers, portal URL, etc.
- **Error handling:** All-or-nothing — reject entire layout if any plan has errors (e.g., "error on line 51, please validate")
- **Incentive identification:** Must use incentive IDs (not names — names are too long and error-prone)
- **Payment type identification:** Can use external ID (payroll system ID)
- **Prerequisite:** Need an incentive audit/export feature so users can extract all incentive IDs and map them to names via VLOOKUP
- **IDs are unique:** Confirmed that incentive IDs are unique across all types (indicators, classifications, limiters, redemptions)

**Dependencies:**
- #6 (Bulk import of Groups) — Groups must exist before creating plans
- Incentive audit/export — Users need a way to get incentive IDs

**Complexity:** High

---

### #8 — Calendar Sorting in Dropdown

**Decision:** Will NOT implement
The current alphabetical sorting has been the platform standard for years and works for all other clients. Changing the dropdown order to accommodate one client's non-standard naming convention would break the UX for everyone else. The platform's UX must remain consistent across all clients.

---

### #9 — Additional Columns in Partials Listing

**Decision:** Implement (with caveats)
**Partially clarified in meeting.**

Three columns requested:
1. **Group name:** Simple — straightforward join
2. **Number of collaborators:** Dynamic per hierarchy (admin sees total, manager sees their team) — complexity is moderate
3. **Final amount (per line, per plan):** Dynamic per hierarchy, calculated at runtime — performance concern for large datasets

**Key clarifications from meeting:**
- The amount is per plan line (not page total) — Luis wants to compare each plan's calculated amount against his control file
- Atento México only uses this as admins (totalized), but other clients have supervisors/managers accessing, so hierarchy filtering must be respected
- Luis's workflow: generate partials → check amounts in listing → if amounts match expected values, proceed to compensation

**Performance risk:** Each line in the listing would require a hierarchy-aware calculation. With 130 plans displayed, this could be slow depending on the number of results per plan.

**Complexity:** Medium-High

---

### #10 — Batch Creation of Partials + Remove 24h Lock

**Decision:** Will NOT implement
**Confirmed in meeting.** The system already generates partials automatically every night. Partials are for monitoring (tracking day-by-day progress), not for final validation. For final validation and closing, users should use the compensation (award) workflow, which supports:
- Batch processing (already implemented for Atento)
- Reprocessing (update indicator → reprocess → validate again)
- Batch report generation

---

### #11 — Automatic Report Generation for Partials

**Decision:** Will NOT implement
**Confirmed in meeting.** Partials are for monitoring via dashboard. Reports are intentionally only available for compensations (awards), which represent the final/actionable data.

---

### #12 — Plan Summary in Partial Result

**Decision:** Implement
**Spike conclusion confirmed.** Display the plan metadata (ID, Name, Type, Description, Calendar, Group, Status, Goal, Participation, Shared Goal, Created at, Ended at, Updated at) on the Partial result screen.

**Complexity:** Low

---

### #13 — Selective Creation of Compensations + Remove 24h Lock

**Decision:** Will NOT implement
**Confirmed in meeting.** The lock exists for performance reasons (heavy processing). Selective plan processing creates usability problems. The batch compensation feature processes all plans intelligently: creates new ones, reprocesses pending ones, skips approved ones.

---

### #14 — Additional Columns in Compensations Listing

**Decision:** Implement
Same request as #9 but for the Compensations listing screen. Client clearly stated the 3 columns needed: group name, number of collaborators, and final generated amount. Same hierarchy-aware performance considerations as #9 apply.

**Complexity:** Medium-High

---

### #15 — Automatic Report Generation for Compensations

**Decision:** Operational fix — enable permissions
Feature already exists but permissions were not enabled for Atento México admins. Discussed during meeting, agreed to enable. Not done yet.
- Generates individual reports for each compensation plan in a calendar
- Reports available for 48 hours (security — files contain financial data)
- If report already exists and is within 48h, provides direct download link
- Processing and report generation are separated to optimize server performance

---

### #16 — Batch Compensation Reports Has Limited Functionality

**Decision:** Bug fix only — no improvement needed
**NOT properly discussed in meeting.** Luis could not access the page (loading issue). The original complaint about "limited functionality" was simply because he did not know how to use the feature since the page was not loading. Fix the loading bug and no further development is needed.

---

### #17 — Explain 12 Unknown Modules

**Decision:** Training
Comprehensive training session to cover all 12 modules. The initial training focused only on minimum necessary for project delivery. Complete training is ready — just need to schedule and confirm participants.

---

## Additional Items Discovered

### #18 — Access Audit (Session Monitoring)

**Decision:** Implement via Keycloak configuration — no development required. Conditional on SSO migration.

**Pain:** Atento México needs to audit whether employees accessed the platform and whether they saw their declarations (ciência). Employees occasionally claim they did not know about a declaration. The client needs evidence to confront this: who accessed, when, how many times, and whether a declaration was already available at that point.

**Requirements gathered:**
- Who logged in and when
- How many times per period
- Login failures
- Session duration
- No need to track individual pages (acknowledged as a separate complexity)

**Solution:** Keycloak's native event logging, fully configured per realm, with a dedicated read-only admin account.

**How it works:**
- Keycloak already has a built-in event system: `LOGIN`, `LOGOUT`, `LOGIN_ERROR` events with timestamp, userId, IP, sessionId
- Each Atento client already has its own isolated realm — events from `atento-mexico` are never visible from another realm, by design
- A read-only admin user is created inside the `atento-mexico` realm with two roles from `realm-management` client: `view-events` and `view-users`
- This user accesses the Keycloak Admin Console scoped to their realm only — cannot see other realms
- Retention is configured to 90 days (recommended) — configurable up to 365 days
- Export: Keycloak Admin Console has no export button. Events are exportable via Keycloak's Admin REST API using the read-only user's own token

**Prerequisite:** Direct login (username/password directly in the app) is not captured by Keycloak. This solution only works if the client migrates to SSO. Recommendation: make SSO the only authentication channel for Atento México — this eliminates password resets as a support burden as well.

**What Keycloak does NOT provide:** pages accessed within the app. Tracking which screens a user visited requires frontend instrumentation — out of scope for this item.

**Complexity:** Trivial (configuration only)
**Projects:** Keycloak (infrastructure configuration only)

---

### Atento Colombia — Decimal Points in Indicators
- **Request:** Display more decimal points in uploaded indicators to avoid rounding confusion
- **Status:** Registered, Santiago to formalize via email to Jessica
- **Scope:** Affects display/precision of indicator values across the platform

---

## Key Principles Reaffirmed

1. **4Shark is not a software house.** Every request must be understood in terms of the real pain/problem, not just the requested solution.
2. **SaaS impact.** Every development affects all clients. Changes must be evaluated for cross-client impact.
3. **Understand the pain, propose the solution.** The client describes the problem; 4Shark proposes the best solution for the product as a whole.
4. **Input validation over output verification.** Pablo's insight: many of the validation needs for #3 could be addressed earlier in the process (at indicator upload time) rather than only at report generation time.
