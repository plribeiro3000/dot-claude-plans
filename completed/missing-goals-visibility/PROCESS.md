# PROCESS - Missing Goals Visibility

## Overview

This document models the business process for the "missing goals visibility" feature.

**Status:** ✅ Backend Complete

## Process Flow

### Main Flow: View and Generate Missing Goals Reports

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────────────────┐
│   Admin      │     │    Frontend      │     │         Backend             │
└──────┬───────┘     └────────┬─────────┘     └─────────────┬───────────────┘
       │                      │                             │
       │  1. Open plan        │                             │
       │  visualization       │                             │
       │─────────────────────>│                             │
       │                      │                             │
       │  2. Click            │                             │
       │  "Auditoria de       │                             │
       │  Metas"              │                             │
       │─────────────────────>│                             │
       │                      │                             │
       │                      │  3. Navigate to             │
       │                      │  audit list page            │
       │                      │                             │
       │                      │  4. Query audits            │
       │                      │  (planGoalAudits)          │
       │                      │────────────────────────────>│
       │                      │                             │
       │                      │  5. Return list             │
       │                      │<────────────────────────────│
       │                      │                             │
       │  6. Display list     │                             │
       │  (history of         │                             │
       │  all audits)         │                             │
       │<─────────────────────│                             │
       │                      │                             │
       │  7. Click "Gerar     │                             │
       │  Nova Auditoria"     │                             │
       │─────────────────────>│                             │
       │                      │                             │
       │                      │  8. Create audit            │
       │                      │  (mutation)                 │
       │                      │────────────────────────────>│
       │                      │                             │
       │                      │                             │  9. Acquire lock
       │                      │                             │     Create record
       │                      │                             │     Enqueue producer
       │                      │                             │
       │                      │  10. Return audit           │
       │                      │<────────────────────────────│
       │                      │                             │
       │  11. Show new audit  │                             │     ┌─────────────┐
       │  in list (status:    │                             │     │  Producer   │
       │  processing)         │                             │     └──────┬──────┘
       │<─────────────────────│                             │            │
       │                      │                             │     12. Load combinations
       │                      │                             │         (user × variable
       │                      │                             │          × period)
       │                      │                             │            │
       │                      │                             │     13. If empty:
       │                      │                             │         error! + release lock
       │                      │                             │            │
       │                      │                             │     14. Else: enqueue
       │                      │                             │         consumers
       │                      │                             │            │
       │                      │                             │     ┌──────┴──────┐
       │                      │                             │     │  Consumer   │
       │                      │                             │     └──────┬──────┘
       │                      │                             │            │
       │                      │                             │     15. Check Goal exists
       │                      │                             │         Save Row
       │                      │                             │            │
       │                      │                             │     ┌──────┴──────┐
       │                      │                             │     │  Finalizer  │
       │                      │                             │     └──────┬──────┘
       │                      │                             │            │
       │                      │                             │     16. Generate CSV
       │                      │                             │         Upload to S3
       │                      │                             │         finish!
       │                      │                             │         Cleanup rows
       │                      │                             │         Release lock
       │                      │                             │            │
       │  17. Poll/refresh    │                             │     └──────┴──────┘
       │  list                │                             │
       │─────────────────────>│                             │
       │                      │  18. Query audits           │
       │                      │────────────────────────────>│
       │                      │                             │
       │  19. See updated     │  20. Return updated list    │
       │  status (final)      │<────────────────────────────│
       │<─────────────────────│                             │
       │                      │                             │
       │  21. Click download  │                             │
       │─────────────────────>│                             │
       │                      │                             │
       │  22. Download CSV    │  (S3 signed URL)            │
       │<─────────────────────│                             │
       │                      │                             │
       └──────────────────────┴─────────────────────────────┘
```

## Actors

| Actor | Role | Responsibilities |
|-------|------|------------------|
| **Plan Administrator** | Primary user | Navigate to audit list, request reports, view history, download files |
| **Frontend** | UI layer | Display audit list, trigger mutations, poll for updates |
| **Backend** | Data layer | Create audits, process in background, generate files |
| **Producer** | Background job | Load combinations, enqueue consumers or fail |
| **Consumer** | Background job | Check goals, save rows |
| **Finalizer** | Background job | Generate CSV, save attachment, cleanup |

## Business Rules

### BR-01: Navigation First

User navigates to the audit list BEFORE generating a new audit:
- Prevents accidental generation
- Allows user to check if audit already exists
- Shows history of all previous audits

### BR-02: One Audit at a Time

Lock mechanism prevents concurrent audits:
- Lock acquired when audit is created
- Lock released when audit finishes or fails
- If locked, mutation returns permission error

### BR-03: Document History

All generated reports are kept:
- Each request creates a new audit record
- Audits are never deleted automatically
- Admin can see complete history for a plan

### BR-04: Empty Combinations = Failed

If no eligible combinations exist:
- Producer transitions audit to `failed` state
- Lock is released immediately
- No CSV file is generated
- User sees "failed" status in list

### BR-05: Audit States

| Status | Description | Lock | File |
|--------|-------------|------|------|
| `initial` | Just created | Held | No |
| `processing` | Being processed | Held | No |
| `final` | Complete | Released | Yes |
| `failed` | Error occurred | Released | No |

## Data Flow

### Audit Creation

```
Frontend                    Backend
   │                           │
   │  createPlanGoalAudit     │
   │  (planId)                 │
   │──────────────────────────>│
   │                           │
   │                           │  Acquire lock
   │                           │  Create audit
   │                           │  Enqueue producer
   │                           │
   │  { id, status }           │
   │<──────────────────────────│
```

### Background Processing

```
Producer
   │
   │  audit.process!
   │  Load plan.periods
   │  Load plan.plan_variables (UserGoal only)
   │  Load plan.user_ids per period
   │  Generate combinations
   │
   ├─── If empty ───────────────────┐
   │                                │
   │  audit.error!                  │
   │  Lock.delete                   │
   │  return                        │
   │                                │
   └─── If has combinations ────────┤
                                    │
        audit.computation.increment_queue
        Sidekiq::Client.push_bulk → Consumer
   Done

Consumer (per combination)
   │
   │  Load user, variable, period
   │  Check Goal.find_by(...)
   │  Create Row with:
   │    - user info
   │    - variable info
   │    - period dates
   │    - formatted goal value (or empty)
   │  computation.increment_executions
   │  If computation.done? → Finalizer
   │
   Done

Finalizer
   │
   │  Generate CSV (localized headers)
   │  Upload to S3
   │  Save attachment
   │  audit.finish!
   │  Delete rows (in batches)
   │  Lock.delete (in ensure)
   │
   Done
```

### Audit List Query

```
Frontend                    Backend
   │                           │
   │  planGoalAudits          │
   │  (planId, pagination)     │
   │──────────────────────────>│
   │                           │
   │  { nodes, pageInfo }      │
   │<──────────────────────────│
```

## Edge Cases

### EC-01: Large Dataset

**Scenario:** Plan with 5000 users × 10 variables × 12 periods

**Behavior:**
- Producer collects all combinations in memory
- Single push_bulk to Sidekiq
- Consumers process in parallel
- No timeout issues

### EC-02: Concurrent Requests

**Scenario:** Admin clicks "Generate" while another is processing

**Behavior:**
- Lock.acquire returns false
- Mutation returns permission error
- Frontend shows error message
- User must wait for current audit to finish

### EC-03: No Eligible Combinations

**Scenario:** Plan has no UserGoal variables, or no users, or no periods

**Behavior:**
- Producer detects empty combinations
- Calls audit.error!
- Releases lock
- Audit marked as `failed`
- User sees failed status in list

### EC-04: Processing Failure

**Scenario:** Background job fails unexpectedly

**Behavior:**
- Audit stays in `processing` state
- Lock stays held (until TTL or manual cleanup)
- Admin can see stuck audit in list
- May need manual intervention

## Success Criteria

1. **Clear navigation:** Button in plan view leads to audit list
2. **History visibility:** All audits visible in list
3. **Status clarity:** User can see processing/final/failed states
4. **Download works:** CSV downloads correctly when ready
5. **No accidental generation:** User must explicitly click to create new audit

---

**Status:** COMPLETE
