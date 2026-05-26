# Plan: Product News January 2026

## Overview

**Feature:** product-news-jan-2026
**Type:** Single-project (marketing)
**Status:** 🟢 Ready to Execute

## Objective

Marketing emails to clients communicating 4Shark platform updates since December/2025.

**Two versions:**
1. **General** - For all clients
2. **Atento** - Special version for our largest client, including payroll integration features

## Dependencies

- **goal-update**: Emails will only be sent after the goal update feature is complete - ✅ Done
- **payroll-requests-bug-fix**: Atento newsletter depends on fixing the payroll requests display bug - ✅ Done (hotfix/3.4.2 + hotfix/1.250.1)

## Reference

Style based on document: `reference-style-example.docx` (copy of "Funcionalidade de Gerar Premiação em Lote 3.docx")

Style characteristics:
- Storytelling: contextualizes the problem before presenting the solution
- Professional but friendly tone
- Clear and accessible language
- Focus on customer value, not technical details

## Features to Communicate

| Feature | Source | Notes |
|---------|--------|-------|
| Security and stability | Releases 3.0.0 - 3.2.0 | Generic, no technical details |
| ID columns in audits | PR #4694 | Highly requested by clients |
| Plan goal audit | Release 2.218.0 | New feature |
| Goal update | feature/goal-update | Main feature of the email |
| Optimized search | Release 3.3.0, 3.3.2 | Full-text search and search with special characters |

---

## Image Planning

| Section | Image Description | How to Capture |
|---------|-------------------|----------------|
| **Plan Goal Audit (1)** | Plan details screen showing "Auditoria de Metas" button | Access Plan > View > Capture showing the button in top right |
| **Plan Goal Audit (2)** | Goal audit listing with "+ Gerar Nova Auditoria" button | Click "Auditoria de Metas" > Capture the listing screen |
| **Goal Update** | Screenshot of goal edit screen showing value, base value and sentido fields | Access a Goal linked to a Plan > Edit > Capture the form |

**Note:**
- "ID in Audits" section has no image - only text describing the feature (screens didn't change, only the exported CSV)
- Images should be inserted inline in the email body (not as attachments). Suggested size: 600-800px width for good email visualization.

**Screenshots captured:**
- `news_plan_goal_audit_button.png` - Plan Goal Audit (1) - Plan view with button ✅
- `news_plan_goal_audit_listing.png` - Plan Goal Audit (2) - Audit listing ✅
- `news_goal_update_form.png` - Goal Update - Edit screen with value, base value, direction ✅
- `news_goal_listing_menu.png` - Goal Listing - Menu with "Atualizar" option ✅

---

## Draft (with image placeholders — described in English, final pt-BR text lives in `EMAIL-GERAL.md`)

The sections below describe each block of the email. The actual pt-BR copy ready to send is in `EMAIL-GERAL.md`. The `[IMAGE X]` markers indicate where each screenshot is inserted.

**Important:** The final email body that goes to clients is in Portuguese (pt-BR) since the audience is Brazilian. This PLAN.md describes the sections in English for the team.

---

### Greeting

Happy New Year wishes for 2026, framing the email as the first of a series with platform updates from 4Shark.

### SECURITY AND STABILITY

Generic block about internal improvements that increase platform stability and reduce security risk. No technical detail — just reassurance that the platform got more robust.

### COMPLETE IDENTIFICATION IN AUDITS

Highly requested change. Audits now include identification columns (document type and value — CPF, RUT, etc.) in user reports, statements, goals, and monthly usage exports. Helps clients reconcile data with payroll and other internal systems.

Security reassurance: audit files are available for up to 15 days and deleted automatically; access restricted to authenticated platform users.

### NEW PLAN GOAL AUDIT

Goal tracking per plan used to require navigating many screens. The new feature exposes all goals associated with a plan in a single report so the client can quickly identify which users have goals configured, which still need attention, and whether values match expectations.

Access: open the desired Plan and click "Auditoria de Metas". On the listing, click "+ Gerar Nova Auditoria" to create a new report.

[IMAGE 1: Plan view with "Auditoria de Metas" button]

[IMAGE 2: Goal audit listing with "+ Gerar Nova Auditoria" button]

### GOAL UPDATE

Mistakes happen, and discovering a wrong goal value after the plan is already linked has been a frustrating workflow. Before: cancel the plan, open a ticket for the team to fix the goal, then create a new plan — heavy dependency, rework, and operational impact.

Now: the value, base value, and direction of a goal can be updated at any time. The change is recorded on the goal and applies to future plans generated from it.

New flow: cancel the current plan, update the goal with the correct value, generate a new plan — the new plan picks up the updated goal automatically. No support ticket needed.

The update can be done in three ways:
- From the goal listing (in the goal actions menu, select "Atualizar")
- Via API, for automated integrations
- Via file upload — which previously only worked for creation, now also supports update

[IMAGE 3: Screenshot of goal edit screen]

### OTHER IMPROVEMENTS

Platform-wide search optimized to handle special characters and accents — easier to find records with names or identifiers that contain them.

### Closing

Thanking the client for the partnership and pointing them to `meajuda@4shark.com.br` for questions or suggestions.

---

## Final Text (Ready to Copy)

Final versions in Markdown format, ready to preview and copy to Gmail:
- `EMAIL-GERAL.md` - General version for all clients
- `EMAIL-ATENTO.md` - Special version for Atento with payroll integration sections

---

## Checklist (General)

- [x] Complete goal-update feature
- [x] Capture screenshots as per Image Planning
- [x] Review final text
- [x] Create EMAIL-GERAL.md with formatted text
- [ ] Send email to clients (scheduled: 2026-01-08)

---

# Atento (Special Version)

## Context

Atento is our largest client and receives exclusive features. The payment-payroll-integration feature was developed specifically for them, enabling:

1. **Direct payroll integration** - Users can trigger integration by clicking a button on the payment screen
2. **Integration logs** - Users can view the history of integration requests (check, execution, validation)
3. **Audit trail** - Records who requested each integration, when, and from where

## Known Bug

**Problem:** ~~Payroll requests are not being fetched to display the integration log to the user.~~

**Impact:** ~~The "View Integration Report" button exists but shows no data.~~

**Status:** ✅ Fixed (hotfix/3.4.2 backend + hotfix/1.250.1 frontend)

**Solution:** Added "skipped" integration status for user payments with zero billable money. These were incorrectly marked as "success" without actual integration logs.

## Features to Communicate (Atento-specific)

| Feature | Source | Notes |
|---------|--------|-------|
| All general newsletter features | (same as above) | Include everything from the general version |
| Payroll integration button | Hotfix 3.0.3 | Click to integrate payment with payroll system |
| Integration log visualization | Hotfix 3.0.3 | View check, execution, validation requests |
| Integration audit trail | Hotfix 3.1.1 | Who integrated, when, from where |
| Payment filters (user, type, status) | Hotfix 3.0.4 | Filter payments by integration status |

## Image Planning (Atento-specific)

| Section | Image Description | How to Capture |
|---------|-------------------|----------------|
| **Integration Audit** | Payment details showing owner (who integrated) and integration report button | Access an integrated payment details |
| **Integration Log + Filters** | User payment list with filters and expanded payroll requests showing check/execution/validation | Access payment > integration report > expand one entry |

**Note:** No image needed for integration button - it's just a button, text description is enough.

**Screenshots captured:**
- `news_atento_payment_details.png` - Payment details with integration report button ✅
- `news_atento_integration_report.png` - Integration Log + Filters - Expanded payroll requests ✅

## Draft (Atento-specific sections)

Add these sections after "OUTRAS MELHORIAS" and before the closing paragraph.

**Note:** Text below is in Portuguese (pt-BR) for the actual email, but documented here in English for reference:

---

### PAYROLL INTEGRATION

Section about triggering integration directly from the payment screen with one click. The system automatically starts the check, execution, and validation process.

[IMAGE: Integration button on payment screen]


### INTEGRATION MONITORING

Section about viewing the complete history of requests for each entry:
- Status of each step (check, execution, validation)
- Processing time for each request
- Technical details for troubleshooting when needed

[IMAGE: Integration log showing payroll requests]


### INTEGRATION AUDIT

Section about automatic tracking:
- Who requested the integration
- When it was requested
- Origin (IP address)

[IMAGE: Payment details with integration audit info]

---

## Checklist (Atento)

- [x] Fix payroll requests display bug
- [x] Complete goal-update feature
- [x] Capture all screenshots (general + Atento-specific)
- [x] Write final Portuguese text for Atento sections
- [x] Review final text
- [x] Create EMAIL-ATENTO.md with formatted text
- [ ] Send email to Atento (scheduled: 2026-01-08)

---

**Created:** 2026-01-06
**Last Update:** 2026-01-07 (Text finalized, ready to send)
