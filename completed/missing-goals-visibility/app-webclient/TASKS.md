# TASKS - Missing Goals Visibility (Frontend)

## Overview

Frontend implementation for the Plan Goals Audit feature.

**Status:** ✅ COMPLETED - In Production

## Scope Summary

1. **New audit list page** - `/plans/:planId/goals-audits`
2. **Navigation buttons** - Both in plan show AND plan finish pages
3. **Enhanced finish page** - Show `usersCount` for context (e.g., "40 goals out of 50 eligible users")
4. **Translations** - All three languages: pt-BR, en, es

## API Contract

### Available Endpoints

#### Query: planGoalAudits
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
      actions         # ["download"] when status is "final"
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

#### Mutation: createPlanGoalAudit
```graphql
mutation CreatePlanGoalAudit($planId: ID!) {
  createPlanGoalAudit(planId: $planId) {
    id
    status
  }
}
```

#### Plan usersCount (new field)
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

### Status States

| Status | Description | UI Behavior |
|--------|-------------|-------------|
| `initial` | Just created | Show spinner/loading |
| `processing` | Being processed in background | Show spinner/loading |
| `final` | Complete, file ready | Show download button |
| `failed` | Error (no eligible combinations) | Show error message |

### Error Handling

**When audit is locked (another in progress):**
```json
{
  "errors": [{ "message": "Você não possui permissão" }]
}
```

## Tasks

### 1. Model & Service

- [x] Create `plan-goals-audit.model.ts`
  ```typescript
  interface PlanGoalAudit {
    id: string;
    status: 'initial' | 'processing' | 'final' | 'failed';
    createdAt: string;
    finishedAt?: string;
    attachment?: {
      fileName: string;
      fileUrl: string;
    };
    actions: string[];
  }
  ```

- [x] Create `plan-goals-audit.service.ts`
  - `list(planId: string): Observable<PlanGoalAudit[]>`
  - `create(planId: string): Observable<PlanGoalAudit>`

### 2. Plan Show Page - Add Navigation Button

**Location:** `src/app/plan/show/plan-show.component.ts`

- [x] Add button "Auditoria de Metas" (Goals Audit)
- [x] Button navigates to `/plans/:planId/goals-audits`
- [x] Visible only if `plan?.actions?.includes('audit')`

### 2b. Plan Finish Page - Add Navigation Button + Users Count

**Location:** `src/app/plan/finish/plan-finish.component.ts`

- [x] Add `usersCount` field to Plan query
- [x] Display users count for context (e.g., "50 usuários elegíveis")
- [x] Add button "Auditoria de Metas" near the goal counts
- [x] Button navigates to `/plans/:planId/goals-audits`
- [x] Visible only if `plan?.actions?.includes('audit')`

### 3. Plan Goals Audit List Page (NEW)

**Route:** `/plans/:planId/goals-audits` (or similar)

- [x] Create new component for listing audits
- [x] Page header with plan name/context
- [x] Button "Gerar Nova Auditoria" (Generate New Audit)
  - Only visible if user has `plan_goal_audit_creation` permission
  - Calls `createPlanGoalAudit` mutation
  - Refreshes list after creation
  - Handle locked error (show "Audit in progress" message)
- [x] List of all audits for the plan:
  - Created date
  - Status (with icon/badge)
  - Finished date (when available)
  - Download button (when status is "final" and `actions.includes('download')`)
- [x] Implement polling/refresh for status updates while any audit is processing
- [x] Handle empty state (no audits yet - show message and create button)

### 4. Download Integration

- [x] Use `attachment.fileUrl` for download
- [x] File is CSV format, localized headers
- [x] Download button only visible when `actions.includes('download')`

### 5. Permissions

**Note:** Navigation visibility uses `plan.actions.includes('audit')` (requires `plan_goal_audit_listing` permission)

- [x] Use `planGoalAuditPermissions(planId)` resolver for creation permission:
  ```graphql
  query PlanGoalAuditPermissions($planId: ID!) {
    planGoalAuditPermissions(planId: $planId) {
      userId
      permissions  # Returns ["plan_goal_audit_creation"] if user can create
    }
  }
  ```
- [x] Check permissions:
  - `plan.actions.includes('audit')` - to show navigation button (from Plan query)
  - `permissions.includes('plan_goal_audit_creation')` - to show "Generate Audit" button
  - `audit.actions.includes('download')` - to show download button (from audit object)

### 6. Translations (All 3 Languages)

**Files:**
- `src/translations/pt-BR.json`
- `src/translations/en.json`
- `src/translations/es.json`

- [x] Add translations for all three languages:
  - Page title ("Auditoria de Metas" / "Goals Audit" / "Auditoría de Metas")
  - Button labels ("Gerar Nova Auditoria" / "Generate New Audit" / "Generar Nueva Auditoría")
  - Status labels (Processando/Processing/Procesando, Concluído/Completed/Completado, Falhou/Failed/Falló)
  - Error messages (audit locked, no permission, etc.)
  - Empty state message
  - Users count label ("usuários elegíveis" / "eligible users" / "usuarios elegibles")

## UI Flow

```
┌─────────────────────────────────────────────────────────┐
│                    Plan Show Page                        │
├─────────────────────────────────────────────────────────┤
│  Plan: Sales Q4 2025                                     │
│  [Edit] [Approve] [Auditoria de Metas →]                │
│  ... plan details ...                                    │
└─────────────────────────────────────────────────────────┘
                           │
         ┌─────────────────┴─────────────────┐
         │                                   │
         ▼                                   ▼
┌─────────────────────────────────────────────────────────┐
│                   Plan Finish Page                       │
├─────────────────────────────────────────────────────────┤
│  Finalizar Plano: Sales Q4 2025                         │
│  👥 50 usuários elegíveis                               │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Variável: Volume                                   │ │
│  │ Metas de grupo: 12  |  Metas de usuário: 40       │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  [Auditoria de Metas →]  [Finalizar]                    │
└─────────────────────────────────────────────────────────┘
                           │
                           │ Click "Auditoria de Metas"
                           ▼
┌─────────────────────────────────────────────────────────┐
│              Plan Goals Audits List                      │
│              Plan: Sales Q4 2025                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  [← Back to Plan]            [Gerar Nova Auditoria]     │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ 📄 Dec 5, 2025 14:32                                │ │
│  │ Status: ✅ Concluído                                │ │
│  │ Finalizado: Dec 5, 2025 14:33                      │ │
│  │ [Download CSV]                                      │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ 📄 Dec 5, 2025 10:15                                │ │
│  │ Status: ⏳ Processando...                           │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ 📄 Dec 4, 2025 16:45                                │ │
│  │ Status: ❌ Falhou                                   │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Notes

- CSV file has localized headers based on user's locale
- Lock prevents multiple concurrent audits for same plan
- All audits are kept for history (never auto-deleted)
- Polling recommended for status updates (every 5-10 seconds while any audit is processing)
- Navigation button should be in plan view, NOT trigger creation automatically
- User decides when to generate a new audit from the list page

## CSV Columns (for reference)

The audit generates a CSV with the following columns (headers are localized):

| Column | pt-BR | Description |
|--------|-------|-------------|
| goal_plan_created_at | Inserção da Meta no Plano | When the user started participating in the plan |
| goal_plan_status | Utilização da Meta | Whether the goal is being used ("Sim"/"Não") |
| goal_type | Tipo de Meta | User or Group goal |
| goal_updated_at | Última Atualização da Meta | Last modification to the goal |
| owner_identifier | Identificador | User/Group identifier |
| owner_name | Dono | User/Group name |
| period_ends_at | Fim do Período | Period end date |
| period_starts_at | Início do Período | Period start date |
| plan_finished_at | Data de Finalização do Plano | When the plan was finalized |
| value | Valor | Goal value |
| variable_key | Chave da Variável | Variable key |
| variable_name | Variável | Variable name |
