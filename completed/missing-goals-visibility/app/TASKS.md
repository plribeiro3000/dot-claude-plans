# TASKS - Missing Goals Visibility (Backend)

## Overview

Backend implementation following the Audit pattern with producer/consumer/finalizer.

**Status:** ✅ COMPLETED

## Tasks

### 1. Database ✅

- [x] Create migration for `plan_goal_audit_rows` table
- [x] Add `PlanGoalAudit` to `Audit::TYPES`
- [x] Create migration for actions (listing, creation, download)
- [x] Add unique index
- [x] Add new columns: `goal_plan_created_at`, `goal_plan_status`, `goal_updated_at`, `plan_finished_at`

### 2. Model PlanGoalAudit ✅

- [x] Create `app/models/plan_goal_audit.rb` (inherits from Audit)
- [x] Create `app/models/plan_goal_audit/row.rb`
- [x] Add `has_many :rows` to PlanGoalAudit
- [x] Add `plan_goals?` method to Audit
- [x] Add validation for plan_id when plan_goals?
- [x] Add `lock_key` class method
- [x] Add `failed` state and `error` event to Audit state machine

### 3. Workers ✅

- [x] `app/workers/plan_goal_audit/producer.rb`
  - Uses `plan.statements.pluck(:user_id)` for finalized plans (correct eligibility)
  - Uses `plan.user_ids` for non-finalized plans
  - Only calls `push_bulk` when array has elements (prevents invalid queue arguments)

- [x] `app/workers/plan_goal_audit/user_consumer.rb`
  - Receives: (audit_id, user_id, variable_id, period_id)
  - Finds goal by user_id, variable_id, period
  - Populates new columns: goal_plan_created_at, goal_plan_status, goal_updated_at, plan_finished_at

- [x] `app/workers/plan_goal_audit/group_consumer.rb`
  - Same as UserConsumer but for group goals

- [x] `app/workers/plan_goal_audit/finalizer.rb`
  - Updated CSV headers with new columns (alphabetical order)

### 4. GraphQL ✅

- [x] Create `app/graphql_mutations/create_plan_goal_audit_graphql_mutation.rb`
- [x] Create `app/graphql_resolvers/plan_goal_audit_graphql_resolver.rb`
- [x] Create `app/graphql_resolvers/plan_goal_audit_permissions_graphql_resolver.rb`
- [x] Create `app/graphql_types/plan_goal_audit_graphql_type.rb`
- [x] Add to QueryType (plural: `planGoalAudits`)
- [x] Add to MutationType (alphabetical order)
- [x] Add `usersCount` field to `PlanGraphqlType`
- [x] Add `'audit'` action to `PlanGraphqlType` actions

### 5. Form & Policy ✅

- [x] Create `app/forms/plan_goal_audit_form.rb`
  - Acquires lock before saving
- [x] Create `app/policies/plan_goal_audit_policy.rb`
  - Actions: index?, create?, download?
  - Follows CommissionIndicatorAuditPolicy pattern (receives audit/form as record)

### 6. Locales ✅

- [x] Updated row translations for all locales (pt-BR, en, es, es-AR, es-CL, es-CO, es-MX, es-PA, es-PE)
  - Headers: goal_plan_created_at, goal_plan_status, goal_type, goal_updated_at, owner_identifier, owner_name, period_ends_at, period_starts_at, plan_finished_at, value, variable_key, variable_name

### 7. Tests ✅

- [x] Model spec for PlanGoalAudit (10 examples)
- [x] Integration spec for create mutation (3 examples)
- [x] Integration spec for resolver query (2 examples)
- [x] All 15 tests passing

## Hotfix 2.218.1 - Bugs Fixed

1. **Permission level** - Changed from module to register level
2. **User eligibility** - Fixed to use `plan.statements.pluck(:user_id)` for finalized plans
3. **Invalid queue arguments** - Added validation before `push_bulk` calls

## New Columns

| Column | Type | Translation (pt-BR) | Description |
|--------|------|---------------------|-------------|
| goal_plan_created_at | datetime | Inserção da Meta no Plano | When goal was linked to plan (GoalPlan.created_at) |
| goal_plan_status | string | Utilização da Meta | "Sim" or "Não" |
| goal_updated_at | datetime | Última Atualização da Meta | Last goal update |
| plan_finished_at | datetime | Data de Finalização do Plano | When plan was finalized |

## API Notes

- **Plan actions:** Returns `'audit'` when user has `plan_goal_audit_listing` permission
- **Permissions resolver:** `planGoalAuditPermissions(planId)` returns `plan_goal_audit_creation` key
