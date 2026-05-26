# The unified integration pipeline

A single integrator run is one **Job**, executed in three sequential stages — Extract, Transform, Load — across a fixed sequence of resources. There is one pipeline. Whatever differences exist between a normalized customer and a custom-shaped customer are absorbed at the per-stream level (different query templates, different mappings); the orchestration is identical.

## One Job per run

Every integration run produces exactly one `Job` document in MongoDB. The Job is the spine of the audit trail — every Resource, Import, and Request created during the run carries a `job_id` back-reference. This makes "what happened in the run that started at 2 AM yesterday" a one-step lookup, regardless of which Resource or Stream the question is about.

The Job tracks the timestamps of each stage transition (`starts_at`, `fetch_ends_at`, `transformation_ends_at`, `ends_at`), the platform's version (`application_version`), the customer database's version (`database_version`, when applicable), the integration schema version (`integration_version`), running counts of HTTP requests (`successful_requests_quantity`, `failed_requests_quantity`, `total_requests_quantity`), and the configuration shape it ran against (`total_sources`, `total_streams`).

A second Job cannot start while the first is open. The integrator enforces this via a Redis lock acquired at the entrypoint; if the lock is held, the new run is rejected silently (no error, no retry — the next scheduled tick will succeed). This means the schedule cadence is effectively "at most one job at a time"; cron triggers that arrive while a job is running drop on the floor. The trade-off is intentional: a backed-up integrator has work to do, not work to multiply.

## The entrypoint: `Job::Starter`

A run begins with `Job::Starter`, a Sidekiq worker the cron schedule kicks off. Its responsibilities are narrow and ordered:

1. **Acquire the integrator lock.** Holds `Lock.acquire('integrator')` via Redis. If acquisition fails (another job is running), `Job::Starter` simply returns. The lock is released in the worker's `ensure` block at the end of the run.
2. **Validate that there are streams to run.** If no `Stream` documents exist at all, emits `MissingStreamsReport::Producer` (a sign the customer was never bootstrapped). If Streams exist but none are enabled, emits `InactiveStreamsReport::Producer` (a sign someone disabled the integration but did not document why). Either case ends the run.
3. **Compute the fetch window.** The Job pulls data updated since the last successful Job's `ends_at` minus a configurable overlap (`ApplicationConfiguration.fetch_days`); on a first run, falls back to `ApplicationConfiguration.initial_fetch_date`. The overlap intentionally re-fetches a small period that the previous run already covered, defending against rows that were committed in the source after the previous run's cutoff but with a timestamp slightly before the cutoff.
4. **Create the Job** with `starts_at` set to the current time.
5. **Materialize pre-flight checks.** One `SourceCheck` per Source that has at least one enabled stream; one `StreamCheck` per enabled Stream. These start in a `pending` state — Chapter 11 covers how they are filled in.
6. **Probe the database version**, when there is a normalized Source. Calls `database_version` on the cached adapter, which forces a real round-trip and stamps the answer onto the Job. This is also the wake-up trigger for hosting providers that auto-pause idle databases (Azure SQL serverless).
7. **Hand off to `HealthCheck::Producer`** to begin the pre-flight stage. Everything that follows runs as separate Sidekiq jobs.

## The three stages

After pre-flight passes, the Job proceeds through the three stages in order.

### Extract

The integrator pulls data from each enabled Stream's Source. For Database Sources, this is a sequence of paginated SELECT queries against the customer's database (rendered from the Stream's Liquid `query_template`). For API Sources, this is a sequence of authenticated HTTP requests against the customer's API endpoint. The raw output of each page is persisted as a per-Stream `<Resource>Collection` document in MongoDB — file-attached for size (the JSON payload is on disk via CarrierWave, not inline in MongoDB).

A Stream proceeds only if its `ready_for?(job)` check passes. That check requires both the Stream's `StreamCheck` and the Source's `SourceCheck` to be successful for this Job. A degraded Source (auth broken, network unreachable) blocks every Stream attached to it but does not block other Sources' Streams. A degraded Stream (the referenced table doesn't exist) blocks only itself.

Extract is the **only** stage that touches the customer's source. Once the Collections are written to MongoDB, the customer's source is no longer in the loop — Transform and Load operate purely on data already pulled.

`Job#fetch_ends_at` is set when every Resource in the sequence has finished extracting (or has been skipped because its Streams aren't ready).

### Transform

The integrator reshapes the extracted data into the JSON bodies the 4Shark API expects. For each Stream, the per-Stream `attribute_mappings` are applied to each row of the corresponding Collection: simple mappings (column → field) first, compound mappings (formula or template, possibly referencing earlier results) second. The output is stored as an `Import` document, embedded under the Resource the row identifies.

Most resources also carry a denormalization step in this stage when the Source is normalized — the Transformer reaches back into the customer's database to JOIN against `users` (and sometimes `parents`) to enrich the import body. Chapter 8 covers why and how.

Transform is the only stage that re-touches the customer's source after Extract — and only for normalized Sources, only for the JOIN denormalization. Custom-shaped Sources are responsible for producing fully-shaped data in Extract.

`Job#transformation_ends_at` is set when every Resource has finished transforming.

### Load

The integrator pushes the transformed Imports through the 4Shark API. Each push is a single HTTP request (POST/PUT/PATCH/DELETE depending on the resource and the operation), with the request body, response status, and response body persisted as an embedded `Request` document under the Import. This is the audit trail: every API call the integrator ever made is durable in MongoDB.

The API's response decides the outcome — a 2xx transitions the Resource into `integrated`; a 4xx records the failure but does not retry (the data is wrong, retrying won't help); a 5xx triggers a retry policy (the API is having a bad moment). Chapter 13 covers the Resource state machine.

`Job#ends_at` is set when every Resource has finished loading.

## No central coordinator

The pipeline does **not** have a top-level orchestrator that loops over the resource sequence. Instead, each per-resource worker chains directly to the next:

- `Subsidiary::TransformerProducer` — when done, calls `Hierarchy::TransformerProducer.perform_async`
- `Hierarchy::TransformerProducer` — when done, calls `User::Admin::TransformerProducer.perform_async`
- ... and so on, through the 25-stream sequence
- The final resource's loader, `Goal::LoaderConsumer`, calls `Job::Finisher.perform_async` to close the run

This pattern has trade-offs. The win is operational simplicity: every advance is a Sidekiq job, observable in the queue, retryable independently, parallelizable when a stage fans out across Streams. The cost is that the resource sequence is encoded by reference across 75 worker classes (3 per resource × 25 resources) — adding a new resource to the middle of the sequence means editing the previous resource's "next" reference and the new resource's "next" reference, with no single place to read the order from. The sequence is a property of the codebase that is documented in `CLAUDE.md` (the `Stream Order` section) and tested in integration specs but has no runtime representation as a list.

The 4Shark Data Processing Pattern lives in this seam: each Producer plucks IDs (never loaded objects) and bulk-pushes them to Consumers, each Consumer processes one ID, fans out per-resource transparently, and the next resource's Producer fires only when the current resource's `Computation.done?` returns true. Chapter 10 covers the Computation primitive that gates the per-stage advance.

## The closing worker: `Job::Finisher`

`Job::Finisher` is small. It calls `Job#finish` (which sets `ends_at` and computes derived totals), then triggers `IntegrationReport::Producer` to assemble the customer-facing email summary of the run. The email lists what was integrated, what failed, with errors aggregated per resource type and per error reason, plus an attached XLSX with one row per failed import.

The report is the customer's primary signal that an integration ran. There is no dashboard for the customer to monitor runs in real time — they receive the report after each run and trust that "no report" means "the integrator hasn't run yet today" and "report with X failures" is what they need to follow up on internally.

## Why one pipeline, not two

The integrator used to carry two pipelines side by side — a "managed" flow for normalized 4Shark-bootstrapped customers and a "self-service" flow for custom-shaped customers — branched at runtime by an `ApplicationConfiguration.managed_integration?` flag. PR #2120 collapsed them into a single flow parameterized by the Stream configuration: every customer, regardless of source shape, runs the same set of workers, and what differs is the Stream's `query_template`, `attribute_mappings`, and Source type. PR #2174 then completed the consolidation by deleting the orphaned legacy worker chain that survived from the pre-merge state.

There is no "managed mode" anymore. A customer with a normalized Source happens to use the schema 4Shark's bootstrap script generates; a customer with a custom Source has the same set of Streams pointing at their own SQL or API. The pipeline cannot tell them apart at the orchestration level — only the per-Stream behavior differs, which is exactly the level where customer-specific configuration belongs.

## Summary

One Job, three stages, fixed resource sequence, no top-level coordinator, audit trail in MongoDB, customer-facing email at the end. The shape is the same for every customer; the configuration is per-Stream. The next chapter walks through that fixed resource sequence and why the order is what it is.
