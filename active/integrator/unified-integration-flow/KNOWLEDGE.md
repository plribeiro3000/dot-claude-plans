# KNOWLEDGE - Unified Integration Flow

## Domain Refinement (2026-04-10)

A late-stage domain review identified that the `Connector` concept, introduced in PR #2087, does
not map to any entity in industry-standard data movement platforms (Airbyte, Fivetran, Singer).
In those platforms, the word "connector" refers either to a plugin (Airbyte) or to the entire
pipeline instance (Fivetran) — never to an entity between Source and Stream. In 4Shark's prior
model, `Connector` was holding extraction and transformation config that belongs conceptually to
the Stream itself.

**Decisions taken at this refinement:**

1. **`Connector` is deleted.** All its fields migrate to `Stream`. A `Stream` IS the extraction +
   transformation config for a resource from a source. No intermediate entity.
2. **`ResourceType` is introduced as a new first-class entity.** It holds the catalog of resource
   types known to the integrator (Subsidiary, Hierarchy, User, Client, …) with their identifier
   prefix when applicable. `Stream.belongs_to :resource_type` replaces the `resource_name` String
   field.
3. **`identifier_prefix` moves from `Source` to `ResourceType`.** The prefix is a property of the
   resource type, not the source. In practice only `User` has a prefix (`4sk_`), because other
   resources in the self-service legacy flow never had their own IDs prefixed — they only
   referenced user IDs with the prefix.
4. **`Connector.headers` is dead code.** Every `managed_api_extractor_consumer.rb` uses
   `source.authenticated_headers` (from the Source's `Authentication`). The embedded `headers`
   on `Connector` was never read. It is deleted, not migrated.
5. **`Stream.position` is removed.** The field was never used for actual ordering — execution
   order remains hardcoded in the worker chain. Position gave a false impression of
   configurability.
6. **Liquid templating is unified across API and database extractors.** Today the API extractor
   uses `Liquid` render via `connector.query(variables)` and the database extractor uses Sequel
   `.where` chaining in Ruby. After the refinement, both paths go through Liquid render using
   the same `Variables` class, which is extended to inject `page`, `previous_record_id`, and
   `page_size` in addition to its existing 32 date-derived keys. `Stream.query_template` (no
   previous record) and `Stream.paginated_query_template` (with previous record) drive both
   flows uniformly.
7. **`Import` reaches the User prefix via `ResourceType.find_by(name: 'User')`**, not via a
   `stream.resource_type` traversal (because the stream's own resource type is usually NOT User
   — e.g., a Deal stream needs the User prefix to resolve `user_identifier`). This eliminates the
   `attr_writer :user_identifier_prefix` pattern and the Sidekiq argument threading through all
   loader consumers.
8. **The seed task is renamed** from `rake integration:seed_normalized` to
   `rake integration:normalized:bootstrap`.
9. **`Resource.streams` is a class method on the Resource STI subclasses.** Producers use
   `Subsidiary.streams.enabled.pluck(:id)` instead of a `Stream.for_resource('Subsidiary')` scope.
   The scope is eliminated — each Resource class owns its own stream lookup via ResourceType.

These decisions are the final word on the domain. Implementation follows.

## The Problem

The Integrator application evolved organically through three phases:

1. **Puller** — Only fetched data from a normalized database schema (`fsk_*` tables) known by 4Shark
2. **Integrator** — Added data transformation, logging, email reports
3. **API support** — Added the ability to fetch from external APIs (no client is using API mode in production yet)

The application now faces a fourth evolution. Two fundamentally different operating models exist:

- **Self-Service Integration** — The client has an engineering/IT team. 4Shark provides the canonical schema (`fsk_*` tables), the client normalizes their data into it, and the integrator just pulls. The heavy lifting is on the client side.
- **Managed Integration** — The client doesn't have a team or can't normalize. 4Shark connects directly to the client's systems (database, API, SSO, whatever), discovers where the data is, builds queries/API calls, configures mapping. The heavy lifting is on 4Shark's side. Can use API, database, or both mixed per resource.

The current architecture treats these as two completely separate, parallel paths controlled by a global environment variable (`INTEGRATION_MODE=api|database`). This has multiple problems:

1. The binary switch makes it impossible to configure a client that uses API for some resources (e.g., users from AD/SSO) and database for others (e.g., deals from SQL Server) within the same integration run
2. The terms "api mode" and "database mode" are misleading — they describe the extraction mechanism, not the operating model
3. The mode is an environment variable, requiring a redeploy to change — it should be a persisted configuration in MongoDB so the web management interface can read it and render the appropriate UI
4. Maintaining two parallel code paths (44 self-service workers + 96 managed workers) is costly and error-prone

The MongoDB models (`ApplicationProgrammingInterface`, `ExternalApplication`, `ExternalResource`, `HealthCheck`, `Authentication`) were hardcoded around API concepts. Replicating this structure for database sources would create a "puxadinho" (hack) where database queries are shoehorned into API-named models — names would not make sense, concepts would not make sense, and it would generate bugs.

**Final target state**: A SINGLE integration flow for all clients. There is no more self-service vs managed distinction at the code level. Self-service becomes a CONFIGURATION of managed — a `DatabaseSource` with `normalized: true`. After the work is complete, there is only ONE flow: managed. The term "self-service" survives only as a business/operations label for clients who normalize their own data. All 44 self-service-specific workers are deleted. Execution depends entirely on having Stream/Connector records in MongoDB — no hardcoded `fsk_*` table assumptions in the pipeline.

**Complete vision**: The engineer explicitly decided that all planning documents must reflect the complete target state, even if implementation is phased. The rationale: "If we don't think about this now, later we might make a decision that prevents us from reaching this goal. We need to be very clear about where we want to arrive, so we make decisions that bring us closer to the objective."

## Current State

### How It Works Today

The integration runs as an ELT pipeline with three phases per resource: **Extract → Transform → Load**.

**Two parallel entry points:**

| Mode | Entry Worker | Config Check | Connectivity Check |
|------|-------------|-------------|-------------------|
| API | `ApiIntegrator` | `Source` count, `Stream` enabled count | `HealthCheck::Processor` → `ConnectionCheck::Processor` (HTTP health + auth) |
| Database | `DatabaseIntegrator` | `Database.connect!`, telnet to host:port | Permission check, lock check, throughput check |

**Integration mode** is currently determined by the `INTEGRATION_MODE` environment variable (`api` or `database`), accessed via `ApplicationConfiguration.api_integration?` / `ApplicationConfiguration.database_integration?`. This is a per-deployment global — each client instance runs in exactly one mode.

**Resource processing (per resource type, e.g., Deal):**

- **API path**: `ApiExtractor` → `ApiTransformer` → `LoaderProducer` → `LoaderConsumer`
- **Database path**: `DatabaseExtractor` → `DatabaseTransformerProducer` → `DatabaseTransformerConsumer` → `LoaderProducer` → `LoaderConsumer`

The Loader phase is shared — both paths converge at `LoaderProducer`/`LoaderConsumer` which sends data to the 4Shark API.

**Resource execution order is hardcoded** in the workers themselves. Each resource's extractor, upon completion, triggers the next resource's extractor (e.g., `Deal::DatabaseExtractor` finishes → calls `DealExtraField::DatabaseExtractor`).

**MongoDB models for API mode:**

- `ExternalApplication` — Represents an external API system (has auth, health check, timezone, resource limit)
- `ExternalResource` — Represents a resource type (Deal, User, etc.) that can be fetched, links to a Ruby class via `resource_name`
- `ApplicationProgrammingInterface` — The actual API endpoint config (URI, query templates, attribute mappings, headers, sensitive keys). Belongs to both `ExternalApplication` and `ExternalResource`
- `AttributeMapping` — Maps source fields to target fields with transformers (dynamic, fixed, template, formula)
- `Authentication` — OAuth/token auth config for an `ExternalApplication`
- `HealthCheck` — Health endpoint for an `ExternalApplication`

**MongoDB models for database mode:**

- `Database` — A plain Ruby class wrapping a Sequel connection pool. Uses `fsk_*` normalized table schema.
- No MongoDB configuration — the normalized schema IS the configuration. Table names are hardcoded in `DATA_SOURCE_TABLES`.

### Implementation Progress

Significant implementation has already happened across three merged PRs:

**PR #2087 — Domain Model Restructure:**
- Renamed `ExternalApplication` → `Source` (STI: `ApiSource`, `DatabaseSource`)
- Renamed `ExternalResource` → `Stream` (with `position` field)
- Renamed `ApplicationProgrammingInterface` → `Connector` (single class, no STI)
- `Authentication` now has STI: `DatabaseAuthentication`, `SalesForceAuthentication`, `TrackmobAuthentication`
- `HealthCheck` belongs to `Source` with unified `reachable?` (HTTP for API, TCP for database)
- Credentials on `DatabaseSource` moved to `DatabaseAuthentication` (username/password encrypted via symmetric-encryption)
- Connector has conditional validations via `api_source?`/`database_source?` (delegates to source)
- All 48 worker files updated, views, controllers, routes, locales (3 languages), specs
- Source type selection via `?type=` query param, submenu buttons
- 600 tests passing, rubocop clean, brakeman clean

**PR #2088 — Adapter Refactoring + Stream Simplification + Managed Extraction:**
- `ApplicationConfiguration.connection_params` centralized hash based on adapter type
- `DatabaseSource#connect!` returns adapter instance using `configuration` as override
- `role` field removed from Stream — `resource_name` now carries full name (e.g., `User::Admin`)
- 24 `ManagedDatabaseExtractorProducer` + 24 `ManagedDatabaseExtractorConsumer` workers created

**PR #2090 — Managed Transformation:**
- 24 `ManagedDatabaseTransformerProducer` + 24 `ManagedDatabaseTransformerConsumer` workers created

**Key model evolution**: The original DDD plan called for `DatabaseRegistration` as a separate model. In practice, it became `DatabaseSource` (STI subclass of `Source`). Similarly, `IntegratorConfiguration` (singleton for persisted mode) was not created — `ApplicationConfiguration` continues to handle integration mode via env var.

### What Works Well

- The ELT pipeline structure (Extract → Transform → Load) is solid and well-proven
- The Loader phase is already shared between API and database paths
- The `Resource` model with its state machine and import tracking works for both modes
- The `Collection` model for batching extracted data works for both modes
- The `Job` model tracks execution metrics, timing, and error aggregation effectively
- The `Computation` model provides reliable distributed coordination via Redis locks and counters
- The `AttributeMapping` system for API mode is flexible (dynamic, fixed, template, formula kinds with transformers)
- The reporting system (email alerts for health check failures, connection failures, throughput anomalies, etc.) is comprehensive
- Per-resource worker isolation allows independent scaling via Sidekiq queues
- The new Source/Stream/Connector model is already working for managed database extraction and transformation

### Pain Points

- **Binary mode switch** — `INTEGRATION_MODE` is a global env var per deployment; no way to mix API and database sources for a single client, and requires redeploy to change
- **Duplicate worker trees** — 44 self-service workers + 96 managed workers for what is conceptually the same pipeline
- **`Import#identifier` has mode branching** — `ApplicationConfiguration.api_integration?` checks scattered throughout model code to decide whether to prefix with `4sk_`
- **Self-service has no MongoDB configuration** — extraction relies on hardcoded `fsk_*` table names and env vars. When self-service is absorbed, these clients need seed-generated config.

### Difficulties

- No client uses the managed models in production — no backwards compatibility needed for MongoDB collections
- The management interface (separate project) configures Source/Stream/Connector — any model change requires coordinated updates
- No client is using API mode in production yet, which means the API path is untested at scale but also means there is no migration burden for API-mode data
- The hardcoded resource execution order (subsidiary → group → user → deal → ...) reflects business dependencies that need to be preserved even if the ordering mechanism changes
- Zero-downtime requirement: existing self-service clients must continue working during the migration. The seed task must run BEFORE the code deploy that removes self-service workers.
- After the unified flow is deployed, execution depends on having Stream records in MongoDB. Clients without seeded config will NOT run.

## Domain Concepts

### Current Terms (Post-PR #2087 codebase)

| Term | Definition |
|------|------------|
| Integration Mode | Global switch (`self_service` or `managed`) that determines how data is extracted for the entire client deployment |
| Source | STI parent model. Represents an external system the integrator connects to. Subclasses: `ApiSource` (API system with auth, health check, pagination) and `DatabaseSource` (database with host, port, adapter, credentials via DatabaseAuthentication) |
| Stream | A type of business entity (User, Deal, Goal, etc.) extracted from a single Source. Owns the extraction config (query templates, primary key, cursor field, pagination) and the transformation config (embedded attribute mappings and sensitive keys). Belongs to a Source and a ResourceType. |
| ResourceType | Catalog of known resource types (Subsidiary, Hierarchy, User, Client, Product, …). Holds the `identifier_prefix` for resources that need one (only `User` today, with `4sk_`). Referenced by Stream via `belongs_to :resource_type`. |
| Connector | SUPERSEDED. Originally introduced in PR #2087 as an intermediate entity between Source and Stream. Deleted in this refinement — its fields migrate to Stream. |
| Attribute Mapping | Rules for transforming a source field into a target field. Supports dynamic (path traversal), fixed (constant), template (Liquid), and formula (Dentaku) kinds |
| Resource | A MongoDB document representing a business entity (User, Deal, Goal, etc.) with its integration state machine and import history |
| Import | A snapshot of data extracted for a Resource during a specific Job. Embedded in the Resource document |
| Collection | A batch of raw extracted data for a specific resource type, belonging to a Job |
| Job | A single execution run of the integration pipeline. Tracks timing, metrics, and errors |
| Computation | Redis-based distributed coordination for tracking queue sizes and execution counts within a Job |
| Database | Sequel connection pool wrapper for accessing the client's normalized `fsk_*` tables (self-service mode only — will be removed when self-service is absorbed) |
| Health Check | Reachability verification for a Source. HTTP for API sources, TCP for database sources |
| Normalized Database Source | A `DatabaseSource` with `normalized: true` flag. Represents a client whose data is in the `fsk_*` canonical schema. No attribute mappings needed (bypass). The `4sk_` prefix applied only to user-derived identifiers, via the `identifier_prefix` field on the `User` ResourceType |
| Bootstrap Task | `rake integration:normalized:bootstrap` — creates ResourceType, DatabaseSource, DatabaseAuthentication, HealthCheck, and one Stream per resource (with query templates pre-filled) from existing environment variables. Idempotent. Used to migrate self-service clients to the unified flow |
| Transformer Bypass | When `source.normalized?`, the transformer saves raw data directly to `import.data` without applying attribute mappings. For User streams, also performs parent lookup query |

### Industry-Standard Integration Terminology

Research into established integration platforms (Airbyte, Fivetran, Meltano/Singer) reveals consistent terminology:

| Industry Term | Definition | Used By |
|---------------|-----------|---------|
| **Source** | The origin system from which data is extracted. Can be a database, API, file, or SaaS application | Airbyte, Fivetran, Meltano |
| **Connector** | A component that knows how to connect to and extract data from a specific type of source (or load into a destination). Source Connectors and Destination Connectors | Airbyte, Fivetran |
| **Tap** / **Target** | Singer protocol terms for source connector (tap) and destination connector (target) | Meltano/Singer |
| **Connection** | A configured pipeline linking a source to a destination, defining what data flows and how | Airbyte |
| **Stream** | A group of related records within a connection (analogous to a table or resource type) | Airbyte |
| **Catalog** | A list of streams available in a source, describing the data structure | Airbyte |
| **Sync** | A single execution of a connection that moves data from source to destination | Airbyte, Fivetran |
| **Sync Mode** | How data is read (full refresh vs incremental) and written (append vs overwrite vs deduped) | Airbyte |

### Proposed Ubiquitous Language (Validated and Implemented)

| Proposed Term | Replaces | Rationale | Status |
|---------------|----------|-----------|--------|
| **Self-Service Integration** | Current `database` mode with `fsk_*` tables | Industry-standard iPaaS/B2B SaaS term. The client has an engineering/IT team, normalizes data into 4Shark's canonical schema (`fsk_*` tables), and the integrator just pulls. No Source/Stream/Connector configuration needed. Stored as `self_service` in MongoDB | Terminology adopted; code absorption pending |
| **Managed Integration** | Current `api` mode + new mixed mode | Industry-standard iPaaS/B2B SaaS term. 4Shark connects to the client's systems, discovers data, builds queries/API calls, configures mapping. Uses Source, Stream, Connector configured in MongoDB. Can be API, database queries, or both mixed per resource. Stored as `managed` in MongoDB | Terminology adopted; unified workers in progress |
| **Source** (STI: ApiSource, DatabaseSource) | `ExternalApplication` + `Database` | Industry-standard. A source is where data comes from — whether API or database. Each source has its own connectivity and health check semantics. In 4Shark's domain, the Data Source concept fulfills this role | Implemented (PR #2087) |
| **Connector** | `ApplicationProgrammingInterface` + implicit database adapter | SUPERSEDED by the 2026-04-10 refinement. Industry research showed no platform uses "Connector" as an intermediate entity between Source and Stream — the extraction config belongs to the Stream itself. Being deleted; fields migrate to Stream | Reversed — deletion in progress |
| **Stream** | `ExternalResource` + `Connector` | Industry-standard. A stream is a unit of data flowing through the pipeline (User, Deal, Goal) with its own extraction config (query template, cursor, primary key, pagination) and transformation config (attribute mappings, sensitive keys). Matches Airbyte's `ConfiguredStream` and Singer's stream metadata | Expanded with Connector absorption |
| **ResourceType** | `Stream.resource_name` (String field) | A catalog of known resource types with per-type metadata (notably `identifier_prefix`). Replaces the String-based `resource_name` with a proper `belongs_to` association. Introduced by the 2026-04-10 refinement | NEW |
| **DatabaseAuthentication** | Credentials on DatabaseSource | Credentials have independent lifecycle from source metadata. Encrypted via symmetric-encryption | Implemented (PR #2087) |
| **Data Source** | Part of `ExternalApplication` + `Database` + `INTEGRATION_MODE` | Engineer-confirmed term. Each integration definition has a Data Source declaring its type — API (pointing to an API application) or Database (pointing to a database registration with host, port, credentials). This is per-stream, not global | Implemented as Source STI (PR #2087) |

## Constraints

### Technical Constraints

- MongoDB stores configuration (Source, Stream, Connector) and integration data (Resources, Imports). Model renames done in PR #2087 — no backwards compatibility needed, no production data exists
- Sidekiq workers are the execution backbone — any restructuring must work within Sidekiq's async job model
- Redis is used for distributed locks and computation counters — this coordination pattern must be preserved
- The management interface (separate project) reads/writes the MongoDB configuration models — changes must be coordinated
- **Zero-downtime migration**: The seed task (`rake integration:seed_normalized`) must run on each self-service client BEFORE deploying the code that removes self-service workers. After the unified code is deployed, execution depends on having Stream records in MongoDB. Clients without seeded config will NOT run.

### Business Constraints

- **There IS external pressure** — When 4Shark deploys the normalized database approach, clients often cannot integrate on their own because they lack the technical team to normalize data into `fsk_*` tables. 4Shark ends up doing all the integration work for them
- **Rapid onboarding target** — The integrator must be dynamic enough that a 1-2 hour call between the operations team and the client is sufficient to discover where the data lives, configure the extraction, and run the integration. AI-assisted data discovery is part of this vision
- **Complete vision in all planning documents** — The engineer decided that all documents must reflect the full target state even if implementation is phased, to avoid decisions that prevent reaching the goal
- The `fsk_*` normalized database schema must continue to work as-is for existing self-service clients (via seed task generating equivalent config)
- Resource execution order reflects real business dependencies (e.g., subsidiaries before users, users before deals) — configurability must not break these constraints

### Operational Constraints

- Each client runs as an isolated deployment (separate EC2 instance, ECS services, MongoDB, Redis)
- Configuration changes happen via the management interface, not code deploys
- The reporting/alerting system (email reports for failures) must work for all source types
- **Web management interface dependency** — The web app reads MongoDB directly to render integration configuration. It needs to know the integration mode to show the appropriate UI

## Answered Questions

- **How should `INTEGRATION_MODE` be stored?** — Currently as environment variable. Will eventually be obsolete when self-service is absorbed (only managed flow exists).
- **What are the integration modes called?** — Self-Service Integration and Managed Integration. These are industry-standard iPaaS/B2B SaaS terms confirmed by research.
- **What happens to the `fsk_*` mode?** — It becomes a DatabaseSource with `normalized: true`. The seed task auto-generates Stream/Connector/Source records from env vars.
- **What about mixed API+database clients?** — This is Managed Integration. A managed client can have any mix of API and database sources per resource.
- **Normalized DB type** — `normalized` Boolean flag on `DatabaseSource`, not a subclass.
- **User role split** — Inherent to source type. Normalized = single stream (code guarantees order). Custom DB/API = separate streams per role (config guarantees order).
- **Throughput/lock checks** — Absorbed into ManagedIntegrator, triggered when source is DatabaseSource.
- **DatabaseWarmer** — Absorbed as optional step for DatabaseSource with warm-up.
- **AttributeMappings for normalized** — NO mappings. Transformer does bypass when `source.normalized?`. Avoids maintenance of column lists.
- **How to detect bypass** — NOT by absence of mappings (fragile). By `DatabaseSource.normalized?` flag (explicit).
- **Should `Job` be renamed to `Sync`?** — No. Referenced in 50+ files; rename cost disproportionate to benefit.
- **What is the exact mapping between current MongoDB models and the proposed new terminology?** — Resolved by PR #2087: `ExternalApplication` → `Source` (STI: ApiSource, DatabaseSource), `ExternalResource` → `Stream`, `ApplicationProgrammingInterface` → `Connector`. `DatabaseRegistration` was planned but became `DatabaseSource` instead. **Updated 2026-04-10**: `Connector` is being deleted — its fields (`query_template`, `paginated_query_template`, `primary_key`, `fetch_since_column`, `page_size`, `collection_source`, `success_response_status_code`, embedded `attribute_mappings` and `sensitive_keys`) migrate to `Stream`. `Connector.headers` is deleted outright (dead code — auth headers come from `Source.authenticated_headers`). A new `ResourceType` entity replaces `Stream.resource_name` (String field).
- **How do health checks and connection checks work for managed clients with mixed sources?** — Both check types run before extraction. API: HealthCheck HTTP GET + auth POST. Database: HealthCheck TCP check. Any failure aborts entire job.
- **How does the "database registration" concept relate to the `Database` class?** — `DatabaseRegistration` became `DatabaseSource` (STI subclass of Source). `Database` class remains the runtime Sequel pool for self-service (removed in Phase 5). `DatabaseSource#connect!` handles managed connections.
- **Where exactly in MongoDB does the `integration_mode` field live?** — It stays as `INTEGRATION_MODE` env var via `ApplicationConfiguration`. IntegratorConfiguration (MongoDB singleton) was planned but not created. Phase 5 removes the mode concept entirely.

## Open Questions

- How should the management interface evolve to support configuring Data Sources (both API and Database types) per stream? Is this a new screen, an extension of existing screens, or a completely redesigned configuration flow?
- Should the hardcoded resource execution order become configurable per client, or should it remain a fixed sequence defined in code?
- What does the AI-assisted data discovery workflow look like in practice? Does AI connect to the client's database, explore tables/columns, suggest queries, and validate data — all within the 1-2 hour call?
- How should the integrator expose data for the web management interface? The web app needs: integration mode, job stats, last job date, and (for managed mode) Source/Stream/Connector data. Is this via direct MongoDB reads or an API?
- What is the migration strategy for the web management interface after Source/Stream/Connector renames? It currently reads MongoDB directly — when does it update to use new model names?

## Key Insights

- **The Loader phase is already source-agnostic** — both API and database paths converge at `LoaderProducer`/`LoaderConsumer`. This validates that the pipeline can be unified at the transformation output level.
- **No client uses API mode in production** — this was the ideal moment to rename API-related MongoDB models. There was no data migration burden for API-mode documents.
- **The `ExternalResource` concept already maps cleanly to "Stream"** — it represents a type of data (User, Deal, Goal) that flows through the pipeline, with enable/disable control. Industry terminology would call this a stream.
- **The industry consistently separates "Source" (system) from "Connector" (extraction config)** — this maps well to the current split between `ExternalApplication` (the system) and `ApplicationProgrammingInterface` (the endpoint config). A database equivalent would be: the database server (Source) and a specific query configuration (Connector). This has been implemented.
- **The `AttributeMapping` system is already generic** — it maps source fields to target fields with transformers. This works for both API responses and database query results without modification.
- **Worker duplication is a symptom, not the root cause** — the ~14 workers per resource exist because the extraction and transformation logic is coupled to the source type. Decoupling via a Connector abstraction reduces this.
- **Self-Service vs Managed is an operating model distinction, not a technical one** — Self-Service means the client normalizes data into `fsk_*` tables; Managed means 4Shark does everything. These are different operational contracts with different responsibilities, not just different extraction mechanisms. At the code level, both will run through the same managed flow.
- **Integration mode belongs in MongoDB, not environment variables** — Moving `INTEGRATION_MODE` from env var to MongoDB enables: the web UI to render mode-appropriate screens without redeploy, runtime mode changes, and a single source of truth for client configuration.
- **Data Source is a first-class domain concept** — Source (STI: ApiSource, DatabaseSource) with per-stream binding replaces the global `INTEGRATION_MODE` switch with per-stream source configuration.
- **Domain model first, worker changes later** — the engineer explicitly stated that workers are NOT in scope for the initial modeling. The priority is getting the domain concepts right. Worker restructuring follows naturally but is a separate concern.
- **Rapid client onboarding is the driving business pressure** — clients cannot self-integrate because they lack technical teams. The integrator must be dynamic enough that operations can configure a new client in a 1-2 hour call, with AI helping to discover where data lives and validate queries.
- **The database extractor query may become dynamic** — rather than creating new worker types, the existing database extractor could evolve to accept dynamic queries from configuration instead of relying on hardcoded `fsk_*` table names. This is a potential implementation path but depends on the domain model.
- **Plan for the complete vision, implement in phases** — the engineer decided all planning documents must reflect the full target state. The rationale is that incomplete planning leads to decisions that block future goals.
- **The web management interface is a key consumer of the domain model** — although the web interface is a separate project (out of scope for implementation), it drives requirements on the integrator's domain: the integration mode must be queryable, managed mode needs Source/Stream/Connector data exposed, self-service needs database connection status and schema validation data.
- **The managed flow has ALREADY absorbed most of what was needed** — PRs #2087, #2088, #2090 implemented the domain model restructure, managed extraction, and managed transformation. What remains is narrow: Phase 4 (unified workers with API consumer separation) and Phase 5 (seed task + self-service worker deletion).
- **44 self-service workers will be deleted** — 14 DatabaseExtractor + 14 DatabaseTransformerProducer + 14 DatabaseTransformerConsumer + DatabaseIntegrator + DatabaseWarmer. Plus the Database singleton, DatabaseConnectionMiddleware, and all self-service env vars.

**Status:** KNOWLEDGE EXTRACTION COMPLETE — Implementation in progress
