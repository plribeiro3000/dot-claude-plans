# PLAN — Missing GraphQL Mutations

## Objective

Create 3 backend GraphQL mutations that the frontend already calls but don't exist in the backend. These mutations cause runtime errors when users trigger the corresponding actions.

## Context

Discovered during the GraphQL Variables Migration audit (January 2026). The frontend has always called these mutations, but the backend never implemented them. Before the migration, the calls used string interpolation; after migration, they use typed GraphQL variables — but in both cases, the backend returns an error because the mutations don't exist in the schema.

## Mutations to Create

### 1. DisableSubsidiary

- **Frontend**: `subsidiary.component.ts` and `subsidiary.service.ts` call `disableSubsidiary(id: $id)`
- **Backend ready**: Model (`Subsidiary`), policy (`SubsidiaryPolicy#disable?`), schema columns (`disabled_at`, `disabler_id`), GraphQL type (`SubsidiaryGraphqlType` with `disable` action) — all exist
- **Missing**: `disable_subsidiary_graphql_mutation.rb` + registration in `MutationType`
- **Reference pattern**: `disable_status_graphql_mutation.rb`

### 2. EnableSubsidiary

- **Frontend**: `subsidiary.component.ts` and `subsidiary.service.ts` call `enableSubsidiary(id: $id)`
- **Backend ready**: Model (`Subsidiary`), policy (`SubsidiaryPolicy#enable?`), GraphQL type with `enable` action — all exist
- **Missing**: `enable_subsidiary_graphql_mutation.rb` + registration in `MutationType`
- **Reference pattern**: `enable_status_graphql_mutation.rb`

### 3. DeleteCollaborativeDealDocument

- **Frontend**: `collaborative-deal-document.component.ts` calls `deleteCollaborativeDealDocument(id: $id)`
- **Backend ready**: Model (`CollaborativeDealDocument`, inherits from `Document`), policy (`CollaborativeDealDocumentPolicy#destroy?` — only allows when `record.failed?`), GraphQL type with `destruction` action — all exist
- **Missing**: `delete_collaborative_deal_document_graphql_mutation.rb` + registration in `MutationType`
- **Reference pattern**: `delete_deal_document_graphql_mutation.rb`

## Discarded

- **RejectPlan**: Initially reported as missing, but investigation showed the frontend does NOT call `rejectPlan`. The `plan-show.component.ts` calls `resetPlan` and `approvePlan`, both of which already exist in the backend. False alarm.

## Files to Create

1. `/app/graphql_mutations/disable_subsidiary_graphql_mutation.rb`
2. `/app/graphql_mutations/enable_subsidiary_graphql_mutation.rb`
3. `/app/graphql_mutations/delete_collaborative_deal_document_graphql_mutation.rb`

## Files to Modify

1. `/app/graphql_types/mutation_type.rb` — register all 3 mutations

## Tests to Create

1. `/spec/requests/graphql_mutations/disable_subsidiary_graphql_mutation_spec.rb`
2. `/spec/requests/graphql_mutations/enable_subsidiary_graphql_mutation_spec.rb`
3. `/spec/requests/graphql_mutations/delete_collaborative_deal_document_graphql_mutation_spec.rb`

## Definition of Done

- [ ] 3 mutation files created following existing patterns
- [ ] 3 mutations registered in MutationType
- [ ] 3 spec files with passing tests
- [ ] Frontend disable/enable subsidiary buttons work
- [ ] Frontend delete collaborative deal document button works

---

**Status:** ACTIVE — Ready for implementation
