# Sources and Streams

The configuration surface for a customer integration is two Mongoid models: `Source` and `Stream`. Together they answer "where does the data come from" (Source) and "what data, how, into which platform resource" (Stream). Everything else — authentication, attribute mappings, sensitive-key masking, query templates — hangs off of one or the other. Adding, modifying, or removing a customer's integration behavior is a matter of editing these documents; no code changes per customer.

## Source — where data comes from

`Source` is a single-table inheritance Mongoid base class with two concrete subclasses: `DatabaseSource` and `ApiSource`. Future source types (FTP, message queues, S3 drops) would join the same hierarchy.

A Source represents one connection point to one customer system. A customer with a single normalized SQL database has one DatabaseSource. A customer with a normalized database **and** a SaaS API for a separate data slice has one DatabaseSource and one ApiSource. The integrator can run with multiple Sources of mixed types.

Common fields across both subclasses:

- **`name`** — human label, used only in reports and logs
- **`normalized`** — boolean flag marking the single 4Shark-bootstrapped Source. Affects the identifier-handling rule (Chapter 7) and gates the user/parent JOIN in the Transformer (Chapter 8). Enforced by a partial unique index on the database side: at most one Source can be `normalized: true` per integrator. Customers without a normalized Source (custom-only) are valid; customers with two normalized Sources are not.
- **`resources`** — array of Resource type names this Source can supply, e.g. `['User', 'Subsidiary', 'Deal']`. Validated against `Resource::TYPES`. Used by Stream's `resource_inclusion` validation: a Stream attached to ResourceType `Manager` (with underlying `Resource = 'User'`) is valid only if `'User'` is listed in the Source's `resources`. This is the model-level guard that prevents a misconfigured Stream from extracting User data from a Source that was never set up to provide it.
- **`timezone`** — the timezone the Source's data is in. Used by the Variables helper (Chapter 8) when rendering Liquid templates that reference `fetch_since`, `starts_at`, or any other Job timestamp — the timestamps are converted to the Source's timezone before string-formatting. A customer with multiple Sources in different timezones (rare but possible) handles each one's timestamps locally.

A custom validation, `user_resource_uniqueness`, ensures **only one Source declares User**. The integrator does not support a customer where User data is split across two Sources — a user record either lives in the normalized DB or in the custom system, never in both. This is a domain constraint: a User has exactly one platform-side identity, and that identity is owned by one Source on the integrator side.

### `Source#user_id_from(id)`

The single entrypoint for the identifier-prefix logic. Takes a raw id from the Source and returns the platform-facing identifier:

```ruby
def user_id_from(id)
  if normalized?
    "4sk_#{id}"
  else
    id
  end
end
```

Two modes only — no per-Source identifier-prefix field, no `managed_integration?` global flag, no special-case branches. Either the Source is normalized (4Shark-bootstrapped) and emits prefixed identifiers, or it is custom and emits whatever identifier the customer's source already uses. Chapter 7 covers why this is the right shape.

### DatabaseSource

Adds the SQL-specific configuration:

- **`adapter`** — `'microsoft_sql_server'` or `'postgres_sql_server'`. Validates inclusion. Determines which adapter class is instantiated by `connect!`.
- **`host`**, **`port`**, **`database_name`** — the connection coordinates
- **`azure`** — boolean. Affects which `SET` statements the MSSQL adapter issues at connection start (Azure SQL has a slightly different set of session-level settings than on-prem SQL Server)
- **`table_prefix`** — string prepended to table names in the bootstrap-generated query templates. The 4Shark normalized schema uses `'fsk_'` (e.g. `fsk_users`, `fsk_subsidiaries`); a customer running the normalized contract sets it once at bootstrap time and never changes it. Custom Sources don't use this field — their query templates reference whatever schema they need directly
- **`timeout`** — the SQL connection timeout, in seconds. Default 5
- **`warm_up`** — boolean opt-in for the wake-up chain. Hosting providers that auto-pause idle databases (Azure SQL serverless) need a real round-trip before the integration job can start; a Source with `warm_up: true` triggers `DatabaseWarmer::Producer` ahead of `Job::Starter` to perform the wake. Sources on always-on infrastructure leave this field unset
- **`max_connections`** — sizes the Sequel connection pool for this Source. When unset, defaults to `ApplicationConfiguration.sql_pool_size` (sized off the Sidekiq concurrency at process boot). When set, overrides per-source. Used by customers whose database has unusually low or unusually high connection limits

### ApiSource

Adds API-specific configuration:

- **`identifier`** — a 4-character unique string, e.g. `'sfdc'` (Salesforce), `'tkmb'` (Trackmob). Validated for length (exactly 4) and uniqueness via index. Used by the `IdentifierPrefixerTransformer` (Chapter 8) to namespace per-API record fields when multiple ApiSources feed the same ResourceType — without the prefix, two APIs reporting attribute `id=42` would collide; with the prefix, they become `sfdc-42` and `tkmb-42`

ApiSource intentionally has no `host` or `port`. The endpoint URL is a property of the Stream (`query_template` for HTTP API streams is the URL template), not of the Source — different Streams under the same ApiSource can hit different endpoints of the same authenticated API.

## Stream — what data, how, into which Resource

`Stream` is the unit of integration. A Stream answers four questions:

1. **What ResourceType am I producing?** (`belongs_to :resource_type`)
2. **From which Source am I reading?** (`belongs_to :source`)
3. **How do I read it?** (`query_template`, `paginated_query_template`, `attribute_mappings`)
4. **What's the gating shape?** (`fetch_since_column`, `page_size`, `primary_key`)

A customer with the normalized contract has 24 Streams (one per `NORMALIZED_SCHEMA` entry, plus User::Unknown which is structural). A customer with mixed sources can have more — the same ResourceType can be supplied by multiple Streams, e.g. a normalized Source providing 80% of the users plus an ApiSource pulling the remaining 20% from a SaaS HR system. The pipeline runs every Stream attached to the ResourceType in parallel and merges the results downstream (Chapter 10).

Key fields:

- **`name`** — human label
- **`query_template`** — Liquid-templated SQL or HTTP path. Required. For DatabaseSources, an example bootstrap-generated template is `SELECT * FROM fsk_users WHERE updated_at >= '{{ fetch_since }}' LIMIT {{ page_size }}`. For ApiSources, this is the path against the authenticated API
- **`paginated_query_template`** — optional second template used when the previous page returned a full batch and the next page must be fetched. References `{{ previous_record_id }}` to seek past the last id of the previous page. A Stream with no paginated template returns at most `page_size` rows (the API or query is "single-shot")
- **`page_size`** — number of rows per page. Required. Validated as positive integer
- **`primary_key`** — the field used for keyset pagination. Default `'id'`. Some APIs return a different key name; some custom DB queries project the primary key as `external_id` or similar
- **`fetch_since_column`** — the column used to scope rows by the Job's `fetch_since` timestamp. Default `'updated_at'`. Five normalized Streams override to `'created_at'` (Hierarchy, ParentUpdate, Groupification, UserField, UserActivity) because these resources represent append-only events whose business identity is "when this happened"
- **`availability_probe`** — a tiny query the AvailabilityCheck worker runs before the Stream is allowed to extract. For DB Streams, typically `SELECT 1 FROM <table> WHERE 1 = 0`. For API Streams, a no-data probe against the endpoint. Chapter 11 covers how this gates the Stream
- **`success_response_status_code`** — for API Streams, the expected HTTP status of a successful page fetch (typically `'200'`). Anything else is a Stream failure
- **`collection_source`** — for nested API responses, the dotted path to the array of records inside the response body (e.g. `'data.users'`). Empty for flat responses
- **`disabled`** — boolean. Disabled Streams are skipped at the Producer level. Used to pause an integration without deleting its configuration

`embeds_many :attribute_mappings` and `embeds_many :sensitive_keys` carry the per-Stream transformation logic (Chapter 8).

### Validations

- `query_template` and `name` and `page_size` and `source_id` are required
- `primary_mapping_presence` — exactly one AttributeMapping must have `primary: true`, unless the mapping list is empty (which is the case for normalized Streams, where the row is denormalized as-is without per-field mapping)
- `resource_inclusion` — the underlying Resource of the Stream's ResourceType must appear in the Source's `resources` array. This is the cross-document validation that prevents "attach a Deal stream to a Source that doesn't supply Deals"
- `disabled` must be a boolean (not nil)

### Helpers

`enabled?`/`disabled?`, `enable`/`disable`, `database_source?`/`api_source?`/`normalized_source?`, `paginated?`, `render_query(variables)` (Liquid render of `query_template` or `paginated_query_template` based on whether `previous_record_id` is in the variables), `ready_for?(job)` (true when both this Stream's StreamCheck and its Source's SourceCheck are successful for the given Job).

## ResourceType — the layer between Stream and Resource

`ResourceType` is the third document in the trio (after Source and Stream). A ResourceType has a `name` (the logical sequence step, e.g. `'Manager'`) and a `resource` (the underlying Resource class, e.g. `'User'`). Streams attach to ResourceType, not directly to Resource.

The decoupling does two things:

1. **Multiple Streams per ResourceType** — when N customers' worth of data lives in N different Sources, the same logical "Users at Manager level" step can have N Streams pulling from each. `Computation` (Chapter 10) coordinates the fan-out.
2. **Multiple ResourceTypes per Resource class** — the 10 user levels (Admin, President, ..., SalesRepresentative) are 10 ResourceTypes that all map to `resource: 'User'`. ParentUpdate is a ResourceType that maps to `resource: 'Hierarchy'` (same model class as the Hierarchy ResourceType, but with a different filter and a different position in the sequence). Adding a new logical step does not require a new Resource class — it requires a new ResourceType row and the worker chain pointers.

Without ResourceType, the pipeline would have to either (a) hardcode 10 separate user-resource classes (one per access level) or (b) carry the access-level filter inside the worker chain. ResourceType is the explicit place where "logical sequence step" diverges from "Resource class".

## How the three documents relate

A Stream `belongs_to` a ResourceType and a Source. Multiple Streams attach to the same ResourceType (the per-Resource fan-out). Multiple Streams attach to the same Source (one Source can supply many Resources). One ResourceType maps to one Resource class. One Resource class can be the target of many ResourceTypes.

```
Source ──< Stream >── ResourceType ──> Resource (class)
            │
            ├─ AttributeMapping (embedded)
            └─ SensitiveKey   (embedded)
```

`AttributeMapping` and `SensitiveKey` are embedded under Stream — they are scoped per-Stream and don't survive the Stream document. This is intentional: two Streams feeding the same ResourceType from different Sources will have different mappings (the column names won't match), so the mappings cannot be shared at the ResourceType level.

## Authentication

`Authentication` is a separate Mongoid STI hierarchy — `DatabaseAuthentication`, `SalesForceAuthentication`, `TrackmobAuthentication` — with `belongs_to :source`. Each Source has at most one Authentication (`has_one :authentication`).

The split between Source and Authentication exists because the Source is the "where" and the Authentication is the "how to log in". In practice, a customer's database connection details (host, port, database name) and credentials (username, password) live in the same place; splitting them into two documents is mostly an artifact of supporting different auth schemes per Source type. SalesForce uses OAuth tokens; Trackmob uses API keys; Database uses username/password — the `Authentication` STI handles the type-specific fields.

## Why this is data, not code

A customer's integration is fully described by:

- 1 or more Source documents (with their Authentications)
- N Stream documents, attached to the appropriate ResourceTypes
- Per-Stream AttributeMappings and SensitiveKeys

Editing any of the above changes the integration's behavior on the next run. There is no "deploy a new version of the integrator with the customer's mapping baked in" step — the mappings live in MongoDB, alongside the data they shape. This makes onboarding a new customer a matter of running the bootstrap rake task (for normalized customers) or hand-creating the documents in the console (for custom customers), not building and deploying a new artifact.

The trade-off is that the configuration is **harder to review in a PR** — a Stream's `query_template` is a string in MongoDB, not a Ruby file. The current state of an integration is read with `Stream.all.to_a`, not with `git log`. This works because the configuration changes infrequently after onboarding, but it is the main reason 4Shark engineering owns the customer's integrator MongoDB rather than letting the customer manage it directly.
