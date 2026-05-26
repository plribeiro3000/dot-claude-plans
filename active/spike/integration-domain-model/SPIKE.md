# SPIKE — Integration domain model: where does resource-type configuration belong?

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-09
**Status:** Research complete — pending decisions

---

## Goal

Where does the "User uses `4sk_` prefix when source is normalized" rule belong in the integration domain model? The investigation needs to identify whether an established domain concept exists that captures "the type of resource and its integration rules for this client" — something distinct from Source (connection config), Stream (flow config), and Resource (individual records).

---

## Method

- Read the integrator codebase: Source, Stream, Connector, Resource, Import, Modifier models and representative workers
- Researched Airbyte, Fivetran, Singer/Meltano, Segment, Kafka Connect, and DataHub documentation
- Looked for industry precedent of a catalog/type-definition layer that separates resource-type rules from flow configuration

---

## Evidence

### 1. Current state in the integrator codebase

**Where the rule lives today** — `Import#user_identifier` (`app/models/import.rb:33`):

```ruby
def user_identifier
  @user_identifier ||=
    if normalized_user?
      "4sk_#{data[:user_id]}"
    elsif self_service?
      "4sk_#{data[:user_id]}"
    else
      data[:user_id]
    end
end

def normalized_user?
  return false if stream_id.blank?
  return false if resource.user? == false
  stream.source.normalized?
end
```

The same conditional appears in `identifier`, `user_identifier`, and `parent_identifier` — three separate methods that all ask the same question.

**The structural problem.** When `Modifier::LoaderConsumer` calls `import.user_identifier` (line 18), that import belongs to the Modifier stream. The method calls `resource.user?` which checks `_type == 'User'` on the Import's resource — but the resource is a `Modifier`, not a `User`. So `normalized_user?` returns `false`, and the `4sk_` prefix is never applied. The modifier's `user_id` field references a User from a different stream entirely, but the Import has no way to know the User stream's source type.

**Evidence of the same pattern in other resources.** `Deal#request_body_for`, `Goal#request_body_for`, `Modifier#request_body_for` all call `import.user_identifier`. Any resource that carries a cross-reference to a User has this same blind spot. Source: `app/models/deal.rb:20`, `app/models/goal.rb:15`, `app/models/modifier.rb:10`.

**What the transformer already knows.** `Modifier::ManagedTransformerConsumer` (line 13, `app/workers/modifier/managed_transformer_consumer.rb`) checks `stream.source.normalized?` to decide whether to apply attribute mappings. The transformer knows the source type — but it throws that knowledge away after transformation. By the time the loader runs, the import only knows its own stream, not the User stream's source type.

---

### 2. Airbyte — AirbyteCatalog and ConfiguredAirbyteCatalog

Source: https://docs.airbyte.com/platform/understanding-airbyte/airbyte-protocol

Airbyte uses a **two-layer model**:

- **AirbyteCatalog** (immutable, source-defined): describes what data exists and how it can be replicated. Fields: `name`, `json_schema`, `namespace`, `supported_sync_modes`, `source_defined_cursor`, `default_cursor_field`. This is the type-level definition. It is produced by the source's `discover` operation and must not be mutated by users.

- **ConfiguredAirbyteCatalog** (mutable, user-configured): wraps each `AirbyteStream` in a `ConfiguredAirbyteStream` and adds how to replicate it. Fields: `sync_mode`, `destination_sync_mode`, `cursor_field`, `primary_key`.

The design principle: "the AirbyteCatalog should be treated as an immutable object; if you are ever manually editing a catalog outside of a source, you've gone off the rails."

**What this means for the problem.** Airbyte explicitly separates "what a resource type is and what it can do" (catalog) from "how we move this resource" (configured catalog). Per-stream metadata (primary keys, cursor fields, sync capabilities) lives in the catalog layer and is source-defined. Per-stream operational choices (sync mode, destination mode) live in the configured layer.

Airbyte does **not** address cross-stream foreign key references or per-resource identifier transformation rules. Primary keys are defined at the stream level, not propagated across streams.

---

### 3. Singer / Meltano — Catalog with breadcrumb metadata

Source: https://github.com/singer-io/getting-started/blob/master/docs/DISCOVERY_MODE.md, https://hub.meltano.com/singer/spec/

Singer uses a catalog with a **breadcrumb metadata system**:

- **Stream-level metadata** (empty breadcrumb `[]`): `table-key-properties`, `valid-replication-keys`, `forced-replication-method`, `schema-name`, `inclusion`
- **Property-level metadata** (breadcrumb `["properties", "field_name"]`): `inclusion` (automatic/available/unsupported), `sql-datatype`

The catalog is produced during discovery. Two categories of metadata:
- **Discoverable** (tap-written): `inclusion`, `valid-replication-keys`, `table-key-properties`, `forced-replication-method`
- **Non-discoverable** (UI/operator-written): `selected`, `replication-method`, `replication-key`

**What this means for the problem.** Singer's model makes the same separation as Airbyte but goes further: some metadata is source-defined (the tap writes it), some is operator-defined (the UI writes it), and both live in the catalog as type-level properties of the stream. The catalog is a first-class object with per-stream, per-property metadata — it is not the same as a sync job or a flow.

Singer also does not handle cross-stream identifier transformation rules. It handles per-field `inclusion` and replication keys, but foreign key relationships between streams are not represented.

---

### 4. Fivetran — Schema config hierarchy

Source: https://fivetran.com/docs/core-concepts, https://fivetran.com/docs/rest-api/api-reference/connector-schema/connector-schema-config

Fivetran exposes a **three-level schema config** per connector:

- **Schema level**: `name_in_destination`, `enabled`, `schema_change_handling`
- **Table level**: `name_in_destination`, `enabled`, `sync_mode` (SOFT_DELETE / HISTORY / LIVE), `supports_columns_config`
- **Column level**: `name_in_destination`, `enabled`, `hashed`, `is_primary_key`

Each table and column can have independent configuration. The response omits unedited entries that follow defaults, meaning configuration is sparse and overrides-only.

Fivetran manages its own normalized schema per connector (source-type) and does not expose per-table identifier transformation rules. Name mapping (`name_in_destination`) is the extent of identifier control.

**What this means for the problem.** Fivetran's per-table config is the closest industry analog to the concept being sought: each table (resource type) has its own configuration object that is separate from the sync job. However, Fivetran only exposes sync mechanics — it does not model cross-resource identifier resolution or source-type-dependent field rules.

---

### 5. Segment — Source Schema and Tracking Plan

Sources: https://segment.com/docs/connections/sources/schema/, https://segment.com/docs/protocols/tracking-plan/create/

Segment uses two complementary concepts:

- **Source Schema**: Tracks which event types have been observed arriving at a source. Events appear grouped by call type (Track, Identify, Group). The schema is auto-built from observed data.

- **Tracking Plan**: A user-defined spec that declares which event types and properties are expected. A tracking plan is connected to one or more sources. When connected, it becomes the reference against which incoming events are validated.

Identifier rules: Segment's Identity Resolution system allows per-identifier-type rules (max values per externalID, merge priority). These rules live in the workspace Unify settings, not in the source schema.

**What this means for the problem.** Segment separates "what arrives" (source schema, observed) from "what should arrive" (tracking plan, specified). The tracking plan is a type-level definition object. Identity resolution rules are per-identifier-type, not per-event-type. This is a closer parallel — the tracking plan concept represents "the definition of what a User event should look like in this context."

---

### 6. Kafka Connect — SMT (Single Message Transforms)

Source: https://docs.confluent.io/kafka-connectors/transforms/current/overview.html

Kafka Connect applies per-connector transformation chains (SMTs). Transforms such as `RegexRouter` can add or remove identifier prefixes. Transforms are conditional via predicates (e.g., `TopicNameMatch`).

However, SMTs are configured at the connector level — not at the message type level. All messages going through a connector share the same transformation chain. Conditional transforms exist but apply based on topic name patterns, not on semantic resource type rules.

**What this means for the problem.** SMTs confirm that identifier prefix transformation is a recognized integration concern. But the Kafka Connect model attaches these rules to connectors (sources/flows), not to resource type definitions. This is the same structural problem the integrator currently has: the rule is on the source, not on the resource type.

---

### 7. DataHub — Data Contracts

Source: https://docs.datahub.com/docs/generated/metamodel/entities/datacontract

DataHub's data contract defines per-dataset (type-level) rules: schema contracts, freshness contracts, data quality contracts. Each dataset can have one active contract. Contracts reference reusable assertion definitions.

This is a type-level governance model, not an integration configuration model. It does not address identifier transformation or cross-entity references.

---

### 8. The structural gap confirmed

No platform researched directly models "per-resource-type, source-type-dependent identifier transformation rules." What the industry does consistently:

1. **Airbyte and Singer**: separate the catalog (type definition, immutable, source-declared) from the configured catalog (flow config, mutable, operator-declared). The catalog is per-stream-type.
2. **Fivetran**: per-table configuration object separate from the sync job.
3. **Segment**: tracking plan (type-level spec) separate from source schema (observed instances).

None of them model the case where Resource Type A (Modifier) carries a foreign key to Resource Type B (User), and the identifier rule for that foreign key depends on User's source type, not Modifier's source type.

This is a domain-specific problem that the integrator must solve itself. The industry provides the pattern (separate type-level catalog from flow config), but not the cross-type identifier resolution.

---

## Conclusions

### C1: There is a missing domain concept — a Resource Type Catalog Entry

Every platform studied separates a **type-level catalog object** from **flow configuration**. The integrator has no equivalent. `Stream` is a flow configuration (`enabled`, `disabled`, `belongs_to :source`, `has_many :connectors`). It has no type-level properties — it has no concept of "the rules for what a User is in this integration context."

The missing concept represents: "For this integration, what are the rules for the User resource type?" This includes:
- Whether the identifier should receive the `4sk_` prefix
- Which source type drives that rule
- Other resource-type-level properties that might be added in future (field inclusion, replication strategy, etc.)

In Airbyte's terms, the integrator has `ConfiguredAirbyteStream` but not `AirbyteStream`. In Singer's terms, it has the sync config but not the catalog entry.

### C2: The rule belongs on the resource type, not on the import, the source, or the stream

**Not on Source**: `Source.normalized?` applies to all resource types in that source. A normalized source defines how Users are stored, but it does not define what to do with a foreign key in a Modifier that references that User. The rule is about the User resource type, not about the Source.

**Not on Stream**: Stream is flow configuration — it connects a source to a connector. A Modifier stream cannot know the User stream's source rules. Putting the rule on Stream creates the exact cross-stream dependency problem that currently breaks.

**Not on Import**: Import is a snapshot of one extraction job. It has the data but not the context to interpret that data. `normalized_user?` is a workaround that only works when the import's own resource is a User — it breaks for Modifier, Deal, Goal because their imports are not User imports.

**On the resource type catalog entry**: The `4sk_` prefix is a property of "what a User identifier means in this integration context." It depends on `source.normalized?` for the User stream — which is available at setup time, not only at runtime. It is static configuration, not runtime data.

### C3: Three viable options exist — the decision is about where the catalog entry lives

**Option A — StreamCatalog (a new model wrapping Stream)**

A new `StreamCatalog` model with `belongs_to :stream` and fields like `identifier_prefix`. Populated when streams are created, based on `stream.source.normalized?`. The Modifier's Import resolves the User identifier by looking up the User stream's catalog entry.

- Accurate separation: Stream remains flow config, StreamCatalog is type config
- Requires a lookup: Modifier's import must find the User's StreamCatalog at load time
- Adds a new model and a new association pattern

**Option B — Per-resource-type fields on Stream**

Add fields directly to Stream: `identifier_prefix` (string, nullable). Set from `source.normalized?` on creation. The Modifier's Import calls `UserStream.identifier_prefix` at load time.

- Simpler: no new model
- Blurs Stream's responsibility: Stream becomes both flow config and type config
- Fragile: adding more type-level properties grows the Stream table indefinitely

**Option C — Store the resolved prefix in Import at transform time**

In the transformer (where `stream.source.normalized?` is already checked), store the resolved prefix for all cross-resource references as part of `import.data`. E.g., `import.data[:user_id_prefix] = "4sk_"` when normalized. The Import uses the stored prefix at load time.

- No new model, no new lookup at load time
- Denormalized: the prefix is embedded in every import record
- Robust to future changes: the transformer is the moment of context resolution, and the import carries what it needs
- Does not solve the conceptual gap (the type definition is still not explicit), but solves the runtime problem

---

## Next Steps

- The engineer must decide which option to pursue before any code is written
- Option A (StreamCatalog) is closest to industry precedent (Airbyte's two-layer model, Singer's catalog) and represents the cleanest domain model — but it is the most structural change
- Option B (per-resource-type fields on Stream) is pragmatic but expands Stream's responsibility
- Option C (denormalized prefix in import.data) is the most isolated change and solves the immediate bug without restructuring the domain — but leaves the conceptual gap open
- If Option A or B is chosen, generate a PLAN.md for implementation
- If Option C is chosen, it may be implemented directly as a targeted fix
