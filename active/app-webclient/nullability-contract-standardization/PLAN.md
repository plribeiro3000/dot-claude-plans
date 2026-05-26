# PLAN — Nullability Contract Standardization

## Parent Plan

[GraphQL Type Contract Standardization](../graphql-type-contract-standardization/PLAN.md)

## Objective

Align nullability markers (`!` = required, no `!` = optional) in frontend GraphQL declarations with the backend's actual type definitions. Eliminate defensive fallback patterns that mask type mismatches.

## Problem

The frontend GraphQL declarations don't consistently match backend nullability:

1. **Mutations with `ID!` when backend is `required: false`** — Frontend declares a field as non-null, but backend accepts null. If the value is missing, GraphQL rejects the request before it reaches the backend
2. **Queries with `ID!` when backend uses `option` (optional)** — Same issue for query filters. `option` in graphql-ruby means the argument is optional, but frontend declares it as required
3. **`|| ''` fallback pattern** — When developers know a value might be null but the type is `!`, they add `|| ''` to avoid TypeScript errors. This sends an empty string instead of null, which causes the resolver to try finding a record with ID `""` instead of properly omitting the argument
4. **String `"true"` for Boolean fields** — Old string interpolation treated everything as strings. After migration, some boolean fields still receive string `"true"` instead of boolean `true`

## Known Issues Found During Audit

### Category 1: Mutation ID! when backend is required: false

Found in the GraphQL Variables Migration audit (Cat 1). Frontend uses `$id: ID!` but backend mutation has `required: false`.

### Category 4: Query ID! when backend uses option (optional)

Found in the GraphQL Variables Migration audit (Cat 4). Frontend uses `$id: ID!` in queries but backend resolver uses `option(:id, type: ID)` which is optional.

**Example (found in PR #5967):**
- `acceptment-document-show.component.ts` — `$acceptmentDocumentId: ID!` and `$documentId: ID!` in queries, but backend uses `option(:acceptment_document_id, type: ID)` and `option(:document_id, type: ID)` (both optional)

### Category 5: String "true" to Boolean

Found in the GraphQL Variables Migration audit (Cat 5). Frontend passes `"true"` (string) where GraphQL expects `Boolean`.

### Defensive `|| ''` Pattern

Discovered during PR #5967 review (Copilot review comments + manual analysis). The pattern `value || ''` is used for ID fields in GraphQL variables, sending empty string instead of null when the value is missing.

**Files with `|| ''` for ID fields:**

| File | Code | GraphQL Type |
|------|------|-------------|
| plan-statement-accept.component.ts:56 | `id: this.planStatementId \|\| ''` | `$id: ID!` |
| statement-accept.component.ts:56 | `id: this.statementId \|\| ''` | `$id: ID!` |
| payment-report.component.ts:194 | `paymentId: this.form.value.paymentId \|\| ''` | `$paymentId: ID!` |
| user/update/user-update.component.ts:91 | `id: customFields.id \|\| ''` | Inside `[FieldInputGraphql!]` |

**Origin:** This is a pre-existing defensive pattern. The old string interpolation code had `${value ? value : ''}` which was faithfully translated to `value || ''` during migration. The migration preserved the behavior but didn't fix the underlying type mismatch.

**Many more `|| ''` exist for String fields** (name, key, description, etc.) where empty string is a valid value. Only the ID-field occurrences are problematic.

## Target State

- Every `!` in a frontend GraphQL declaration matches a `required: true` or `argument` (not `option`) in the backend
- No `|| ''` on ID fields — use nullable type (`ID` without `!`) and pass `null` when value is missing
- Boolean fields receive `true`/`false` (boolean), not `"true"`/`"false"` (string)
- String fields can keep `|| ''` where empty string is a semantically valid value

## Scope

- **Frontend**: All `.component.ts` and `.service.ts` files with GraphQL declarations
- **Backend**: Reference only (to verify correctness) — no backend changes expected for this front
- Exact file lists from the migration audit categories 1, 4, and 5

## Definition of Done

- [ ] Every frontend `!` marker verified against backend definition
- [ ] No `|| ''` on ID fields
- [ ] Boolean variables pass actual booleans
- [ ] No runtime GraphQL type errors from nullability mismatches

---

**Status:** DRAFT — Pending detailed planning
