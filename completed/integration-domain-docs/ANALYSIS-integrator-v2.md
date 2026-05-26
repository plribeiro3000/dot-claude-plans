# Integrator Domain Analysis — v2 (post-merge refresh)

**Date:** 2026-05-06
**Phase:** Phase 4 (D3 — Integrator Domain) — survey refreshed
**Status:** Refresh of `ANALYSIS-integrator.md` (the pre-merge snapshot, captured 2026-05-05 against `develop` @ `3d42dad1`). PR [#2120](https://github.com/4shark/integrator/pull/2120) (`feature/define-flow-task` — "feat(integrator): unify managed flow and bootstrap normalized streams") merged on 2026-05-06 as `06b5721a` into `develop`. New `develop` HEAD: `3e0ce458`. v1 is preserved as the historical snapshot; this v2 supersedes it for drafting purposes.

## Why a refresh was needed

PR #2120 reshaped the per-client configuration surface and the identifier-prefix logic — exactly the parts the original outline (chapters 3, 4, 5, 6, 7) was anchored on. The structural changes are large enough that drafting against v1 would produce documentation that is wrong on its first read.

## What PR #2120 did, in domain terms

The PR collapses two parallel realities into one:

- **Before:** the integrator had two integration modes — a normalized-database "managed" mode (4Shark-managed clients with the `fsk_` schema) and a custom-config mode (clients with their own DB schema, multiple sources per resource via Connectors). The codebase carried both, with branching at multiple layers (`ApplicationConfiguration.managed_integration?`, dual identifier-prefix paths, separate worker chains).
- **After:** there is **one pipeline**. A Stream is the configurable unit — it points to a Source (DB or API) and to a ResourceType, carries a Liquid query template, and is fully self-describing. Both the normalized-DB shape and the custom-shape shape flow through the same workers, parameterized per-stream by what the Source and Stream tell them. The "managed flow" is the only flow now; the worker class names retain the `Managed` prefix as a legacy artifact.
- **Bootstrap of normalized clients** is now a Rake task (`integration:normalized:bootstrap`) that reads a fixed `Integrator::NORMALIZED_SCHEMA` and creates the ResourceTypes + Source + Authentication + HealthCheck + Streams that previously existed implicitly in code paths.

The rest of the changes (Connector model removal, AttributeMapping/SensitiveKey moving to Stream, Header model removal, Preflight → SourceCheck + StreamCheck split, AvailabilityCheck workers) are the structural consequences of that unification.

## Method

- Read the new `Source`, `Stream`, `ResourceType`, `Import`, `Resource`, `SourceCheck`, `StreamCheck` models in full
- Read the new `lib/tasks/integration/normalized/bootstrap.rake` and `config/normalized_schema.rb` for the bootstrap shape
- Read `app/workers/managed_integrator.rb` and a representative `User::Manager::Managed*` worker pair (Producer + DatabaseExtractorConsumer) for the new orchestration
- Read `app/workers/availability_check/producer.rb`
- Cross-checked `git diff 3d42dad1..3e0ce458` for adds/deletes
- Confirmed the new architecture against the project's own `CLAUDE.md` (added in PR #2168, sibling work)

## Inventory (post-merge)

### Pipeline orchestration

- **Job** — Mongoid document; one per integration run. Tracks `starts_at`, `fetch_ends_at`, `transformation_ends_at`, `ends_at`, `application_version`, `database_version`, `integration_version`, request counts, `skip_throughput` flag. Also gains `total_sources` and `total_streams` (set by `ManagedIntegrator` at job start).
- **`ManagedIntegrator` worker** — entrypoint. Acquires a Redis lock, validates that there are enabled streams (otherwise emits `MissingStreamsReport` or `InactiveStreamsReport`), creates the Job, materializes a `SourceCheck` per Source-with-enabled-streams and a `StreamCheck` per enabled-stream for this Job, then kicks off `HealthCheck::Producer`.
- **`Job::Finisher` worker** — closes the Job and triggers `IntegrationReport::Producer`. Same role as before.
- **No central pipeline coordinator** — workers chain directly to the next resource's producer. The chain advances per ResourceType, not per Stream.
- **`Computation` (Redis) primitive** — same role as before (counters + lock for multi-N coordination). Now used at the **stream level**: when N streams feed the same ResourceType, `Computation.done?` gates the advance to the next ResourceType.

### Source configuration — the new shape

The major architectural change. The pre-merge Source/Stream/Connector triad collapsed into a Source/Stream pair.

- **Source** (Mongoid STI base) — `TYPES = [ApiSource, DatabaseSource]`. `has_many :streams`, `has_one :authentication`, `has_one :health_check`, `has_many :checks (SourceCheck)`. Fields: `name`, `normalized` (Boolean — partial unique index ensures at most one normalized Source per integrator), `resources` (Array of resource type names — declares which Resource subclasses this source can provide), `timezone`. Validates `resources` against `Resource::TYPES`. Custom validation `user_resource_uniqueness` ensures only one Source declares `User` (cannot have two Sources both providing User).
- **`Source#user_id_from(id)`** — the new identifier-prefix entrypoint. Returns `"4sk_#{id}"` if the source is `normalized`, otherwise returns the id as-is. Replaces the old three-mode logic that lived on `Import#identifier`.
- **DatabaseSource** — fields: `adapter` (`microsoft_sql_server` or `postgres_sql_server`), `host`, `port`, `database_name`, `azure` (Boolean), `table_prefix`, `timeout`. `connect!` returns the matching adapter. Note: `table_prefix` no longer has a default value — it is set explicitly during bootstrap (the legacy `'fsk_'` default is gone from the model; `ApplicationConfiguration.table_prefix` is the bootstrap-time default for normalized clients).
- **ApiSource** — fields: `identifier` (4-char unique string, e.g. `sfdc`/`tkmb`). The previous `resource_limit` (page size) and `timezone` fields moved up: `timezone` is now on Source; page size is on Stream (`page_size`). `last_page?` logic moved out of the model.
- **Stream** — `belongs_to :resource_type`, `belongs_to :source` (optional). `embeds_many :attribute_mappings`, `embeds_many :sensitive_keys`, `has_many :checks (StreamCheck)`. Fields: `name`, `query_template`, `paginated_query_template`, `availability_probe`, `collection_source`, `fetch_since_column` (default `'updated_at'`), `page_size`, `primary_key` (default `'id'`), `success_response_status_code`, `disabled` (Boolean). **No `position` field** — order is hardcoded in worker chaining (per CHANGELOG: "Stream position removed"). Validates `primary_mapping_presence` (exactly one `primary: true` mapping unless empty) and `resource_inclusion` (the stream's `resource_type.resource` must appear in the source's `resources` array). Helpers: `enable`/`disable`/`enabled?`/`disabled?`, `database_source?`/`api_source?`/`normalized_source?`, `paginated?`, `render_query(variables)` (Liquid render of `query_template` or `paginated_query_template`), `ready_for?(job)` (true when both this stream's StreamCheck and its source's SourceCheck are `successful?`).
- **ResourceType** (NEW) — Mongoid document. Fields: `name` (unique, e.g. `'Manager'`, `'ParentUpdate'`, `'UserIdentifier'`), `resource` (the Resource subclass name, e.g. `'User'`, `'Hierarchy'`). `has_many :streams`. Decouples the stream's logical name from the underlying Resource class — multiple ResourceTypes can map to the same Resource (the 10 user-type ResourceTypes all map to `Resource = 'User'`; ParentUpdate and Hierarchy both map to `Resource = 'Hierarchy'`).
- **AttributeMapping** — now `embedded_in :stream` (was `embedded_in :connector`). Same 4 kinds (`dynamic`, `fixed`, `formula`, `template`), same transformer field, same primary flag.
- **Authentication** — Mongoid STI, `TYPES = [DatabaseAuthentication, SalesForceAuthentication, TrackmobAuthentication]`. Belongs to Source. Same shape as before.
- **Connector — REMOVED.** The class no longer exists. The Stream now carries everything that lived on Connector (`query_template`, `paginated_query_template`, `collection_source`, `fetch_since_column`, `page_size`, `primary_key`, `success_response_status_code`, `attribute_mappings`, `sensitive_keys`).
- **Header — REMOVED.** No replacement model is visible; either rolled into a different mechanism (likely embedded directly on Authentication) or eliminated as configuration that no longer needs explicit modeling.
- **Transformers — unchanged.** 8 implementations under `app/transformers/` (`boolean`, `float`, `floating_point_currency`, `beginning_of_month`, `end_of_month`, `identifier_prefixer`, `variable_prefixer`, plus the application base). `identifier_prefixer` and `Source#user_id_from` operate at different layers and remain complementary — see findings below.

### Source data access

- **Database** wrapper class and the two adapters (`PostgresSqlAdapter`, `MicrosoftSqlAdapter`) — interface unchanged (`fetch`, `insert`, `page`, `count`, `select_ids`, `delete`, etc.), but the per-Source `table_prefix` is no longer a default-applied prefix at the adapter level — the Stream's `query_template` is rendered by Liquid before reaching the adapter, so the table name is fully resolved by the template (the bootstrap embeds `#{source.table_prefix}#{table}` directly into the SQL it generates). This eliminates an implicit mutation of every query.
- **Per-stream Liquid query** — `Stream#render_query(variables)` is the new query-resolution surface. Variables come from `Variables.new(job, source, previous_record_id:, page_size:)`. The bootstrap-generated templates use `{{ fetch_since }}`, `{{ page_size }}`, `{{ previous_record_id }}`.

### Identifier handling at Load time — the simplification

The pre-merge logic on `Import#identifier` had three modes (per-source `identifier_prefix`, `managed_integration?` no-prefix, `4sk_` default). All three are gone. The new logic:

```ruby
# Source#user_id_from
def user_id_from(id)
  if normalized?
    "4sk_#{id}"
  else
    id
  end
end
```

Two modes:
- **Normalized source** (the single 4Shark-bootstrapped source) → `"4sk_#{id}"`
- **Non-normalized source** (custom DB query, API source, future FTP source) → id as the source emitted it

Invoked by every Resource subclass's `request_body_for(import)` and by every loader_consumer that needs to reference a user identifier. Examples (from grep):
- `User#request_body_for`: `value: import.stream.source.user_id_from(import.data[:id])` for the primary identifier; same call for `parent_id` if present
- `Deal`/`Goal`/`Modifier#request_body_for`: `user_id: import.stream.source.user_id_from(import.data[:user_id])`
- `Hierarchy#request_body_for`: `parent_identifier = import.stream.source.user_id_from(import.data[:parent_id])`
- All `*::loader_consumer.rb` workers that resolve a user reference

The `ApplicationConfiguration.managed_integration?` flag still exists in `lib/application_configuration.rb` (not deleted in this PR) but is no longer referenced from `Import` or any model — confirm whether it has dead callers elsewhere.

### Pre-flight checks — split into two layers

The pre-merge `Preflight` model is gone. Replaced by:

- **SourceCheck** — `belongs_to :job, :source`. Tracks `reachability` (network/connection) and `authentication` separately, each as an enumerized state (`pending`/`passed`/`failed`/`skipped`). Has a `failure` enum (`missing_permissions`/`open_transactions`/`connection_error`/`authentication_error`) and a free-form `detail` string. `successful?` requires both reachability and authentication to be passed. Materialized at job start by `ManagedIntegrator` (one per Source-with-enabled-streams). Producers/consumers in `Authorization::*` and `HealthCheck::*` workers fill in the fields.
- **StreamCheck** — `belongs_to :job, :stream`. Single field `accessibility` (enumerized: `pending`/`passed`/`failed`/`skipped`). Materialized at job start by `ManagedIntegrator` (one per enabled Stream). Filled in by `AvailabilityCheck::*` workers, which run each Stream's `availability_probe` (a tiny query like `SELECT 1 FROM <table> WHERE 1 = 0` for DB streams) to verify the Stream's referenced object actually exists.
- **`Stream#ready_for?(job)`** — gates extraction. A Stream proceeds only if its own StreamCheck is successful AND its Source's SourceCheck is successful for the same Job. Per-resource extractor producers filter `streams.enabled` by `ready_for?(job)` before dispatching consumers.

### Per-job collection model

Unchanged in shape — `<Resource>Collection` (e.g. `UserCollection`) is still per-Job + per-Stream + per-page. One field name changed: `connector_id` → `stream_id`. Used as the Extract → Transform handoff.

### Resource model

- `TYPES` unchanged (15 entries, same as v1).
- `model_version` defaults to `'1.0'` on `Resource` and `'3.0'` on `User`. **The User bump is pre-existing**, not introduced by this PR — `git show 3d42dad1:app/models/user.rb` confirms `default: '3.0'` was already there.
- `state_machine` unchanged in shape: `pending → integrated`, `pending → disabled`, `integrated → disabled`, `disabled → integrated`, `integrated → erased` (plus `erased → integrated`, which v1 missed: the `integrate` event accepts both `pending` and `erased` as inputs).
- `Resource.get(external_id)` — same MongoDB-as-cache, S3-as-long-term-store pattern. S3 restoration logic unchanged.

### Audit trail

- **Import** — `embedded_in :resource, embeds_many :requests`. Now also `belongs_to :api_request`, `belongs_to :job`, `belongs_to :stream` (was: `:source` instead of `:stream`). Fields simplified to `data` (Hash) and `model_version`. Validates `job_id` presence. Drops the `Import#identifier` method entirely (logic moved to `Source#user_id_from`). New helpers: `upstream_id` (raw `data[:id]`), `active?`/`inactive?`, `primary?`, `external_id?`, plus type predicates (`finish?`, `promotion?`, `demotion?`, `update_parent?`, `delete?`, `enable?`).
- **`Import#find_request` / `request_exists?`** — new methods that do MongoDB aggregation against the embedded `requests` to find a previous HTTP call by `(http_method, url, job_id)`. Suggests an idempotency / replay mechanism at the integrator side (verify whether this is a new safety net or pre-existing infra surfaced).
- **Request** — embedded in Import; same shape (`url`, `http_method`, `body`, `timestamp`, `Response { status, body }`).
- **Indexes on Resource** — same heavy indexing on `imports.job_id`, `imports.data.type`, `imports.requests.{job_id,url,http_method}`. `_type, external_id` and `external_id` and `updated_at` indexes also present.

### Stream sequence

The 25-stream order in `CLAUDE.md` matches the pre-merge order — Subsidiary, Hierarchy, 11 user types (Admin → SalesRepresentative → Unknown), ParentUpdate, UserIdentifier, Client, Product, Group, Groupification, UserField, UserActivity, Deal, DealExtraField, Modifier, Goal, then Job::Finisher.

The bootstrap's `NORMALIZED_SCHEMA` lists 24 entries (the User::Unknown entry is absent — Unknown is a runtime fallback for source rows whose `type` did not match any of the 10 known access levels, not a separately-bootstrapped stream). The same 10 user-type ResourceTypes are created with `condition: "type = '<TypeName>'"` filtering against the same `users` table.

### Worker shape

For each ResourceType (e.g. `User::Manager`):

- `<Resource>::ManagedExtractorProducer` — finds enabled streams of this ResourceType that are `ready_for?(job)`, partitions by source kind (DB / API), bulk-pushes to `ManagedDatabaseExtractorConsumer` / `ManagedApiExtractorConsumer`, increments the Job's Computation queue counter. If no streams are ready, advances directly to the next ResourceType's producer.
- `<Resource>::ManagedDatabaseExtractorConsumer` — connects via `stream.source.connect!`, renders the Liquid query, fetches via Sequel, persists raw data to a per-Job Collection, self-reschedules with `collection_last_id` if paginated, otherwise increments executions and (if all done) advances to the next ResourceType.
- `<Resource>::ManagedApiExtractorConsumer` — analogous for API sources.
- `<Resource>::ManagedTransformerProducer` / `Consumer` — fan-out for transformation.
- `<Resource>::LoaderProducer` / `Consumer` — fan-out for the load step.
- The non-managed ("`*::DatabaseExtractor`" without the `Managed` prefix that v1 mentioned) variants are GONE — only the `Managed*` flow exists. The naming is legacy from when the codebase carried both.

### Per-client configuration is data, not code — reaffirmed and simplified

Every client-specific decision still lives in Mongoid (Source/Stream/AttributeMapping/Authentication). The unification removes the in-code `managed_integration?` branch — what mode a client is in is now determined by their data (whether their single Source is `normalized: true`, what `resources` it declares, what `query_template`s the Streams carry).

## Cross-cutting findings (vs. v1 and vs. PLAN.md)

The v1 outline (12 chapters) needs targeted rework; not a full rewrite. The principles hold, but the names and the boundaries shift:

1. **The Source/Stream/Connector triad is now a Source/Stream pair.** Chapter 5 of the v1 outline ("Source types and per-stream configuration") needs to drop Connector and recenter on (Source × ResourceType) → Stream. AttributeMapping (4 kinds) and SensitiveKey (embedded list) are now embedded in Stream.
2. **The `4sk_` prefix logic is now two modes, not three.** Chapter 7 ("The identifier prefix on records") shrinks to: normalized Source → `4sk_{id}`, otherwise → id passes through. The `identifier_prefix` per-Source field is gone; the `managed_integration?` no-prefix mode is gone; the `4sk_` default is now an explicit consequence of `normalized: true`.
3. **The "managed flow" concept needs a re-explanation.** The codebase still uses `Managed*` worker class names, but conceptually there is **one** flow now. Chapter 3 ("The integration pipeline") should call this out — what looks like a "managed" pipeline IS the only pipeline; the prefix is legacy.
4. **`ResourceType` is a new top-level concept** that did not exist in v1. It deserves its own chapter or a prominent section: it decouples the logical stream-name from the Resource subclass (10 user-type ResourceTypes → 1 User Resource; ParentUpdate ResourceType → Hierarchy Resource).
5. **Pre-flight is a two-layer check.** v1 did not cover Preflight at all; the new SourceCheck + StreamCheck + AvailabilityCheck split is non-trivial and integration-blocking — it should have its own chapter.
6. **`Stream#ready_for?(job)` gates extraction per stream**. Worth surfacing because it is the actual mechanism that makes a degraded source (one bad stream) not block the rest of the pipeline.
7. **The bootstrap rake task is the entry point for new normalized clients.** Chapter 11 of v1 ("The normalized database contract") should incorporate the bootstrap task as the operational binding between the schema and the configuration documents.
8. **Stream `position` is gone.** v1 said "position is informational" — now there is no `position` field at all. The 25-stream order is purely from worker chaining (`<Next>::ManagedExtractorProducer.perform_async`).
9. **Header model is gone** without an obvious replacement. v1 listed Header as part of the Connector-embedded configuration. Confirm whether headers are now embedded directly on Authentication or whether the use case was eliminated.
10. **`Computation` semantics shift from connector-level to stream-level.** v1 described Computation as coordinating "N connectors feeding the same stream"; post-merge it coordinates "N streams feeding the same ResourceType". Same primitive, different layer.
11. **Bootstrap NORMALIZED_SCHEMA is the source of truth for normalized clients.** 24 ResourceType definitions. Note the special cases: (a) the 10 user types use the same `users` table with a `type =` filter; (b) ParentUpdate uses the `hierarchy` table with `created_at` (not `updated_at`) as fetch-since column.
12. **`Import` no longer carries the identifier method.** The 4Shark/non-4Shark identification logic moved one layer up (to Source). v1's chapter on identifier handling needs to point readers at `Source#user_id_from`, not `Import#identifier`.

## Implications for the documentation plan

The v1 12-chapter outline is salvageable with surgical edits. Proposed v2 outline for `INTEGRATOR_DOMAIN.md`:

1. **What the integrator is and why it exists** — *(unchanged from v1)* one-side-of-integration ownership, customer's perspective, 4Shark's perspective, configurable-without-code value proposition.
2. **Topology and isolation** — *(unchanged from v1)* one integrator per client per environment; ECS, MongoDB, Redis, VPN provisioned via Terraform; no multi-tenancy.
3. **The unified integration pipeline** — *(REWRITTEN)* single Job, three stages (E → T → L), worker chaining without a central coordinator, per-stage durations tracked. **There is one flow** — the legacy "managed" prefix in worker class names is historical, not categorical.
4. **The 25-stream fixed sequence and the role of ResourceType** — *(REWRITTEN)* the fixed order, the three special cases (Hierarchy before users, User::Unknown as the typo-catcher, ParentUpdate after users); the ResourceType abstraction as the layer that lets multiple Streams feed one Resource subclass.
5. **Sources and Streams** — *(REWRITTEN)* the post-merge configuration surface. Source (with `resources` declaring what it can provide; `normalized` flag; uniqueness rules) and Stream (with Liquid query templates; embedded AttributeMappings and SensitiveKeys; `ready_for?` gating). What used to be Stream → Connectors is now ResourceType → Streams.
6. **Source data access** — *(LIGHTLY EDITED)* the adapter abstraction, Sequel under the hood, Liquid-rendered queries (no more implicit `table_prefix` mutation by the adapter), the read API.
7. **Identifier handling on records** — *(REWRITTEN — SIMPLER)* two modes (normalized → `4sk_{id}`, otherwise pass-through); how this connects to the app's multi-identifier User design and its identifier-prefix recommendation.
8. **AttributeMapping and the transformer pipeline** — *(LIGHTLY EDITED)* 4 mapping kinds, 8 transformers, Liquid + Dentaku, why normalized streams have only the dynamic-from-source primary mapping.
9. **Mongoid storage of resources, imports, and requests** — *(LIGHTLY EDITED)* the audit trail; per-job Collections; MongoDB-as-cache / S3-as-long-term-store; how the README debug queries work; the new `Import#find_request` lookup.
10. **Multi-stream coordination via Computation** — *(EDITED)* Redis-backed counters and lock; now operates at the stream level (multiple Streams feeding one ResourceType) instead of the connector level.
11. **Pre-flight: SourceCheck, StreamCheck, AvailabilityCheck** — *(NEW chapter)* the two-layer check; what each layer verifies; how `ready_for?(job)` gates per-stream extraction; what each `failure` enum value means in operational terms.
12. **The normalized database contract and the bootstrap task** — *(REWRITTEN)* the `NORMALIZED_SCHEMA` constant, the rake task that materializes ResourceTypes + Source + Authentication + HealthCheck + Streams from `ApplicationConfiguration`; how integrator tolerates schema-version drift across clients.
13. **Resource integration_status lifecycle** — *(LIGHTLY EDITED)* pending / integrated / disabled / erased; the state machine; what triggers each transition; the `erased → integrated` re-integration path that v1 missed.

## Findings

### Header model

The pre-merge `Header` (`embedded_in :connector`, fields `key`/`value`) persisted API response-header metadata per Connector in a Mongoid-indexed structure. With Connector removed, this representation is gone. The complementary file-based response-header store remains: `Collection.raw_headers` (CarrierWave uploader, persisted via `CollectionRawHeadersUploader`) — the API extractor writes `http_response.to_hash.to_json` to it on every API call. Response headers continue to be persisted per call; the indexed/queryable representation is what went away.

### `ApplicationConfiguration.managed_integration?` — to be removed

The flag is conceptually obsolete after the unification. It used to mean "managed pipeline mode vs self-service pipeline mode" — a distinction that no longer exists. Both surviving callers — `app/views/integration_report_mailer/create.html.erb:28` (toggles a section in the email body) and `config/initializers/symmetric_encryption.rb:3` (gates encryption initialization) — must be replaced.

The replacement is a top-level helper `Integrator.fully_normalized?`, defined in a new `lib/integrator.rb`. The check is intentionally simple:

```ruby
# True iff this integrator is configured to run exclusively against a single
# normalized source. Relies on the partial unique index
# `{ normalized: 1 }, unique: true, partial_filter_expression: { normalized: true }`
# on Source: at most one Source can carry normalized=true at any time, so a total
# count of exactly 1 implies that single Source IS the normalized one.
def self.fully_normalized?
  Source.count == 1
end
```

Replacement plan:
- View toggle (`integration_report_mailer/create.html.erb`): switch the conditional to `Integrator.fully_normalized?`. The two branches still make sense — when fully-normalized, show DB-version info; when not, show source/stream counts.
- Symmetric encryption initializer (`config/initializers/symmetric_encryption.rb`): remove the conditional entirely and run unconditionally. Encrypted fields are encrypted in every deployment regardless of source composition.
- Delete `ApplicationConfiguration.managed_integration?`, `self_service_integration?`, `api_integration?`, `database_integration?`, `integration_mode`, and the `INTEGRATION_MODE` env var.
- Remove orphan i18n strings in `integration_report.*` for branches that no longer exist.

This work is scheduled as a separate PR in the integrator repo (`feature/replace-managed-integration-flag`), independent of D3 drafting.

### `IdentifierPrefixerTransformer`

Field-level transformer applied during the Transform stage to a single AttributeMapping output. Implementation: `"#{source.identifier}-#{value}"`, where `source.identifier` is the 4-char unique string on `ApiSource` (e.g., `sfdc`, `tkmb`). `ApplicationTransformer#source` is `attribute_mapping.stream.source`, so the transformer reads the Source of the Stream that owns the mapping it was attached to.

Only meaningful when the Stream's Source is an `ApiSource` — `DatabaseSource` has no `identifier` field. Use case: namespacing record fields with the ApiSource's 4-char identifier, e.g. when multiple ApiSources feed the same ResourceType and an attribute would otherwise collide. Belongs in D3's transformer chapter alongside the other 7 transformers.

### User::Unknown — structural, always runs

- **Unknown has only Loader workers** (no Extract, no Transform). The user records reach Mongo through the per-type extractor chain; Unknown picks them up at Load time.
- **Unknown is unconditionally chained from User::SalesRepresentative.** Both `LoaderProducer` and `LoaderConsumer` call `User::Unknown::LoaderProducer.perform_async(job_id)` — no opt-in, no skip path.
- **Selection.** `User.where('imports.job_id': job.id).nin('imports.data.type': User::TYPES)` — every User imported in this Job whose post-mapping `data.type` is outside the 10 known access levels.
- **Behavior.** Each candidate is loaded into the app's API via `UserLoader#create(import.request_body)`. The app rejects the request because the seat type is invalid; the rejection is recorded in the request audit trail in Mongo (request body + response body + status code on `imports.requests`).
- **Reporting.** The aggregate counts (`failed_requests_quantity`, percentages) include Unknown's failures because every API call goes through `ApplicationLoader#create_request`, which feeds the same aggregator. The detailed errors appear in the email's xlsx attachment (`ApiReportWorkBook`): one worksheet per failing resource type, columns `ID | Campo | Mensagem de erro`, one row per (resource_id × error field). The recipient sees what failed and why without running a Mongo query.
- **Why the design.** A user whose post-mapping `data.type` is outside the 10-known set must still hit the app's API, so the misconfiguration surfaces at the platform boundary instead of being silently dropped at the integrator. This is true for any source type — DB normalized, DB custom, or API — because the integrator does not gatekeep type values; the app does.

### Other findings (no correction required)

- **`resource_inclusion` validation on Stream.** Bootstrap satisfies it by construction — `source.resources` is computed from the same `NORMALIZED_SCHEMA` used to create the Streams, so every `resource_type.resource` is present in `source.resources`.
- **`paginated_query_template` is optional.** Stream validates only `query_template`. `Stream#paginated?` returns true when paginated_query_template is present. `render_query(variables)` selects the paginated template only when `previous_record_id` is in variables.
- **`User#model_version = '3.0'` is pre-existing.** Already `'3.0'` before PR #2120 — the actual user.rb diff in this PR is two lines replacing `import.identifier` / `import.parent_identifier` with `import.stream.source.user_id_from(...)`.
- **Database adapter console syntax.** Current correct form: `connection.fetch(:table_name, id: 34)` (and similar keyword-argument filters). Older form `connection.fetch(:table_name, "where id=34")` is no longer supported. The README's §2.5.1 uses the older form and must be updated as part of the same `feature/replace-managed-integration-flag` PR.

## Diff against v1 — quick reference

| v1 claim | v2 status |
|---|---|
| Source → Stream → Connector triad | **Stream is the unit; Connector removed.** |
| AttributeMapping embedded in Connector | **Embedded in Stream.** |
| SensitiveKey embedded in Connector | **Embedded in Stream.** |
| Header model | **Removed.** |
| Three identifier-prefix modes (per-source / managed-no-prefix / `4sk_` default) | **Two modes (normalized → `4sk_`, otherwise → pass-through).** |
| `ApplicationConfiguration.managed_integration?` is referenced from `Import#identifier` | **No longer referenced from Import.** Flag survives at view + initializer; scheduled for removal in `feature/replace-managed-integration-flag` (replaced by `Integrator.fully_normalized?`). |
| Stream has `position` field | **Field removed; order is in worker chaining only.** |
| Preflight model | **Replaced by SourceCheck (per source) + StreamCheck (per stream) + AvailabilityCheck workers.** |
| `Computation` coordinates N connectors per stream | **Coordinates N streams per ResourceType.** |
| Worker pairs include `<Resource>::DatabaseExtractor` (non-managed) | **Only `Managed*` variants exist; the prefix is legacy.** |
| `fsk_` table prefix is a per-source default | **No model-level default; bootstrap sets `table_prefix` from `ApplicationConfiguration`.** |
| Resource state transitions: `pending → integrated`, etc. | **Same shape; v1 missed `erased → integrated` re-integration path.** |
| `Import#identifier` computes the load-time identifier | **Removed; logic moved to `Source#user_id_from`.** |
| 14 Resource subtypes, 25 streams | **15 Resource TYPES (added TableLocks); 25 streams confirmed.** Unknown is structural and unconditionally part of the user-loading chain — not a configurable Stream and not a fallback only when a stream is missing. |
| `User` model_version `'2.0'` (implicit) | **Pre-existing `'3.0'`** — not changed by this PR. v1 underestimated the version; default on `Resource` is `'1.0'`. |
| `Header` model `embedded_in :connector` carries arbitrary key/value pairs | **Eliminated.** Was a Mongoid-indexed store of API response headers. The file-based equivalent on `Collection.raw_headers` (CarrierWave uploader) survives and continues to persist response headers per call. |
| `ApplicationConfiguration.managed_integration?` gates pipeline behavior | **Scheduled for removal.** Replaced by `Integrator.fully_normalized?` (top-level helper in `lib/integrator.rb`); symmetric encryption initializer becomes unconditional; view branch keyed on the new helper. |

v1 stays as the historical record of the pre-merge state. v2 is the source of truth for D3 drafting from here on.
