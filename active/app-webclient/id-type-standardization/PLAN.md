# PLAN — ID Type Standardization

## Parent Plan

[GraphQL Type Contract Standardization](../graphql-type-contract-standardization/PLAN.md)

## Objective

Standardize how IDs are declared, passed, and consumed across the backend (Rails/graphql-ruby) and frontend (Angular/TypeScript/Apollo).

## Problem

The codebase has inconsistent ID handling:

1. **Backend** — Some mutations use `argument :id, ID, required: true`, others use `Integer` or accept both string and integer inconsistently
2. **Frontend** — Some places use `parseInt(id)` or `Number(id)` before passing to GraphQL, others pass as string. Some use `ID!` type, others pass IDs without type declaration
3. **GraphQL `ID` type** — Per the GraphQL spec, `ID` is a scalar that serializes as a `String` but can be parsed from both string and integer input. The codebase doesn't leverage this consistently

## Target State

- **Backend**: All ID arguments and fields use the GraphQL `ID` type. Always returns IDs as strings in responses
- **Frontend**: All IDs are `string` in TypeScript. No `parseInt`, `Number()`, or numeric conversions on IDs. GraphQL declarations use `ID` or `ID!` consistently
- **Contract**: `ID` means string. Period

## Known Issues Found During Audit

| Issue | Files | Source |
|-------|-------|--------|
| `parseInt` used on IDs passed to GraphQL variables | Multiple files across migrated codebase | GraphQL Variables Migration audit (Cat 6) |
| `Number()` conversions on IDs | Found in several components | GraphQL Variables Migration audit |

## Scope

- **Frontend**: All `.component.ts` and `.service.ts` files that pass IDs to GraphQL operations
- **Backend**: All `graphql_mutations/` and `graphql_resolvers/` files with ID arguments
- Exact file lists to be compiled during task creation

## Definition of Done

- [ ] No `parseInt` or `Number()` on IDs in frontend code
- [ ] All GraphQL ID arguments use `ID` type in backend
- [ ] All TypeScript ID variables typed as `string`
- [ ] All GraphQL declarations in frontend use `ID` or `ID!` for ID fields

---

**Status:** DRAFT — Pending detailed planning
