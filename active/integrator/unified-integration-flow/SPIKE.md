# SPIKE: Merge Self-Service and Managed Integration Flows

## Question

What is the effort required to merge the two existing integration flows (self-service and managed) into a single unified flow, where each stream can have its own data source type (normalized database, custom query, API, or future formats)?

## Context

The integrator currently has two entry points controlled by `INTEGRATION_MODE` env var:

- **Self-service** (`database`/`self_service`): Reads from a normalized client database with hardcoded table names and column conventions. Each worker knows the next worker in the chain.
- **Managed** (`managed`/`api`): Configuration-driven via Stream/Connector/Source models. Each step can read from a database query or an API. Workers are also hardcoded in chain order but dispatch to DB or API consumers based on connector configuration.

The goal is to have a **single flow** where each of the ~25 resource steps can independently be configured as normalized DB, custom query, API, or any future source type.

## Current Architecture

### Entry Points

| Flow | Worker | Env Var Values |
|------|--------|----------------|
| Self-service | `DatabaseIntegrator` | `database`, `self_service` |
| Managed | `ManagedIntegrator` | `managed`, `api` |

Decision happens in `lib/tasks/integration.rake` via `ApplicationConfiguration.self_service_integration?` / `.managed_integration?`.

### Extraction Chain Order (both flows follow the same resource order)

| # | Resource | Self-Service Extractor | Managed Extractor Producer |
|---|----------|----------------------|---------------------------|
| 1 | Subsidiary | `Subsidiary::DatabaseExtractor` | `Subsidiary::ManagedExtractorProducer` |
| 2 | Hierarchy | `Hierarchy::DatabaseExtractor` | `Hierarchy::ManagedExtractorProducer` |
| 3 | User (all roles) | `User::DatabaseExtractor` (single) | `User::Admin::ManagedExtractorProducer` -> President -> VicePresident -> Director -> Superintendent -> GeneralManager -> Manager -> Coordinator -> Supervisor -> SalesRepresentative |
| 4 | UserIdentifier | `UserIdentifier::DatabaseExtractor` | `UserIdentifier::ManagedExtractorProducer` |
| 5 | Client | `Client::DatabaseExtractor` | `Client::ManagedExtractorProducer` |
| 6 | Product | `Product::DatabaseExtractor` | `Product::ManagedExtractorProducer` |
| 7 | Group | `Group::DatabaseExtractor` | `Group::ManagedExtractorProducer` |
| 8 | Groupification | `Groupification::DatabaseExtractor` | `Groupification::ManagedExtractorProducer` |
| 9 | UserField | `UserField::DatabaseExtractor` | `UserField::ManagedExtractorProducer` |
| 10 | UserActivity | `UserActivity::DatabaseExtractor` | `UserActivity::ManagedExtractorProducer` |
| 11 | Deal | `Deal::DatabaseExtractor` | `Deal::ManagedExtractorProducer` |
| 12 | DealExtraField | `DealExtraField::DatabaseExtractor` | `DealExtraField::ManagedExtractorProducer` |
| 13 | Modifier | `Modifier::DatabaseExtractor` | `Modifier::ManagedExtractorProducer` |
| 14 | Goal | `Goal::DatabaseExtractor` | `Goal::ManagedExtractorProducer` |

### Transformation Chain Order (same resource order)

| Flow | Pattern | Workers per Resource |
|------|---------|---------------------|
| Self-service | `DatabaseTransformerProducer` -> `DatabaseTransformerConsumer` | 2 (producer + consumer) |
| Managed | `ManagedTransformerProducer` -> `ManagedTransformerConsumer` | 2 (producer + consumer) |

### Loading Chain Order (shared between both flows)

The loading phase is already unified. Both flows converge at `Subsidiary::LoaderProducer` after transformation completes. The loader chain has 25 steps (14 resources + 10 user roles + ParentUpdate) ending at `Job::Finisher`.

### Worker Count

| Type | Self-Service | Managed | Shared (Loaders) |
|------|-------------|---------|-------------------|
| Extractors | 14 (`DatabaseExtractor`) | 24 (`ManagedExtractorProducer` + `ManagedDatabaseExtractorConsumer` + `ManagedApiExtractorConsumer`) | - |
| Transformers | 14 (`DatabaseTransformerProducer`) + 14 (`DatabaseTransformerConsumer`) | 24 (`ManagedTransformerProducer`) + 24 (`ManagedTransformerConsumer`) | - |
| Loaders | - | - | 25 (`LoaderProducer`) + 25 (`LoaderConsumer`) |

**Total workers involved in the merge**: ~114 (self-service extractors + transformers + managed extractors + transformers). Loaders are already shared and don't need changes.

### Key Structural Differences

#### 1. Extraction

**Self-service (`DatabaseExtractor`):**
- Connects to a single `Database.connect!` (client's normalized DB)
- Uses hardcoded table names: `connection.page(:subsidiaries, conditions, last_id)`
- Raw data stored directly in collection: `job.subsidiary_collections.create(raw: raw_collection)`
- Pagination via `collection_last_id` on the `:id` column
- Filter: `updated_at >= fetch_since`

**Managed (`ManagedExtractorProducer` + consumers):**
- Reads `Stream.where(resource_name: 'Subsidiary').enabled` to find configuration
- For each stream, iterates connectors and dispatches to DB or API consumer
- `ManagedDatabaseExtractorConsumer`: connects via `stream.source.connect!`, executes `connector.query`, custom `primary_key` and `fetch_since_column`
- `ManagedApiExtractorConsumer`: HTTP GET with Liquid-templated URI, authenticated headers, JSON pagination
- Raw data stored as file uploads: `collection.raw_body = File.new(...)`
- Coordination via `job.computation` (Redis counter) — multiple connectors run in parallel per resource

#### 2. Transformation

**Self-service (`DatabaseTransformerConsumer`):**
- Reads raw objects directly from MongoDB collection's `raw` array field
- Direct field mapping: `raw_object[:id]` -> `resource.imports.create(data: raw_object)`
- No attribute mapping configuration — raw data IS the transformed data
- Special cases handled in code (e.g., User fetches parent data)

**Managed (`ManagedTransformerConsumer`):**
- Reads raw JSON from file uploads (`collection.raw_body.read`)
- Applies `AttributeMapping` configuration: dynamic, fixed, template (Liquid), formula (Dentaku)
- Handles `collection_source_keys` for nested JSON navigation
- Nullifies sensitive keys
- Uses `Variables` for template rendering context

#### 3. Identifier Format

**Self-service:** Prefixes IDs with `"4sk_"` (e.g., `"4sk_123"`)
**Managed:** Uses raw IDs from source

This is controlled in `Import#identifier` via `ApplicationConfiguration.managed_integration?`.

#### 4. User Role Handling

**Self-service extraction:** Single `User::DatabaseExtractor` extracts all users. Single `User::DatabaseTransformerProducer/Consumer` transforms all users. Role separation happens only at loading phase.

**Managed extraction:** Separate producers per role: `User::Admin::ManagedExtractorProducer`, `User::President::ManagedExtractorProducer`, etc. (10 role-specific producers). Each has its own DB and API consumer.

#### 5. Pre-flight Checks

**Self-service (`DatabaseIntegrator`):**
- Throughput validation (`ThroughputCalculator`)
- Database permissions check (`connection.permissions.missing`)
- Table locks check (`connection.locks.check`)
- Host reachability (Net::Telnet)

**Managed (`ManagedIntegrator`):**
- Source health checks (`source.health_check.reachable?` for all sources)
- API authentication (HTTP POST to each API source's auth endpoint)
- No throughput or lock checks

### Configuration Models (Managed Only)

These models exist today but are only used by the managed flow:

- **Source** (STI): `ApiSource`, `DatabaseSource` — connection configuration
- **Stream**: Links a `resource_name` to a `Source`, has many `Connectors`
- **Connector**: Query/URI template, pagination config, attribute mappings
- **AttributeMapping**: Field extraction/transformation rules (dynamic/fixed/template/formula)
- **Authentication**: Credentials for API sources (SalesForce, Trackmob, etc.)
- **HealthCheck**: Reachability verification endpoint

## Findings

### What the unified flow needs

1. **Every resource step must be driven by Stream/Connector configuration** — even the normalized DB case. The self-service normalized DB becomes just another `DatabaseSource` with auto-generated connectors that use the standard table/column conventions.

2. **The hardcoded chain order must be preserved** — both flows already use the same resource order. The chain can remain hardcoded (Resource A calls Resource B) but the extraction/transformation logic within each step must be configurable.

3. **The `"4sk_"` prefix logic must become per-source or per-stream configuration** — not a global env var check.

4. **User role separation must be unified** — either all flows split by role (managed pattern) or the split happens later. Since loaders already split by role, the simplest path is to keep extraction/transformation unified per resource (self-service pattern) and let the loader handle role dispatch.

5. **Pre-flight checks need to work across multiple source types** — a single job might have DB sources that need lock checks and API sources that need auth.

### Merge Strategy: Managed absorbs Self-Service

The managed flow is the superset. It already supports:
- Multiple sources per resource
- Database and API extraction
- Configurable queries and attribute mappings
- Parallel connector execution with computation tracking

The self-service flow is a special case where:
- There's exactly one `DatabaseSource` (the client's normalized DB)
- Each stream has one connector with a standard query (`SELECT * FROM {table} WHERE updated_at >= ?`)
- Attribute mappings are identity (source field = target field)
- IDs get prefixed with `"4sk_"`

**To merge:**
1. Create a "normalized database" source type (or use `DatabaseSource` with a `normalized: true` flag)
2. Auto-generate Stream + Connector + AttributeMapping records for each resource based on the normalized schema conventions
3. Make the `ManagedExtractorProducer`/`ManagedTransformerConsumer` handle the normalized case (identity mappings, standard queries)
4. Remove `DatabaseIntegrator`, `DatabaseExtractor`, `DatabaseTransformerProducer/Consumer` workers
5. Remove the `INTEGRATION_MODE` env var — there's only one mode now

### Effort Estimate

| Phase | Description | Workers Affected | Complexity |
|-------|-------------|-----------------|------------|
| **1. Seed normalized config** | Create service/migration to auto-generate Stream/Connector/AttributeMapping records for normalized DB clients | 0 | Medium |
| **2. Unify extractor** | Make `ManagedExtractorProducer` handle normalized DB case (identity query, standard pagination) or reuse existing `ManagedDatabaseExtractorConsumer` with normalized queries | 14 extractors to remove, 24 managed extractors to keep | Medium |
| **3. Unify transformer** | Make `ManagedTransformerConsumer` handle identity mapping (raw data = transformed data, no attribute mappings needed) | 28 transformers to remove, 48 managed transformers to keep | Low-Medium |
| **4. Unify integrator** | Merge `DatabaseIntegrator` pre-flight checks into `ManagedIntegrator` | 2 integrators -> 1 | Medium |
| **5. Unify identifier logic** | Move `"4sk_"` prefix from global config to per-source/per-stream configuration | Import model + loaders | Low |
| **6. Unify user role handling** | Decide: either managed adopts self-service pattern (single User extraction) or self-service adopts managed pattern (per-role extraction). Recommend: keep managed per-role pattern since it's already built | 0-10 depending on direction | Low |
| **7. Remove self-service workers** | Delete `DatabaseExtractor` (14) + `DatabaseTransformerProducer` (14) + `DatabaseTransformerConsumer` (14) + `DatabaseIntegrator` (1) + `DatabaseWarmer` (1) | 44 workers deleted | Low |
| **8. Update rake tasks** | Remove `self_service_integration?` / `managed_integration?` branching | 1 file | Low |
| **9. Update tests** | All specs for removed workers need removal; all specs for kept workers need updating | ~90+ spec files | High |
| **10. Migration for existing clients** | Script to create Stream/Connector/AttributeMapping records for all existing self-service clients | 0 code, 1 migration script | Medium |

### Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Self-service clients break during migration | High | Create migration script that generates exact equivalent config; run in staging first |
| Performance regression (managed has more DB lookups for config) | Medium | The extra queries are Stream/Connector reads — cached in memory during the job |
| `"4sk_"` prefix change breaks existing integrated resources | High | Must be backwards-compatible — existing resources keep their prefix, new config controls future behavior |
| Normalized DB special cases (parent lookup in User transformer) | Medium | Must be preserved as connector-level or transformer-level configuration |

### Open Questions (resolved in PLAN.md)

All questions below were resolved during planning. See `PLAN.md` for details.

1. **Normalized DB type** → Resolved: `normalized` Boolean flag on `DatabaseSource`, not a subclass.
2. **User role split** → Resolved: inherent to source type. Normalized = single stream (code guarantees order). Custom DB/API = separate streams per role (config guarantees order).
3. **Throughput/lock checks** → Resolved: absorbed into ManagedIntegrator, triggered when source is DatabaseSource.
4. **DatabaseWarmer** → Resolved: absorbed as optional step for DatabaseSource with warm-up.
5. **AttributeMappings for normalized** → Resolved: NO mappings. Transformer does bypass when `source.normalized?`. Avoids maintenance of column lists.
6. **How to detect bypass** → Resolved: NOT by absence of mappings (fragile). By `DatabaseSource.normalized?` flag (explicit).

## Conclusion

The merge is **feasible and the path is clear**: the managed flow is the superset, and self-service becomes a configuration of managed. Three source types in one flow: normalized DB (bypass), custom query DB (mappings), API (mappings).

The implementation followed the DDD workflow (KNOWLEDGE → PROCESS → DOMAIN → PLAN) and is now in execution. See `PLAN.md` for the unified execution plan with completed phases and current work.

**Status:** VALIDATED — Spike findings confirmed through implementation. PRs #2087, #2088, #2090 merged successfully.
