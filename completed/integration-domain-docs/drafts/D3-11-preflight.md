# Pre-flight: SourceCheck, StreamCheck, AvailabilityCheck

Before any data extraction begins, the integrator runs a pre-flight stage that verifies the customer's source is reachable, the credentials work, the integrator's account has the right permissions, and each Stream's referenced object actually exists. The pre-flight stage exists because the customer's source is the most fragile part of the pipeline — the integrator owns everything past the source boundary, and a misconfigured Source or a broken credential cannot be papered over by retry policies. Surfacing the failure early, with a precise reason, is what lets the operator fix it.

The pre-flight has two layers: per-Source checks (`SourceCheck`) and per-Stream checks (`StreamCheck`). They run concurrently across all Sources/Streams and gate the rest of the pipeline at the per-Stream granularity (`Stream#ready_for?(job)`).

## Two layers, two scopes

A `SourceCheck` answers "can the integrator talk to this Source as a whole?". A `StreamCheck` answers "can the integrator read this specific Stream's data?". Both states are recorded per-Job; a check that passed yesterday does not exempt today's run from re-checking.

- **SourceCheck** — `belongs_to :job, :source`. One per Source-with-enabled-streams per Job. Tracks two independent dimensions:
  - **`reachability`** — can the integrator open a network connection to the Source's host? Network state, firewall state, VPN state, DNS state.
  - **`authentication`** — can the integrator log in with the configured credentials? Credential validity, token expiration, certificate validity.

  Both default to `pending`, transition to `passed`, `failed`, or `skipped`. A SourceCheck is `successful?` only when **both** dimensions are `passed` — a reachable Source with bad credentials is not usable; an authenticated Source on an unreachable host is not usable. The check also carries a `failure` enum (`missing_permissions`, `open_transactions`, `connection_error`, `authentication_error`) and a free-form `detail` string for human-readable diagnostic context.

- **StreamCheck** — `belongs_to :job, :stream`. One per enabled Stream per Job. Tracks one dimension:
  - **`accessibility`** — can the integrator read from the Stream's referenced object (the table, the API endpoint)? Defaults to `pending`, transitions to `passed`/`failed`/`skipped`.

  StreamChecks are `successful?` when `accessibility` is `passed`. They share the four-state pattern with SourceCheck for consistency, even though only one dimension is meaningful at the Stream level.

## Why the split

Splitting reachability from authentication, and Source-level from Stream-level, lets the pipeline give precise diagnostics:

- **A reachability failure** (network unreachable, VPN down) blocks every Stream attached to the Source, with a single root cause to investigate. Streams from other Sources are not affected.
- **An authentication failure** (credentials expired) is also Source-wide but distinct from a network outage — the operator's response is different (rotate credentials, not restart networking).
- **A permissions failure** (the integrator's account exists but cannot read this specific table) is Stream-level — the rest of the Source's Streams may work fine. This kind of partial failure is common when the customer's DBA grants per-table permissions and forgets one of them; the integrator must keep the rest of the integration running while flagging the specific gap.
- **A missing-object failure** (the Stream's table no longer exists, or the API endpoint was renamed) is also Stream-level. Same shape: the Source is fine, this one Stream is broken.

The 4-state granularity (`pending`/`passed`/`failed`/`skipped`) plus the FAILURES enum gives the customer-facing report enough detail to say "Source X authenticated but Stream Y is missing permissions on the `commissions` table" — which is what the customer's MIS team needs to act on.

## How the checks run

Three worker chains fill in the checks during the pre-flight stage:

### `HealthCheck::Producer/Consumer`

Verifies **reachability** at the Source level. For each Source with at least one enabled Stream, the Producer pushes a HealthCheck::Consumer that opens a connection to the Source (database connection, HTTP HEAD/probe request) and reports back. The result lands on the SourceCheck's `reachability` field.

For DatabaseSources, "open a connection" is `source.connect!` — which, for normalized Sources with `warm_up: true`, may have already been done by the `DatabaseWarmer` chain ahead of `Job::Starter`. The HealthCheck step is idempotent on the cached adapter; calling `connect!` again just returns the cached instance.

For ApiSources, "open a connection" is a probe request against the API's authenticated endpoint. The probe is configured per Source (or defaults to a known-good endpoint).

A `HealthCheck::Finalizer` runs at the end of the chain to flip the SourceCheck states to terminal values (any still in `pending` becomes `failed` because the Consumer never reported back).

### `Authorization::Producer/Consumer`

Verifies **authentication** at the Source level. Splits by source type — `Authorization::DatabaseConsumer` for DB Sources (run a tiny SELECT to verify the credentials work and the user has at least baseline read access), `Authorization::ApiConsumer` for API Sources (refresh the token / make an authenticated request). The result lands on the SourceCheck's `authentication` field.

The Authorization stage runs **after** HealthCheck — there is no point checking credentials on an unreachable host. A SourceCheck with `reachability=failed` has its Authorization stage skipped (sets `authentication=skipped` rather than running and failing for a different reason).

A `Authorization::Finalizer` finalizes the per-Source state, flipping any still-pending or skipped to terminal.

### `AvailabilityCheck::Producer/DatabaseConsumer/ApiConsumer`

Verifies **accessibility** at the Stream level. For each enabled Stream whose Source has both `reachability=passed` and `authentication=passed`, dispatches a Consumer that runs the Stream's `availability_probe` — a tiny query that exercises the Stream's referenced object without pulling data. For DB Streams, typically `SELECT 1 FROM <table> WHERE 1 = 0`; for API Streams, a no-data variation of the endpoint.

The probe verifies:
- The referenced table or endpoint exists (no "object not found" error)
- The integrator account has read permission on it
- The schema/shape is at least syntactically what the Stream expects (a column the query references is there)

If the probe succeeds, the StreamCheck's `accessibility` becomes `passed`. If it fails, `failed` — and the failure typically carries diagnostic detail in the SourceCheck's `failure` enum (`missing_permissions` is the common case) along with the error message.

Streams whose Source's SourceCheck is unsuccessful skip the AvailabilityCheck entirely — `accessibility=skipped`. There is no point probing a Stream when the path to its Source is already broken.

## The gating rule: `Stream#ready_for?(job)`

After all three pre-flight chains finish, every Stream has both a SourceCheck (via its Source) and a StreamCheck. The gate the rest of the pipeline consults is:

```ruby
def ready_for?(job)
  check_for(job).successful? && source.check_for(job).successful?
end
```

A Stream proceeds only if **both** its own StreamCheck **and** its Source's SourceCheck are `successful?`. Either failure blocks the Stream.

The per-Resource Extractor Producers filter `streams.enabled` by `ready_for?(job)` before fanning out:

```ruby
stream_ids =
  ResourceType.find_by(name: 'Manager').streams.enabled.pluck(:id).select do |stream_id|
    Stream.find(stream_id).ready_for?(job)
  end
```

A Stream that fails pre-flight is **not** dispatched to the Extractor; the rest of the ResourceType's Streams (that did pass) proceed normally. The Computation queue counts only the ready Streams; the Job's accounting reflects what actually ran, not what was configured.

## What happens to the failed Streams

A failed pre-flight is not silent. The SourceCheck and StreamCheck states are persisted on the Job; the customer-facing report email lists every failed pre-flight with its reason, alongside the per-Stream extraction failures. The failed Streams contribute to the report even though no rows were extracted from them.

Specific report producers exist for the common failure shapes:

- **`SourceCheckReport::Producer`** — surfaces SourceCheck failures (unauthenticated Sources, unreachable Sources)
- **`MissingPermissionReport::Producer`** — surfaces the `missing_permissions` failure specifically
- **`UnreachableHostReport::Producer`** — surfaces network-level failures
- **`OpenTransactionsReport::Producer`** — flags Sources with long-running transactions that prevent extraction (a real failure mode for some customers' SQL Server setups)
- **`DatabaseConnectionReport::Producer`** — surfaces low-level DB connection errors that don't fit cleanly into the others

The proliferation of report producers reflects the operational reality: each failure shape has different audiences (DB admin, network admin, application owner) and different urgency. Bundling them into a single "pre-flight failed" report would lose the distinction.

## When pre-flight passes

If every SourceCheck and every StreamCheck is `successful?`, the chain advances to the first Extractor Producer (`Subsidiary::ExtractorProducer`). The pre-flight stage's pass-through is silent — the customer-facing email at the end of the run shows "all Sources reachable, all Streams accessible" without elaboration.

A common operational observation: the pre-flight typically passes for an established customer (the MIS team's setup is stable) and typically uncovers something for a new customer's first runs (one column in one table doesn't match the expected name, one credential is for the wrong environment, one endpoint requires a header the Source doesn't carry). The pre-flight is most valuable during onboarding; once the integration stabilizes, it becomes background insurance.

## Why pre-flight runs every Job

The checks repeat on every Job — they are not cached across runs. Reasons:

- **Credentials rotate.** Customers with strong policies rotate database credentials weekly or monthly. Yesterday's `passed` status on authentication does not mean today's authentication works. Re-checking is the only safe answer.
- **Permissions change.** A DBA grants new permissions for a different team and inadvertently revokes the integrator's existing ones. The pre-flight catches it on the first run after the change.
- **Schemas drift.** Customers add and rename columns. A column the Stream references can disappear between runs. The AvailabilityCheck's probe catches this when it executes the configured query shape.

The cost of re-checking every Job is small — the probes are tiny, the chain runs in parallel, and the whole pre-flight finishes in seconds for a typical customer.

## Why two layers instead of one big check

A simpler pre-flight could collapse into one check per Source ("is this whole Source operational?"). The integrator does not do this because the failure modes do not collapse cleanly:

- A Source with one bad table is still 80% operational. Blocking the entire Source would block 14 healthy Streams to surface one broken one.
- A bad credential blocks every Stream at once. Pretending the failure is per-Stream would emit 14 identical failure reports for one root cause.

The two-layer split matches the failure shapes. SourceCheck blocks all when it fails (a single root cause); StreamCheck blocks only its own Stream (per-table issues). The customer's report reflects the true topology of the failure, not an artificial granularity.

## Summary

Pre-flight is a two-layer check (Source-level reachability/authentication, Stream-level accessibility) materialized as MongoDB documents at Job start, populated by three worker chains (HealthCheck, Authorization, AvailabilityCheck), and consulted by `Stream#ready_for?(job)` to gate the per-Stream extraction. Every Job runs the full pre-flight; failures are persisted, reported per category, and prevent only the affected Streams from advancing. The split between the two layers is what makes partial-degradation handling tractable — a customer with one broken Stream still gets the rest of their data.
