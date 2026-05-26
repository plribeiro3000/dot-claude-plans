# PLAN — Input Type Standardization

## Parent Plan

[GraphQL Type Contract Standardization](../graphql-type-contract-standardization/PLAN.md)

## Objective

Standardize how input types (enums, input objects, filter arguments) are handled between backend and frontend.

## Problem

1. **Enum inputs rejected as string literals** — GraphQL enums must be sent as unquoted identifiers (`status: final`), but the frontend sends them as strings (`status: "final"`). This was documented in the abandoned `graphql-enumerize-enums` plan. The current workaround is using String type for all enum inputs on the backend, with no validation
2. **Input type names incorrect** — Some frontend mutations reference input type names that don't exist in the backend schema (e.g., using `FieldInput` when backend defines `FieldInputGraphql`). Found in the GraphQL Variables Migration audit (Cat 7)
3. **No input validation on enum values** — Backend accepts any string for enum filter fields. Invalid values cause silent failures or unexpected results instead of clear error messages

## Prior Work

The `graphql-enumerize-enums` plan (now abandoned) attempted to solve this by adding GraphQL Enum types for enumerize fields. It failed because:
- GraphQL spec requires enum values as unquoted identifiers
- String literals fail at query validation stage, before coercion
- The `coerce_input` workaround doesn't work (validation happens before coercion)

The abandoned plan's recommended solution (Option 1: String type with shared validation module) remains viable and should be revisited here.

**Reference:** [graphql-enumerize-enums/PLAN.md](../../abandoned/graphql-enumerize-enums/PLAN.md)

## Target State

- Enum filter inputs use String type on backend with server-side validation against allowed values
- Invalid enum values return 400 with clear error message listing allowed values
- Input object type names in frontend match backend schema exactly
- Frontend TypeScript types reflect the actual input structure

## Scope

- **Backend**: Resolver filter arguments with enum values (~20 resolvers), validation infrastructure
- **Frontend**: Input type name corrections, TypeScript type definitions for inputs
- Exact file lists from the migration audit (Cat 7) and the abandoned enum plan

## Definition of Done

- [ ] All enum filter inputs validated server-side
- [ ] Invalid enum values return 400 (not 500 or silent failure)
- [ ] All frontend input type names match backend schema
- [ ] Abandoned `graphql-enumerize-enums` solution implemented via viable approach

---

**Status:** DRAFT — Pending detailed planning
