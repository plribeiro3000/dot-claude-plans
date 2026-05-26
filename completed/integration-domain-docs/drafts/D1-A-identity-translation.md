# Identity translation pattern

Every API call from the client into 4Shark refers to entities by the client's own identifier — never by a 4Shark-assigned ID. The 4Shark internal database ID is opaque and never appears in payloads in either direction. The platform translates client-side identifiers into internal IDs at the controller boundary and translates them back when serializing responses.

## The rule

Every model the client can create or affect carries an `external_id` (or, in the User case, a `value` on a separate `UserIdentifier` row). The client supplies this value in every payload that references the resource:

- `Deal` payload: `client_id: "CLI-001"` (the Client's `external_id`), `product_id: "P-42"` (the Product's `external_id`), `user_id: "EMP-9991"` (the value of one of the User's identifiers)
- `Goal` payload: `variable: "sales_target"` (the Variable's `key`), `group_id: "GRP-NORTH"` (the Group's `external_id`)

The server resolves each one to its internal ID before persisting anything. If any client-supplied ID does not exist on the server, the call fails with a 404 or a validation error pointing at the offending field.

## Why

This is a deliberate platform choice and a real differentiator. The client's source systems already have stable identifiers for everything (employee codes, product SKUs, customer numbers); forcing the client to also store and maintain a 4Shark ID would create a mapping layer on every system that integrates with us. By accepting the client's identifiers verbatim, the integration surface stays narrow: the client sends what it already knows, and the platform adapts.

The cost is borne entirely by 4Shark — we maintain the mapping, we carry the lookup overhead on every call, and our database has dual identity (internal numeric ID + external string ID with a unique-per-company constraint). The client never knows the cost exists.

## Why the customer can't take on this work themselves

The customer's source data does not have a single stable column to act as a unique identifier. When such a column exists, it is usually a composite of 2 or 3 columns (e.g., subsidiary code + employee number + register type). Customers also typically purge or wipe their data after some period — driven by their own retention policies or legal obligations — which means a customer-side mapping table would lose entries the platform still needs.

The platform takes on the work because it has to. The mapping must:

- Translate the customer's column combination into a unique internal ID
- Resolve that ID through a lookup that is fast enough to run on every request
- Survive long enough for queries about historical data the customer might still ask about

## How the translation is implemented

The translation is two-tier: Redis as the primary store, PostgreSQL as the fallback.

For every resource the customer integrates, the model defines a `cache_id` class method that produces a unique string from the customer's identifying columns. Example for Indicator (which uses a composite identity rather than an `external_id`):

```ruby
class Indicator < ApplicationRecord
  cache_ttl 35.days

  def self.cache_id(attributes)
    "indicators.cid.#{attributes['company_id']}.vid.#{attributes['variable_id']}.uid.#{attributes['user_id']}.date.#{compiled_at}"
  end
end
```

The string is the cache key; the value stored at that key is the resource's primary key in PostgreSQL. The `cache_ttl` declaration sets how long the entry survives in Redis — varying per resource based on how often it is touched.

When a request needs to translate from customer-supplied identifiers to internal ID, `ApplicationRecord.get_id` runs:

```ruby
def self.get_id(arguments)
  cache_id = cache_id(arguments)
  Rails.cache.read(cache_id) || find_by!(arguments).id
end
```

Redis lookup first (~300 microseconds typical). If the key is missing or evicted, fall through to PostgreSQL (5–10 milliseconds typical). The same shape backs `get` (which returns the full record).

### Cache invalidation

Cache entries change when the underlying data changes. ApplicationRecord callbacks keep the cache consistent:

```ruby
after_create   :cache_external_id
around_update  :update_external_id_cache
after_destroy  :delete_external_id_cache
before_save    :delete_external_id_cache
```

`update_external_id_cache` deletes the old key, runs the update (which may change the columns the cache_id is built from), and writes the new key. `before_save :delete_external_id_cache` covers the case where attribute changes mean the new key differs from the old one — the old entry is invalidated before the new one is written.

### Why Redis and not just PostgreSQL

A cold lookup on PostgreSQL takes ~10ms; a Redis lookup ~0.3ms. Across the volume the platform sees during heavy integration windows (thousands of writes per minute, each requiring N foreign-key resolutions), the difference compounds into seconds of wall-clock time per request. Redis as the primary store keeps the API responsive under integration load.

The cost is memory: Redis holds all values in RAM, so the active mapping set is bounded. The TTL per resource (`cache_ttl`) is the tool for managing this — frequently-touched resources keep longer TTLs; one-shot resources keep shorter ones; the Postgres fallback covers anything Redis evicts.

## Exception 1 — User has many identifiers

The general rule of "one external_id per resource" does not hold for User. A user can have N `UserIdentifier` rows, each with a different `value`. One identifier is marked `primary: true` (enforced by a partial unique index); all others are secondary.

This exists because clients with multiple source systems have the same person registered with different IDs in each system. A call center with three CRMs (an internal one, plus contractually-mandated CRMs from clients A1 and A2) will have the same employee enrolled three times. Forcing the client to unify identifiers in the source data is not realistic — those source systems are external to the client too.

The recommended client behavior, encoded in the integrator's contract, is to **prefix each identifier with its origin** in the integration script: `intern-EMP-001`, `a1-EMP-001`, `a2-EMP-001`. The prefix is the client's namespace; the suffix is whatever the source system uses. The mapping is set up once when the user is registered (`identifiers_attributes` carries all known values on User create), and subsequent integration calls can use any of the values to identify the user — the lookup will resolve to the same User regardless of which identifier was supplied.

## Exception 2 — Indicator has no external_id

Many clients drive their Indicator data from spreadsheets. Spreadsheets do not have stable per-row identifiers — a row's position is not its identity, and the same business value re-emerges in different rows on different exports.

The platform refuses to ask the client for an `external_id` it cannot reliably produce. Instead, an Indicator's identity is composite: `(variable, user, compiled_at)`. If the same combination is sent twice, the second call updates the first row. This is reflected in the API contract by the singular `/api/v3/indicators` resource (no URL identifier — the identity is in the payload).

## Failure mode

When the client sends an unknown identifier, the lookup at the controller boundary returns `nil`. The `nil` propagates into the strong_params, where the model validation rejects it with a presence error. The client receives a 422 with the offending field — but the field name in the error refers to the internal column, not the payload key. A `user_id` in the payload becomes a `user_id` validation error after the identifier-to-User resolution; debugging requires understanding that the error refers to the resolved foreign key, not the original payload string.

The integrator's drift-detection logic relies on this: a mismatch between client truth and app state surfaces as a 422 from one of these lookups, not as silent acceptance.
