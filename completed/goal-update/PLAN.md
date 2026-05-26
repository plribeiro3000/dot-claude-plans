# Plan: Goal Update

## Overview

**Feature:** goal-update
**Type:** Multi-project (app + app-webclient)
**Status:** ✅ Complete

## Completed

| Phase | Release | PRs | Description |
|-------|---------|-----|-------------|
| 1 | 3.3.0 | #4697 | Add format/output to CommissionGoal & GoalPlan |
| 2 | 3.3.0 | #4698, #4700 | Fix backend to use snapshot values + unique index |
| 3a | 3.3.0 | #4695 | New frontend - Use CommissionGoal.output |
| 3b | - | #5816 | Old frontend - Use CommissionGoal.output |
| 3c | 3.3.4 | #4707 | Fix payment report to use CommissionGoal.value |
| 4a | 3.4.0 | #4708 | Backend - Enable Goal updates (policy, model, GraphQL, REST API, upload) |
| 4b | 1.250.0 | #5825 | Frontend - Send baseline/direction in update mutation |
| 5 | 3.4.1 | #4711 | Remove goal_updated_at from PlanGoalAudit |

## Remaining

None. Feature complete.

---

## Phase 5 Details: Remove goal_updated_at from PlanGoalAudit

**Reason:** This column showed when the Goal was last updated. Before, Goals couldn't be updated after linking to a Plan, so it indicated how recent the value was. Now that Goals can be updated, this date could be after the Plan was created, making it confusing/misleading.

**Files to change:**
1. `app/workers/plan_goal_audit/user_consumer.rb` - remove `row.goal_updated_at = goal&.updated_at`
2. `app/workers/plan_goal_audit/group_consumer.rb` - remove `row.goal_updated_at = goal&.updated_at`
3. `app/workers/plan_goal_audit/finalizer.rb` - remove `goal_updated_at` from CSV columns
4. `config/locales/*/models/plan_goal_audit/row.yml` - remove translations (8 files)
5. New migration to remove `goal_updated_at` column from `plan_goal_audit_rows` table

**Frontend:** Not affected (column not used)

## Pre-Phase 4 Checklist

Before enabling Goal updates, run these queries to identify existing discrepancies:

### Query 1 - Goal vs GoalPlan discrepancies

```sql
SELECT
  g.id AS goal_id,
  g.value AS goal_current_value,
  gp.value AS goal_plan_snapshot_value,
  g.baseline AS goal_current_baseline,
  gp.baseline AS goal_plan_snapshot_baseline,
  g.direction AS goal_current_direction,
  gp.direction AS goal_plan_snapshot_direction,
  g.updated_at AS goal_updated_at,
  gp.created_at AS goal_plan_created_at,
  p.id AS plan_id,
  p.name AS plan_name
FROM goals g
INNER JOIN goal_plans gp ON gp.goal_id = g.id
INNER JOIN plans p ON p.id = gp.plan_id
WHERE (g.value != gp.value
   OR g.baseline != gp.baseline
   OR g.direction != gp.direction)
  AND g.updated_at > gp.created_at
ORDER BY g.updated_at DESC;
```

### Query 2 - Goal vs CommissionGoal discrepancies

```sql
SELECT
  g.id AS goal_id,
  g.value AS goal_current_value,
  cg.value AS commission_goal_snapshot_value,
  g.baseline AS goal_current_baseline,
  cg.baseline AS commission_goal_snapshot_baseline,
  g.direction AS goal_current_direction,
  cg.direction AS commission_goal_snapshot_direction,
  g.updated_at AS goal_updated_at,
  cg.created_at AS commission_goal_created_at,
  c.id AS commission_id,
  p.id AS plan_id,
  p.name AS plan_name
FROM goals g
INNER JOIN commission_goals cg ON cg.goal_id = g.id
INNER JOIN commissions c ON c.id = cg.commission_id
INNER JOIN plans p ON p.id = c.plan_id
WHERE (g.value != cg.value
   OR g.baseline != cg.baseline
   OR g.direction != cg.direction)
  AND g.updated_at > cg.created_at
ORDER BY g.updated_at DESC;
```

## Problem

Goals cannot be updated after being linked to a Plan. This was intentional to preserve calculation history, but creates friction when clients make mistakes:

1. Client creates a Goal with wrong `value` or `baseline`
2. Client creates a Plan and links the Goal
3. Client realizes the mistake
4. **Current behavior:** Cannot update the Goal because it's linked to a Plan
5. Client must cancel the Plan and create a new one
6. But the Goal still cannot be updated because it remains linked to the old Plan (for history)

## Solution

Allow Goal updates for `value`, `baseline`, and `direction` fields because these values are already copied to `GoalPlan` and `CommissionGoal` entities when the Plan/Commission is processed.

---

## Field Classification

### Identity Fields (ALWAYS blocked for update)

These fields define WHAT the goal is. They are **never editable** after creation - changing them would fundamentally change the goal identity.

| Field | Description |
|-------|-------------|
| `variable_id` | The variable being measured |
| `user_id` | Owner of the goal (UserGoal) |
| `group_id` | Owner of the goal (GroupGoal) |
| `starts_at` | Period start date |
| `ends_at` | Period end date |
| `type` | UserGoal or GroupGoal |

**Important:** This is not conditional. These fields cannot be updated regardless of whether the Goal has Plans or not. If the user made a mistake in any of these fields, they must delete the Goal and create a new one.

### Value Fields (always editable)

These fields define the TARGET values. They are snapshotted to GoalPlan/CommissionGoal when used.

| Field | Description |
|-------|-------------|
| `value` | The goal target value |
| `baseline` | The starting point for calculation |
| `direction` | ascending (higher=better) or descending (lower=better) |

---

## Audit Results

### Initial Audit (2026-01-05)

#### Snapshot Models Analysis

| Model | Has `value`, `baseline`, `direction` | Has `format`, `output` |
|-------|--------------------------------------|------------------------|
| Goal | ✅ Yes | ✅ Yes (uses Variable) |
| GoalPlan | ✅ Yes | ❌ No → Fixed in Phase 1 |
| CommissionGoal | ✅ Yes | ❌ No → Fixed in Phase 1 |

#### Problems Found and Fixed

| File | Problem | Fixed in |
|------|---------|----------|
| `goal_dataset/consumer.rb` | Uses `goal.*` instead of `commission_goal.*` | Phase 2 |
| `indicator_options_processor.rb` | Uses `goal.format` | Phase 2 |
| Frontend `user-commission-show` | Uses `element.goal.output` | Phase 3a/3b |

---

### Final Audit (2026-01-06)

Full codebase audit before enabling Goal updates.

#### Backend - All Correct ✅

| File | Status | Details |
|------|--------|---------|
| `plan/goals_processor.rb` | ✅ | Creates GoalPlan from Goal (snapshot) |
| `commission_goal/consumer.rb` | ✅ | Creates CommissionGoal from GoalPlan |
| `plan_participation/consumer.rb` | ✅ | Creates snapshot correctly |
| `goal_dataset/consumer.rb` | ✅ | Uses `commission_goal.*` (fixed in Phase 2) |
| `indicator_options_processor.rb` | ✅ | Uses `commission_goal.*` (fixed in Phase 2) |
| `performance/consumer.rb` | ⚠️ TODO | Uses Goal directly - needs future fix |
| `payment_work_book/results_by_goal_sheet.rb` | ✅ | Uses `commission_goal.value` (fixed in Phase 3c) |

#### Frontend - All Correct ✅

| Component | Context | Usage |
|-----------|---------|-------|
| `goal/*` | Standalone | Goal directly (correct) |
| `plan-show.component.html` | Plan | `goalPlan.value` (snapshot) |
| `user-commission-show.component.ts` | Commission | `commissionGoal.output/direction` |
| `statement-show.component.ts` | Commission | `commissionGoal.output/direction` |
| `dashboard-plan.component.html` | Dashboard | GoalDataset (uses CommissionGoal) |
| `goal-widget.component.html` | Widget | GoalDataset |
| `goal-document-show.component.html` | Import | Goal standalone (correct) |

#### Bug Found and Fixed

| File | Problem | Fix |
|------|---------|-----|
| `payment_work_book/results_by_goal_sheet.rb` | Used `goal.value` in Commission context | Fixed in hotfix/3.3.4 (PR #4707) |

---

## Implementation Plan

### Phase 1: Backend - Add Format/Output to Snapshot Models

#### Task 1.1: Add methods to CommissionGoal

```ruby
# app/models/commission_goal.rb

def variable
  goal.variable
end

def format
  return if variable.nil?
  variable.format(value)
end

def output
  return value if variable.duration?
  variable.output(value)
end

def formatted_baseline
  return if variable.nil?
  variable.format(baseline)
end
```

**Files:**
- `app/models/commission_goal.rb`
- `spec/models/commission_goal_spec.rb`

#### Task 1.2: Add methods to GoalPlan

```ruby
# app/models/goal_plan.rb

def variable
  goal.variable
end

def format
  return if variable.nil?
  variable.format(value)
end

def output
  return value if variable.duration?
  variable.output(value)
end

def formatted_baseline
  return if variable.nil?
  variable.format(baseline)
end
```

**Files:**
- `app/models/goal_plan.rb`
- `spec/models/goal_plan_spec.rb`

#### Task 1.3: Expose fields in GraphQL Types

```ruby
# app/graphql_types/commission_goal_graphql_type.rb
field :format, String, null: true
field :formatted_baseline, String, null: true
field :output, String, null: true

# app/graphql_types/goal_plan_graphql_type.rb
field :format, String, null: true
field :formatted_baseline, String, null: true
field :output, String, null: true
```

**Files:**
- `app/graphql_types/commission_goal_graphql_type.rb`
- `app/graphql_types/goal_plan_graphql_type.rb`

---

### Phase 2: Backend - Fix Code Using Goal Instead of Snapshot

#### Task 2.1: Fix GoalDataset::Consumer

Change from:
```ruby
goal.baseline
goal.format
goal.output
goal.formatted_baseline
goal.direction
```

To:
```ruby
commission_goal.baseline
commission_goal.format
commission_goal.output
commission_goal.formatted_baseline
commission_goal.direction
```

**Files:**
- `app/workers/goal_dataset/consumer.rb`
- `spec/workers/goal_dataset/consumer_spec.rb`

#### Task 2.2: Fix IndicatorOptionsProcessor

Change from:
```ruby
goal.format
```

To:
```ruby
commission_goal.format
```

**Files:**
- `app/services/commission/indicator_options_processor.rb`
- `spec/services/commission/indicator_options_processor_spec.rb`

---

### Phase 3: Frontend - Use Snapshot Fields

#### Task 3.1: Fix User Commission Show

Change GraphQL query to fetch CommissionGoal fields instead of Goal:

```typescript
// Before
goals {
  output
  value
  direction
  ...
}

// After - use commission_goals with snapshot fields
commissionGoals {
  output
  value
  direction
  format
  formattedBaseline
  goal {
    variable { id name }
    owner { name }
    type
  }
}
```

Update template:
```html
<!-- Before -->
{{ element.goal.output }}

<!-- After -->
{{ element.commissionGoal.output }}
```

**Files:**
- `src/app/user-commission/show/user-commission-show.component.ts`
- `src/app/user-commission/show/user-commission-show.component.html`

#### Task 3.2: Audit and fix any other places using Goal.output/format in Commission/Plan context

Search for `goal.output`, `goal.format`, `goal.value` in Plan/Commission contexts and update to use snapshot.

---

### Phase 4: Backend + Frontend - Enable Goal Updates

#### Task 4.1: Update GoalPolicy ✅ DONE

Removed the `record.plans?` check from policy.

**Commit:** `9f0363f5f fix(goal): remove plans check from update policy`

**Files:**
- `app/policies/goal_policy.rb`
- `spec/policies/goal_policy_spec.rb`

#### Task 4.2: Remove Model Validation

Remove the `plan_usage` validation from Goal model that blocks updates when Goal has plans.

```ruby
# app/models/goal.rb
# REMOVE this validation:
validate :plan_usage

# REMOVE this method:
def plan_usage
  return if plans.empty?

  if user?
    errors.add(:user_id, :in_use)
  elsif group?
    errors.add(:group_id, :in_use)
  end
end
```

**Files:**
- `app/models/goal.rb`
- `spec/models/goal_spec.rb`

#### Task 4.3: Expand UpdateGoalGraphqlMutation

Add `baseline` and `direction` arguments to allow full value field updates.

**Important:** The strong parameters (`goal_params`) guarantee that identity fields (variable_id, user_id, group_id, starts_at, ends_at, type) can NEVER be updated via this mutation. No model validation needed.

```ruby
# app/graphql_mutations/update_goal_graphql_mutation.rb
argument :id, ID, required: true
argument :value, String, required: false
argument :baseline, String, required: false      # NEW
argument :direction, String, required: false     # NEW

def goal_params
  params.permit(:value, :baseline, :direction)   # Only value fields allowed
end
```

**Files:**
- `app/graphql_mutations/update_goal_graphql_mutation.rb`
- `spec/requests/graphql_mutations/graphql_controller_update_goal_spec.rb`

#### Task 4.4: Expand REST API v3 Goals Update

Add `direction` to the permitted params in both API controllers. Currently only `baseline` and `value` are allowed.

```ruby
# app/controllers/api/v3/goals_controller.rb
def goal_params_on_update
  params.require(:goal).permit(:baseline, :value, :direction)  # ADD :direction
end

# app/controllers/api/v3/subsidiaries/goals_controller.rb
def goal_params_on_update
  params.require(:goal).permit(:baseline, :value, :direction)  # ADD :direction
end
```

Also update OpenAPI documentation (`UpdateGoalParams` and `SubsidiaryUpdateGoalParams` components) to include `direction` field.

**Files:**
- `app/controllers/api/v3/goals_controller.rb`
- `app/controllers/api/v3/subsidiaries/goals_controller.rb`
- `spec/requests/api/v3/goals_controller_spec.rb`
- `spec/requests/api/v3/subsidiaries/goals_controller_spec.rb`

#### Task 4.5: Implement Upsert in GoalDocument::Processor

Change upload from insert-only to upsert (find_or_initialize_by identity fields).

```ruby
# app/workers/goal_document/processor.rb
# Instead of: goal = Goal.new(...)
# Use: goal = Goal.find_or_initialize_by(identity_fields)
# Then: goal.assign_attributes(value_fields)

goal = Goal.find_or_initialize_by(
  company_id: company.id,
  variable_id: variable_id(...),
  starts_at: row[3].to_s.strip,
  ends_at: row[4].to_s.strip,
  type: type(row[7].to_s.strip),
  user_id: user_id(...),      # for UserGoal
  group_id: group_id(...)     # for GroupGoal
)

goal.assign_attributes(
  value: row[2].to_s.strip,
  baseline: row[5].to_s.strip,
  direction: row[6].to_s.strip,
  owner_id: owner.id,
  goal_document_id: goal_document.id,
  document_line: line
)
```

**Files:**
- `app/workers/goal_document/processor.rb`
- `spec/workers/goal_document/processor_spec.rb`

#### Task 4.6: Frontend - Send All Value Fields in Update Mutation

Update frontend to send `baseline` and `direction` in the mutation.

```typescript
// src/app/goal/update/goal-update.component.ts
private goalUpdateQuery() {
  return `mutation {
    updateGoal(
      id: ${this.goalId}
      value: "${this.form.value.value || ''}"
      baseline: "${this.form.value.baseline || ''}"
      direction: "${this.form.value.direction || ''}"
    ) {
      id
    }
  }`;
}
```

**Files:**
- `src/app/goal/update/goal-update.component.ts`

#### Task 4.7: Remove in_use Translations from Frontend

Remove unused `in_use` error translations for `group_id` and `user_id` fields.

**Files:**
- `src/assets/i18n/en.json`
- `src/assets/i18n/es.json`
- `src/assets/i18n/pt.json`

---

### Phase 4: Deploy Strategy (Zero Downtime)

#### PRs and Deploy Strategy

| PR | Tasks | Project | Description |
|----|-------|---------|-------------|
| 1 | 4.1, 4.2, 4.3, 4.4, 4.5 | app | Enable Goal updates (policy + model + mutation + API + upload) |
| 2 | 4.6, 4.7 | webclient | Send baseline/direction in update form + remove in_use translations |

#### Deploy Order

```
┌─────────────────────────────────────────────────────────────┐
│ PR 1 / DEPLOY 1: Backend (app)                               │
│                                                              │
│   Tasks: 4.1 ✅, 4.2, 4.3, 4.4, 4.5                          │
│                                                              │
│   - Policy allows update for Goals with Plans (done)         │
│   - Model validation removed                                 │
│   - GraphQL mutation accepts baseline/direction (optional)   │
│   - REST API accepts direction (optional)                    │
│   - Upload does upsert                                       │
│   - Old frontend keeps working (only sends value)            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ PR 2 / DEPLOY 2: Frontend (webclient)                        │
│                                                              │
│   Task: 4.6                                                  │
│                                                              │
│   - Now sends baseline/direction                             │
│   - Backend already accepts the fields                       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

#### Why Zero Downtime?

1. **Mutation/API args are optional** (`required: false`) - old frontend keeps working
2. **No database migration** - no schema change required
3. **Backward compatible** - no existing functionality breaks

---

### Phase 5: Remove goal_updated_at from PlanGoalAudit

See "Phase 5 Details" section above.

---

## Files Summary

### Phase 1 - Add Format/Output to Snapshots

| File | Change |
|------|--------|
| `app/models/commission_goal.rb` | Add `format`, `output`, `formatted_baseline` methods |
| `app/models/goal_plan.rb` | Add `format`, `output`, `formatted_baseline` methods |
| `app/graphql_types/commission_goal_graphql_type.rb` | Expose `format`, `output`, `formatted_baseline` |
| `app/graphql_types/goal_plan_graphql_type.rb` | Expose `format`, `output`, `formatted_baseline` |
| `spec/models/commission_goal_spec.rb` | Add tests |
| `spec/models/goal_plan_spec.rb` | Add tests |

### Phase 2 - Fix Backend Code

| File | Change |
|------|--------|
| `app/workers/goal_dataset/consumer.rb` | Use CommissionGoal instead of Goal |
| `app/services/commission/indicator_options_processor.rb` | Use CommissionGoal instead of Goal |
| `spec/workers/goal_dataset/consumer_spec.rb` | Update tests |
| `spec/services/commission/indicator_options_processor_spec.rb` | Update tests |

### Phase 3 - Fix Frontend

| File | Change |
|------|--------|
| `src/app/user-commission/show/user-commission-show.component.ts` | Use CommissionGoal fields |
| `src/app/user-commission/show/user-commission-show.component.html` | Use CommissionGoal.output |

### Phase 4 - Enable Goal Updates

| Task | File | Change |
|------|------|--------|
| 4.1 ✅ | `app/policies/goal_policy.rb` | Remove `record.plans?` check |
| 4.2 ✅ | `app/models/goal.rb` | Remove `plan_usage` validation |
| 4.3 ✅ | `app/graphql_mutations/update_goal_graphql_mutation.rb` | Add `baseline` and `direction` to strong params |
| 4.4 ✅ | `app/controllers/api/v3/goals_controller.rb` | Add `direction` to permitted params |
| 4.4 ✅ | `app/controllers/api/v3/subsidiaries/goals_controller.rb` | Add `direction` to permitted params |
| 4.5 ✅ | `app/workers/goal_document/processor.rb` | Implement upsert instead of insert-only |
| 4.5 ✅ | `config/locales/*/models/goal.yml` | Remove `in_use` translations |
| 4.6 | `src/app/goal/update/goal-update.component.ts` | Send `baseline` and `direction` in mutation |
| 4.7 | `src/assets/i18n/*.json` | Remove `in_use` translations |

**Note:** Identity fields protection is via strong parameters in the mutation and API. No additional model validation needed.

### Phase 5 - Remove goal_updated_at from PlanGoalAudit

| File | Change |
|------|--------|
| `app/workers/plan_goal_audit/user_consumer.rb` | Remove `row.goal_updated_at = goal&.updated_at` |
| `app/workers/plan_goal_audit/group_consumer.rb` | Remove `row.goal_updated_at = goal&.updated_at` |
| `app/workers/plan_goal_audit/finalizer.rb` | Remove `goal_updated_at` from CSV columns |
| `config/locales/*/models/plan_goal_audit/row.yml` | Remove translations (8 files) |
| Migration | Remove `goal_updated_at` column from `plan_goal_audit_rows` |

---

## Execution Order

```
┌─────────────────────────────────────────────────────────┐
│ RELEASE 1: Backend - Snapshot Support                   │
│                                                         │
│   PR 1: Add format/output to CommissionGoal & GoalPlan  │
│   PR 2: Fix workers/services to use snapshot values     │
│                                                         │
│   (Single deploy)                                       │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ RELEASE 2: Frontend - Use Snapshot Fields               │
│                                                         │
│   PR 3: Update frontend to use CommissionGoal fields    │
│                                                         │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ RELEASE 3: Backend - Enable Goal Updates                │
│                                                         │
│   PR 4: Remove policy/validation blocks                 │
│                                                         │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ RELEASE 4: Cleanup (if needed)                          │
│                                                         │
│   PR 5: Remove unused code, decide on PlanGoalAudit     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

**Created:** 2026-01-04
**Last Update:** 2026-01-06 (Phases 1-3 complete. Phase 4 expanded: added model validation removal, REST API update, renumbered tasks.)
