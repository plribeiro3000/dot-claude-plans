# SPIKE — Effort to make the integrator read the Colombia VKPI database

## Investigation question

What does it cost to add the VKPI SQL Server (`COLBOGSQL58\MSSQL58_KPI`) as a second, **non-normalized** source on the existing Atento Colombia integrator, feeding a `Modifier` stream — starting from `develop`, which is believed to already support multiple databases but has never been exercised that way?

Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).

## Sources consulted

- `~/Projects/4Shark/integrator` at `origin/develop`, verified current with `git rev-list --left-right --count origin/develop...HEAD` → `0 0` before any code claim below.
- `~/.claude/skills/integrators/environments.json` — the per-client data-acquisition catalogue.
- `~/Projects/4Shark/dot-claude-plans/active/atento-colombia-vkpi-integration/PLAN.md` — the agreed integration shape (second non-normalized source + Modifier stream, stack `co`, root mode).
- `~/Projects/4Shark/integrator/CLAUDE.md` — the pipeline and stream-order contract.

## Findings

### Finding 1: the multi-source machinery exists and is complete for this shape

`Source` is a Mongoid model with two subtypes and a `normalized` flag; `Stream` binds one resource type to one source and carries its own query.

```ruby
# app/models/source.rb:4,18-31
TYPES = %w[ApiSource DatabaseSource].freeze
...
field :name, type: String
field :normalized, type: Boolean, default: false
field :resources, type: Array, default: []
field :timezone, type: String

validates :_type, inclusion: { in: TYPES }
validates :name, presence: true
validates :resources, presence: true, array_inclusion: { in: Resource::TYPES }
validates :timezone, presence: true
validate :user_resource_uniqueness

scope :normalized, -> { where(normalized: true) }

index({ normalized: 1 }, unique: true, background: true, partial_filter_expression: { normalized: true })
```

The producer fans out per stream and routes each one by its own source's type, so several streams of the same resource can come from different databases:

```ruby
# app/workers/modifier/extractor_producer.rb:19-33
stream_ids.each do |stream_id|
  stream = Stream.find(stream_id)
  args = [job_id, stream_id.to_s]

  if stream.source.database?
    database_arguments << args
  else
    api_arguments << args
  end
end

total_streams = database_arguments.size + api_arguments.size
job.computation.increment_queue(by: total_streams)
Sidekiq::Client.push_bulk('class' => Modifier::DatabaseExtractorConsumer, 'args' => database_arguments) if database_arguments.any?
Sidekiq::Client.push_bulk('class' => Modifier::ApiExtractorConsumer, 'args' => api_arguments) if api_arguments.any?
```

**Significance:** no new worker, no new model, no schema change. Adding the VKPI source is configuration — one `DatabaseSource` document plus one `Stream` document — not a new code path. That is the single biggest input to the estimate.

### Finding 2: the permission gate already exempts a non-normalized source

The authorization check that demands SELECT on the fifteen normalized-base tables is explicitly gated on the source being normalized:

```ruby
# app/workers/authorization/database_consumer.rb:12-37
if source.normalized?
  connection = source.connect!
  missing_permissions = connection.permissions.missing

  if missing_permissions.any?
    source_check.update(
      authentication: :failed,
      failure: :missing_permissions,
      affected_resources: missing_permissions
    )
  else
    ...
  end
else
  source_check.update(authentication: :skipped)
end
```

**Significance:** this was the most likely place for a non-normalized database source to fail on the first run, because `Permissions#missing` rejects `DatabaseSource::DATA_SOURCE_TABLES` — fifteen tables that do not exist on the VKPI server — without itself checking `normalized?` (`app/adapters/microsoft_sql_adapter/permissions.rb:13-17`). The guard sits one level up, in the worker, and it is correct. **The cost of this is that the VKPI source gets NO authorization check at all** — its credentials and grants are validated only when the extract query actually runs.

### Finding 3: the transform half is battle-tested; only the extract half is new

The transformer branches on the same flag, and the non-normalized branch is the one that applies attribute mappings:

```ruby
# app/workers/modifier/transformer_consumer.rb:31-59 (else branch — non-normalized)
simple_attribute_mapping_ids = stream.attribute_mappings.in(kind: [0, 1]).pluck(:id)
compound_attribute_mapping_ids = stream.attribute_mappings.in(kind: [2, 3]).pluck(:id)
variables = Variables.new(job, stream.source)
sensitive_keys = stream.sensitive_keys

collections.each do |collection|
  records = JSON.parse(collection.raw_body.read.force_encoding('UTF-8'))
  records = records.dig(*stream.collection_source_keys) if stream.collection_source_keys.present?

  records.each do |record|
    ...
    simple_attribute_mapping_ids.each do |attribute_mapping_id|
      attribute_mapping = stream.attribute_mappings.find(attribute_mapping_id)
      attribute_value = attribute_mapping.simple(record)
      attributes[attribute_mapping.target] = attribute_value
    end
```

That branch is **not** dead code: every `ApiSource` in production goes through it, because an API source is non-normalized by construction. What has never run is the pairing of a **database** source with the non-normalized branch — the extract side (`Modifier::DatabaseExtractorConsumer` rendering a Liquid `query_template` against a customer schema and writing a raw collection) rather than the transform side.

**Significance:** the untested surface is one worker, not the pipeline. That bounds the risk and is what makes a two-to-three-week window credible rather than optimistic.

### Finding 4: no client anywhere runs a non-normalized database source today

`environments.json` describes exactly two acquisition models, and both terminate in a normalized base:

> `"harvester"`: *"4Shark runs a dedicated .NET Simplex ETL … and writes the normalized base the Ruby integrator then consumes. Only Atento MX and CO use this model."*
> `"normalized-base-only"`: *"No harvester — the Ruby integrator reads a normalized base that the customer (or another process) populates … Every integrator except Atento MX/CO uses this model."*

Every one of the twelve environments in that file carries `"source_model"` equal to one of those two, and every `normalized_base` entry names a real database.

**Significance:** this confirms the engineer's own reading — the capability is built and has zero production mileage. It also means there is no reference configuration to copy: the first `DatabaseSource` with `normalized: false` in the fleet will be this one.

### Finding 5: the query is a Liquid template with a fixed variable vocabulary

`Stream#render_query` picks the paginated template when a previous record id is present and renders it through Liquid:

```ruby
# app/models/stream.rb:74-78
def render_query(variables)
  template_source = variables['previous_record_id'].present? ? paginated_query_template : query_template

  Liquid::Template.parse(template_source).render(variables.stringify_keys)
end
```

The variables available are fixed by `Variables#to_h` (`app/models/variables.rb:13-47`) — `fetch_since`, `starts_at`, their month/year boundaries, `page`, `page_size`, `previous_record_id`. Both timestamps are rendered `'%Y-%m-%d %H:%M:%S'` in the **source's own timezone**, taken from `Source#timezone`.

**Significance:** the incremental-read strategy has to be expressible with those variables and nothing else. That lands directly on the `DT_CREATED` / `DT_MODIFIED` columns `PLAN.md` requires Atento to add: without them there is no `fetch_since` predicate to write, and the stream degrades to a full read of the score table on every run. **This is a hard dependency of the build on Atento's side, not a nice-to-have** — and it is the same column pair already on the open-items list.

### Finding 6: pagination needs a monotonic primary key the VKPI table does not obviously have

The consumer paginates by carrying the last row's primary key forward:

```ruby
# app/workers/modifier/database_extractor_consumer.rb:31-37
if stream.paginated?
  collection_last_id = raw_collection.last[stream.primary_key.to_sym]
  Modifier::DatabaseExtractorConsumer.perform_async(job_id, stream_id, collection_last_id)
else
  job.computation.increment_executions
  Goal::ExtractorProducer.perform_async(job_id) if job.computation.done?
end
```

`Stream#primary_key` defaults to `'id'`. The keyset walk is correct only if that column is unique and ordered, and the paginated template orders by it.

**Significance:** `PLAN.md` records the score table's identity as the composite **period + person + programa + indicator**, with no single surrogate key mentioned and no unique index applied yet. If no monotonic single column exists, either the stream runs unpaginated (one query returning the whole month — viable at this volume, but it holds a connection and a JSON blob in memory) or Atento adds an identity column. **This has not been raised with Atento and is not on the open-items list in `PLAN.md`.**

## Effort

Three weeks are committed to Atento, 17-sep to 08-oct. The findings support that figure, and the shape of the work is what follows — noting that the table below covers only the VKPI half, six to nine working days of it; the rest of the window is spent making `develop` deployable, which is not VKPI work:

| Work | Driver | Rough weight |
|---|---|---|
| Network path from the `co` integrator tasks to `COLBOGSQL58` | A second SQL Server on a host the integrator has never reached; may need a route, a firewall rule, or a new VPN leg | Unknown until tested — the one item that can blow the window |
| The `DatabaseSource` + `Stream` documents, with query template and attribute mappings | Configuration; no code | Small |
| First real run of the database + non-normalized extract | Finding 3 — the single untested worker | Medium, and the likeliest source of small fixes |
| Pagination decision (Finding 6) | Whether a monotonic key exists | Small if unpaginated is accepted; a round-trip with Atento if not |
| Validation on `atento-co-staging` before production | The staging environment exists (`glazrdbvp051`, db `CO_4Shark_DB`) | Medium |
| Release and rollout | Normal HubFlow release of the integrator, one deployment per `INTEGRATORS` key | Small |

**What the three weeks do NOT cover, and must not be folded in silently:** Atento's own time to run the structure script and populate `llave`. The build starts on 17-sep regardless, but it cannot be validated against a base that does not yet carry the structure, so a delay there moves the 08-oct delivery by the same amount — the term the roadmap states to Atento.

## What remains uncertain

- **Network reachability from the integrator's ECS tasks to the VKPI host.** Not tested, and not answerable from this machine. It is the only line in the table with an unbounded upper end.
- **Whether the score table has a single monotonic column** suitable for `Stream#primary_key`. Finding 6; unraised with Atento.
- **Whether `DT_CREATED` / `DT_MODIFIED` will be populated for historical rows** or only for rows written after the change. An incremental `fetch_since` read against a column that is null for existing rows silently returns nothing.
- **Connection-pool behaviour with two database sources on one integrator.** `DatabaseSource.adapters` is a `Concurrent::Map` keyed by source id (`app/models/database_source.rb:40,48-50`) so each source gets its own pool, sized by `max_connections || ApplicationConfiguration.sql_pool_size` — but two pools per task against two servers has never run, and the task's memory ceiling is not something this spike measured.
