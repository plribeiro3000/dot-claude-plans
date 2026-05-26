# Improvement Proposal — Atento México

**Date:** February 27, 2026

---

## Summary

After detailed analysis of the 17 improvement requests and the alignment meeting held on February 26, 2026, the proposed action plan is presented below.

The requests were organized into four tracks:

- **Adjustments and no-cost deliveries** — immediate fixes and features available via configuration
- **7 platform improvements** — prioritized on the roadmap at Atento México's request
- **2 custom developments** — exclusive to Atento México
- **1 training session** — enabling clients on existing features

Additionally, 4 requests were evaluated and are already covered by existing platform features.

---

## 1. No-Cost Adjustments and Deliveries

### 1.1 — Immediate Fixes

Specific adjustments already incorporated into the next development sprint.

**Registration date on Monthly Usage** — the drill-down screen will start showing each employee's registration date on the platform.

**Plan summary on Partial result** — the partial result screen will start showing the associated plan's general data (name, type, calendar, group, status).

**Permissions for compensation reports** — permissions for automatic report generation will be enabled for every Atento México administrator.

**Fix for the batch reports page** — the loading issue on the batch compensation reports page will be fixed.

| Item | Hours |
|------|-------|
| Registration date on Monthly Usage | 3h |
| Plan summary on Partial result | 4h |
| Permissions for compensation reports | 1h |
| Fix for the batch reports page | 3h |
| **Total — Immediate Fixes** | **10h** |

**Timeline:** Next sprint
**Additional cost:** None

---

## 2. Platform Improvements

Platform features that will be developed at Atento México's request.

Delivery order considers the value delivered to the client and the technical dependencies between items.

### 2.1 — Access Control and Login History — 70h

**Problem:** Atento México needs to audit employee access to the platform — who logged in, when, how many times, and whether there were failed attempts. Employees occasionally claim they did not see a declaration; the company needs evidence to confront these situations.

**Solution:** Automatic logging of every access to the platform, regardless of the authentication method used (direct login or single sign-on). Each access records: employee, date and time, IP address, authentication method, identity provider (when applicable), and whether the access was successful.

The data is available for querying directly on the platform for 90 days, with filters by period, employee, authentication method, and outcome. After 90 days, records are automatically archived to long-term storage and remain available on request.

### 2.2 — Bulk employee update via upload — 25h

**Problem:** The employee import today only allows creating new records. When an employee already exists, the upload rejects the row. To correct the data of ~20 employees per fortnight (typos, status changes), it is necessary to edit one by one.

**Solution:** The employee upload will start detecting existing records and updating their data automatically, keeping the creation behavior for new employees.

### 2.3 — Employee History Export — 35h

**Problem:** The Employee History shows paginated data, making it impractical to inspect hundreds of records for audits, transfers, or promotions.

**Solution:** New Excel export with all consolidated information: payments, indicators, transactions, groups, hierarchy, goals, and statements.

### 2.4 — Additional information on Partial and Compensation listings — 50h

**Problem:** The partial and compensation listings show only basic information (ID, Plan, Period, Status). To validate the values of each plan, it is necessary to open each item individually — with 130 plans, this consumes significant time.

**Solution:** Add three pieces of information to both listings: group name, number of employees, and total generated value. Values respect the access hierarchy (administrator sees the total, manager sees only their team).

### 2.5 — Bulk Group import — 40h

**Problem:** Group creation is done one by one through the UI. With ~130 new groups per month, the manual process is unfeasible.

**Solution:** New bulk group import via file, allowing mass creation and updates. Existing groups will be identified and updated; new groups will be created automatically.

### 2.6 — Bulk Plan import — 160h

**Problem:** Creating 130 plans per month is done manually, picking calendar, group, incentives, and payment types one by one for each plan.

**Solution:** New plan import via file. The file allows defining every plan parameter (calendar, group, incentives, payment types, approvers). Full validation before creation — if any row has an error, the entire file is rejected with a detailed message indicating the error and the line number.

This feature requires a platform-preparation step: existing incentives need to receive an external identifier so they can be referenced in the import file. That preparation includes migrating existing records and extensive testing to guarantee no in-flight calculation is affected.

**Dependency:** Bulk group import (item 2.5) must be delivered first, since plans reference groups that need to exist on the platform.

### 2.7 — Validation Rules for Indicators — 120h

**Problem:** Incorrect data in indicators (e.g., quality above 100%, negative values) is only detected late — once the compensation has been calculated or, worse, after the compensation letter has been sent to the employee. Correcting at that point is costly and risky.

**Solution:** Validation rules configurable per incentive variable. Data is validated at entry into the system, preventing invalid values from propagating into calculations and payments. Validation happens on the way in, not on the way out — the system prevents the problem instead of allowing it to reach the payment.

The rules have their own lifecycle (activation and deactivation) with full history for auditing.

Includes an initial proof-of-concept period to validate the technical approach and define the level of rule complexity the system will support.

| Item | Hours |
|------|-------|
| Access Control and Login History | 70h |
| Bulk employee update via upload | 25h |
| Employee History Export | 35h |
| Additional information on listings | 50h |
| Bulk Group import | 40h |
| Bulk Plan import | 160h |
| Validation Rules for Indicators | 120h |
| **Total — Platform Improvements** | **500h** |

---

## 3. Customization

### 3.1 — Encryption of extra employee fields — 80h

Extra employee fields store data associated with each user (key-value), populated via upload. Today these fields have no encryption — which prevents storing sensitive data such as the monthly salary (protected by LFPDPPP).

This deliverable implements at-rest encryption on the extra fields, allowing Atento México to send sensitive data safely. The work includes: encrypting the value columns in 2 tables, migrating all existing data across every platform environment, and adjustments to internal processes that manipulate this data.

### 3.2 — Consolidated report per calendar (Sábana) — 160h

**Problem:** Atento México manually maintains an Excel spreadsheet ("TBL General") consolidating all operational indicators and bonus calculation results across the 130 plans (~120 columns). This spreadsheet is used for financial control and auditing with Banco de México.

**Solution:** Two deliverables:

A new report that consolidates all plans into a single table — one row per employee, with columns for employee data, extra fields (including salary), indicators, and calculation results per payment type. Available at any point in the process (not only after final payment), with payment-approval status flagged.

**Conditions:**

- We recommend the Validation Rules (item 2.7) be delivered before this report, to guarantee the quality of the exported data

#### Column mapping — what the report will contain

After analyzing Atento México's current spreadsheet and the alignment meeting on February 26, we did a preliminary column mapping. The ~120 columns of the TBL General split into three categories:

**Category A — Data 4Shark already has, the report delivers automatically:**

| Column | Source in 4Shark |
|--------|--------------------|
| Mes | Calendar / Period |
| Id Coordinador | Organizational hierarchy |
| Nombre Coordinador | Organizational hierarchy |
| Id Supervisor | Organizational hierarchy |
| Nombre Supervisor | Organizational hierarchy |
| Id Agente | Employee unique identifier |
| Nombre Agente | Employee record |
| Servicio Especifico | Group name |
| Puntos Bono | Calculation result (points) |
| Porcentaje Bono | Calculation result (aggregated indicator) |
| Bono Politica (tope) | Limiter result |
| Monto Final | Final monetary value of the compensation |
| Comisión | Monetary values per payment type |
| Operational indicators (Calidad, Adherencia, Hold, Casos, Resolución, Captura, Cumplimiento, etc.) | Aggregated indicators — as long as fed as variables on the platform |
| Payment status | "Pago aprobado" / "No pago aprobado" |

The report will include each employee's unique identifiers (ID, external_id, unique document), allowing cross-referencing with other systems via VLOOKUP.

**Category B — Data Atento México can include via extra employee fields:**

The platform supports associating extra fields (key-value) with each employee. These fields can be fed via upload and will be included in the report.

| Column | How to populate |
|--------|----------------|
| Centro | Extra employee field — feed via upload with the cost center code |
| Login/AC | Extra employee field — feed via upload with the phone-system ID |
| Fecha de Ingreso | Extra employee field — feed via upload with the hire date |
| Sueldo Mensual | Extra employee field (encrypted) — feed via upload with the monthly salary |

These columns depend on Atento México keeping the data up to date on the platform. The extra-fields feature already exists — no additional development for Centro, Login/AC, and Fecha de Ingreso. Secure storage of the monthly salary is enabled by deliverable 3.1 (extra-fields encryption).

**Category C — Data left out of the report:**

| Column | Reason |
|--------|--------|
| Observaciones | Free-text field of large length, incompatible with extra employee fields (limited to short values). **Recommendation:** complement via VLOOKUP in Excel after export, using the employee's unique identifier as the cross-reference key. |
| Aclaraciones | Same as Observaciones. |

#### Summary

The vast majority of the ~120 columns of the TBL General correspond to operational indicators that are already fed into the platform. The report will consolidate all this data automatically — including the monthly salary, which can be stored safely as an encrypted extra field. The two columns that stay out (observations and clarifications) can be complemented via VLOOKUP in Excel — the report will include all of the employee's unique identifiers to make that cross-reference easy.

If Atento México identifies additional columns that do not fit the categories above, the scope and estimate will be revised together.

| Item | Hours |
|------|-------|
| 3.1 — Encryption of extra employee fields | 80h |
| 3.2 — Consolidated Report (Sábana) | 160h |
| **Total — Customization** | **240h** |

---

## 4. Existing Features

The requests below were evaluated and are already covered by existing platform features:

| Request | Status |
|---------|--------|
| Bulk creation of partials and removal of the 24h lock | The system generates partials automatically every night with updated data. For closing and final validation, the batch compensation flow already covers this need. |
| Automatic report generation for partials | Partials are monitoring instruments via dashboard. Full reports are available in the compensation flow. |
| Selective creation of compensations and removal of the 24h lock | Batch processing already operates intelligently: creates new compensations, reprocesses pending ones, and preserves approved ones. The 24h interval exists to guarantee processing stability. |
| Calendar sorting by ID | Alphabetical sorting is the platform standard for every client. Changing it would impact every other client's experience. |

---

## 5. Training

Two training requests will be handled in a single session:

- **Identifications** — Multi-identifier system per employee and its relevance to payroll integration
- **Platform modules** — Performance reports, Products, Clients, Transactional incentives, Classifications, Campaigns, Transactions, Collaborative transactions, Metrics, Classification configurations, States, and Reasons for recognition

The session will include a demo of the bulk password reset feature.

**Additional cost:** None
**Next step:** Confirm date and participants

---

## Schedule

| Phase | Scope | Start |
|-------|-------|-------|
| **Phase 1** | Immediate fixes (section 1.1) | Next sprint |
| **Phase 2** | 7 platform improvements (500h) | After approval |
| **Phase 3** | Consolidated report + encryption (240h) | After approval |
| **Training** | 1 session | Schedule independently |

Phase 2 will be delivered in the order presented in section 2, respecting the technical dependencies between items.

---


## Next Steps

1. **Approve the platform-improvements scope** (Phase 2) so the roadmap reorganization can begin
2. **Validate the consolidated report column mapping** (Phase 3) — the preliminary mapping is described in section 3 of this document. If Atento México identifies additional columns not covered, the scope will be revised together
3. **Confirm date and participants** for the training session
4. The immediate fixes (Phase 1) will be delivered independently in the next sprint
