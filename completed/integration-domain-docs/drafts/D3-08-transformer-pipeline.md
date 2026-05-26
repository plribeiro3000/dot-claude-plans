# AttributeMapping and the transformer pipeline

The Transform stage reshapes a row from the customer's source into the JSON body the 4Shark API expects. The reshape is configured per Stream, declaratively, by a list of `AttributeMapping` documents embedded under the Stream. Each mapping says "take this from the source, do this to it, put it under that target attribute". When all mappings have been applied, the result is the API request body for that record.

Normalized Sources also carry a denormalization step at the same stage — pulling user (and sometimes parent) data from the source DB and folding it into the body. That step lives in the worker, not in the AttributeMapping list.

## Four mapping kinds

`AttributeMapping#kind` takes one of four values:

- **`dynamic`** — copy a value from the source row to the target attribute, optionally piped through a transformer. The most common kind. Example: `source: 'first_name'`, `target: 'first_name'`, no transformer; the row's first_name becomes the body's first_name.
- **`fixed`** — emit a hardcoded value, regardless of the source row. Example: `target: 'company_id'`, `fixed_value: '4Shark'`. Used for fields that are constant across the customer's data — the company tenant the API resolves the customer into, a fixed `type` value when the source row doesn't carry it.
- **`template`** — render a Liquid template that interpolates source fields and Variables. Example: `source: '{{ first_name }} {{ last_name }}'`, `target: 'full_name'`. Lets the customer combine columns or insert Job-level values (timestamps, fetch windows) without changing the source schema.
- **`formula`** — evaluate a Dentaku formula against source fields. Example: `source: 'price * quantity * (1 - discount)'`, `target: 'net_amount'`. Used for derived numeric fields where the customer would otherwise have to write a CASE expression in the source query.

Two mappings can target the same attribute, in which case the second overwrites the first. This is occasionally useful for "default value, then override if the source has a real value", but the more common use is just one mapping per target.

## Two passes per record

The Transformer runs the mapping list twice — once for "simple" mappings (`dynamic` and `fixed`) and once for "compound" mappings (`template` and `formula`). The split exists because compound mappings can reference earlier mapping outputs:

- `dynamic` and `fixed` only consult the source row; they have no inter-mapping dependencies
- `template` and `formula` may reference any field that has already been computed — both source columns and the outputs of earlier `dynamic`/`fixed` mappings

Running `dynamic`/`fixed` first guarantees that by the time a `template` or `formula` references `'subsidiary_external_id'`, the value is already in the attribute hash regardless of which order the mappings were defined in. Within each pass, mappings run in the order they appear on the Stream.

The two-pass shape matters because customer mapping lists are not guaranteed to be in a useful order — the configuration is a Mongoid embedded list, edited over time, and the mappings may be added in any sequence as the customer's needs evolve. Sorting by kind at the worker level removes one source of ordering bugs.

## The primary mapping

Exactly one mapping per Stream carries `primary: true`. The primary mapping identifies the source field that becomes the **external_id** of the record on the platform side — the customer-side identifier that the rest of the integration uses to refer to this record.

For normalized Streams, the primary mapping is degenerate: every row is denormalized as-is into the import, so there is no per-field mapping list and no `primary: true` flag (the validation `primary_mapping_presence` only requires the flag when the mapping list is non-empty). The "primary" identifier comes from `Source#user_id_from(record['id'])` instead.

For custom Streams, the primary mapping is the heart of the configuration. A Salesforce contacts stream might have `source: 'Id'`, `target: 'external_id'`, `primary: true` — the SF contact ID becomes the external id on the platform.

The `primary_mapping_presence` validation enforces "exactly one or none" — you cannot have a Stream with two `primary: true` mappings, because the platform identity has to be unambiguous.

## Transformers — field-level functions

Each `dynamic` or `fixed` mapping can optionally specify a `transformer` — a class name that runs the mapped value through a transformation before storing it under the target. The transformer set is fixed in the codebase:

- **`BooleanTransformer`** — coerce to true/false. Source values like `'1'`, `'true'`, `'Y'` become `true`; everything else becomes `false`. Used for source schemas that store booleans as varchar.
- **`FloatTransformer`** — coerce to a Float. Used for numeric fields that arrive as strings.
- **`FloatingPointCurrencyTransformer`** — coerce currency strings (e.g. `'1.234,56'`) to a Float. Handles locale-specific formatting that the customer's source emits.
- **`BeginningOfMonthTransformer`** — round a Date to the first of its month. Used for goals and indicators where the business semantics are "this entire month".
- **`EndOfMonthTransformer`** — round a Date to the last day of its month. Same use case, opposite end.
- **`IdentifierPrefixerTransformer`** — prepend the ApiSource's 4-character `identifier` to the value. Implementation: `"#{source.identifier}-#{value}"`. Used when multiple ApiSources feed the same ResourceType and an attribute (typically the external_id of a referenced entity) would otherwise collide between sources. Only meaningful on ApiSources — DatabaseSource has no `identifier` field.
- **`VariablePrefixerTransformer`** — prepend a configured prefix to values that reference a registered Variable on the platform. Used for DealField mappings where the variable name in the customer's source needs a namespace before being recognized by the API.
- **`ApplicationTransformer`** — base class. Defines the shared interface and the `source` accessor (which resolves to `attribute_mapping.stream.source`).

There are 7 concrete transformers plus the base. Adding a new one is a code change — a new file under `app/transformers/`, registered in `ApplicationTransformer::TRANSFORMERS`. This is intentional: transformers are tiny, type-aware functions that need to be reviewed and tested. A customer-controlled "type your own transformer" mechanism would let configuration cause crashes, which would push a per-customer-debugging incident onto a customer whose IT staff cannot debug Ruby. The fixed set is the right shape for the persona.

## `IdentifierPrefixerTransformer` vs `Source#user_id_from` — different layers, complementary

Both touch identifiers; both prepend a string. They operate at different layers and solve different problems:

- **`Source#user_id_from`** (Chapter 7) — Source-level rule, applied at API-request-body time, decides whether the record's own customer-side identifier gets the `'4sk_'` prefix. Two modes: normalized → `'4sk_<id>'`, otherwise pass-through. Operates on the record's own primary identifier.
- **`IdentifierPrefixerTransformer`** — AttributeMapping-level transformer, applied during the Transform stage to **a specific field** of the import body, decides whether that field gets the ApiSource's 4-character prefix. Operates on whatever field the mapping points at — typically a foreign-key field referencing another resource within the same ApiSource.

A Deal coming from Salesforce ApiSource (`identifier = 'sfdc'`) might have:

- Its own external_id resolved by `user_id_from`: pass-through (Salesforce is non-normalized), so the deal's external_id is the raw Salesforce id like `'D-001'`
- Its `user_id` field (the seller) transformed by `IdentifierPrefixerTransformer`: becomes `'sfdc-EMP-99'` because the seller record came in via the same Salesforce stream and was registered with the prefixed identifier earlier in the pipeline

The two mechanisms compose. The transformer is per-field; the Source rule is per-record.

## The Variables helper — Liquid context

Compound mappings (`template`, `formula`) can reference variables from the Job context, not just the source row. The variables are provided by `Variables.new(job, source, ...)`. The hash includes:

- **`fetch_since`** — the Job's fetch cutoff timestamp, in the Source's timezone, formatted as `'%Y-%m-%d %H:%M:%S'`
- **`starts_at`** — the Job's start timestamp, same shape
- **A grid of derived timestamps** — beginning-of-month, end-of-month, beginning-of-year, end-of-year, last-month, last-year, "previous month of fetch_since", "previous year of starts_at", and so on. Roughly 30 derived values, all timezone-aware.
- **`page_size`** — the current Stream's page size
- **`previous_record_id`** — set during pagination; the largest id of the previous page, used by paginated query templates to seek
- **`page`** — the current page number (zero-indexed); used by API streams that paginate by page number rather than by id

The grid of derived timestamps exists because customer formulas commonly need them (a goal definition that says "values from beginning_of_month_of_fetch_since to end_of_month_of_fetch_since", a deal extraction that filters by "starts_at.last_month") and computing them ad-hoc inside Liquid would be brittle. Pre-computing them and exposing them as a flat hash keeps the templates short.

The same `Variables` instance is reused across all records in the same page and the same Stream's worker invocation — the values are deterministic per-Job-per-Stream, so caching is safe.

## Sensitive keys — masking

Each Stream has `embeds_many :sensitive_keys` — a list of paths (e.g. `'card_number'`, `'authentication.password'`) whose values must be masked in logs. The Transformer Consumer walks the list before processing each record and replaces the targeted values with `nil` in the in-memory copy. The masked record is what gets persisted to the Import, what gets emitted in API request bodies, and what shows up in audit-trail searches.

The 4Shark side of the integrator is operational, not security-cleared — engineers debugging a customer issue read MongoDB exports and Sidekiq job dumps without going through a separate access-controlled pipeline. SensitiveKey is the layer that keeps high-sensitivity fields (customer document numbers, credentials, payment details) out of those debug paths. A customer's source schema is reviewed at onboarding to identify which fields need masking; the Stream documents reflect those decisions.

## The normalized JOIN — denormalization at transform time

For 8 of the 25 streams, a record from a normalized Source carries foreign keys (`user_id`, sometimes `parent_id`) that the API expects to receive **resolved** — not as references, but as embedded objects. The pipeline handles this with a JOIN at the Transformer Consumer, executed only when the Source is normalized:

```ruby
if stream.source.normalized?
  connection = stream.source.connect!

  collections.each do |collection|
    records = JSON.parse(collection.raw_body.read)
    records.each do |record|
      users = connection.fetch(:users, { id: record['user_id'] })
      record['user'] = users.first
      # for Hierarchy and User: also fetch parent
      resource = Hierarchy.get(record['id'].to_s)
      import = resource.imports.find_or_initialize_by(job_id: job.id.to_s)
      import.data = record
      import.stream_id = stream.id
      import.save
    end
  end
end
```

The eight resources that participate:

- **Hierarchy** — JOINs `users` by `user_id` (always) and by `parent_id` (when present)
- **User** (each of the 10 access-level Streams) — JOINs `users` by `parent_id` when the user has a parent
- **UserIdentifier** — JOINs `users` by `user_id` (always)
- **Groupification** — JOINs `users` by `user_id` (always)
- **UserField** — JOINs `users` by `user_id` (always)
- **UserActivity** — JOINs `users` by `user_id` (always)
- **Deal** — JOINs `users` by `user_id` (always — the seller)
- **Modifier** — JOINs `users` by `user_id` (always)
- **Goal** — JOINs `users` by `user_id` when present (group goals don't have a user)

The five resources that don't JOIN (Subsidiary, Client, Product, Group, DealExtraField) are either independent of the user graph or carry their references in a shape the API accepts directly.

The JOIN is **not** an AttributeMapping — it is hardcoded in the Transformer Consumer for each of the 8 resources. The reason it lives in the worker rather than in the mapping is that the JOIN is a property of the data shape (users live in a separate table; the API needs them embedded) rather than a property of one field. Configuring it as a mapping would require a meta-mapping ("this column is a foreign key to that table; resolve and embed"), which is a much larger surface area than the hardcoded approach. Since the JOIN is deterministic for normalized schemas, hardcoding is the right shape.

For non-normalized Sources, the worker takes the `else` branch and runs the AttributeMapping pipeline. The custom mapping list is responsible for producing whatever shape the API needs — including embedding nested objects when the customer's source query returns them denormalized already.

## Why mappings live on the Stream, not on the ResourceType

A reasonable alternative would be to attach the AttributeMappings to the ResourceType — same mappings for every Stream that produces that ResourceType. The integrator does not do this for a concrete reason: two Streams feeding the same ResourceType from different Sources will have different column names. A `Manager` stream from a normalized DB has `first_name`/`last_name`/`subsidiary_id` columns; a `Manager` stream from a Salesforce ApiSource has `FirstName`/`LastName`/`AccountId` (Salesforce convention). The mappings differ; embedding them on the Stream is the right scope.

The cost is that two Streams of the same ResourceType in the same customer's setup may carry duplicate mappings if the column names happen to match. This is an acceptable cost — the duplication is local, and hand-editing two Streams to apply the same change is workable for the configuration scale at hand.

## Summary

Per-Stream AttributeMappings, four kinds, two-pass execution, optional field-level transformers, primary-flag identifying the external-id source. Sensitive keys masked before persistence. For normalized Sources, a hardcoded denormalization JOIN at the Transformer Consumer enriches User-bearing resources with the embedded user (and sometimes parent) records the API expects. Variables helper exposes Job timestamps timezone-aware. The whole shape is data, not code — except for the transformer set itself, which is a fixed library to keep configuration from causing crashes.
