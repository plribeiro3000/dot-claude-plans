# Plano de Correção - PR #5792 (old-front-secure-downloads)

> **Note:** This fix plan refers to the legacy frontend that still exists on the `old-front` branch of the app-webclient repository.

## Problema Identificado

A migração do Secure Downloads para a branch `old-front` foi feita incorretamente:
- **Arquivos HTML foram copiados inteiros do master**, mudando layout, estrutura e classes CSS
- **Arquivos TS foram copiados inteiros do master**, trazendo dependências que não existem no old-front
- **Resultado**: ~7000 linhas alteradas quando deveria ser muito menos

### Exemplo do Erro (user-audit.component.html)

**Original do old-front:**
```html
<div class="row">
  <div class="col-md-6 col-12">
    <h2 class="section-title" translate>user_audit.other</h2>
    <ul class="breadcrumb">
      <li>
        <p [routerLink]="['/users/']">{{ 'breadcrumb.list' | translate }} /</p>
      </li>
```

**O que foi feito (ERRADO - copiado do master):**
```html
<section>
  <h1 class="title">{{ 'user_audit.other' | translate }}</h1>
  <div class="breadcrumbs">
    <span class="breadcrumb" [routerLink]="['/users/']">{{ 'user.other' | translate }}</span>
```

**O que deveria ter sido feito (CORRETO - mudança mínima):**
- Manter TODA a estrutura HTML original
- Apenas trocar `href="{{ element.attachment?.file?.file?.publicUrl }}"` para `(click)="download($event, element)"`

---

## Erro de Build Atual

```
Error: src/app/upload/upload.component.ts:131:35 - error TS2339: Property 'type' does not exist on type 'Document'.
```

**Causa**: O `upload.component.ts` foi copiado do master e usa `document.type`, mas o modelo `Document` do old-front não tem essa propriedade.

---

## Estatísticas do PR Atual

| Tipo | Quantidade |
|------|------------|
| Arquivos criados (corretos) | 29 |
| Arquivos modificados | 99 |
| Linhas adicionadas | ~3,277 |
| Linhas removidas | ~5,431 |

---

## Plano de Correção

### Fase 1: Reverter TODOS os arquivos modificados para o estado original do old-front

```bash
# Listar todos os arquivos modificados
git diff --diff-filter=M --name-only old-front...old-front-secure-downloads

# Reverter cada arquivo para a versão do old-front
git checkout old-front -- <cada-arquivo>
```

**Arquivos a reverter (99 arquivos):**

#### HTML (34 arquivos):
- src/app/acceptment-document/acceptment-document.component.html
- src/app/calendar-audit/calendar-audit.component.html
- src/app/campaign/show/campaign-show.component.html
- src/app/client-document/client-document.component.html
- src/app/collaborative-deal-document/collaborative-deal-document.component.html
- src/app/commission-indicator-audit/commission-indicator-audit.component.html
- src/app/commission-report-creation-batch/show/commission-report-creation-batch-show.component.html
- src/app/commission/show/commission-show.component.html
- src/app/dashboard/calendar/dashboard-calendar.component.html
- src/app/deal-document/deal-document.component.html
- src/app/easy-product/plan-slice-commission/show/plan-slice-commission-show.component.html
- src/app/goal-document/goal-document.component.html
- src/app/group-audit/group-audit.component.html
- src/app/group-document/group-document.component.html
- src/app/home/home.component.html
- src/app/incentive-document/incentive-document.component.html
- src/app/indicator-document/indicator-document.component.html
- src/app/monthly-usage/monthly-usage.component.html
- src/app/payment/show/payment-show.component.html
- src/app/plan-statement-audit/plan-statement-audit.component.html
- src/app/plan-statement/plan-statement-show/plan-statement-show.component.html
- src/app/product-document/product-document.component.html
- src/app/responsible-audit/responsible-audit.component.html
- src/app/statement-audit/statement-audit.component.html
- src/app/statement/statement-show/statement-show.component.html
- src/app/upload/upload.component.html
- src/app/user-audit/user-audit.component.html
- src/app/user-document/user-document.component.html
- src/app/user-identifier-audit/user-identifier-audit.component.html
- src/app/user-identifier-document/user-identifier-document.component.html
- src/app/user/show/user-show.component.html
- src/app/user/user.component.html
- src/app/variable-audit/variable-audit.component.html
- src/app/variable-document/variable-document.component.html

#### TypeScript Components (30+ arquivos):
- Todos os *.component.ts listados no diff

#### TypeScript Services (15+ arquivos):
- Todos os *.service.ts que NÃO são temporary*.service.ts

#### TypeScript Models (4 arquivos):
- src/app/accumulated-deal/accumulated-deal.model.ts
- src/app/attachment/attachment.model.ts
- src/app/campaign/campaign.model.ts
- src/app/core/authentication/user-credential.model.ts

#### Outros:
- src/assets/scripts/card.js

### Fase 2: Manter APENAS os arquivos de serviços temporários (já corretos)

**Arquivos a MANTER (29 arquivos criados):**
- src/app/acceptment-document/acceptment-document.service.ts (novo)
- src/app/calendar-audit/temporary-calendar-audit.service.ts
- src/app/campaign/temporary-campaign.service.ts
- src/app/client-document/temporary-client-document.service.ts
- src/app/collaborative-deal-document/temporary-collaborative-deal-document.service.ts
- src/app/commission-indicator-audit/temporary-commission-indicator-audit.service.ts
- src/app/commission/temporary-commission.service.ts
- src/app/deal-document/temporary-deal-document.service.ts
- src/app/deal-extraction/deal-extraction.service.ts (novo)
- src/app/goal-document/temporary-goal-document.service.ts
- src/app/group-audit/temporary-group-audit.service.ts
- src/app/group-document/temporary-group-document.service.ts
- src/app/incentive-document/temporary-incentive-document.service.ts
- src/app/indicator-document/temporary-indicator-document.service.ts
- src/app/monthly-usage/temporary-monthly-usage-audit.service.ts
- src/app/payment-exportation/temporary-payment-exportation.service.ts
- src/app/payment-report/temporary-payment-report.service.ts
- src/app/plan-statement-audit/temporary-plan-statement-audit.service.ts
- src/app/product-document/temporary-product-document.service.ts
- src/app/profile/temporary-profile.service.ts
- src/app/responsible-audit/temporary-responsible-audit.service.ts
- src/app/shared/constants/document-resolver.map.ts
- src/app/statement-audit/temporary-statement-audit.service.ts
- src/app/user-audit/temporary-user-audit.service.ts
- src/app/user-document/temporary-user-document.service.ts
- src/app/user-identifier-audit/temporary-user-identifier-audit.service.ts
- src/app/user-identifier-document/temporary-user-identifier-action-document.service.ts
- src/app/variable-audit/temporary-variable-audit.service.ts
- src/app/variable-document/temporary-variable-document.service.ts

### Fase 3: Fazer a migração CORRETA (mínima)

Para cada componente que precisa de Secure Downloads, fazer APENAS:

#### 3.1 No arquivo .component.ts:

```typescript
// 1. Adicionar import do temporary service
import { TemporaryXxxService } from './temporary-xxx.service';

// 2. Injetar no constructor
constructor(
  // ... outros serviços existentes
  private temporaryXxxService: TemporaryXxxService,
) {}

// 3. Adicionar método download()
download(event: Event, element: any) {
  event.preventDefault();

  const id = element.id; // ou element.attachment?.id dependendo do caso

  if (!id) {
    return;
  }

  this.temporaryXxxService.get(id).valueChanges.subscribe((response: any) => {
    const url = response.data?.temporaryXxx?.url;

    if (url) {
      window.location.href = url;
    }
  });
}
```

#### 3.2 No arquivo .component.html:

**ANTES:**
```html
<a href="{{ element.attachment?.file?.file?.publicUrl }}">
  <i class="fas fa-cloud-download-alt"></i>
  {{ element.attachment?.file.file.filename }}
</a>
```

**DEPOIS:**
```html
<a href="#" (click)="download($event, element)">
  <i class="fas fa-cloud-download-alt"></i>
  {{ element.attachment?.filename }}
</a>
```

#### 3.3 No arquivo .service.ts (de listagem):

**ANTES:**
```graphql
attachment {
  file {
    file {
      publicUrl
      filename
    }
  }
}
```

**DEPOIS:**
```graphql
attachment {
  id
  filename
}
```

---

## Lista de Componentes a Migrar Corretamente

| Componente | Temporary Service | Tipo de Download |
|------------|-------------------|------------------|
| acceptment-document | temporaryAcceptmentDocument | attachment |
| calendar-audit | temporaryCalendarAudit | audit |
| campaign-show | temporaryCampaign | campaign |
| client-document | temporaryClientDocument | attachment |
| collaborative-deal-document | temporaryCollaborativeDealDocument | attachment |
| commission-indicator-audit | temporaryCommissionIndicatorAudit | audit |
| commission-report-creation-batch-show | (usa commission) | batch |
| commission-show | temporaryCommission | attachment |
| dashboard-calendar | temporaryCampaign | campaign |
| deal-document | temporaryDealDocument | attachment |
| goal-document | temporaryGoalDocument | attachment |
| group-audit | temporaryGroupAudit | audit |
| group-document | temporaryGroupDocument | attachment |
| home | temporaryCampaign | campaign |
| incentive-document | temporaryIncentiveDocument | attachment |
| indicator-document | temporaryIndicatorDocument | attachment |
| monthly-usage | temporaryMonthlyUsageAudit | audit |
| payment-show | (vários) | payment |
| plan-statement-audit | temporaryPlanStatementAudit | audit |
| plan-statement-show | (vários) | statement |
| product-document | temporaryProductDocument | attachment |
| responsible-audit | temporaryResponsibleAudit | audit |
| statement-audit | temporaryStatementAudit | audit |
| statement-show | (vários) | statement |
| upload | (document-resolver-map) | upload |
| user-audit | temporaryUserAudit | audit |
| user-document | temporaryUserDocument | attachment |
| user-identifier-audit | temporaryUserIdentifierAudit | audit |
| user-identifier-document | temporaryUserIdentifierActionDocument | attachment |
| user-show | temporaryProfile | profile |
| user (list) | (user) | user |
| variable-audit | temporaryVariableAudit | audit |
| variable-document | temporaryVariableDocument | attachment |

---

## Próximos Passos

1. **Decisão do usuário**: Confirmar se este plano está correto
2. **Executar Fase 1**: Reverter todos os 99 arquivos modificados
3. **Executar Fase 2**: Garantir que os 29 arquivos de serviços temporários estão intactos
4. **Executar Fase 3**: Fazer a migração mínima arquivo por arquivo
5. **Build e testes**: Validar que tudo funciona
6. **Atualizar PR**: Force push para atualizar o PR #5792

---

## Estimativa de Mudanças Corretas

| Tipo | Estimativa |
|------|------------|
| Arquivos modificados | ~65 (vs 99 atualmente) |
| Linhas por HTML | ~5-10 linhas por arquivo |
| Linhas por TS | ~15-20 linhas por arquivo |
| Total aproximado | ~600-800 linhas (vs ~8700 atualmente) |
