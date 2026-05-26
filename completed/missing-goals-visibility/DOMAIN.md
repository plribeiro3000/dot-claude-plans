# DOMAIN - Missing Goals Visibility

## Core Concepts

### Plan
A compensation plan that defines which indicators will be used to measure performance and calculate commissions for a group of employees during a calendar period.

### Indicator (Variable)
A measurable metric used to evaluate performance (e.g., "Sales Volume", "Call Count").

### Goal
A target value assigned to an employee for a specific indicator during a specific period. Goals define what the employee should achieve.

### Eligible User
An employee who participates in a plan and should have goals assigned. Eligibility is determined by group membership during the plan's period.

### Missing Goal
A combination of (user + indicator + period) where the user is eligible but no goal has been assigned yet.

### Plan Goals Audit (NEW)
An audit report that lists all missing goal combinations for a plan. Follows the existing Audit pattern with producer/consumer/finalizer processing.

## Relationships

```
Plan ──── has many ──── Indicators (via PlanVariable)
Plan ──── has many ──── Periods (via Calendar)
Plan ──── has many ──── Eligible Users (via Group membership)
Plan ──── has many ──── Plan Goals Audits

Goal ──── belongs to ──── User
Goal ──── belongs to ──── Indicator
Goal ──── belongs to ──── Period (via starts_at/ends_at)

Plan Goals Audit ──── belongs to ──── Plan
Plan Goals Audit ──── has many ──── Rows (temporary, deleted after file generation)
Plan Goals Audit ──── has one ──── File (CSV)
```

## Goal Types

| Type | Description | Visibility Problem? |
|------|-------------|---------------------|
| **User Goal** | Individual target per employee | Yes - can have many missing |
| **Group Goal** | Single target for entire team | No - only 1 per period |

This feature only addresses **User Goals** because:
- User Goals require one record per (user × indicator × period)
- With many users, it's hard to know WHO is missing
- Group Goals only need one record per period - easy to see if missing

## Business Rules

### User Eligibility
A user is eligible for goals in a plan if:
- User belongs to the plan's group
- User was active in the group during the period

### Missing Goal Detection
A goal is "missing" when:
- The indicator is configured for User Goals
- The user is eligible for that period
- No goal record exists for that (user + indicator + period)

### Document Generation
- Admin requests a report → document created with status "processing"
- Background job calculates missing combinations
- Excel file generated and attached
- Document status updated to "final"

### Document History
- All generated documents are kept
- Admin can view history of all requests for a plan
- Documents are never automatically deleted

---

**Status:** COMPLETE
