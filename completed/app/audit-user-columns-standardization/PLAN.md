# PLAN — Standardize User Identification Columns Across All Audits

**Status:** ✅ COMPLETED
**Merged:** PR #4694 (2025-12-31)
**Release:** 3.3.0

## Overview

Standardized user identification columns across all 7 audit types to use consistent 4-column format:
- `{role}_name`
- `{role}_register_type`
- `{role}_primary_identifier_value`
- `{role}_unique_register_id`

## Problem Solved

Inconsistent column naming across audit exports created confusion and made cross-audit analysis difficult:
- CalendarAudit used `user_identifier` while PlanStatementAudit used `user_external_id`
- Some audits had `register_type` and `unique_register_id`, others didn't
- Parent information incomplete in some audits

## Implementation Summary

### Migrations (19 total)

| Audit | Changes |
|-------|---------|
| CalendarAudit | Renamed `user_identifier` → `user_primary_identifier_value`, `subordinate_identifier` → `subordinate_primary_identifier_value` |
| UserAudit | Renamed `user_identifier`, added `user_register_type`, `user_unique_register_id` |
| PlanStatementAudit | Renamed `user_external_id`, added 3 user columns + 3 parent columns |
| PlanGoalAudit | Renamed `owner_identifier`, added 2 owner columns, recreated unique index |
| ResponsibleAudit | Added 3 responsible columns |

### Workers Updated (12 files)

- `calendar_audit/consumer.rb`, `finalizer.rb`
- `user_audit/consumer.rb`, `finalizer.rb`
- `monthly_usage_audit/row/consumer.rb`
- `plan_statement_audit/consumer.rb`, `finalizer.rb`
- `plan_goal_audit/user_consumer.rb`, `group_consumer.rb`, `finalizer.rb`
- `responsible_audit/consumer.rb`, `finalizer.rb`

### Worksheets Updated (3 files)

- `group_audit_work_book/groupifications_work_sheet.rb`
- `monthly_usage_audit_work_book/monthly_usages_work_sheet.rb`
- `statement_audit_work_book/statements_work_sheet.rb`

### I18n Translations (12 files)

All translations added for en, es, pt-BR locales.

## Affected Audits

| Audit | User Columns | Parent/Other Columns |
|-------|--------------|----------------------|
| CalendarAudit | ✅ 4 columns | ✅ 4 subordinate columns |
| UserAudit | ✅ 4 columns | - |
| MonthlyUsageAudit | ✅ 4 columns | - |
| PlanStatementAudit | ✅ 4 columns | ✅ 4 parent columns |
| PlanGoalAudit | ✅ 4 owner columns | - |
| ResponsibleAudit | ✅ 4 responsible columns | - |
| StatementAudit | ✅ 4 columns (worksheet) | ✅ 4 parent columns |
| GroupAudit | ✅ 4 columns (worksheet) | - |

---

**Created:** 2025-12-31
**Completed:** 2025-12-31
