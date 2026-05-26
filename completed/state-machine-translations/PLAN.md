# Feature: State Machine Translations

**Status:** ✅ COMPLETED
**Last PR:** #5823 (2026-01-06)

## Overview

Ensure all backend state machine states are translated in the frontend across 3 languages (pt-BR, en, es).

## Scope

**Type**: Multi-project (Backend + Frontend)

**Projects Affected**:
- `app` (Backend - Rails) - State source
- `app-webclient` (Frontend - Angular) - Translations

---

## Implementation Summary

### All State Machines ✅

| Model | States | Status |
|-------|--------|--------|
| Payment | initial, processing, review, final, failed, exporting, exported, integrating, integrated, integration_error | ✅ |
| Commission | initial, processing, review, final, locked, error | ✅ |
| Document | initial, processing, erasing, final, failed | ✅ |
| Plan | initial, final, review, canceled, processing, approving | ✅ |
| Audit (9 types) | initial, processing, final, failed | ✅ PR #5823 |
| PlanStatement | pending, accepted, canceled | ✅ |
| PlanParticipation | locked, review, final, expired | ✅ |
| Campaign | initial, final | ✅ |
| CampaignFund | initial, review, final | ✅ |
| IncentivePayment | initial, processing, locked, review, releasing, final, failed | ✅ |
| IncentiveCampaign | exhausted, available, error | ✅ |
| Company | initial, processing, final | ✅ |
| CollaborativeDeal | initial, enabling, disabling | ✅ |
| UserPayment | pending, success, failure | ✅ |
| PayrollRequest | pending, success, failure | ✅ |
| PaymentReport | initial, processing, final, expired | ✅ |
| PlanSlice | initial, final, waiting_processing, processing | ✅ |
| PartialCommission | initial, processing, final, error | ✅ |
| UserHistory | processing, final | ✅ |

### Changes Made

| Model | States Added | Languages | PR |
|-------|--------------|-----------|-----|
| Payment | integrating, integrated, integration_error | pt-BR, en, es | - |
| IncentiveCampaign | error | pt-BR, en, es | - |
| Company | status section | pt-BR, en, es | - |
| CollaborativeDeal | state section | pt-BR, en, es | - |
| UserPayment | integration_status | pt-BR, en, es | - |
| PayrollRequest | new resource + status | pt-BR, en, es | - |
| 9 Audits | failed | pt-BR, en, es | #5823 |

### Bug Fixes Applied
- Fixed `exporting` translation in es.json: "Exportador" → "Exportando"
- Fixed company.component.html using `password_document.status` instead of `company.status`

---

**Created:** 2025-12-XX
**Completed:** 2026-01-06
