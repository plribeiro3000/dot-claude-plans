# PLAN — GraphQL Variables Migration

## Objective

Migrate the entire frontend from string concatenation to GraphQL variables to fix "Unterminated string" bugs caused by special characters (`\r\n`, quotes, etc.) in user input.

## Analysis

**Total affected:** 140 files with string interpolation in GraphQL queries

### Files by Pattern

| Pattern | Files | Same Code Pattern? |
|---------|-------|-------------------|
| Attachment Services | 15 | ✅ Yes - all follow same upload pattern |
| Temporary Services | 28 | ✅ Yes - all follow same export/download pattern |
| Audit Services | 9 | ✅ Yes - all follow same listing pattern |
| Document Services | 11 | ✅ Yes - all follow same CRUD pattern |
| Document-Create Services | 16 | ✅ Yes - all follow same creation pattern |
| Core Services | ~38 | ❌ No - each has unique business logic |

### Strategy

Services with identical patterns can be grouped in a single PR (low risk, mechanical changes). Core services need individual attention.

---

## Workflow Decision

**Independent PRs in Parallel:**
- All branches from `develop`
- Multiple PRs created at once
- Batch review at end of day
- Merge in any order
- Single changelog entry at release

---

## Migration Process (per file)

**IMPORTANT:** For each file being migrated, follow these steps:

1. **Read the frontend file** - Identify the GraphQL query/mutation and parameters
2. **Find the backend definition** - Look up the corresponding mutation/query in `app/graphql_mutations/` or `app/graphql_types/`
3. **Check argument types** - The backend defines exact types (`ID`, `Int`, `String`, `Boolean`, etc.)
4. **Use exact same types in frontend** - Do NOT assume types. The backend is inconsistent (some use `Int` instead of `ID`, etc.)
5. **Update the frontend** - Apply the migration with correct types

This is slower but necessary to avoid type mismatches.

---

## Migration Pattern

### Before (string concatenation):

```typescript
const query = gql`
  query {
    incentives(search: "${search}", first: ${first}) {
      nodes { id, description }
    }
  }
`;
this.apollo.query({ query, variables: {} });
```

### After (GraphQL variables):

```typescript
const query = gql`
  query ListIncentives($search: String, $first: Int) {
    incentives(search: $search, first: $first) {
      nodes { id, description }
    }
  }
`;
this.apollo.query({ query, variables: { search, first } });
```

---

## Definition of Done (per PR)

- [x] All queries/mutations use GraphQL variables
- [x] No string concatenation in query strings
- [x] Dynamic values passed via `variables: { ... }`
- [x] Application compiles without errors

---

## Code Review Patterns (Copilot Comments)

### Comments to IGNORE (not our scope):

| Comment | Reason to Ignore |
|---------|------------------|
| `variables: variables` → `variables` (shorthand) | Our standard is explicit notation `{ key: value }` as per Pattern 3 |
| Empty string vs undefined for search | Backend handles both the same way |
| Loading state not cleared on early return | Pre-existing pattern, not scope of this refactoring |
| Unused `id` parameter in methods | Pre-existing pattern, not scope of this refactoring |

### Comments to RESOLVE:

| Comment | Resolution |
|---------|------------|
| `if (params.enabled)` won't pass `false` | Use `if (params.enabled !== undefined && params.enabled !== null)` for all boolean params |
| `$id: ID` vs `$id: ID!` inconsistency | Check backend schema and use exact same type |
| Number ID vs String ID | IDs should be strings - use `String(id)` when needed |

---

## Coding Patterns (Established Rules)

These patterns MUST be followed in all migrations:

### Pattern 1: Queries INLINE (no private methods)
```typescript
// WRONG - private method
this.service.query('name', this.getQuery()).subscribe(...)

// CORRECT - inline
this.service.query('name', `query GetData($id: ID) { ... }`, variables).subscribe(...)
```

### Pattern 2: Conditional variables with `if` statements
```typescript
// WRONG
const variables = { search: search || undefined };

// CORRECT
const variables: Record<string, any> = { first: 9 };
if (search) {
  variables.search = search;
}
```

### Pattern 3: Explicit object notation
```typescript
// WRONG (shorthand)
{ variables }

// CORRECT (explicit)
{ variables: variables }
```

### Pattern 4: Declare `const variables` BEFORE the GraphQL call
```typescript
// WRONG
this.service.query('name', query, { id: this.id })

// CORRECT
const variables: Record<string, any> = { id: this.id };
this.service.query('name', query, variables)
```

### Pattern 5: IDs - DO NOT use parseInt()
```typescript
// WRONG - converts string ID to number
variables.id = parseInt(event, 10);
variables.companyId = parseInt(params.companyId, 10);
const id = parseInt(event, 10);

// CORRECT - keep ID as string (GraphQL ID type is string)
variables.id = event;
variables.companyId = params.companyId;
const id = event;
```
**Note:** IDs come from GraphQL as strings and should stay as strings. The `ID` scalar in GraphQL serializes as string. Do NOT convert with `parseInt()` unless the backend explicitly declares `Integer` type.

### Pattern 6: Boolean parameters
```typescript
// WRONG - won't send false
if (params.enabled) {
  variables.enabled = params.enabled;
}

// CORRECT - handles false correctly
if (params.enabled !== undefined && params.enabled !== null) {
  variables.enabled = params.enabled;
}
```

### Pattern 7: Blank lines around multiline statements
Add blank lines BEFORE and AFTER multiline statements (GraphQL queries, object declarations).

### Pattern 8: ALWAYS verify types match backend BEFORE coding
**CRITICAL:** Never assume types. Always check the backend definition first:
```bash
# For queries (resolvers) - check option type:
grep -n "option.*field_name" app/graphql_resolvers/*_graphql_resolver.rb

# For mutations - check argument type:
grep -n "argument :field_name" app/graphql_mutations/*_graphql_mutation.rb

# For input types - check argument type:
grep -n "argument :field_name" app/graphql_types/*_input_graphql_type.rb
```
Use the EXACT same type in frontend. Backend is inconsistent (some use `ID`, some use `Integer`).

---

## Errors to Check (Verification Checklist)

### Error 1: Mutation ID type `$id: ID` instead of `$id: ID!`

**Problem:** Mutations require non-nullable ID (`ID!`), but code uses nullable (`ID`).

**How to find:**
```bash
grep -rn 'mutation.*\$id: ID[^!]' src/app/
```

**How to fix:** Change `$id: ID` to `$id: ID!` in mutation declarations.

**Backend reference:** `app/graphql_mutations/*_graphql_mutation.rb` defines `argument :id, ID, required: true`

---

### Error 2: `loadingGroups = false` outside subscribe

**Problem:** Loading state set to false immediately after calling subscribe, not when response arrives.

**How to find:**
```bash
grep -A 15 'loadingGroups = true' src/app/ | grep -B 2 'loadingGroups = false'
```

**How to fix:** Move `this.loadingGroups = false` inside the subscribe callback.

**Pattern:**
```typescript
// WRONG
this.service.query(...).subscribe((response) => {
  // handle response
});
this.loadingGroups = false;  // ❌ Outside

// CORRECT
this.service.query(...).subscribe((response) => {
  // handle response
  this.loadingGroups = false;  // ✅ Inside
});
```

---

### Error 3: Boolean params with simple `if` check

**Problem:** `if (params.enabled)` won't send `false` values.

**How to find:**
```bash
grep -rn 'if (params\.enabled)' src/app/
grep -rn 'if (params\.override)' src/app/
grep -rn 'if (params\.shared)' src/app/
```

**How to fix:** Use `if (params.enabled !== undefined && params.enabled !== null)`

---

### Error 4: Query ID type using `ID!` instead of `ID`

**Problem:** Queries use optional ID (`option(:id, type: ID)`), so frontend should use `$id: ID` (nullable).

**How to find:**
```bash
grep -rn 'query.*\$id: ID!' src/app/
```

**How to fix:** Change `$id: ID!` to `$id: ID` in query declarations (only if it's a query, not mutation).

---

### Error 5: String `"true"` passed to Boolean GraphQL variable

**Problem:** The `enabled` field in `Filter` model is typed as `string` because it comes from URL query params. When passed directly to GraphQL variables expecting `Boolean`, the server rejects with: `"Could not coerce value \"true\" to Boolean"`.

**Symptoms:** Infinite loading on listing pages (API returns error, component never sets `loading = false`).

**How to find:**
```bash
grep -rn 'variables.enabled = params.enabled' src/app/
```

**How to fix:** Convert string to boolean before assigning:
```typescript
// WRONG - passes string "true"
if (params.enabled !== undefined && params.enabled !== null) {
  variables.enabled = params.enabled;
}

// CORRECT - converts to boolean
if (params.enabled !== undefined && params.enabled !== null && params.enabled !== '') {
  variables.enabled = params.enabled === 'true';
}
```

**Future improvement:** Change `enabled` type from `string` to `boolean` in `Filter` model and convert at the component level when reading from query params.

---

### Error 6: Using `parseInt()` for GraphQL ID variables

**Problem:** Frontend uses `parseInt(id, 10)` to convert IDs to numbers, but GraphQL `ID` type expects strings. This causes type mismatches.

**Symptoms:** GraphQL type errors, data not loading, infinite loading spinners, or silent failures.

**How to find:**
```bash
grep -rn "parseInt.*id" src/app/ --include="*.ts"
grep -rn "parseInt.*Id" src/app/ --include="*.ts"
```

**How to fix (2 steps):**

**Step 1:** Remove `parseInt()` from the variable assignment:
```typescript
// WRONG - converts to number
variables.id = parseInt(this.id, 10);
variables.userId = parseInt(event.id, 10);
const id = parseInt(event, 10);

// CORRECT - keep as string
variables.id = this.id;
variables.userId = event.id;
const id = event;
```

**Step 2:** If the query declares wrong type, also fix the GraphQL type declaration:
```typescript
// WRONG - declares Int but backend expects ID
query Groups($companyId: Int) {
  groups(companyId: $companyId) { ... }
}

// CORRECT - matches backend type
query Groups($companyId: ID) {
  groups(companyId: $companyId) { ... }
}
```

**CRITICAL: Always verify backend type BEFORE fixing:**
```bash
# For queries (resolvers):
cat app/graphql_resolvers/<name>_graphql_resolver.rb | grep "option.*type:"

# For mutations:
cat app/graphql_mutations/<name>_graphql_mutation.rb | grep "argument"

# For input types:
cat app/graphql_types/<name>_input_graphql_type.rb | grep "argument"
```

**Backend type mapping:**
| Backend | Frontend | Keep parseInt? |
|---------|----------|----------------|
| `type: ID` | `$field: ID` | ❌ NO |
| `type: Integer` or `Integer` | `$field: Int` | ✅ YES |
| `type: String` | `$field: String` | ❌ NO |

**Exception:** Some backend mutations expect `Integer` instead of `ID`. Always check the backend definition:
- `argument :variable_id, Integer` → KEEP `parseInt()`
- `argument :variable_id, ID` → REMOVE `parseInt()`

**Files fixed in hotfix/1.253.4:**

| File | Fields Fixed |
|------|--------------|
| deal/deal.component.ts | id (disabledButton, enabledButton) |
| deal/create/deal-create.component.ts | variableId |
| deal/update/deal-update.component.ts | id, variableId |
| deal/deal.service.ts | clientId, companyId, productId, statusId, userId |
| group/group.component.ts | id (disabledButton, enabledButton) |
| group/group.service.ts | companyId |
| group/finish/group-finish.component.ts | userId |
| group/start/group-start.component.ts | userId |
| rankifier/rankifier.component.ts | id (disabledButton, enabledButton) |
| rankifier/rankifier.service.ts | companyId |
| redemption-incentives/clone/redemption-incentive-clone.component.ts | groupId |
| redemption-incentives/create/redemption-incentive-create.component.ts | groupId |
| redemption-incentives/update/redemption-incentive-update.component.ts | groupId |
| user/create/user-create.component.ts | seatParentId, stateId, subsidiaryId, companyId, countryId, id |
| user/show/user-show.component.ts | id |
| user/update/user-update.component.ts | stateId, countryId, userId, companyId, id |
| user/user.service.ts | companyId, id, stateId |

**NOT fixed (backend expects Integer):**

| File | Field | Backend Type |
|------|-------|--------------|
| rankifier/clone/rankifier-clone.component.ts | variableId | `Integer` |
| rankifier/create/rankifier-create.component.ts | variableId | `Integer` |
| rankifier/update/rankifier-update.component.ts | variableId | `Integer` |

---

### Error 7: Incorrect GraphQL Input Type Names

**Problem:** GraphQL Input type names in the frontend don't match the backend schema. The backend uses `XxxInputGraphqlType` class names, and graphql-ruby only removes the `Type` suffix, resulting in `XxxInputGraphql` as the exposed GraphQL type name.

**Symptoms:** GraphQL error `"XxxInput isn't a defined input type (on $fieldName)" (Did you mean 'XxxInputGraphql'?)`

**Root Cause:** The project's Ruby naming convention adds `Graphql` before `Type` in class names (e.g., `FieldInputGraphqlType`). The graphql-ruby library only removes the `Type` suffix, so the exposed name becomes `FieldInputGraphql`, NOT `FieldInput`.

**How to find:**
```bash
# Find all Input type usages in frontend
grep -rn '\[.*Input.*\]' src/app/ --include="*.ts"

# List all Input types in backend with correct GraphQL names
cd app && for f in app/graphql_types/*_input_graphql_type.rb; do head -3 "$f" | grep "class" | awk '{print $2}' | sed 's/Type$//'; done
```

**Incorrect types found and fixed:**

| Wrong (Frontend) | Correct (Backend) | Files Affected |
|------------------|-------------------|----------------|
| `IdentifierInput` | `IdentifierInputGraphql` | user-create.component.ts |
| `FieldInput` | `FieldInputGraphql` | user-create.component.ts, user-update.component.ts |
| `DealFieldInput` | `DealFieldInputGraphql` | deal-create.component.ts, deal-update.component.ts |
| `DealCollaborationInput` | `DealCollaborationInputGraphql` | collaborative-deal-create.component.ts, collaborative-deal-update.component.ts |
| `PaymentExportationFieldsInput` | `PaymentExportationFieldsInputGraphql` | payment-exportation-create.component.ts |
| `CompanyBusinessTerritoryInput` | `CompanyBusinessTerritoryInputGraphql` | company-create.component.ts, company-update.component.ts |

**How to fix:**
1. Check which Input types exist in the backend: `ls app/graphql_types/*_input_graphql_type.rb`
2. The GraphQL type name is the class name with only `Type` removed (NOT `GraphqlType`)
3. ALL Input types end with `Graphql` suffix

**Backend type to GraphQL name conversion:**
| Backend Class | GraphQL Type Name |
|--------------|-------------------|
| `FieldInputGraphqlType` | `FieldInputGraphql` |
| `IdentifierInputGraphqlType` | `IdentifierInputGraphql` |
| `DealFieldInputGraphqlType` | `DealFieldInputGraphql` |
| `DealCollaborationInputGraphqlType` | `DealCollaborationInputGraphql` |
| `CompanyBusinessTerritoryInputGraphqlType` | `CompanyBusinessTerritoryInputGraphql` |
| `PaymentExportationFieldsInputGraphqlType` | `PaymentExportationFieldsInputGraphql` |

**Rule:** ALL Input types in this project end with `Graphql`. NEVER use names like `FieldInput` - always use `FieldInputGraphql`.

---

### Error 8: Numeric Fields with Value 0 Not Being Sent

**Problem:** Using `if (value)` for numeric fields (like `budget`, `goal`) won't send the value when it equals `0`, because `0` is falsy in JavaScript.

**Symptoms:** User sets a numeric field to `0`, but the backend doesn't receive the value. The field keeps its previous value or becomes `null`.

**How to find:**
```bash
# Find numeric field checks that might fail with 0
grep -rn 'if (this.form.value.budget)' src/app/ --include="*.ts"
grep -rn 'if (this.form.value.goal)' src/app/ --include="*.ts"
grep -rn 'if (this.form.value.amount)' src/app/ --include="*.ts"
grep -rn 'if (this.form.value.value)' src/app/ --include="*.ts"
grep -rn 'if (this.form.value.quantity)' src/app/ --include="*.ts"
```

**How to fix:** Use explicit null/undefined check:
```typescript
// WRONG - won't send value if it's 0
if (this.form.value.budget) {
  variables.budget = this.form.value.budget;
}

// CORRECT - handles 0 correctly
if (this.form.value.budget !== undefined && this.form.value.budget !== null) {
  variables.budget = this.form.value.budget;
}
```

**Known affected fields:**
- `budget` (Int) - plan-create, plan-update
- `goal` (Int) - plan-update (plan-create was already correct)

**Note:** This is a pre-existing bug in the codebase. The migration should preserve the original behavior, but when found, it's worth fixing.

---

## Released PRs ✅

All PRs below are merged and deployed to production.

### Release 1.253.0
| PR | Module |
|----|--------|
| #5880 | Attachment |
| #5881 | Easy Product |
| #5887 | Campaign |
| #5895 | Plan |
| #5896 | Easy Product (hotfix) |
| #5898 | Plan Participation |
| #5899 | Indicator Incentives |
| #5900 | Deal Incentive |
| #5901 | Limiter Incentives |
| #5902 | Rankifier Incentives |

### Release 1.253.3
| PR | Module |
|----|--------|
| #5913 | Redemption Incentives |
| #5914 | Rankifier |
| #5915 | Group |
| #5916 | User |
| #5917 | Deal |

### Release 1.253.4
| PR | Module |
|----|--------|
| #5921 | Temporary Services (29 files) |
| #5923 | Fix parseInt() for GraphQL ID variables |

### Release 1.253.5
| PR | Module |
|----|--------|
| #5924 | Misc |
| #5929 | Documents (Client, Deal, Goal) |
| #5930 | Documents 2 |
| #5931 | User Audit |
| #5933 | Documents 4 |
| #5934 | Audits |
| #5935 | Plan Misc |
| #5936 | Commission Batches |
| #5937 | Commission Events |
| #5938 | Documents 3 |
| #5939 | Goal |
| #5940 | Commission |
| #5941 | Collaborative Deal |
| #5942 | Payment |
| #5943 | Metric |
| #5944 | Dashboard |
| #5945 | Fix GraphQL Input Type Names (hotfix) |

---

## Merged PRs (Phase 2 — Friday Batch)

| PR | Module | Status |
|----|--------|--------|
| #5947 | Calendar + Calendar Audit | ✅ Merged |
| #5948 | Client | ✅ Merged |
| #5949 | Company | ✅ Merged |
| #5951 | Plan (7 files) | ✅ Merged |
| #5952 | Misc single-file modules (21 files) | ✅ Merged |

---

## Merged PRs (Phase 2 — Thread PRs)

| PR | Branch | Module | Status |
|----|--------|--------|--------|
| #5959 | feature/graphql-vars-thread-1 | acceptment, dashboard, deal | ✅ Merged |
| #5960 | feature/graphql-vars-thread-2 | incentive, indicator | ✅ Merged |
| #5961 | feature/graphql-vars-thread-3 | statement, partial-commission, payment | ✅ Merged |
| #5962 | feature/graphql-vars-thread-4 | indicator, subsidiary, seat | ✅ Merged |
| #5963 | feature/graphql-vars-thread-5 | variable, status, product, user-history, trade, upload | ✅ Merged |

---

## Implementation Complete ✅

All 140 files have been migrated. The work was executed in two phases:

### Phase 1: Individual PRs (34 PRs)

Released across versions 1.253.0, 1.253.3, 1.253.4, and 1.253.5. See "Released PRs" section above.

### Phase 2: Consolidated Thread PRs (9 PRs)

Remaining files were consolidated into thread-based parallel execution instead of the originally planned 44 individual PRs (PRs #10-53 in TASKS.md were superseded).

**Friday — 4 thread PRs** (merged, pending release):
- #5947: Calendar + Calendar Audit
- #5948: Client
- #5949: Company
- #5951: Plan (7 files)
- #5952: Misc single-file modules (21 files)

**Today — 5 thread PRs** (pending merge):
- #5959: acceptment, dashboard, deal (17 files)
- #5960: incentive, indicator (16 files)
- #5961: limiter, partial-commission, payment, plan (19 files)
- #5962: product, rankifier, seat, statement, status (19 files)
- #5963: subsidiary, trade, upload, user, variable (21 files)

**Post-execution review:** Copilot review found 7 bugs across 4 PRs. 5 were fixed (Error 1 x2, Error 2 x1, nested array x1, missing query method x1). 1 deferred to `error-handling-standardization` plan (optional chaining). 1 PR was clean.

### Total: 44 PRs (34 individual + 5 merged pending release + 5 open pending merge)

---

## Pre-Release Verification Process

**MANDATORY:** Before every release that includes GraphQL changes, this process MUST be executed.

### Step 1: List All Changed Files

```bash
# Get all GraphQL-related commits since last release
git log --since="<last-release-date>" --oneline develop | grep -i "graphql\|fix("

# For each commit, list changed TypeScript files
git show --stat --name-only <commit-hash> | grep "\.ts$"
```

### Step 2: For EACH File, Verify Against Backend

For every file that contains a GraphQL mutation or query:

#### 2.1 Identify the Operation

```typescript
// Look for mutation/query declarations
mutation CreateSomething($field: Type) { ... }
query GetSomething($field: Type) { ... }
```

#### 2.2 Find Backend Definition

```bash
# For mutations:
cat app/graphql_mutations/<mutation_name>_graphql_mutation.rb | grep "argument"

# For queries (resolvers):
cat app/graphql_resolvers/<resolver_name>_graphql_resolver.rb | grep "option\|argument"

# For base classes (if mutation inherits):
cat app/graphql_mutations/<base_class>_graphql_mutation.rb | grep "argument"
```

#### 2.3 Compare Types

| Backend | Frontend | Match? |
|---------|----------|--------|
| `argument :field, ID, required: true` | `$field: ID!` | ✅ |
| `argument :field, ID, required: false` | `$field: ID` | ✅ |
| `argument :field, String, required: true` | `$field: String!` | ✅ |
| `argument :field, String, required: false` | `$field: String` | ✅ |
| `option(:field, type: ID)` | `$field: ID` | ✅ |

**CRITICAL MISMATCHES TO CATCH:**

| Backend | Frontend | Problem |
|---------|----------|---------|
| `required: false` | `Type!` | Frontend too strict (may work but inconsistent) |
| `required: true` | `Type` | **BREAKING** - Backend will reject |
| `type: ID` | `Int` | **BREAKING** - Type mismatch |
| `type: Integer` | `ID` | **BREAKING** - Type mismatch |

### Step 3: Document Results

Create/update `GRAPHQL-ANALYSIS.md` in project root with:

1. Date of analysis
2. List of files verified
3. Backend type for each parameter
4. Frontend type for each parameter
5. Match status (✅ or ❌)
6. Any issues found and their resolution

### Step 4: Sign-off Checklist

Before release, confirm:

- [x] All mutations have correct nullability (`ID` vs `ID!`)
- [x] All queries have correct nullability (usually nullable for filters)
- [x] All temporary services use `$id: ID!` (required)
- [x] All document create services have types matching backend
- [x] No `parseInt()` on fields where backend expects `ID` type
- [x] Boolean parameters use proper null check, not just `if (value)`

---

**Status:** COMPLETED ✅ — All 44 PRs merged. All files migrated. Bug fixes tracked separately in `graphql-variables-bugfix` plan.

---

## Completion Note

**Date:** 2026-01-27

All 140 files have been migrated from string interpolation to typed GraphQL variables across 44 PRs. All PRs are merged into develop. Remaining type safety issues (nullability contracts, `parseInt()` cleanup, numeric zero-value handling, loading state patterns, and `|| ''` defensive patterns for ID fields) are tracked in the `graphql-type-contract-standardization` plan for future work.
