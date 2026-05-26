# Integrator Domain Analysis

**Date:** 2026-05-05
**Phase:** Phase 4 (D3 — Integrator Domain) — survey
**Status:** **Snapshot — refresh required before drafting.** Captured against `develop` @ `3d42dad14` on 2026-05-05, **before the merge of PR #2120** ([feat(integrator): unify managed flow and bootstrap normalized streams](https://github.com/4shark/integrator/pull/2120), branch `feature/define-flow-task`). That PR materially changes the managed flow and normalized-stream bootstrapping — chapters 3, 4, 5, 6, and 7 in the proposed outline are likely to need rework once it lands. The findings below remain useful as orientation but should not be turned into final docs until the PR is merged and a refresh pass confirms what changed.

## Purpose

Map the integrator's full domain so the eventual `INTEGRATOR_DOMAIN.md` can describe everything that affects integration behavior. Unlike the app (where scope was narrowed to API-affected models), the integrator's entire purpose IS the integration — every concept, model, and mechanism affects the flow and is in scope.

## Method

- Read `README.md` and `CLAUDE.md` for high-level orientation
- Read every model needed to understand the orchestration: `Job`, `Source`, `Stream`, `Connector`, `Authentication`, `Database`, `Resource`, `Collection`, `Import`, `Request`, `Computation`, plus the two adapters
- Read a representative worker (`Subsidiary::DatabaseExtractor`) to confirm the worker-chaining pattern
- Read transformers and one resource (`User`) to confirm the per-resource API request building
- Cross-checked the original `PLAN.md` § Deliverable 3 outline against actual code; captured what was missing

## Inventory

### Pipeline orchestration

- **Job** — Mongoid document; one per integration run. Tracks `starts_at`, `fetch_ends_at` (extraction done), `transformation_ends_at` (transform done), `ends_at` (load done) so each stage's duration is queryable. Also tracks `application_version`, `database_version`, `integration_version`, request counts (`failed`/`successful`/`total`), and `skip_throughput` flag.
- **JobMetric** — auto-created per Job from the most recent `job_metric_quantity` jobs (or all if fewer); used for throughput baselining.
- **`Job::Finisher` worker** — closes the job and triggers `IntegrationReport::Producer`; not a coordinator, just the end marker.
- **No central pipeline coordinator** — workers explicitly call `<NextResource>::SomeWorker.perform_async` to chain to the next stream. Each worker is self-contained.
- **Computation** — Redis-backed primitive for multi-connector coordination per step. Wraps two counters (`queue:<key>` and `executions:<key>`) and a lock (`lock:<key>`). `done?` returns true when execution count matches queue count. Used when N connectors feed the same stream and the next stream must wait until all finish.

### Source configuration

The platform has a small fixed taxonomy of sources, but the per-client configuration of those sources is unbounded — entirely Mongoid-stored, no code branches per client.

- **Source** (Mongoid STI base) — `TYPES = [ApiSource, DatabaseSource]`. Has many Streams. Has one Authentication and one HealthCheck. Fields: `name`, `identifier_prefix` (used at load time, see "Identifier handling"), `normalized` (Boolean, only one normalized Source per integrator via partial unique index).
- **DatabaseSource** — fields: `adapter` (`microsoft_sql_server` or `postgres_sql_server`), `host`, `port`, `database_name`, `azure` (Boolean), `table_prefix` (default `'fsk_'`), `timeout`. `connect!` returns the matching adapter class.
- **ApiSource** — fields: `identifier` (4-char unique string, e.g. `sfdc`/`tkmb`), `resource_limit` (page size for paginated APIs), `timezone`. `last_page?` decides pagination based on returned size vs `resource_limit`.
- **Stream** — Mongoid; `belongs_to :source`; fields: `name`, `position`, `resource_name` (e.g. `User::Manager`), `disabled` flag. Has many Connectors. The fixed integration order is enforced in code (worker chaining), not in `Stream.position` — position is informational. `Stream#user?` checks if the resource_name starts with `User::`.
- **Connector** — `belongs_to :stream`; embeds attribute_mappings, headers, sensitive_keys. Fields: `query`/`query_template`/`paginated_query_template` (DB), `uri` (API), `collection_source` (key path within an API JSON response), `fetch_since_column` (default `'updated_at'`), `page_size`, `primary_key` (default `'id'`), `success_response_status_code`. A Stream can have multiple Connectors when multiple sources feed the same resource (e.g., users from CRM A AND CRM B).
- **AttributeMapping** — embedded in Connector. `KINDS = [dynamic, fixed, formula, template]`:
  - `dynamic` — pull value from `raw_object.dig(*source.split('.'))`
  - `fixed` — hardcode to `fixed_value`
  - `formula` — Dentaku formula evaluated against attributes
  - `template` — Liquid template rendered with attributes
  Each can pass through an optional `transformer` (see Transformers). Connectors must have exactly one `primary: true` mapping unless the source is normalized (normalized DB has fixed schema, no mapping needed).
- **Authentication** — Mongoid STI, `TYPES = [DatabaseAuthentication, SalesForceAuthentication, TrackmobAuthentication]`. Belongs to Source. For DB auth: encrypted username/password. For API auth: `endpoint`, `success_response_status_code`, `client_id`, `grant_type`, encrypted `client_secret`/`security_token`.
- **Transformers** — 8 implementations under `app/transformers/`: `boolean`, `float`, `floating_point_currency`, `beginning_of_month`, `end_of_month`, `identifier_prefixer`, `variable_prefixer`. All inherit from `ApplicationTransformer`. Listed by name in `AttributeMapping.transformer`; instantiated per-mapping at runtime.

### Source data access

- **Database** — wrapper class. Static `connect!` returns a `Database` instance backed by a connection pool of adapters. `method_missing` delegates everything to an adapter from the pool, returning the adapter to the pool when done. The `with_connection(&)` helper is the explicit-block equivalent for code that needs to control the connection lifetime.
- **PostgresSqlAdapter** / **MicrosoftSqlAdapter** — both implement the same interface: `fetch`, `insert`, `page`, `count`, `select_ids`, `delete`, `sample`, `first`, `maximum_identifier_for`, `execute_procedure`, `permissions`, `locks`, `integration_version`, `database_version`. Built on top of Sequel (`Sequel::TinyTDS` for MSSQL, `Sequel::Postgres` for PG). Both apply `ApplicationConfiguration.table_prefix` to every collection name before issuing the query.
- **`fsk_` table prefix** — default per `DatabaseSource#table_prefix`. The prefix exists so that integrator tables can coexist with the client's own tables in the same database without collision. Configurable per-source.

### Resource model

- **Resource** (Mongoid base, STI) — every integrated entity inherits from this. Fields: `external_id` (from source), `model_version` (per-resource schema version), `integration_status` (enumerized state machine).
- **State machine** on `integration_status`: `pending → integrated`, `pending → disabled`, `integrated → disabled`, `disabled → integrated` (re-enable), `integrated → erased`. Enforces explicit lifecycle states per record.
- **MongoDB-as-cache, S3-as-long-term-store** — `Resource.get(external_id)` tries Mongo first, then attempts to restore from S3 (re-hydrating embedded imports/requests with proper BSON ids), then creates a stub if neither path works. S3 archival keeps resource history beyond Mongo's retention.
- **Resource subtypes** — 14 (matching the 14 normalized-DB tables): `Subsidiary`, `Hierarchy`, `User` (with 11 subtypes — `Admin`/.../`SalesRepresentative` plus `Unknown`), `UserIdentifier`, `Client`, `Product`, `Group`, `Groupification`, `UserField`, `UserActivity`, `Deal`, `DealExtraField`, `Modifier`, `Goal`. Each defines its own `request_body_for(import)` that builds the JSON for the app's API call.

### Audit trail

- **Import** — embedded in Resource; `embeds_many :requests`. One Import per pull of this resource from the source within a Job. Holds the raw `data` Hash, plus `job_id` and `source_id` (so cross-source feeds remain attributable). The `Import#identifier` method computes the prefixed identifier (see "Identifier handling").
- **Request** — embedded in Import; `embeds_one :response`. One per HTTP call to the app's API. Stores `url`, `http_method`, `body`, `timestamp`, plus `Response { status, body }`.
- **Heavy MongoDB indexing** — Resource has indices on `imports.job_id`, `imports.data.type`, `imports.requests.url`, `imports.requests.http_method`. The README's debug examples (`User.where('imports.job_id': 23, ...)`) read directly from this audit trail.
- **Per-job Collection** — `<Resource>Collection` (e.g., `UserCollection`) is a separate Mongoid doc per Job + per (connector, stream, page). Stores the raw payload from the source either inline (`raw: Array`) or via uploader to file storage. Used as the intermediate between Extract and Transform.

### Identifier handling at Load time

The `Import#identifier` method computes the value sent in API payloads. Three modes:

- **Per-source override** — when the Import's Source has `identifier_prefix` set, use `"#{prefix}#{data[:id]}"`. Used when one integrator feeds multiple source systems and each needs a distinct namespace
- **Managed-integration mode** — when `ApplicationConfiguration.managed_integration?` is true, no prefix at all (the source data already carries identifiers in the platform's expected form)
- **Default** — `"4sk_#{data[:id]}"`. Used when 4Shark is both running the integrator and chose `4sk_` as the namespace per the platform's [identifier prefix recommendation](API_DOMAIN.md identity translation)

The same logic applies to `user_identifier` (for streams referencing the user) and `parent_identifier` (for hierarchy / parent_update streams referencing the manager).

### Stream sequence

Fixed order across the 25 streams (E, T, L stages each follow this order):

1. Subsidiary, 2. Hierarchy, 3-13. User::Admin / President / VicePresident / Director / Superintendent / GeneralManager / Manager / Coordinator / Supervisor / SalesRepresentative / Unknown, 14. ParentUpdate, 15. UserIdentifier, 16. Client, 17. Product, 18. Group, 19. Groupification, 20. UserField, 21. UserActivity, 22. Deal, 23. DealExtraField, 24. Modifier, 25. Goal. Then Job::Finisher.

Three non-obvious orderings:

- **Hierarchy (step 2)** runs *before* user registration so promotions/demotions land on the seat before new users get registered under it (otherwise a freshly-promoted supervisor could be registered below a still-existing supervisor)
- **User::Unknown (step 13)** captures user records whose `type` did not match one of the 10 supported access levels (typo, wrong language, custom value). Pushed to the API anyway so the misconfiguration surfaces as a visible error rather than silently dropped
- **ParentUpdate (step 14)** runs *after* all users are registered so the manager (parent) is guaranteed to exist when the relationship update lands

### Worker shape

Most resources have:

- `<Resource>::DatabaseExtractor` — pulls from the client's DB via Sequel `page`, persists to a Collection, self-reschedules for the next page, chains to the next stream's extractor when done
- `<Resource>::DatabaseTransformerProducer` / `Consumer` — split for fan-out
- `<Resource>::LoaderProducer` / `Consumer` — split for fan-out at Load time
- Plus `Managed*` variants for managed-integration mode and `ApiExtractor*` for ApiSource streams

Workers retry on connection exceptions by self-rescheduling.

### Per-client configuration is data, not code

All client-specific behavior — which sources, which streams enabled, which queries, which mappings, which auth — lives in Source/Stream/Connector/AttributeMapping/Authentication Mongoid records. Onboarding a new client is a configuration exercise; the codebase is generic.

## Cross-cutting findings (vs. the original PLAN.md outline)

The PLAN's 9-bullet outline missed substantial structure. Specifically:

1. **Three identifier-prefix modes**, not one — `PLAN.md` said only `4sk_`. Reality is per-source override + managed-integration (no prefix) + `4sk_` default.
2. **The Source/Stream/Connector triad** as the per-client config surface — `PLAN.md` did not mention any of these. They are the central abstraction.
3. **AttributeMapping with 4 kinds** (dynamic, fixed, formula via Dentaku, template via Liquid) — the per-attribute mapping mechanism is the core of how non-normalized integrations work.
4. **Authentication has 3 STI types** — Database, SalesForce, Trackmob.
5. **Transformer pipeline** (8 implementations) — the per-attribute pre-processing layer.
6. **MongoDB-as-cache, S3-as-long-term-store** — the resource access pattern.
7. **Per-resource Collection model** — the intermediate between Extract and Transform.
8. **Resource integration_status state machine** — pending/integrated/disabled/erased lifecycle.
9. **`Computation` primitive for multi-connector coordination** — Redis-backed counters + lock; needed when N sources feed one stream.
10. **Worker chaining pattern, not central coordinator** — and producer/consumer split for fan-out at Transform and Load.
11. **Console adapter gotcha is more nuanced** — `connection.fetch(:table)` does work (per README §2.5.1) and `connection[:clients].insert(...)` also works in the README example. The original `PLAN.md` claim that `conn[:table]` does NOT work needs verification — the adapter's `fetch`/`page`/`count`/etc. methods all internally use `connection[Sequel.identifier(table)]` which IS the bracket form. The gotcha is probably more nuanced than the plan stated.
12. **The "U2 streams" are not just listing** — Hierarchy, User::Unknown, and ParentUpdate are special cases each with a distinct reason for being.

## Implications for the documentation plan

The original PLAN's 9-bullet D3 outline is too thin for the user's directive that "everything affects integration". Proposed chapter structure for `INTEGRATOR_DOMAIN.md` (12 chapters):

1. **What the integrator is and why it exists** — one-side-of-integration ownership, customer's perspective, 4Shark's perspective, configurable-without-code value proposition
2. **Topology and isolation** — one integrator per client per environment; ECS, MongoDB, Redis, VPN provisioned via Terraform; no multi-tenancy
3. **The integration pipeline** — single Job, three stages (E → T → L), worker chaining (no central coordinator), per-stage durations tracked
4. **The 25-stream fixed sequence** — the order, three special-case streams (Hierarchy, User::Unknown, ParentUpdate), why fixed-order across stages
5. **Source types and per-stream configuration** — Source (DB / API), Stream, Connector, AttributeMapping (4 kinds), Authentication (3 types). The Mongoid configuration surface that makes onboarding code-free
6. **Source database access** — the adapter abstraction, Sequel under the hood, the `fsk_` table prefix, the read API (`fetch`/`page`/`count`/etc.)
7. **The identifier prefix on records** — three modes (`4sk_` default / per-source override / managed-mode no-prefix); how this connects to the app's multi-identifier User design
8. **Transformers and the AttributeMapping pipeline** — 4 mapping kinds, 8 transformers, Liquid + Dentaku, why normalized streams skip mapping
9. **Mongoid storage of resources, imports, and requests** — the audit trail; per-job Collections; MongoDB-as-cache / S3-as-long-term-store; how the README debug queries work
10. **Multi-connector coordination via Computation** — Redis-backed counters, distributed lock; when it's needed (N sources feeding one stream)
11. **The normalized database contract** — fsk_ tables, schema versions per SGBD, migration paths, how integrator tolerates version drift
12. **Resource integration_status lifecycle** — pending / integrated / disabled / erased; the state machine; what triggers each transition

## Open questions to verify before writing

- **`conn[:table]` vs `conn.fetch(:table)` gotcha** — the original PLAN claimed `conn[:table]` does NOT work in the integrator console. The adapter code uses `connection[Sequel.identifier(table)]` internally, suggesting the bracket form does work. Verify by reading `microsoft_sql_adapter.rb` and confirming whether the gotcha is real or apocryphal.
- **Resource erase state transition** — `state_machine` declares `integrated → erased` but the trigger isn't obvious from the model. When does erase happen? (Anonymization downstream of the app's user activity destroy?)
- **`managed_integration?` config** — exists on `ApplicationConfiguration`. What flag toggles it? Used in three places in `Import#identifier`. Need to read the config method and its callers.
- **FTP source mentioned in CLAUDE.md** — README §1 mentions FTP as a future source type, but no STI exists. Is this aspirational or in development?
- **Subsidiary-scoped vs root-scoped User payloads** — `User#request_body_for` checks `import.data[:subsidiary_id].present?` and adds `subsidiary_id` + `external_parent_subsidiary_id` if present. Confirm this corresponds to the app's subsidiary mode contract.

These are not blockers — they are sharpening points for the doc that should be resolved during writing.
