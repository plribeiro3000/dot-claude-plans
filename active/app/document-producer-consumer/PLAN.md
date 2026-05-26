# Document Producer/Consumer Pattern

## Overview

Refactor the Document workers to use the Producer/Consumer/Finalizer pattern with parallel processing and idempotency.

## PRs

### PR #4754 - DealDocument
- **Branch:** `feature/deal-document-producer-consumer`
- **Status:** ✅ READY TO MERGE
- **URL:** https://github.com/4shark/app/pull/4754

**Changes:**
- Replaced `Processor` with `Producer/Consumer/Finalizer`
- Created `DealDocument::Row` model for temporary storage
- Migrations: `create_deal_document_rows` + unique index `(document_id, document_line)`
- Moved `CLEANUP_BATCH_SIZE` from `Audit` to `ApplicationRecord`
- Batch deletion in the Finalizer (avoids timeout)

**Fixes applied:**
- `Document.find` → `DealDocument.find`
- `invalid_file` → `invalid_encoding` (keep the original message)
- Handling of empty CSV (mark as `error!` and return)
- `TypeError` added to `parsed_date`

---

### PR #4755 - GroupDocument
- **Branch:** `feature/group-document-idempotent`
- **Worktree:** `/private/tmp/4shark-worktrees/group-document`
- **Status:** ⏳ AWAITING VALIDATION
- **URL:** https://github.com/4shark/app/pull/4755

**Changes:**
- Made Producer idempotent (reset computation, delete rows before reprocessing)
- Batch deletion in the Finalizer
- Unique index: `(document_id, line)`

**Fixes applied:**
- Handling of empty CSV

---

### PR #4756 - IndicatorDocument
- **Branch:** `feature/indicator-document-idempotent`
- **Worktree:** `/private/tmp/4shark-worktrees/indicator-document`
- **Status:** ⏳ AWAITING VALIDATION
- **URL:** https://github.com/4shark/app/pull/4756

**Changes:**
- Made Producer idempotent
- Dropped old index `(document_id, user_identifier_value, subsidiary_external_id, variable_key, compiled_at)`
- Created new index: `(document_id, document_line, variable_key)`
- Batch deletion in the Finalizer

**Fixes applied:**
- `Document.find` → `IndicatorDocument.find`
- Handling of empty CSV
- `TypeError` added to `parsed_date`

---

## Established Patterns

### 1. Unique Index
- Must be on `(document_id, document_line)` — tied to the FILE, not to the resource
- IndicatorDocument includes `variable_key` because a single CSV line can produce multiple rows (horizontal format)

### 2. Empty CSV
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
- Use the specific class: `DealDocument.find`, not `Document.find`

### 5. Inherited Constants
- `Row::CLEANUP_BATCH_SIZE` works because Ruby inherits constants from the superclass
- Copilot was WRONG when it claimed this would raise `NameError`

### 6. Error Message
- DealDocument uses `invalid_encoding` (that was the original)
- IndicatorDocument and GroupDocument use `invalid_file` (that was the original)

---

## Next Steps

1. [ ] Validate PR #4755 (GroupDocument)
2. [ ] Validate PR #4756 (IndicatorDocument)
3. [ ] Merge the 3 PRs
4. [ ] Move this folder to `~/.claude/plans/completed/`
