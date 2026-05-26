# PLAN — GraphQL Standardization

## Objective

Standardize the GraphQL query/mutation structure across the entire frontend following industry best practices.

## Current State

The codebase has inconsistent patterns for GraphQL operations:

1. **Pattern A (Attachment Services):** Each service has its own method with inline `gql` tag
2. **Pattern B (Most components):** Components build query strings dynamically and pass to generic `AppService.mutation()`/`query()` methods
3. **No separation:** Queries are mixed with business logic inside components/services

## Target State (Industry Standard)

### Structure

```
src/app/{module}/
├── graphql/
│   ├── {module}.queries.ts      # Query constants
│   └── {module}.mutations.ts    # Mutation constants
├── {module}.service.ts          # Service with specific methods
└── {module}.component.ts        # Component injects service
```

### Query Constants File

```typescript
// src/app/user/graphql/user.queries.ts
import gql from 'graphql-tag';

export const GET_USER = gql`
  query GetUser($id: ID!) {
    user(id: $id) {
      id
      name
      email
    }
  }
`;

export const LIST_USERS = gql`
  query ListUsers($first: Int, $after: String, $search: String) {
    users(first: $first, after: $after, search: $search) {
      pageInfo { endCursor }
      nodes { id name email }
    }
  }
`;
```

### Service Pattern

```typescript
// src/app/user/user.service.ts
import { Injectable } from '@angular/core';
import { Apollo } from 'apollo-angular';
import { GET_USER, LIST_USERS } from './graphql/user.queries';
import { CREATE_USER, UPDATE_USER } from './graphql/user.mutations';

@Injectable({ providedIn: 'root' })
export class UserService {
  constructor(private apollo: Apollo) {}

  getUser(id: string) {
    return this.apollo.watchQuery({
      query: GET_USER,
      variables: { id: id }
    });
  }

  listUsers(params: { first?: number; after?: string; search?: string } = {}) {
    return this.apollo.watchQuery({
      query: LIST_USERS,
      variables: {
        first: params.first || 9,
        after: params.after || null,
        search: params.search || null
      }
    });
  }

  createUser(input: CreateUserInput) {
    return this.apollo.mutate({
      mutation: CREATE_USER,
      variables: { input: input }
    });
  }
}
```

### Component Usage

```typescript
// src/app/user/user.component.ts
@Component({ ... })
export class UserComponent implements OnInit {
  constructor(private userService: UserService) {}

  ngOnInit() {
    this.userService.listUsers({ search: this.searchTerm })
      .valueChanges.subscribe(response => {
        this.users = response.data.users.nodes;
      });
  }
}
```

## Benefits

1. **Separation of concerns** - Queries separate from business logic
2. **Reusability** - Same query can be used in multiple places
3. **Maintainability** - Change query in one place, affects all usages
4. **Type safety** - Easier to add TypeScript types
5. **Testing** - Services can be mocked easily
6. **Caching** - Apollo can cache effectively with named, static queries
7. **Debugging** - Named operations appear in Apollo DevTools

## Migration Strategy

### Phase 1: Create Query/Mutation Files
- For each module, create `graphql/` folder
- Extract all queries into `{module}.queries.ts`
- Extract all mutations into `{module}.mutations.ts`
- All queries must be named and use variables

### Phase 2: Refactor Services
- Remove dynamic query building from services
- Import query constants
- Create specific methods for each operation
- Remove generic `query()`/`mutation()` methods from AppService

### Phase 3: Update Components
- Remove query building methods from components
- Update calls to use new service methods
- Remove unused imports

### Phase 4: Cleanup
- Remove deprecated patterns
- Update documentation
- Run tests

## Scope

**Affected modules:** ~88 modules with GraphQL operations

**Estimated effort:**
- Query extraction: ~2-3 days
- Service refactoring: ~3-4 days
- Component updates: ~2-3 days
- Testing & cleanup: ~1-2 days

## Definition of Done

- [ ] All queries/mutations in dedicated files per module
- [ ] All operations named and using variables
- [ ] Services have specific methods (no generic query builders)
- [ ] Components don't build queries
- [ ] AppService generic methods removed or deprecated
- [ ] Application compiles and works correctly
- [ ] Consistent pattern across entire codebase

---

**Status:** DRAFT - Pending approval after GraphQL Variables Migration completion
