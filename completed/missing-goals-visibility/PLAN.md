# Plan: Missing Goals Visibility

## Overview

**Feature:** missing-goals-visibility
**Type:** Multi-project (app + app-webclient)
**Status:** ✅ COMPLETED - In Production

## Problem

The goal finalization page shows aggregated numbers (e.g., "40 goals out of 50 eligible people") but doesn't show WHICH users are missing goals. Customers cannot identify who still needs goals assigned.

## Solution

### Architecture Decision

**NOT a synchronous query** - too expensive for large plans (5000 users × 10 variables × 12 periods = 600k combinations with 7-8 table joins).

**Background processing with audit storage:**
- User requests a "missing goals report"
- Backend processes in background (producer/consumer/finalizer)
- Result is stored as CSV attachment
- User can view history of all requests and download files

### Flow

1. Admin opens plan visualization page
2. Sees button "Auditoria de Metas" (Goals Audit)
3. Click → navigates to audit LIST page (not mutation!)
4. Views list of all previous audits (history)
5. If needs new report: clicks "Gerar Nova Auditoria" button
6. Mutation creates audit → processed in background
7. Poll/refresh to see status update
8. Downloads the CSV file when ready (status = final)
9. Goes after users to collect goal values
10. Uploads via existing GoalDocument flow

### Scope

**In scope:**
- ALL variables from the plan (not filtered by goal_type)
- Both goal types: GroupGoal and UserGoal
- For each variable × period: check if GroupGoal exists AND if UserGoal exists for each user
- PlanGoalAudit inheriting from Audit pattern
- Background processing (producer/consumer/finalizer)
- GraphQL query and mutation
- CSV file generation with goal type identification
- Lock mechanism to prevent concurrent audits

**Out of scope:**
- Changes to existing finalization flow
- Upload flow (already exists)

### Goal Types

| Type | Description | Owner |
|------|-------------|-------|
| Meta de grupo | Single goal for all users in the group | Group (identified by external_id) |
| Meta de usuário | Individual goal per user | User (identified by primary_identifier_value) |

The audit must show BOTH types for each variable × period combination, allowing the customer to see:
- Which group goals exist/are missing
- Which user goals exist/are missing

## Implementation Status

### Phase 1: Backend (app) ✅ COMPLETED

1. **PlanGoalAudit model** ✅
   - Inherits from `Audit`
   - Has `PlanGoalAudit::Row` for temporary storage
   - Stores: plan reference, status, file attachment, timestamps
   - States: initial → processing → final/failed

2. **Background processing** ✅
   - Producer: collects all (variable, period) combinations for ALL plan_variables
   - Consumer: checks BOTH GroupGoal and UserGoal, saves Row with goal_type
   - Finalizer: generates CSV with new columns, saves attachment, cleans up rows

3. **GraphQL API** ✅
   - Query: `planGoalAudits` (paginated list)
   - Mutation: `createPlanGoalAudit`
   - Type: `PlanGoalAuditGraphqlType` with download action
   - Added: `usersCount` field on `PlanGraphqlType`

4. **Permissions** ✅
   - Actions: listing, creation, download
   - Integrated with PlanPermissions resolver

### Phase 2: Frontend (app-webclient) ✅ COMPLETED

See [app-webclient/TASKS.md](./app-webclient/TASKS.md) for detailed tasks.

## API Contract

### Query: planGoalAudits

```graphql
query PlanGoalAudits($planId: ID!, $first: Int, $after: String) {
  planGoalAudits(planId: $planId, first: $first, after: $after) {
    nodes {
      id
      status          # "initial" | "processing" | "final" | "failed"
      createdAt
      finishedAt
      attachment {
        fileName
        fileUrl       # S3 signed URL for download
      }
      actions         # ["download"] when available
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

### Mutation: createPlanGoalAudit

```graphql
mutation CreatePlanGoalAudit($planId: ID!) {
  createPlanGoalAudit(planId: $planId) {
    id
    status
  }
}
```

**Response when locked (another audit in progress):**
```json
{
  "errors": [{ "message": "Você não possui permissão" }]
}
```

### Plan usersCount

```graphql
query Plan($id: ID!) {
  plans(id: $id) {
    nodes {
      id
      usersCount    # Total eligible users in the plan
    }
  }
}
```

## Status States

| Status | Description | UI Behavior |
|--------|-------------|-------------|
| `initial` | Just created | Show spinner |
| `processing` | Being processed | Show spinner |
| `final` | Complete, file ready | Show download button |
| `failed` | Error (no combinations) | Show error state |

## CSV Output Format

Columns (localized headers):

| Column | pt-BR | en | Description |
|--------|-------|-----|-------------|
| goal_type | Tipo de Meta | Goal Type | "Meta de grupo" or "Meta de usuário" |
| owner_identifier | Identificador | Identifier | external_id (group) or primary_identifier_value (user) |
| owner_name | Dono | Owner | Group name or User name |
| variable_key | Chave da Variável | Variable Key | Variable key |
| variable_name | Variável | Variable | Variable name |
| period_starts_at | Início do Período | Period Start | Period start date |
| period_ends_at | Fim do Período | Period End | Period end date |
| value | Valor | Value | Formatted goal value (empty if no goal) |

### Example CSV

```csv
Tipo de Meta,Identificador,Dono,Chave da Variável,Variável,Início do Período,Fim do Período,Valor
Meta de grupo,GRP001,Vendas SP,qualidade,Qualidade,2025-01-01,2025-01-31,90%
Meta de usuário,12345,João Silva,volume,Volume,2025-01-01,2025-01-31,100
Meta de usuário,67890,Maria Santos,volume,Volume,2025-01-01,2025-01-31,
```

## Database Schema

### plan_goal_audit_rows

| Column | Type | Description |
|--------|------|-------------|
| audit_id | bigint | FK to audits |
| goal_type | string | "GroupGoal" or "UserGoal" |
| owner_identifier | string | external_id or primary_identifier_value |
| owner_name | string | Group or User name |
| variable_key | string | Variable key |
| variable_name | string | Variable name |
| period_starts_at | date | Period start |
| period_ends_at | date | Period end |
| value | string | Formatted goal value |

## Constraints

- **Performance:** Producer/consumer pattern for large datasets
- **Locking:** Only one audit per plan at a time (Redis lock)
- **History:** All generated reports kept for reference
- **Backward compatibility:** Existing finalization flow unchanged

## Documents

- [KNOWLEDGE.md](./KNOWLEDGE.md) - Problem analysis and context
- [PROCESS.md](./PROCESS.md) - Business process flow
- [DOMAIN.md](./DOMAIN.md) - Domain concepts
- [app/TASKS.md](./app/TASKS.md) - Backend tasks
- [app-webclient/TASKS.md](./app-webclient/TASKS.md) - Frontend tasks

## Completed

All phases implemented and deployed to production:
- ✅ Backend with support for both goal types
- ✅ CSV format with all new columns
- ✅ Locales for all 9 languages
- ✅ Frontend implementation complete
