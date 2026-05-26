# DOMAIN - Dynamic Integration Mode

> Reference: KNOWLEDGE.md, PROCESS.md

## Domain Refinement (2026-04-10)

This document was updated after a late-stage domain review. See the matching section in
KNOWLEDGE.md for the full rationale. Summary of the breaking changes reflected below:

- **`Connector` is deleted.** Its fields migrate to `Stream` (see updated Stream entity).
  Sections marked `SUPERSEDED — absorbed into Stream` document what was removed.
- **`ResourceType` is a new entity.** Replaces `Stream.resource_name` (String) with a proper
  catalog of resource types. Holds `identifier_prefix` (moved from Source).
- **`identifier_prefix` moved from `Source` to `ResourceType`.** Only `User` has a prefix
  (`4sk_`) in the NORMALIZED_REGISTRY.
- **`Stream.position` removed.** Execution order remains hardcoded in the worker chain.
- **`Stream.resource_name` (String) removed.** Replaced by `belongs_to :resource_type`.
- **Liquid render unified.** DB extractor reworked to use Liquid template render (same mechanism
  as API), driven by a single extended `Variables` class with `page`, `previous_record_id`, and
  `page_size` injected alongside the existing 32 date-derived keys.
- **`Import` reaches the User prefix via `ResourceType.find_by(name: 'User')`** — not via
  `stream.resource_type`, because the import's own stream is usually NOT a User stream.
- **`Resource.streams`** is a class method on Resource STI subclasses (Subsidiary.streams,
  Deal.streams, ...) — replaces `Stream.for_resource` scope.
- **`Connector.headers` is dead code** — auth headers come from `Source.authenticated_headers`.
  Deleted outright, not migrated.

## Overview

The Unified Integration Flow restructures the integrator's domain model into a single pipeline
for all clients. Industry-standard terminology (Source, Stream, Connector) has been implemented
(PR #2087). Source uses STI with `ApiSource` and `DatabaseSource` subclasses. The managed flow
handles both database and API extraction (PRs #2088, #2090).

The remaining work unifies the worker tree (Phase 4) and absorbs the self-service flow entirely
(Phase 5), after which there is only ONE execution path. Self-service becomes a configuration
of managed — a `DatabaseSource` with `normalized: true`.

**Implementation status**: The domain model restructure is complete (PR #2087). Key differences
from the original plan: `DatabaseRegistration` became `DatabaseSource` (STI subclass of Source),
`IntegratorConfiguration` was not created (ApplicationConfiguration continues handling mode),
and Connector does not use STI (single class, source type determines behavior).

Models that are already well-designed and source-agnostic — `Resource`, `Import`, `Collection`,
`Job`, `Computation`, `Lock`, `Account`, `JobMetric` — remain untouched.

---

## Entities

### IntegratorConfiguration — NOT IMPLEMENTED

> **Superseded**: This entity was planned but not created. `ApplicationConfiguration` continues
> to handle integration mode via the `INTEGRATION_MODE` environment variable. When self-service
> is fully absorbed (Phase 5), `INTEGRATION_MODE` will be removed entirely — there will be only
> one flow (managed), so no mode field is needed.

### Source (STI Parent — IMPLEMENTED PR #2087)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: STI parent model representing an external system the integrator connects to.
  Subclasses: `ApiSource` (API systems) and `DatabaseSource` (database systems).
- **Relationships**:
  - has_many :streams (direct — Connector deleted by 2026-04-10 refinement)
  - has_one :authentication (STI: DatabaseAuthentication, SalesForceAuthentication, TrackmobAuthentication)
  - has_one :health_check (unified: HTTP for API, TCP for database)
- **MongoDB Collection**: `sources`
- **No `identifier_prefix` field.** The 2026-04-10 refinement moved `identifier_prefix` to
  `ResourceType`. Source has no identifier concerns.
- **Planned removal**: `normalized` field stays on `DatabaseSource` (not Source). The existing
  `normalized` field on `Source` introduced in PR #2120 is removed — only DatabaseSource needs it.

### ApiSource < Source (IMPLEMENTED PR #2087)

- **Purpose**: Represents an external API system (SalesForce, Trackmob, etc.)
- **State**:
  - `identifier`: String (4 chars, unique) - short code
  - `name`: String - human-readable name
  - `resource_limit`: Integer (default 0) - page size for API pagination
  - `timezone`: String - timezone for date calculations in query templates
- **Behavior**:
  - `last_page?(collection_size)`: determines if API pagination is complete
  - `authenticated_headers()`: delegates to Authentication for HTTP headers

### DatabaseSource < Source (IMPLEMENTED PR #2087)

- **Purpose**: Stores database connection configuration for managed database sources.
  Originally planned as `DatabaseRegistration` — became a Source subclass instead.
- **State**:
  - `name`: String - human-readable name
  - `host`: String - database server hostname or IP
  - `port`: Integer - database server port
  - `database_name`: String - target database name
  - `adapter`: String (`microsoft_sql_server` | `postgres_sql_server`)
  - `azure`: Boolean (default false) - Azure SQL connection flag
  - `timeout`: Integer (default 5) - connection timeout in seconds
- **Planned fields (Phase 5)**:
  - `normalized`: Boolean (default false) — when true, represents a self-service client's
    canonical `fsk_*` database. Transformer bypasses attribute mappings.
  - `table_prefix`: String (default nil) — from `TABLE_PREFIX` env var
- **Behavior**:
  - `connect!()`: returns adapter instance using `configuration` as override (implemented PR #2088)
  - `normalized?()`: returns true if `normalized` flag is set (Phase 5)
- **Credentials**: Stored in `DatabaseAuthentication` (username, password encrypted via
  symmetric-encryption), not on the model itself
- **MongoDB Collection**: `sources` (shared with ApiSource via STI)

### Stream (RENAME of ExternalResource, ABSORBED Connector fields — 2026-04-10)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: A stream is a unit of data flowing through the pipeline from a single Source. It
  knows **how to extract** (query templates, pagination, cursor) and **how to transform**
  (attribute mappings, sensitive keys). Matches Airbyte's `ConfiguredStream` and Singer's stream
  metadata. After the 2026-04-10 refinement, Stream absorbs all responsibilities that previously
  lived in `Connector`.
- **State**:
  - `name`: String - human-readable label (e.g., "Users", "Deals")
  - `disabled`: Boolean (default false) - whether this stream is excluded from integration runs
  - `source_id`: ObjectId - points to a Source (ApiSource or DatabaseSource)
  - `resource_type_id`: ObjectId - points to a ResourceType (replaces `resource_name` String)
  - **Extraction config (absorbed from Connector):**
    - `query_template`: String (Liquid) - template used when `previous_record_id` is nil (first
      page or no pagination). Works for both DB (SQL) and API (URL) sources
    - `paginated_query_template`: String (Liquid) - template used when `previous_record_id` is
      present. In DB this adds `AND id > {{ previous_record_id }}`; in API this may point to a
      different endpoint (e.g., `/page/{{ page }}`)
    - `primary_key`: String (default `id`) - cursor key for incremental extraction
    - `fetch_since_column`: String (default `updated_at`) - column or field used for incremental
      filtering (= Airbyte `cursor_field`, Singer `replication-key`)
    - `page_size`: Integer - batch size (falls back to `ApplicationConfiguration.sql_page_size`)
    - `collection_source`: String - dot-path to the collection inside the API response body
      (API only; nil for database streams)
    - `success_response_status_code`: String - expected HTTP status (API only)
- **Removed fields**:
  - `resource_name` (String) - replaced by `belongs_to :resource_type`
  - `position` (Integer) - never used; ordering remains hardcoded in the worker chain
- **Behavior**:
  - `resource()`: delegates to `resource_type.resource` (constantized class)
  - `enable()` / `disable()`: toggles the `disabled` flag
  - `enabled?()` / `disabled?()`: query helpers
  - `api_source?()` / `database_source?()`: delegates to `source`
  - `normalized_source?()`: delegates to `source.normalized?` (DatabaseSource only)
  - `render_query(variables)`: renders the appropriate Liquid template. Picks
    `paginated_query_template` when `variables['previous_record_id']` is present, otherwise
    `query_template`. Used uniformly by both DB and API extractor consumers
- **Validations**:
  - `name`, `source_id`, `resource_type_id` presence
  - `query_template` presence
  - At least one embedded `attribute_mapping` with `primary: true` — **unless**
    `source.normalized?` (normalized bypass has no mappings)
- **Lifecycle**: Created during managed onboarding or by the `integration:normalized:bootstrap`
  rake task for normalized clients. Updated when source assignment, query, or mappings change.
- **Relationships**:
  - belongs_to :source
  - belongs_to :resource_type
  - embeds_many :attribute_mappings (absorbed from Connector)
  - embeds_many :sensitive_keys (absorbed from Connector — API only semantically)
- **MongoDB Collection**: `streams`
- **Note on headers**: `Connector.headers` (embedded) is NOT migrated — it was dead code. All
  HTTP requests use `source.authenticated_headers` (from `Source`'s `Authentication`).

### Connector — SUPERSEDED (deleted by 2026-04-10 refinement)

> **Status**: Deleted. Industry research (Airbyte, Fivetran, Singer) confirmed that "Connector"
> is not an entity between Source and Stream in any established data movement platform. In 4Shark
> the Connector was holding config (query, primary_key, cursor, mappings) that conceptually
> belongs to the Stream itself. Fields migrated as follows:
>
> - `uri`, `query_template`, `paginated_query_template`, `collection_source`,
>   `success_response_status_code`, `primary_key`, `fetch_since_column`, `page_size` → **Stream**
>   (see updated Stream entity above)
> - `embeds_many :attribute_mappings` → **Stream**
> - `embeds_many :sensitive_keys` → **Stream**
> - `embeds_many :headers` → **DELETED** (dead code; no extractor ever read it — auth headers
>   come from `source.authenticated_headers` via the Source's Authentication)
> - `query(attributes)` Liquid render method → moved to **`Stream#render_query`**
> - `unexpected_response?` → moved to Stream (API only)
> - `table_name` field → never implemented; bootstrap writes the table name directly into the
>   Liquid template (`SELECT * FROM fsk_clients WHERE ...`)
> - `has_many :api_requests` → `ApiRequest` is itself being deleted in Phase 4 (replaced by
>   `Collection.raw_body` in S3)
>
> The `connectors` MongoDB collection is dropped.

### ResourceType — NEW (introduced 2026-04-10)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: Catalog of known resource types (Subsidiary, Hierarchy, User, Client, Product,
  Group, Groupification, UserField, UserActivity, Deal, DealExtraField, Modifier, Goal,
  UserIdentifier, …). Holds the `identifier_prefix` for resources that need prefixed IDs (only
  `User` today, with `4sk_`). Replaces the `Stream.resource_name` String field with a proper
  reference model.
- **State**:
  - `name`: String - must match a `Resource` STI subclass name exactly (e.g., `'User'`, `'Deal'`,
    `'User::Admin'` in the managed mode where User is split per role). Unique, indexed.
  - `identifier_prefix`: String (optional) - prefix applied to user-derived identifiers. Only
    `User` has this set (`'4sk_'`) in the NORMALIZED_REGISTRY. Other resource types return nil.
- **Constants**:
  - `NORMALIZED_REGISTRY` - array of 14 hashes defining the resource types needed for the
    normalized/self-service flow. Only `User` carries `identifier_prefix: '4sk_'`. Used by the
    `integration:normalized:bootstrap` rake task to idempotently create ResourceTypes and Streams.
- **Behavior**:
  - `resource()`: `@resource ||= name.constantize`
  - `user?()`: `name == 'User'` (or `name.start_with?('User')` for managed role variants)
- **Lifecycle**: Created by the bootstrap rake task for normalized clients, or by the management
  interface for managed clients. Rarely changes after creation.
- **Relationships**:
  - has_many :streams
- **MongoDB Collection**: `resource_types`
- **Validations**: `name` presence and uniqueness (with unique index)
- **Note on User prefix derivation**: The prefix is resolved by `Import#user_identifier_prefix`
  via `ResourceType.find_by(name: 'User')`, **not** via the import's own stream. This is
  because when loading a Deal, `import.stream.resource_type` is `Deal` (not `User`), but the
  Deal payload references user IDs that must carry the User prefix.

### Authentication (UNCHANGED)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: OAuth/token authentication configuration for an API source. Uses STI with
  `SalesForceAuthentication` and `TrackmobAuthentication` subclasses.
- **State**:
  - `endpoint`: String - auth endpoint URL
  - `client_id`, `client_secret`, `email`, `username`, `password`, `security_token`: String -
    credential fields (usage varies by subclass)
  - `grant_type`: String - OAuth grant type
  - `success_response_status_code`: String - expected HTTP status for auth success
- **Behavior**:
  - `successful_response?(response)`: checks response status
  - `uri()`: builds auth request URI (implemented per subclass)
  - `data()`: returns request body (implemented per subclass)
  - `headers()`: returns request headers (implemented per subclass)
  - `authenticated_headers()`: returns headers with Bearer token from stored response
- **Lifecycle**: Created alongside Source. Updated when credentials rotate.
- **Relationships**:
  - belongs_to :source (was `external_application`)
  - has_one :response (class: AuthenticationResponse)

### HealthCheck (UNCHANGED)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: HTTP health endpoint for verifying an API source is reachable before extraction.
- **State**:
  - `endpoint`: String - health check URL
  - `success_response_status_code`: String - expected HTTP status
- **Behavior**:
  - `successful_response?(response)`: checks response status
  - `uri()`: parses endpoint to URI
- **Relationships**:
  - belongs_to :source (was `external_application`)

### Job (UNCHANGED)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: A single execution run of the integration pipeline. Tracks timing, metrics, and
  error aggregation. The term "Job" is preserved despite industry preference for "Sync" because
  it is deeply embedded in the codebase and well-understood.
- **State**:
  - `starts_at`, `ends_at`, `fetch_ends_at`, `transformation_ends_at`: DateTime - phase timing
  - `fetch_since`: DateTime - incremental extraction boundary
  - `application_version`, `database_version`, `integration_version`: String - version tracking
  - `total_external_applications`: Integer - source count at job start
  - `total_external_resources`: Integer - enabled stream count at job start
  - `successful_requests_quantity`, `failed_requests_quantity`, `total_requests_quantity`:
    Integer - request counters
- **Behavior**:
  - `start()`: class method, creates job with `starts_at`
  - `finish()`, `finish_extraction()`, `finish_transformation()`: mark phase completions
  - `duration()`, `extraction_duration()`, `transformation_duration()`, `load_duration()`:
    computed timing
  - `aggregate_errors!()`: runs aggregation pipeline to compute request statistics
  - `computation()`: returns Computation instance for distributed coordination
- **Relationships**:
  - has_many :api_requests, :*_collections (14 collection types), :table_locks
  - has_one :metric (JobMetric)
- **Note**: `total_external_applications` and `total_external_resources` are legacy field names
  that store source count and enabled stream count respectively.

### Resource (UNCHANGED)

- **Identity**: `_id` (MongoDB ObjectId) + `external_id` (String, unique per STI type)
- **Purpose**: A business entity (User, Deal, Goal, etc.) with its integration state machine and
  import history. Uses STI for each entity type. Source-agnostic — works identically for both
  self-service and managed extraction.
- **State**:
  - `external_id`: String - identifier from the source system
  - `integration_status`: Integer (enum: unknown, pending, integrated, disabled, erased)
  - `model_version`: String (default `1.0`)
- **Behavior**:
  - State machine: pending -> integrated -> disabled -> erased (with transitions)
  - `get(id)`: finds by external_id, restores from S3, or creates stub
  - `restore_from_s3(id)`: restores archived document
- **Relationships**:
  - embeds_many :imports
- **STI Subclasses**: User, Deal, Goal, Group, Groupification, Client, Product, Subsidiary,
  Hierarchy, UserIdentifier, UserField, UserActivity, DealExtraField, Modifier, Password,
  TableLocks

### Import (MODIFIED — 2026-04-10 refinement)

- **Identity**: `_id` (MongoDB ObjectId), embedded in Resource
- **Purpose**: A snapshot of data extracted for a Resource during a specific Job. Contains the
  transformed data hash and tracks which job produced it.
- **State**:
  - `data`: Hash - transformed record data
  - `model_version`: String (default `2.0`)
- **Removed fields**:
  - `source_type` - never needed; the link to the stream already carries source information
- **Relationships**:
  - embedded_in :resource
  - embeds_many :requests
  - belongs_to :stream (optional) - set by the transformer when the import is produced by the
    managed flow. Used for traceability. Replaces the earlier `belongs_to :source` (PR #2110).
  - belongs_to :job (optional)
  - belongs_to :api_request (optional)
- **Behavior**:
  - `identifier()`: returns `data[:id]` prefixed with `user_identifier_prefix` when present.
    Used exclusively by User loaders (`app/models/user.rb`, `app/workers/user/*/loader_consumer.rb`)
  - `user_identifier()`: returns `data[:user_id]` prefixed with `user_identifier_prefix` when
    present. Used by Deal, Goal, Modifier, UserActivity, UserField, UserIdentifier,
    Groupification, Hierarchy loaders (resources that reference a user by ID in their payload)
  - `parent_identifier()`: returns `data[:parent_id]` prefixed with `user_identifier_prefix` when
    present. Used by Hierarchy loaders (parent user reference)
  - `user_identifier_prefix()`: resolves the prefix in three steps — (1) fallback to `'4sk_'`
    when `ApplicationConfiguration.self_service_integration?` is true (legacy mode bridge,
    removed in Phase 5 cleanup); (2) otherwise `ResourceType.find_by(name: 'User').identifier_prefix`;
    (3) nil if no User ResourceType exists. **Not** derived from `self.stream.resource_type`,
    because an Import of a Deal stream still needs the User prefix for `user_identifier`
  - `request_body()`: delegates to Resource for API request construction
  - Various query helpers: `active?`, `finish?`, `promotion?`, etc.
- **No attr_writer pattern**: The earlier PR #2120 used `attr_writer :user_identifier_prefix`
  threaded via Sidekiq args. The refinement removes this in favor of the ResourceType lookup,
  eliminating the Sidekiq argument and the 14 duplicated lookups in `LoaderProducer` workers.
- **Backward compatibility**: None needed. No production data uses managed flow yet. Self-service
  legacy flow works via the `self_service_integration?` branch.

### Collection (MODIFIED — Phase 4 adds managed fields)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: A batch of raw extracted data for a specific resource type, belonging to a Job.
  Uses STI for each resource type (SubsidiaryCollection, DealCollection, etc.).
- **State**:
  - `raw`: Array - extracted raw records (self-service only — will be removed Phase 5)
  - `connector_id`: BSON::ObjectId - which connector produced this page (managed only, Phase 4)
  - `stream_id`: BSON::ObjectId - which stream this belongs to (managed only, Phase 4)
  - `source_type`: String (`database` | `api`) - source type (managed only, Phase 4)
  - `page`: Integer - page number (managed only, Phase 4)
  - `query`: String - SQL query or HTTP URI (managed only, Phase 4)
  - `status_code`: String - HTTP status code (API managed only, Phase 4)
  - `raw_body`: CarrierWave uploader → S3 - full raw response (managed only, Phase 4)
  - `raw_headers`: CarrierWave uploader → S3 - HTTP headers (API managed only, Phase 4)
- **Behavior**:
  - `pair_ids_for(job_id:)`: self-service only, operates on `raw` array
  - `find_raw_object(raw_object_id)`: self-service only, operates on `raw` array
  - `job_resource_quantity()`: counts records via aggregation
- **Relationships**:
  - belongs_to :job

### ApiRequest (UNCHANGED — association rename only)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: Audit log for API HTTP requests made during extraction. Tracks URI, page number,
  and stores response.
- **State**:
  - `uri`: String - request URI
  - `page`: Integer - pagination page number
- **Relationships**:
  - belongs_to :connector (was `application_programming_interface`) - the API connector that
    produced this request
  - belongs_to :job
  - embeds_one :response (class: ApiResponse)
- **Note**: The `belongs_to` foreign key in MongoDB remains
  The association name is `:connector`.

### Account (UNCHANGED)

- **Identity**: `_id` (MongoDB ObjectId)
- **Purpose**: 4Shark API credentials for the Load phase. Stores the API endpoint and token used
  by LoaderConsumer to push data to 4Shark.
- **State**:
  - `api_endpoint`: String
  - `api_token`: String
  - `primary`: Boolean
- **Behavior**:
  - `api_headers()`: constructs authenticated HTTP headers for 4Shark API calls

---

## Value Objects

### AttributeMapping (MODIFIED — embedded_in changed)

- **Purpose**: Maps a source field to a target field with optional transformation. Supports four
  kinds: dynamic (path traversal), fixed (constant value), template (Liquid), formula (Dentaku).
  Already generic — works for both API JSON responses and database query result hashes.
- **Attributes**:
  - `kind`: Enum (dynamic, fixed, template, formula)
  - `source`: String - source path (dot-separated for dynamic, Liquid template for template,
    Dentaku formula for formula, constant for fixed)
  - `target`: String - target field name
  - `fixed_value`: String - constant value (for fixed kind)
  - `primary`: Boolean - whether this mapping identifies the record
  - `transformer`: String - optional transformer class name
- **Behavior**:
  - `simple(raw_object)`: applies dynamic or fixed mapping
  - `compound(attributes)`: applies template or formula mapping
  - `source_keys()`: splits source by `.` for dig traversal
- **Immutable**: Yes (embedded document, replaced on update)
- **Embedded in**: **Stream** (moved from Connector by 2026-04-10 refinement)

### Header — DELETED (dead code)

> The embedded `Header` value object, previously embedded in `Connector`, was never read by any
> extractor. All HTTP requests use `source.authenticated_headers` (from the Source's
> Authentication). Deleted outright by the 2026-04-10 refinement — not migrated to Stream.

### SensitiveKey (MODIFIED — embedded_in changed)

- **Purpose**: Dot-path reference to a field that should be stripped from stored API responses
  before they reach disk / S3.
- **Attributes**:
  - `value`: String - dot-separated path
- **Behavior**:
  - `path()`: all segments except last
  - `key()`: last segment
- **Immutable**: Yes (embedded document)
- **Embedded in**: **Stream** (moved from Connector by 2026-04-10 refinement). Semantically
  still API-only — database streams leave this empty.

### Variables (MODIFIED — 2026-04-10 refinement: pagination vars added)

- **Purpose**: Generates the hash of variables for Liquid query template rendering. Used
  uniformly by both database and API extractors after the 2026-04-10 unification.
- **Constructor**: `Variables.new(job, source, page: nil, previous_record_id: nil, page_size: nil)`
- **Attributes** — 35 keys:
  - **32 date-derived keys** (unchanged): `fetch_since`, `starts_at`, `resource_limit`,
    and 29 variants like `beginning_of_month_of_fetch_since`, `end_of_year_of_starts_at`,
    `last_month_of_fetch_since`, etc. Computed from `job.fetch_since`, `job.starts_at`,
    `source.timezone`, `source.resource_limit`
  - **`page`** (new) — current page number for paginated API extraction. Nil for
    first-page/database
  - **`previous_record_id`** (new) — cursor value for incremental extraction. In database
    flow, used in the Liquid `{% if previous_record_id %}AND id > {{ previous_record_id }}{% endif %}`
    branch. In API flow, used when the API supports cursor-based pagination
  - **`page_size`** (new) — batch size (from `stream.page_size` falling back to
    `ApplicationConfiguration.sql_page_size`). Makes `LIMIT {{ page_size }}` renderable in
    DB templates
- **Behavior**:
  - `to_h()`: returns the full variables hash for template rendering
- **Usage change**: Previously the API extractor did an inline `.merge({ 'page' => page,
  'previous_record_id' => previous_record_id })` at `managed_api_extractor_consumer.rb:22`. The
  refinement moves that merge into the `Variables` constructor so both DB and API paths use
  a single source of truth for the variable set. If a template doesn't reference a variable,
  Liquid silently ignores it — no harm in always injecting the full set.
- **Immutable**: Yes (computed on construction)

### JobMetric (UNCHANGED)

- **Purpose**: Statistical analysis of historical job throughput for anomaly detection.
- **Attributes**:
  - `values`: Array of historical request quantities
- **Behavior**:
  - `mean()`, `standard_deviation()`: basic statistics
  - `final_values()`, `final_mean()`, `final_standard_deviation()`: filtered statistics
  - `ceiling()`: anomaly threshold (final_mean + 2 * final_standard_deviation)
- **Relationships**:
  - belongs_to :job

---

## Aggregates

### IntegratorConfiguration Aggregate — NOT IMPLEMENTED

> `ApplicationConfiguration` continues to handle integration mode via env var. When self-service
> is absorbed (Phase 5), the mode concept becomes obsolete — only managed flow exists.

### Source Aggregate (API Sources)

- **Root**: Source
- **Members**: Authentication (with AuthenticationResponse), HealthCheck
- **Invariants**:
  - A Source must have exactly one Authentication and one HealthCheck
  - `identifier` must be unique and exactly 4 characters
  - Authentication must be a valid subclass (SalesForceAuthentication or TrackmobAuthentication)
  - Source cannot be deleted while Connectors reference it
- **Boundary**: Source + embedded/associated auth and health check. Connectors are outside the
  boundary (they reference the Source but are managed through the Stream aggregate).

### DatabaseRegistration Aggregate — SUPERSEDED

> Originally planned as a separate aggregate. Became `DatabaseSource` (STI subclass of Source,
> part of the Source Aggregate). See DatabaseSource entity above. Invariants (host, port,
> adapter, database_name required) are now validations on `DatabaseSource`.

### Stream Aggregate (Managed Mode Configuration)

- **Root**: Stream
- **Members**: Connector(s) with embedded AttributeMappings, Headers, SensitiveKeys
- **Invariants**:
  - `resource_name` must map to a valid Resource STI subclass
  - `position` must be unique across enabled streams (no two streams share the same position)
  - If `source_type` is `api`, the referenced Source must exist and have valid auth/health check
  - If `source_type` is `database`, the referenced DatabaseSource must exist
  - A Connector's source must match its Stream's source (same Source instance)
  - At least one AttributeMapping with `primary: true` must exist on each Connector
  - Execution order (position) must respect business dependencies: upstream resources before
    downstream (e.g., Subsidiary before User, User before Deal)
- **Boundary**: Stream + its Connectors + embedded value objects. Source (ApiSource/DatabaseSource)
  is outside (referenced by ID).

### Job Aggregate (Execution Run)

- **Root**: Job
- **Members**: JobMetric, ApiRequests, *Collections (14 types), TableLocks
- **Invariants**:
  - `starts_at` must be present (set at creation)
  - `fetch_since` must be before `starts_at`
  - Phase timestamps must be chronological: starts_at <= fetch_ends_at <= transformation_ends_at <= ends_at
  - Request quantities must be non-negative
  - JobMetric is created on Job creation (after_create callback)
- **Boundary**: Job + all associated execution data. Resources/Imports are outside (Imports
  reference Job by ID but are embedded in Resources).

### Resource Aggregate

- **Root**: Resource (STI subclass)
- **Members**: Imports (with embedded Requests and Responses)
- **Invariants**:
  - `external_id` must be unique per STI type
  - State machine transitions must be valid (pending -> integrated, integrated -> disabled, etc.)
  - Each Import must reference a valid Job
- **Boundary**: Resource + embedded Imports + embedded Requests/Responses. Collections and Jobs
  are outside (referenced by ID).

---

## Domain Services

> **Implementation note**: These services were planned as separate Ruby service objects. In
> practice, their logic was implemented inline in the workers. This section documents the
> conceptual responsibilities and where they live in the actual code.

### ConnectivityChecker — Inline in ManagedIntegrator

- **Purpose**: Verifies that all configured sources are reachable and authorized before an
  integration run begins.
- **Actual implementation**: `ManagedIntegrator` performs health checks for all sources and
  inline API authentication before dispatching the first extractor producer.
- **Behavior**:
  - API check: `source.health_check.reachable?` → inline POST for auth → store token
  - Database check: `source.health_check.reachable?` (TCP check via HealthCheck)
  - Phase 5 adds: throughput, permission, and lock checks for DatabaseSource

### StreamRouter — Extractor Producer Dispatch

- **Purpose**: Determines which consumer class to use based on source type.
- **Actual implementation**: `ManagedExtractorProducer` checks `connector.source.is_a?(DatabaseSource)`
  and dispatches to `ManagedDatabaseExtractorConsumer` or `ManagedApiExtractorConsumer`.
- **Key rule**: The producer is the ONLY place that knows about source types. Consumers do one
  thing only — no source type conditionals inside.

### ExecutionOrderResolver — Hardcoded Chain Order

- **Purpose**: Determines stream execution order.
- **Actual implementation**: Hardcoded in workers — each resource's producer calls the next
  resource's producer upon completion. The chain order is fixed:
  Subsidiary → Hierarchy → User roles → Client → Product → Group → Groupification →
  Deal → DealExtraField → Modifier → UserField → UserIdentifier → UserActivity →
  ParentUpdate → Goal
- **Future consideration**: Could be replaced by position-based ordering from Stream documents.

### DatabaseConnectionPool — DatabaseSource#connect!

- **Purpose**: Provides database connections for managed sources.
- **Actual implementation**: `DatabaseSource#connect!` (PR #2088) returns an adapter instance
  using the source's configuration. No separate pool service was needed.
- **Self-service**: Uses `Database.connection_pool` singleton (will be removed Phase 5).

### ThroughputCalculator (UNCHANGED — Phase 5 absorbs into ManagedIntegrator)

- **Purpose**: Counts all `fsk_*` table rows updated since `fetch_since` to detect anomalous
  data volumes before extraction.
- **Input**: Job (for `fetch_since`)
- **Output**: Integer (total row count across all tables)
- **Dependencies**: Database (connection pool), Job
- **Note**: Currently self-service only. Phase 5 absorbs this into ManagedIntegrator for
  DatabaseSource with `normalized: true`.

---

## Relationships

```
Source (STI parent)
  ├── ApiSource
  │     ├──1:1──► Authentication (STI: SalesForce, Trackmob) ──1:1──► AuthenticationResponse
  │     └──1:1──► HealthCheck (HTTP)
  │
  └── DatabaseSource
        ├──1:1──► DatabaseAuthentication (username, password encrypted)
        └──1:1──► HealthCheck (TCP)

Source ──1:N──► Stream
                   │
                   ├── belongs_to :resource_type
                   ├── embeds_many :attribute_mappings
                   └── embeds_many :sensitive_keys (semantically API only)

ResourceType ──1:N──► Stream
  │  (identifier_prefix set only on 'User' — NORMALIZED_REGISTRY)

Resource (STI: Subsidiary, Deal, User, ...)
  └── self.streams → Stream.where(resource_type_id: ResourceType.find_by(name: name).id)

Job ──1:N──► *Collection (14 types, STI)
  ├──1:N──► ApiRequest
  ├──1:1──► JobMetric
  └──1:N──► TableLocks

Resource (STI: User, Deal, Goal, ...) ── embeds_many :Import
                                              │
                                              ├── embeds_many :Request
                                              │        └── embeds_one :Response
                                              ├── belongs_to :ApiRequest
                                              └── belongs_to :Job

Account (standalone — 4Shark API credentials)
Computation (Redis-based — not a MongoDB model)
Lock (Redis-based — not a MongoDB model)
Database (Ruby class — self-service only, will be removed Phase 5)
```

| From | To | Type | Description |
|------|----|------|-------------|
| ApiSource | Authentication | 1:1 | API source has one auth config |
| DatabaseSource | DatabaseAuthentication | 1:1 | DB source has one auth config (encrypted) |
| Source | HealthCheck | 1:1 | Every source has one health check (HTTP or TCP) |
| Source | Stream | 1:N | Source serves multiple streams (direct — Connector deleted) |
| Stream | ResourceType | N:1 | Stream binds to a resource type from the catalog |
| Stream | Source | N:1 | Stream is bound to one source (ApiSource or DatabaseSource) |
| Stream | AttributeMapping | 1:N | Stream embeds field mapping rules (absorbed from Connector) |
| Stream | SensitiveKey | 1:N | Stream embeds sensitive field paths (API only; absorbed from Connector) |
| ResourceType | Stream | 1:N | Resource type has many streams (e.g., multi-source configs) |
| Job | Collection (STI) | 1:N | Job owns extracted data batches |
| Job | ApiRequest | 1:N | Job owns API request audit logs |
| Job | JobMetric | 1:1 | Job has throughput statistics |
| Resource | Import | 1:N | Resource embeds import snapshots (embedded) |
| Import | Request | 1:N | Import embeds 4Shark API request logs (embedded) |
| Import | Job | N:1 | Import references its producing job |

---

## Responsibilities Matrix

| Object | Knows | Does | Decides |
|--------|-------|------|---------|
| ApplicationConfiguration | INTEGRATION_MODE env var | Returns mode, convenience methods | Whether client is self-service or managed (Phase 5 removes this) |
| ApiSource | API system identity, timezone, pagination limit | Delegates auth, checks page completion | Whether pagination is complete |
| DatabaseSource | DB host, port, credentials (via DatabaseAuthentication), adapter | Provides connection config via `connect!`, reachability check | Nothing — pure configuration |
| Stream | Resource type, enabled state, source binding, extraction config (query templates, cursor, pagination), transformation config (attribute mappings, sensitive keys) | Enable/disable, resolve source and resource class, render Liquid query templates, check responses | Nothing — just holds the extraction + transformation config |
| ResourceType | Resource type name and identifier prefix | Provides resource class (via `name.constantize`) | Whether user-derived identifiers need a prefix |
| AttributeMapping | Source path, target field, kind, transformer | Applies simple/compound mapping with transformation | How to extract and transform a value |
| Authentication | Credentials, endpoint, grant type | Builds auth request (URI, data, headers) | Whether auth response is successful |
| HealthCheck | Endpoint, expected status | Parses URI or TCP check, checks response | Whether health response is successful |
| Job | Timing, versions, request quantities | Starts, finishes phases, aggregates errors | Nothing — pure tracking |
| Resource | External ID, integration status | State machine transitions, S3 restore | State transition validity |
| Import | Transformed data, source_type | Computes identifier with mode-aware prefix | Whether to prefix with `4sk_` |
| Collection | Raw extracted data batch | Efficient record lookup via aggregation | Nothing — pure storage |
| ManagedIntegrator | All sources | Runs connectivity checks, dispatches first producer | Whether to abort job on failure |
| ManagedExtractorProducer | Stream source types | Dispatches to DB or API consumer by source type | Which consumer class to use |

---

## Rename Mapping

| Current Name | New Name | Change Type | MongoDB Collection | Notes | Status |
|---|---|---|---|---|---|
| `ExternalApplication` | `Source` (STI: ApiSource, DatabaseSource) | RENAME + STI | `sources` | No backwards compatibility needed — no production data | Done (PR #2087) |
| `ExternalResource` | `Stream` (absorbs Connector fields) | RENAME + MERGE | `streams` | No backwards compatibility needed — no production data. 2026-04-10 refinement: Stream absorbs all Connector fields (query templates, primary_key, fetch_since_column, page_size, attribute_mappings, sensitive_keys). Loses `position` and `resource_name` | Done (PR #2087); absorption pending |
| `ApplicationProgrammingInterface` | `Connector` → DELETED | RENAME then DELETE | `connectors` → dropped | Superseded by 2026-04-10 refinement. Fields migrated to Stream. Collection dropped | Deletion pending |
| — | `ResourceType` | NEW | `resource_types` | Introduced by 2026-04-10 refinement. Catalog with identifier_prefix. Replaces Stream.resource_name String | NEW — pending implementation |
| — | `ApiConnector` | PLANNED (STI) | — | NOT IMPLEMENTED — single Connector class used | Superseded (Connector itself deleted) |
| — | `DatabaseConnector` | PLANNED (STI) | — | NOT IMPLEMENTED — single Connector class used | Superseded (Connector itself deleted) |
| — | `IntegratorConfiguration` | PLANNED (NEW) | — | NOT IMPLEMENTED — ApplicationConfiguration continues | Superseded |
| — | `DatabaseRegistration` | PLANNED (NEW) | — | NOT IMPLEMENTED — became DatabaseSource (STI subclass of Source) | Superseded |
| `Authentication` | `Authentication` | UNCHANGED | `authentications` | `belongs_to` updated from `:external_application` to `:source` |
| `SalesForceAuthentication` | `SalesForceAuthentication` | UNCHANGED | `authentications` | STI subclass of Authentication |
| `TrackmobAuthentication` | `TrackmobAuthentication` | UNCHANGED | `authentications` | STI subclass of Authentication |
| `AuthenticationResponse` | `AuthenticationResponse` | UNCHANGED | `authentication_responses` | No changes |
| `HealthCheck` | `HealthCheck` | UNCHANGED | `health_checks` | `belongs_to` updated from `:external_application` to `:source` |
| `AttributeMapping` | `AttributeMapping` | MODIFIED | (embedded) | `embedded_in` updated from `:connector` to `:stream` (2026-04-10) |
| `Header` | — | DELETED | (embedded) | Dead code — never read. Deleted outright by 2026-04-10 refinement. Not migrated |
| `SensitiveKey` | `SensitiveKey` | MODIFIED | (embedded) | `embedded_in` updated from `:connector` to `:stream` (2026-04-10) |
| `ApiRequest` | `ApiRequest` | DELETED | — | Deleted in Phase 4 — replaced by `Collection.raw_body` in S3 |
| `ApiResponse` | `ApiResponse` | UNCHANGED | (embedded) | No changes |
| `Job` | `Job` | UNCHANGED | `jobs` | No structural changes |
| `JobMetric` | `JobMetric` | UNCHANGED | `job_metrics` | No changes |
| `Resource` | `Resource` | UNCHANGED | `resources` | No changes |
| `Import` | `Import` | MODIFIED | (embedded) | 2026-04-10: `belongs_to :stream` (not `:source`). Prefix methods read from `ResourceType.find_by(name: 'User').identifier_prefix`. No `attr_writer`, no Sidekiq arg threading. `source_type` field removed |
| — | `ResourceType` | NEW | `resource_types` | Catalog. `belongs_to :streams`. Holds `name`, `identifier_prefix`. `NORMALIZED_REGISTRY` constant |
| `Collection` | `Collection` | UNCHANGED | `collections` | No changes |
| `Account` | `Account` | UNCHANGED | `accounts` | No changes |
| `Variables` | `Variables` | UNCHANGED | (not persisted) | Constructor param renamed from `application` to `source` |
| `Database` | `Database` | UNCHANGED | (not persisted) | Remains as-is for self-service. Managed mode uses DatabaseConnectionPool |
| `Computation` | `Computation` | UNCHANGED | (Redis) | No changes |
| `Lock` | `Lock` | UNCHANGED | (Redis) | No changes |
| `ThroughputCalculator` | `ThroughputCalculator` | UNCHANGED | (not persisted) | Self-service only |

---

## What Stays Untouched

These components are explicitly out of scope for the domain model changes:

| Component | Status | Notes |
|-----------|--------|-------|
| `Database` class | **Deleted in Phase 5** | Replaced by `DatabaseSource#connect!` |
| `config/initializers/database_pool.rb` | **Deleted in Phase 5** | Replaced by per-source connection |
| `DatabaseIntegrator` worker | **Deleted in Phase 5** | Pre-flight checks absorbed into ManagedIntegrator |
| `ApiIntegrator` worker | **Deleted in Phase 4** | Replaced by ManagedIntegrator |
| All `*::DatabaseExtractor` workers | **Deleted in Phase 5** | Replaced by ManagedDatabaseExtractorConsumer |
| All `*::DatabaseTransformerProducer/Consumer` workers | **Deleted in Phase 5** | Replaced by ManagedTransformerProducer/Consumer |
| All `*::ApiExtractor` workers | **Deleted in Phase 4** | Replaced by ManagedApiExtractorConsumer |
| All `*::ApiTransformer` workers | **Deleted in Phase 4** | Replaced by ManagedTransformerConsumer |
| All `*::LoaderProducer/Consumer` workers | Unchanged | Source-agnostic loading |
| `Resource` and all STI subclasses | Unchanged | Source-agnostic data storage |
| `Collection` and all STI subclasses | Unchanged | Source-agnostic batch storage (new managed fields added Phase 4) |
| `Computation`, `Lock`, `Counter` | Unchanged | Redis coordination |
| `Account` | Unchanged | 4Shark API credentials |
| All env vars for self-service clients | **Migrated in Phase 5** | Replaced by DatabaseSource/DatabaseAuthentication via seed task |
| `ApplicationConfiguration` | **Modified in Phase 5** | INTEGRATION_MODE methods removed when self-service absorbed |
| Reporting workers | Unchanged | All report workers preserved |
| `S3`, `Ec2`, `Ecs` | Unchanged | Infrastructure utilities |
| `MailEnvelope`, `MailDeliverer` | Unchanged | Email delivery |

---

## Domain Rules

| Rule | Description | Enforced By | Status |
|------|-------------|-------------|--------|
| Integration Mode | INTEGRATION_MODE env var determines self_service or managed | ApplicationConfiguration | Current — removed in Phase 5 |
| Source Identifier Uniqueness | ApiSource.identifier must be unique and exactly 4 characters | Source validation + unique index | Active |
| Business Dependency Order | Subsidiary < Hierarchy < User < Deal (upstream resources before downstream) | Hardcoded chain order in workers | Active |
| Stream Requires Primary Mapping | Every Stream for non-normalized sources must have at least one embedded AttributeMapping with primary=true | Stream validation (conditional on `source.normalized?`) | Active — absorbed from Connector |
| Stream Requires Query Template | Every Stream must have `query_template` present (SQL for DB, URL for API) | Stream validation | Active |
| Self-Service Needs No Streams | Self-service mode uses hardcoded fsk_* tables; Source/Stream/ResourceType documents are not required | DatabaseIntegrator checks Database.connect! | Current — removed in Phase 5 |
| Managed Needs Streams | Managed mode requires at least one enabled Stream with a valid Source and ResourceType | ManagedIntegrator pre-flight check | Active |
| Identifier Prefix | ResourceType (named 'User').identifier_prefix determines whether user-derived identifiers are prefixed (e.g., `4sk_`) | Import#user_identifier_prefix | Planned (2026-04-10) |
| ResourceType Name Uniqueness | ResourceType.name must be unique | ResourceType validation + unique index | NEW (2026-04-10) |
| Concurrent Run Prevention | Only one integration run at a time per deployment (Redis lock) | Lock.acquire / Computation | Active |
| Phase Ordering | Extraction must complete before transformation; transformation before loading | Job phase timestamps + worker chaining | Active |

---

## Gap Analysis

### Existing (in codebase) — Status after PR #2087

| Object | Planned Change | Status |
|--------|---------------|--------|
| ExternalApplication | Rename to Source (STI: ApiSource, DatabaseSource) | Done (PR #2087) |
| ExternalResource | Rename to Stream. Absorb Connector fields. Remove position. Replace resource_name with belongs_to :resource_type | Partial (rename done PR #2087; absorption pending) |
| ApplicationProgrammingInterface | Rename to Connector (single class, no STI), then DELETE | Rename done (PR #2087); deletion pending (2026-04-10) |
| Authentication | Update belongs_to to :source. Add STI (DatabaseAuthentication) | Done (PR #2087) |
| HealthCheck | Update belongs_to to :source. Unified reachable? | Done (PR #2087) |
| AttributeMapping | Update embedded_in from :connector to :stream | Partial (:connector done PR #2087; :stream pending) |
| Header | DELETED (dead code, not migrated) | Pending deletion |
| SensitiveKey | Update embedded_in from :connector to :stream | Partial |
| ApiRequest | Deleted in Phase 4 (replaced by Collection.raw_body) | Pending |
| Import | belongs_to :stream (not :source). Rewrite identifier methods via ResourceType lookup. No attr_writer. Remove source_type field | Pending (2026-04-10) |
| Variables | Extend constructor with page, previous_record_id, page_size | Pending (2026-04-10) |
| ApplicationConfiguration | Add self_service_integration?/managed_integration? | Done (PR #2087) |
| Job, Resource, Collection, Database, Computation, Lock, Account | No structural changes | Unchanged |
| ThroughputCalculator | Absorb into ManagedIntegrator | Pending (Phase 5) |

### New (planned)

| Object | Planned | Actual Status |
|--------|---------|---------------|
| IntegratorConfiguration | Singleton for persisted mode | Not created — ApplicationConfiguration continues |
| DatabaseRegistration | Managed DB source credentials | Not created — became DatabaseSource (STI) |
| ApiConnector | STI subclass of Connector | Not created — Connector itself being deleted |
| DatabaseConnector | STI subclass of Connector | Not created — Connector itself being deleted |
| ResourceType | Catalog of resource types with identifier_prefix | NEW (2026-04-10) — pending implementation |
| ConnectivityChecker | Unified pre-flight service | Implemented inline in ManagedIntegrator |
| StreamRouter | Source type → worker class mapping | Implemented in ManagedExtractorProducer dispatch |
| ExecutionOrderResolver | Ordered stream list service | Implemented as hardcoded chain order |
| DatabaseConnectionPool | Per-source connection pools | Implemented as DatabaseSource#connect! |

### Removed (Phase 4 + Phase 5)

| Object | Phase | Replaced By |
|--------|-------|-------------|
| ApiIntegrator | Phase 4 | ManagedIntegrator |
| 24 ApiExtractor workers | Phase 4 | ManagedApiExtractorConsumer |
| 24 ApiTransformer workers | Phase 4 | ManagedTransformerConsumer |
| ApiRequest, ApiResponse, ApiResponseUploader | Phase 4 | Collection.raw_body (S3) |
| **Connector model and `connectors` collection** | Phase 4 (2026-04-10) | Fields absorbed into Stream |
| **Header embedded value object** | Phase 4 (2026-04-10) | Deleted (dead code) |
| **Stream.for_resource scope** | Phase 4 (2026-04-10) | `Resource.streams` class method on each STI subclass |
| **Import `attr_writer :user_identifier_prefix` + Sidekiq arg threading** | Phase 4 (2026-04-10) | ResourceType lookup in `Import#user_identifier_prefix` |
| **Stream.position, Stream.resource_name** | Phase 4 (2026-04-10) | Position: unused; resource_name: replaced by belongs_to :resource_type |
| DatabaseIntegrator, DatabaseWarmer | Phase 5 | ManagedIntegrator |
| 14 DatabaseExtractor workers | Phase 5 | ManagedDatabaseExtractorConsumer |
| 28 DatabaseTransformerProducer/Consumer workers | Phase 5 | ManagedTransformerProducer/Consumer |
| Database class, DatabaseConnectionMiddleware | Phase 5 | DatabaseSource#connect! |

---

## Testing Considerations

### Invariants to Test

| Invariant | Enforced By | Test Approach |
|-----------|-------------|---------------|
| Source identifier uniqueness (4 chars) | Source validation + index | Unit: validate length, uniqueness constraint |
| Stream position uniqueness across enabled streams | Stream validation | Unit: two enabled streams with same position fails |
| Stream-Connector source consistency | Stream aggregate | Unit: connector source must match stream source |
| Connector requires primary AttributeMapping (non-normalized) | Connector validation | Unit: non-normalized connector with no primary mapping fails |
| Import identifier prefix by source | Import#identifier | Unit: source with identifier_prefix prefixes, without returns raw |
| Concurrent run prevention | Lock | Integration: two simultaneous Lock.acquire, second fails |
| Phase ordering (extraction < transformation < loading) | Job timestamps | Unit: verify timestamps are chronological after each finish |

### Behaviors to Verify

| Behavior | Trigger | Expected Outcome | Type |
|----------|---------|-------------------|------|
| ApiSource.last_page? with resource_limit=0 | Any collection_size | Returns true (no pagination) | Unit |
| ApiSource.last_page? with collection < limit | collection_size < resource_limit | Returns true | Unit |
| Stream.source resolves to ApiSource | source is ApiSource | Returns ApiSource instance | Unit |
| Stream.source resolves to DatabaseSource | source is DatabaseSource | Returns DatabaseSource instance | Unit |
| Connector.query renders Liquid template (API source) | Attributes hash provided | Returns rendered query string | Unit |
| DatabaseSource#connect! returns adapter | Valid connection config | Returns MicrosoftSqlAdapter or PostgresSqlAdapter | Integration |
| ManagedIntegrator health check for API source | ApiSource with HealthCheck + Auth | Health check passes, token stored | Integration |
| ManagedIntegrator health check for database source | DatabaseSource with HealthCheck | TCP check passes | Integration |
| ManagedIntegrator mixed sources | Both API and DB sources | Both checked, any failure aborts | Integration |
| ManagedExtractorProducer dispatches by source type | Stream with DatabaseSource | Dispatches to ManagedDatabaseExtractorConsumer | Unit |
| ManagedExtractorProducer dispatches by source type | Stream with ApiSource | Dispatches to ManagedApiExtractorConsumer | Unit |
| Import#identifier with source prefix | Source.identifier_prefix = "4sk_" | Returns "4sk_#{id}" | Unit |
| Import#identifier without source prefix | Source.identifier_prefix = nil | Returns raw id | Unit |
| Import#identifier fallback (nil source_type) | Pre-migration import | Uses ApplicationConfiguration.managed_integration? | Unit |

### Edge Cases from Domain Rules

| Edge Case | Rule | Why It Matters |
|-----------|------|----------------|
| Stream with position gap (1, 2, 5, 8) | Business Dependency Order | Gaps are OK — only relative order matters |
| All streams disabled in managed mode | Managed Needs Streams | Job should abort gracefully, not crash |
| DatabaseSource credentials wrong | Connectivity check | ManagedIntegrator must fail with clear error, not crash |
| Mixed-source client with one source down | Mixed-source failure policy | Current: abort entire job. Must send correct report |
| Import with nil source_type (pre-migration) | Backward compatibility | identifier() must still work via ApplicationConfiguration fallback |
| Connector with empty attribute_mappings (non-normalized) | Connector requires primary | Validation prevents save. Transformation would produce empty data |
| Stream referencing deleted Source | Source deletion guard | Validation prevents orphaned streams |
| Self-service client without seeded config | Seed task required | After Phase 5, clients without Stream records will NOT run |
| Normalized source with attribute_mappings present | Transformer bypass | Mappings ignored — bypass uses raw data regardless |

---

## Notes

- **No backwards compatibility needed for MongoDB collections** — No client uses the managed
  models (Source, Stream, Connector) in production. Collections use the new names (`sources`,
  `streams`, `connectors`) directly. No `store_in` directives needed.

- **Connector is being deleted entirely** — 2026-04-10 refinement. Industry research (Airbyte,
  Fivetran, Singer) confirmed that no established data movement platform uses "Connector" as an
  entity between Source and Stream. All Connector fields migrate to Stream. This simplifies the
  domain to Source → Stream → ResourceType, matching industry convention.

- **Liquid templating unified across DB and API** — Before the refinement, the DB extractor used
  Sequel `.where` chaining in Ruby while the API extractor used Liquid template rendering. After
  the refinement, both paths use `Stream#render_query(variables)` with the same extended
  `Variables` class. The DB extractor is reworked to consume Liquid-rendered SQL instead of
  building the query in Ruby. Since no client uses managed mode in production, this rework has
  no migration burden.

- **Source uses STI** — `Source` is the STI parent with `ApiSource` and `DatabaseSource` subclasses.
  Both live in the `sources` collection. `DatabaseRegistration` was originally planned as a
  separate model but became `DatabaseSource` instead.

- **Stream source reference** — `source_id` + `source_type` on Stream reference the Source (ApiSource
  or DatabaseSource) via Mongoid's belongs_to association.

- **Self-service path is currently a closed system** — Self-service clients use env vars, the
  `Database` class, hardcoded `fsk_*` tables, and `DatabaseIntegrator`. Phase 5 absorbs this
  entirely — self-service becomes a managed configuration with `DatabaseSource(normalized: true)`.

- **Variables constructor rename is cosmetic** — The `Variables` class accepts `(job, application)`
  where `application` is an `ExternalApplication`. Renaming the param to `source` aligns with
  the new terminology. No behavioral change.

- **Worker restructuring is explicitly deferred** — The KNOWLEDGE.md states that worker
  restructuring follows from the domain model but is a separate concern. This domain model
  defines the entities and relationships; the plan will determine how workers evolve to use them.

- **The web management interface reads MongoDB directly** — The document structure of Source,
  Stream, and Connector IS the API contract with the web app. Any field changes must be
  coordinated with the web team.

---

## Self-Service Absorption Impact

When Phase 5 is complete, the following domain objects will be REMOVED:

### Workers (44 total)
- `DatabaseIntegrator` — entry point for self-service runs
- `DatabaseWarmer` — retry handler for DB connection failures
- 14 `{Resource}::DatabaseExtractor` — self-service extraction workers
- 14 `{Resource}::DatabaseTransformerProducer` — self-service transformation coordinators
- 14 `{Resource}::DatabaseTransformerConsumer` — self-service transformation workers

### Infrastructure
- `Database` class — singleton Sequel connection pool wrapper
- `DatabaseConnectionMiddleware` — Sidekiq middleware injecting DB connection via Thread.current
- `config/initializers/database_pool.rb` — self-service connection pool initialization

### Configuration
- `INTEGRATION_MODE` env var and related `ApplicationConfiguration` methods
- `self_service_integration?`, `managed_integration?`, `api_integration?`, `database_integration?`
- Client env vars migrated to DatabaseSource/DatabaseAuthentication: `CLIENT_HOST`, `CLIENT_PORT`,
  `CLIENT_DATABASE`, `CLIENT_USERNAME`, `CLIENT_PASSWORD`, `DATABASE_ADAPTER`, `CLIENT_AZURE`,
  `CLIENT_TIMEOUT`, `TABLE_PREFIX`

### What Replaces Them
- `ManagedIntegrator` absorbs `DatabaseIntegrator` pre-flight checks (throughput, permissions, locks)
- `ManagedExtractorProducer` → `ManagedDatabaseExtractorConsumer` replaces `DatabaseExtractor`
- `ManagedTransformerProducer` → `ManagedTransformerConsumer` (with bypass for `normalized?`) replaces `DatabaseTransformerProducer/Consumer`
- `DatabaseSource#connect!` replaces `Database.connect!` singleton
- `DatabaseSource` + `DatabaseAuthentication` records replace client env vars
- `identifier_prefix` on Source replaces global `ApplicationConfiguration.managed_integration?` check in `Import#identifier`

---

**Status:** DOMAIN MODELING COMPLETE — Implementation in progress
