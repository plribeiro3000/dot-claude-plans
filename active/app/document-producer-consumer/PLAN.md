# Document Producer/Consumer Pattern

## Overview

Refactoring dos Document workers para usar padrão Producer/Consumer/Finalizer com processamento paralelo e idempotência.

## PRs

### PR #4754 - DealDocument
- **Branch:** `feature/deal-document-producer-consumer`
- **Status:** ✅ PRONTO PARA MERGE
- **URL:** https://github.com/4shark/app/pull/4754

**Mudanças:**
- Substituiu `Processor` por `Producer/Consumer/Finalizer`
- Criou `DealDocument::Row` model para armazenamento temporário
- Migrations: `create_deal_document_rows` + índice único `(document_id, document_line)`
- Moveu `CLEANUP_BATCH_SIZE` de `Audit` para `ApplicationRecord`
- Batch deletion no Finalizer (evita timeout)

**Correções aplicadas:**
- `Document.find` → `DealDocument.find`
- `invalid_file` → `invalid_encoding` (manter mensagem original)
- Tratamento de CSV vazio (marca como `error!` e retorna)
- `TypeError` adicionado no `parsed_date`

---

### PR #4755 - GroupDocument
- **Branch:** `feature/group-document-idempotent`
- **Worktree:** `/private/tmp/4shark-worktrees/group-document`
- **Status:** ⏳ AGUARDANDO VALIDAÇÃO
- **URL:** https://github.com/4shark/app/pull/4755

**Mudanças:**
- Tornou Producer idempotente (reset computation, delete rows antes de reprocessar)
- Batch deletion no Finalizer
- Índice único: `(document_id, line)`

**Correções aplicadas:**
- Tratamento de CSV vazio

---

### PR #4756 - IndicatorDocument
- **Branch:** `feature/indicator-document-idempotent`
- **Worktree:** `/private/tmp/4shark-worktrees/indicator-document`
- **Status:** ⏳ AGUARDANDO VALIDAÇÃO
- **URL:** https://github.com/4shark/app/pull/4756

**Mudanças:**
- Tornou Producer idempotente
- Dropou índice antigo `(document_id, user_identifier_value, subsidiary_external_id, variable_key, compiled_at)`
- Criou índice novo: `(document_id, document_line, variable_key)`
- Batch deletion no Finalizer

**Correções aplicadas:**
- `Document.find` → `IndicatorDocument.find`
- Tratamento de CSV vazio
- `TypeError` adicionado no `parsed_date`

---

## Padrões Estabelecidos

### 1. Índice Único
- Deve ser por `(document_id, document_line)` - relacionado ao ARQUIVO, não ao recurso
- IndicatorDocument inclui `variable_key` porque uma linha CSV pode gerar múltiplas rows (formato horizontal)

### 2. CSV Vazio
```ruby
if row_ids.empty?
  Document.with_uncached_connection { document.error! }

  return
end
```

### 3. parsed_date
```ruby
def parsed_date(date)
  Date.parse(date.to_s)
rescue ArgumentError, TypeError
  nil
end
```

### 4. Find
- Usar a classe específica: `DealDocument.find`, não `Document.find`

### 5. Constantes Herdadas
- `Row::CLEANUP_BATCH_SIZE` funciona porque Ruby herda constantes da superclasse
- Copilot estava ERRADO ao dizer que daria NameError

### 6. Mensagem de Erro
- DealDocument usa `invalid_encoding` (era assim no original)
- IndicatorDocument e GroupDocument usam `invalid_file` (era assim no original)

---

## Próximos Passos

1. [ ] Validar PR #4755 (GroupDocument)
2. [ ] Validar PR #4756 (IndicatorDocument)
3. [ ] Fazer merge dos 3 PRs
4. [ ] Mover esta pasta para `~/.claude/plans/completed/`
