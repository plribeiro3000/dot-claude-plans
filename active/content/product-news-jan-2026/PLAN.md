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

## Draft (with image placeholders)

The text below is ready for use. The `[IMAGE X]` markers indicate where to insert each screenshot.

**Important:** The email content is in Portuguese (pt-BR) as it's intended for Brazilian clients.

---

Olá,

Feliz Ano Novo! Desejamos que 2026 seja um ano de muito sucesso e conquistas para você e toda sua equipe.

Iniciamos o ano com uma série de novidades que gostaríamos de compartilhar com vocês, fruto do trabalho contínuo de evolução da plataforma 4Shark.


SEGURANÇA E ESTABILIDADE

Realizamos melhorias internas que aumentam a estabilidade e reduzem riscos de segurança, garantindo uma plataforma mais robusta e confiável para o dia a dia de vocês.


IDENTIFICAÇÃO COMPLETA NAS AUDITORIAS

Sabemos que a conciliação de dados entre sistemas é uma necessidade frequente, e que muitas vezes o CPF ou documento de identificação é a chave para essa integração.

Atendendo a essa solicitação, incluímos colunas de identificação (tipo do documento e valor, como CPF, RUT etc.) nas auditorias da plataforma, incluindo relatórios de usuários, extratos, metas e consumo mensal. Agora, ao exportar esses arquivos, vocês terão acesso direto à identificação de cada pessoa, facilitando a conciliação com folha de pagamento e outros sistemas internos.

E podem ficar tranquilos quanto à segurança desses dados: os arquivos de auditoria ficam disponíveis por até 15 dias e são apagados automaticamente após esse período. O acesso é restrito a usuários autenticados na plataforma.


NOVA AUDITORIA DE METAS DO PLANO

Acompanhar as metas configuradas em cada plano era um processo que exigia navegar por diversas telas da plataforma, dificultando a identificação rápida de possíveis inconsistências.

Entendendo essa necessidade, desenvolvemos uma nova funcionalidade de auditoria específica para metas. Com ela, vocês podem visualizar todas as metas associadas a um plano em um único relatório, identificando rapidamente quais usuários possuem metas configuradas, quais ainda precisam de atenção, e se os valores estão de acordo com o esperado.

Para acessar, abra o Plano desejado e clique em "Auditoria de Metas". Na listagem, clique em "+ Gerar Nova Auditoria" para criar um novo relatório.

[IMAGE 1: Plan view with "Auditoria de Metas" button]

[IMAGE 2: Goal audit listing with "+ Gerar Nova Auditoria" button]


ATUALIZAÇÃO DE METAS

Erros acontecem, e sabemos o quanto é frustrante perceber que uma meta foi cadastrada com o valor errado depois que o plano já foi vinculado.

Antes, para corrigir esse tipo de situação, era necessário cancelar o plano, abrir um chamado para nossa equipe realizar a correção da meta, e só então criar um novo plano. Esse processo gerava dependência, retrabalho e podia impactar o andamento das operações.

Agora isso mudou. Implementamos a possibilidade de atualizar o valor, valor base e sentido de uma meta a qualquer momento. A alteração fica registrada na meta e passa a valer nos próximos planos gerados.

O novo fluxo é simples: basta cancelar o plano atual, atualizar a meta com o valor correto, e gerar um novo plano. O novo plano já será criado com a meta atualizada. Tudo isso sem depender de chamados.

Essa atualização pode ser feita de três formas:
- Pela listagem de metas (no menu de ações da meta, selecione "Atualizar")
- Via API, para integrações automatizadas
- Por upload de arquivo, que antes funcionava apenas para cadastro e agora também permite atualização

[IMAGE 3: Screenshot of goal edit screen]


OUTRAS MELHORIAS

A busca geral da plataforma foi otimizada para funcionar melhor com caracteres especiais e acentuação, facilitando encontrar registros com nomes ou identificadores que contenham esses caracteres.


Estamos muito felizes em trazer essas evoluções para a plataforma, e esperamos que elas simplifiquem ainda mais o dia a dia de trabalho de vocês.

Agradecemos pela parceria e nos colocamos à disposição para eventuais dúvidas e sugestões através do nosso canal meajuda@4shark.com.br.

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
