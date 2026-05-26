# STATEMENT OF WORK — Atento México Improvements

> **Input:** `KNOWLEDGE.md` (domain context), `ANALYSIS-v2.md` (decisions), `ANALYSIS.md` (technical analysis)
> **Client document:** See `PROPOSAL.md` for the client-facing version in Portuguese
> **Client document:** See `PROPOSAL.md` for the client-facing version in Portuguese

---

## Classification

| Group | Description | Charge Model |
|-------|-------------|--------------|
| **Quick Fixes** | Frontend-only or operational changes. Minimal effort, immediate delivery. | No charge |
| **Platform Improvements** | Benefits all clients. 4Shark would build eventually, but prioritizing due to Atento's request. | Charge for prioritization |
| **Client-Specific** | Only benefits Atento México. Custom development driven by their specific contract/workflow. | Full charge |
| **Training** | Knowledge transfer sessions, no development. | No charge |

---

## Group 0 — Keycloak Configuration (conditional, no development)

Available immediately if the client migrates to SSO. No development, no charge. Communicate the condition clearly.

### #18 — Access Audit / Session Monitoring

**What:** Atento México needs to audit employee access — who logged in, when, and how many times — to confirm employees had access to the platform when declarations were available. Used to address cases where employees claim they did not see a declaration.

**Approach:** Keycloak-native. Enable event logging in the `atento-mexico` realm, configure 90-day retention, create a read-only admin account restricted to that realm with `view-events` + `view-users` roles. Realm isolation is guaranteed by Keycloak's architecture — this user cannot see events from any other client's realm.

**What they get:**
- Full login/logout history per user with timestamps
- Login failure log (with IP)
- Session duration (calculable from LOGIN → LOGOUT via sessionId)
- Export via Keycloak Admin REST API (no UI export button in Keycloak console)

**Prerequisite:** Client must migrate to SSO as the only authentication channel. Direct login in the app bypasses Keycloak — those sessions are invisible to this feature. SSO migration also eliminates password reset requests as a side benefit.

**What this does NOT cover:** pages accessed within the app. Frontend instrumentation would be required for that — not in scope.

**Estimate:** ~2h (infrastructure configuration)
**Charge model:** No charge

---

## Group 1 — Quick Fixes

No client discussion needed. We do them and communicate what was done.

### A1 (#1) — Monthly Usage: Registration Date

**What:** Add user registration date column to Monthly Usage drill-down.
**Approach:** Frontend-only — `createdAt` already exposed by backend. Add to GraphQL query + new column in table.
**Estimate:** 3h
**Projects:** app-webclient

### A8 (#12) — Plan Summary in Partial Result

**What:** Display plan metadata (ID, Name, Type, Calendar, Group, Status, etc.) on the Partial result screen.
**Approach:** Frontend-only — expand GraphQL query to include all plan fields + add summary section replicating `plan-show` layout.
**Estimate:** 4h
**Projects:** app-webclient

### #15 — Compensation Report Permissions

**What:** Admins cannot generate automatic reports for compensations — feature exists but permissions were not enabled.
**Approach:** Operational fix — enable permissions for all Atento México admins in production.
**Estimate:** 1h
**Projects:** Production configuration

### #16 — Batch Reports Loading Bug

**What:** Batch compensation reports page doesn't load for the client.
**Approach:** Investigate and fix the page loading issue. Root cause unknown — needs investigation.
**Estimate:** 3h (investigation + fix)
**Projects:** app or app-webclient (TBD)

| Item | Hours |
|------|-------|
| A1 — Registration date | 3h |
| A8 — Plan summary | 4h |
| #15 — Permissions | 1h |
| #16 — Bug fix | 3h |
| **Group 1 Total** | **10h** |

---

## Group 2 — Platform Improvements

Features that benefit all clients. 4Shark would build these eventually — Atento's request accelerates priority. **Charge for prioritization**, not for the feature itself.

Ordered by suggested delivery priority (quick wins first, dependencies respected).

### A4 (#4) — Bulk User Update via Upload

**What:** Allow updating existing users via the same file upload used for creation. Currently, if a user already exists, the upload rejects the row. They need ~20 corrections/fortnight.
**Approach:** Modify `UserDocument::Processor` — detect existing users by unique identifier and update instead of rejecting. Creation behavior unchanged for new users. Password column ignored for existing users.
**Estimate:** 25h
**Projects:** app

### A2 (#2) — UserHistory Excel Export

**What:** Export all consolidated user history data to Excel. Currently, the UserHistory page shows data paginated (9 items per section) which is impractical for hundreds of records.
**Approach:** Add Excel export to existing UserHistory feature. New WorkBook with 8 sheets (Payments, Indicators, Transactions, Groups, Hierarchy, Goals, Plan Statements, Statements). Async generation following PaymentReport pattern.
**Estimate:** 35h
**Projects:** app, app-webclient

### A7+A9 (#9, #14) — Additional Columns in Partials and Compensations Listings

**What:** Add group name, collaborator count, and total amount to each row in both the Partials and Compensations listing screens. Currently these listings only show basic info (ID, Plan, Period, Status).
**Approach:** The data needed (hierarchy-aware collaborator count and total amount) does not exist today in the format required. A new backend data layer must be built first — Mongo aggregation pipeline with hierarchy-aware filtering (admin sees all, manager sees their team). Once the backend data layer is ready, adding the columns to each listing screen is straightforward.
**Estimate:** 50h
- Backend data layer (new Mongo aggregator, hierarchy filtering, indexes): 30h
- Partials listing (frontend columns + GraphQL query): 10h
- Compensations listing (reuses same backend, frontend columns + GraphQL query): 10h

**Projects:** app, app-webclient

### A5 (#6) — Bulk Import of Groups

**What:** Create and update groups in bulk via file upload. Currently groups must be created one by one through the UI.
**Approach:** The platform already has a Group model used for groupification (associating users to existing groups). We will update it to also support group creation and update via upload — find by external_id, update if exists, create if not. Same model, two capabilities, two screens.
**Estimate:** 40h
**Projects:** app, app-webclient

### A6 (#7) — Bulk Import of Plans

**What:** Create plans in bulk via file upload. Currently 130 plans/month are created manually.
**Approach:** New PlanDocument with multi-entity CSV (IncentiveDocument pattern — `#####` separators between plan blocks). All-or-nothing validation (two-pass: validate all, then create all). **Prerequisite:** add `external_id` to Incentive model — this affects 50,000+ existing incentives that currently have no external identifier. Strategy: generate default external_id for all existing records (based on internal ID), allow users to change at any time. Requires careful migration and testing to ensure nothing breaks.
**Estimate:** 160h
**Dependencies:** A5 must be delivered first (groups must exist before plans).
**Projects:** app, app-webclient

### A3 Strategy 1 (#3) — Indicator Validation Rules

**What:** Configurable validation rules per indicator variable. Catches invalid data at upload time before it propagates to calculation and payment. New resource with activation/deactivation lifecycle and full audit history.
**Approach:** New `ValidationRule` entity (belongs_to Variable) with `ValidationRulePeriod` for activation history. Rules can be activated/deactivated but never deleted — preserves audit trail. Enforced at all entry points: file upload, API, manual entry.
**Estimate:** 120h (includes 15h POC)
- **POC (15h):** Validate the technical approach — determine whether the system can support complex rules (using existing calculation engine) or should use a simpler min/max approach. The POC result defines the final scope.
- **Two possible outcomes:**
  - **Complex rules** (if POC succeeds): multiple rule types per variable, potentially leveraging existing calculation logic. 120h covers this scenario fully.
  - **Simple rules** (if POC shows complex is not viable): min/max per variable, simpler implementation. May take less time, but the 120h estimate guarantees delivery with quality regardless of which path we take.

**Projects:** app, app-webclient

| Item | Hours |
|------|-------|
| A4 — Bulk user update | 25h |
| A2 — UserHistory Excel export | 35h |
| A7+A9 — Listing columns (Partials + Compensations) | 50h |
| A5 — Bulk groups | 40h |
| A6 — Bulk plans | 160h |
| A3 S1 — Validation Rules (includes POC) | 120h |
| **Group 2 Total** | **430h** |

---

## Group 3 — Client-Specific

Features that only benefit Atento México. Custom development — **full charge**.

### Extra Field Encryption (prerequisite for Sábana)

**What:** Encrypt extra fields at rest on the database. Currently extra fields store key-value pairs per user without encryption, which prevents storing sensitive data (e.g., monthly salary — protected by LFPDPPP).
**Approach:** Encrypt value columns in 2 tables, migrate all existing data across all environments, adjust internal processes that handle these fields.
**Estimate:** 80h

### A3 Strategy 2 (#3) — Consolidated Report (Sábana)

**What:** Report per calendar consolidating ALL plans into a single table. One row per employee, dynamic columns (employee data + all indicators from all plans + calculation results per payment type + payment status). Required by Banco de México contract.
**Approach:** New CalendarReport model, cross-plan WorkBook with dynamic column generation, async batch processing (10,000 users × 130 plans cannot be real-time). This is a global audit of the platform — extracting data from across the entire system into a single Excel. It is an extremely heavy customization that will only be available for Atento México.

**Estimate:** 160h — scoped to information that already exists in the platform.

**Important caveats:**
- The 160h covers exporting data the platform already has. A column mapping study is needed to determine exactly which columns are available vs. which don't exist.
- If the client requires columns that don't exist in the system today (e.g., "centro", "login AC", "fecha de ingreso"), the scope and cost increase significantly — new data collection screens, new upload processes, potential LGPD implications. A new estimate would be provided for any additional columns.
- A3 Strategy 1 (Validation Rules) should be delivered first — prevents bad data from entering the report.

**STATUS: BLOCKED** — Column mapping must be validated with the client before final scope is confirmed.

**Preliminary column mapping:** A preliminary breakdown (Categoría A: data ForShark already has, Categoría B: via extra fields, Categoría C: out of scope) was included in `PROPOSAL.md` section 3.2 and shared with the client. Pending client validation.

**Dependencies:**
- Column mapping validation with client (preliminary mapping in `PROPOSAL.md` section 3.2)
- A3 Strategy 1 (Validation Rules) delivered first
- Extra field encryption delivered first (if client needs salary in the report)

| Item | Hours |
|------|-------|
| Extra field encryption | 80h |
| A3 S2 — Sábana report (existing data only) | 160h |
| **Group 3 Total** | **240h** |

---

## Group 4 — Training

No development involved. Schedule and deliver.

### #5 — Explain Identifications Functionality

Multi-identifier system, relevance for payroll integration.

### #17 — Explain 12 Unknown Modules

Calendar reports, Products, Clients, Transactional incentives, Classifications, Campaigns, Transactions, Collaborative transactions, Metrics, Classifications config, States, Recognition reasons.

**Recommendation:** Combine both into a single comprehensive training session. Include password reset bulk functionality demo. Consider inviting all Atento countries if content is shareable.

**Action:** Schedule date + confirm participants.

---

## Delivery Timeline

### Phase 1 — Quick Fixes (immediate)

No approval needed. Deliver and communicate.

| # | Item | Hours | Projects |
|---|------|-------|----------|
| 1 | #15 — Enable report permissions | 1h | Production |
| 2 | #16 — Fix batch reports bug | 3h | app / app-webclient |
| 3 | A1 — Registration date column | 3h | app-webclient |
| 4 | A8 — Plan summary in Partial | 4h | app-webclient |
| | **Subtotal** | **10h** | |

### Phase 2 — Platform Improvements (after client approves prioritization)

Delivery order considers: value delivered, technical dependencies, and progressive complexity.

| # | Item | Hours | Dependencies | Projects |
|---|------|-------|-------------|----------|
| 1 | A4 — Bulk user update | 25h | None | app |
| 2 | A2 — UserHistory Excel export | 35h | None | app, app-webclient |
| 3 | A7+A9 — Listing columns (Partials + Compensations) | 50h | None | app, app-webclient |
| 4 | A5 — Bulk groups | 40h | None | app, app-webclient |
| 5 | A6 — Bulk plans | 160h | A5 | app, app-webclient |
| 6 | A3 S1 — Validation Rules | 120h | None | app, app-webclient |
| | **Subtotal** | **430h** | | |

### Phase 3 — Client-Specific (after column mapping + client approval + payment)

| # | Item | Hours | Dependencies | Projects |
|---|------|-------|-------------|----------|
| 1 | Extra field encryption | 80h | None | app |
| 2 | A3 S2 — Sábana report | 160h | Column mapping, A3 S1, encryption | app, app-webclient |
| | **Subtotal** | **240h** | | |

### Training — Schedule independently

Combine #5 + #17 into one session. No dependency on development.

---

## Effort by Layer

| Layer | Items | Hours | % |
|-------|-------|-------|---|
| Quick fixes | A1, A8, #15, #16 | 10h | 2% |
| Medium features | A4 (25h), A2 (35h), A7+A9 (50h), A5 (40h) | 150h | 25% |
| Large features | A6 (160h), A3 S1 (120h) | 280h | 47% |
| Customization | Encryption (80h) + A3 S2 (160h) | 240h | 26% |
| **Total** | **12 items** | **680h** | **100%** |

---

## Grand Total

| Group | Items | Hours | Charge |
|-------|-------|-------|--------|
| Quick Fixes | 4 items | 10h | No charge |
| Platform Improvements | 6 items | 430h | Prioritization fee |
| Client-Specific | 2 items | 240h | Full charge |
| Training | 2 items | N/A | No charge |
| **Total** | **14 items** | **680h** | |

---

## Open Actions

1. **Column mapping study** — Two parts: (a) 4Shark side: inventory all data the platform can export for the sábana; (b) Client side: get the full list of ~120 columns from their spreadsheet. Schedule session with Atento México (Luis, Jessica) to cross-reference. Blocks A3 Strategy 2 final scope.
2. **Santiago** — Email Jessica about Atento Colombia decimal points request.
3. **Training session** — Schedule date + confirm participants for #5 + #17.
4. **Client proposal document** — See `PROPOSAL.md` for the client-facing version in Portuguese.
