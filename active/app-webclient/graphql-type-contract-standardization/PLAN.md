# PLAN — GraphQL Type Contract Standardization

## Objective

Establish a formal type contract between backend (Rails/graphql-ruby) and frontend (Angular/TypeScript/Apollo), following each technology's native conventions.

The frontend Angular/TypeScript/GraphQL stack is strongly typed, but the codebase was built following Ruby (dynamically typed) conventions. This creates a systematic mismatch that produces bugs, defensive code patterns, and maintainability issues.

## Current State

The GraphQL Variables Migration (completed) replaced string interpolation with typed GraphQL variables across the entire frontend. This exposed a fundamental problem: the frontend's type declarations don't consistently match the backend's type definitions. Issues found during the migration audit include:

- `ID!` used in frontend when backend declares `required: false` or `option` (optional)
- `|| ''` fallbacks passing empty strings as IDs instead of using nullable types
- String `"true"` passed where GraphQL expects `Boolean`
- `parseInt` used on IDs that should be strings
- Queries and mutations inline in components, not typed or reusable
- Unsafe error access patterns (`err.errors[0].extensions` without validation)
- Enum filter inputs rejected when sent as string literals

## Deliverables

This plan is delivered through 5 independent standardization efforts. Each has its own detailed plan. This plan is complete when all 5 are delivered.

### 1. ID Type Standardization

**Plan:** [id-type-standardization/PLAN.md](../id-type-standardization/PLAN.md)

Backend always declares and returns `ID` type (which accepts string or integer). Frontend always treats IDs as `string`. Removes `parseInt`, `Number()`, and manual conversions from both sides.

### 2. Nullability Contract Standardization

**Plan:** [nullability-contract-standardization/PLAN.md](../nullability-contract-standardization/PLAN.md)

Align `!` (required) markers in frontend GraphQL declarations with backend `required: true` / `option` definitions. Queries using `option` use type without `!`. Mutations with `argument required: true` use `!`. Eliminate `|| ''` defensive fallbacks in favor of proper nullable types.

### 3. GraphQL Operations Extraction

**Plan:** [graphql-standardization/PLAN.md](../graphql-standardization/PLAN.md)

Move queries and mutations from inside components into dedicated `.queries.ts` / `.mutations.ts` files with proper TypeScript types. Refactor services to have specific methods instead of generic `query()`/`mutation()` wrappers. *(Plan already exists)*

### 4. Error Handling Standardization

**Plan:** [error-handling-standardization/PLAN.md](../error-handling-standardization/PLAN.md)

Safe access to GraphQL error responses. Error callbacks on all mutations. Centralized error utility. *(Plan already exists)*

### 5. Input Type Standardization

**Plan:** [input-type-standardization/PLAN.md](../input-type-standardization/PLAN.md)

Standardize how enum values, input objects, and filter arguments are typed between backend and frontend. Resolve the abandoned `graphql-enumerize-enums` approach with a viable solution.

## What This Is NOT

- Not a frontend rewrite
- Not a framework or library change
- It is standardizing what already exists according to each technology's native conventions

## Execution Order

No strict dependency between the 5 fronts. Recommended order based on risk and impact:

1. **ID Type Standardization** — Smallest scope, highest bug density found during audit
2. **Nullability Contract** — Direct follow-up to the variables migration audit findings
3. **Error Handling** — Independent, already planned
4. **Input Type** — Requires backend changes, design decisions needed
5. **GraphQL Operations Extraction** — Largest scope, best done last when types are stable

## Definition of Done

- [ ] ID Type Standardization delivered
- [ ] Nullability Contract Standardization delivered
- [ ] GraphQL Operations Extraction delivered
- [ ] Error Handling Standardization delivered
- [ ] Input Type Standardization delivered
- [ ] All frontend GraphQL declarations match backend type definitions
- [ ] No defensive `|| ''` patterns for typed GraphQL variables
- [ ] No `parseInt`/`Number()` conversions on IDs
- [ ] All GraphQL operations in dedicated typed files
- [ ] All error responses handled safely

---

**Status:** DRAFT — Pending approval
