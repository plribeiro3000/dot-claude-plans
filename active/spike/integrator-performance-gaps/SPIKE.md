# SPIKE — Integrator performance gaps (develop, 3 tasks × 10 threads)

## Question

Where is the integrator saturated, and what closes each saturation — of infra and of code — in the develop version, given the target shape of 3 worker tasks × 10 threads? The bar is the one the thread-tuning already set: not "add hardware", but "find the place that is provably at its ceiling and fix that area". Redis response time and instance sizing, the job flow, wasted time, and rework are explicit sub-questions.

## Method

Read against the `develop` branch of `integrator` and the live `atento-co-staging` infrastructure (sa-east-1). The run this analysis anchors on is Run 3 in `../integrator-co-staging-thread-tuning/ANALYSIS.md`: 10 threads × 3 worker tasks, 45 min 38 s total (processing 23 min 50 s, sending 20 min 31 s), 39,192 requests. The phase split from that run is the spine of every finding here — processing is CPU-pegged 99–100%, sending is I/O-bound at 20–70% CPU.

Code paths read in full: `Modifier::CustomCollectionConsumer`, `Modifier::EnricherProducer/Consumer`, `Modifier::LoaderProducer/Consumer`, `Resource` (`.get`, cold-storage restore), `Resource::Producer/Consumer`, `Variables`, `AttributeMapping`, `Computation`, `Counter`, `ApplicationLoader`, `ModifierLoader`, `Job`, plus the Sidekiq/Mongo/Redis initializers and `sidekiq.yml`. Infra pulled live: the worker task definition (rev 54), the ElastiCache node, and its CloudWatch metrics over the Run-3 window.

## The current shape (baseline facts)

**Worker task**: 512 CPU units (0.5 vCPU) / 2048 MB, `SIDEKIQ_THREADS=10`, command `bundle exec sidekiq`. Run 3 ran 3 of these tasks by hand (the service rests at `desired=0`). Aggregate during the run: 1.5 vCPU, 30 threads.

**Mongo (source of the integrator's own state)**: replica set on `t3.small`/`t3.micro` nodes (`integrator-atento-mongo004/005/006`). Mongoid pool is fixed at `max = min = generic_pool_size = max(puma_threads=3, sidekiq_threads=10) = 10` connections per task.

**Redis (Sidekiq queues + the `Computation` counters)**: ElastiCache `cache.t3.medium` (2 vCPU, ~3 GB, Redis 7.1.0), single node, replication group `integrator-atento-redis001`, shared across the Atento integrators by DB index (co-staging = db 7).

**The pipeline is a fan-out of one-job-per-record at every stage.** For the Modifier stream the record travels through three separate per-record passes over the ~39 k modifiers:

1. **Transform** — `Modifier::CustomCollectionConsumer`, one job per *collection* (~67 jobs), each looping its records. Writes one `Modifier` document per record. **This is the CPU-pegged processing phase.**
2. **Enrich** — `Modifier::EnricherConsumer`, one job per *modifier* (~39 k jobs), each re-loading the modifier and its stream, attaching the enrichment (`user`) object.
3. **Load** — `Modifier::LoaderConsumer`, one job per *modifier* (~39 k jobs), each doing one HTTP request to the app API. **This is the I/O-bound sending phase.**

Completion between stages is coordinated by `Computation` (atomic Redis `INCR`/`GET` on `queue:`/`executions:` keys), and each stage's producer paginates ids with `MONGO_PAGE_SIZE` (set to **50** on this stack) and `push_bulk`s the next stage.

---

## Findings

Ranked within the two saturated phases. Each names the evidence, why it is a gap, the fix, and the expected effect. Effort/risk is called out where it is not trivial.

### Phase A — Processing (CPU pegged 99–100%): the real ceiling

This is the phase the thread reduction already helped (per-job 15.5 → 4.9 min, the GIL-oversubscription relief). It is still where the machine is at its limit, so every CPU cycle removed here converts directly to wall-clock. Three of the four gaps below are wasted CPU inside the hot loop; the fourth is wasted I/O on a clean run.

#### A1 — `Variables#to_h` is rebuilt for every record × every compound mapping (should be once per collection)

`app/workers/modifier/custom_collection_consumer.rb:35` calls `attribute_mapping.compound(attributes.merge(variables.to_h))` inside the per-record loop. `Variables#to_h` (`app/models/variables.rb:12`) builds a ~40-key hash, and every value is an ActiveSupport date computation (`beginning_of_month`, `last_month.beginning_of_year`, `end_of_year`, …). None of those keys depends on the record — they derive only from `job.fetch_since`, `job.starts_at`, and constructor arguments that are all `nil` here. So the same ~40 date operations are recomputed once per compound mapping per record. For a collection of R records with C compound mappings that is `R × C` rebuilds of a constant hash.

**Fix**: compute `variables_hash = variables.to_h` once before `records.each`, reuse it in the loop. Referentially transparent for the whole collection, so it is a plain hoist.

**Effect**: removes a large, fixed slice of the per-record CPU in the exact phase that is pegged. High impact, trivial change, no behavior change.

#### A2 — Attribute mappings are converted to ids then re-`find`-ed per record (and it defeats the mapping's own memoization)

`custom_collection_consumer.rb:12-13` plucks the simple and compound mapping **ids**; then `:27-28` and `:33-34` re-fetch each mapping with `stream.attribute_mappings.find(id)` **inside** the record loop. `AttributeMapping` is `embedded_in :stream` (`app/models/attribute_mapping.rb:10`), so `attribute_mappings` is an in-memory array and `.find(id)` is an O(M) linear scan of it — run `R × M` times. The objects were already in hand before they were turned into ids.

The second cost is worse than the scan: `AttributeMapping#compound` memoizes the parsed Liquid template (`@template ||= Liquid::Template.parse(source)`, `:94`) and the transformer instance (`:86`) on the mapping object. Re-`find`-ing the mapping per record hands back a fresh object each time, so those memoizations never survive — the Liquid template is re-parsed and the transformer re-instantiated once per record.

**Fix**: load the two mapping sets once as objects before the loop (`simple_mappings = stream.attribute_mappings.select(&:simple-kind)` / the compound equivalent) and iterate the objects. This deletes the per-record scans *and* makes the template/transformer memoization effective (parse once per mapping, not once per record).

**Effect**: compounding CPU win in the pegged phase — removes the scans and the repeated Liquid parsing together. High impact, low effort.

#### A3 — Each modifier is re-loaded from Mongo in every phase; the stream is re-loaded per modifier in enrichment

`Modifier.find(resource_id)` runs once per modifier in enrichment (`enricher_consumer.rb:9`) and again once per modifier in load (`loader_consumer.rb:9`) — two full fetches of a document whose embedded `imports`/`requests` arrays grow as the run proceeds. Enrichment additionally does `import.stream.downstreams…` (`enricher_consumer.rb:13`), loading the `Stream` (with its embedded attribute mappings and downstreams) once per modifier — ~39 k Stream loads for a handful of distinct streams. BSON→Mongoid instantiation is CPU, and this phase is CPU-bound, so the repeated deserialization is part of the ceiling, not just Mongo I/O. (By contrast `Job.find` per job is cheap — `Job` is a lean, reference-only document — so it is *not* on this list.)

**Fix (low-risk half)**: in `EnricherConsumer`, resolve the downstreams from the stream once per *batch* rather than per record — the producer already groups ids by stream implicitly (a collection is single-stream). Passing the stream/downstream set down, or memoizing per-stream within the process, removes ~39 k Stream loads. **Fix (larger half, note only)**: the three per-record passes could be collapsed so a modifier is loaded once and transformed→enriched→sent without a full re-fetch between stages; that is a topology change and belongs in its own analysis, not a quick win.

**Effect**: medium-high, and the Stream-reload half is cheap. The full collapse is larger and riskier — flagged, not recommended yet.

#### A4 — On a clean run, every new modifier triggers an S3 cold-storage restore that is guaranteed to 404

`custom_collection_consumer.rb:39` calls `Modifier.get(external_id)`. `Resource.get` (`app/models/resource.rb:70`) does `find_by(external_id:)`; on miss, because `AWS_BUCKET` is set (`4shark-integrator-atento-co-staging`, confirmed on the task def), it calls `restore_from_s3`, which does an S3 `GET` that returns `Excon::Error::NotFound`, and only then `create!`s the stub. On a wiped-base run like Run 3 **every** modifier is new, so this path fires ~39 k times: a failed `find_by`, an S3 GET that 404s, then a create. The S3 round-trip per new record is pure rework on a first/clean integration.

**Fix**: skip the S3 restore attempt when the run is known to be a first load (a flag on the job, or gating `restore_from_s3` on "cold storage has run for this deployment"). Cold-storage restore only makes sense once records have actually been archived to S3.

**Effect**: removes ~39 k pointless S3 GETs from the processing phase on every clean/first run (production go-lives are exactly clean runs). Medium impact, easy to gate. Verify the magnitude against the New Relic trace for `Modifier::CustomCollectionConsumer` before/after — the S3 calls are overlapped by threads, so the wall-clock share is a measurement, not an assumption.

### Phase B — Sending (I/O-bound, CPU 20–70%): saturated on connection-wait, not CPU

Sending gained only ~1.8× in Run 3 while processing gained ~3× (`ANALYSIS.md`), because this phase waits on the network, not the CPU — adding vCPU does little here. The ceiling is how fast each thread can complete an HTTP request, and the dominant cost is connection setup.

#### B1 — `HTTParty.post` opens a new TCP + TLS connection for every request (no keep-alive)

`ModifierLoader#create` (`app/loaders/modifier_loader.rb:8`) calls the class method `HTTParty.post(indicator_endpoint, …)`. The class-method form holds no connection — each of the ~39 k sends does a fresh TCP handshake **and** a full TLS handshake (the endpoint is `https://…/api/v3/indicators`) before the request byte is sent. TLS setup is 1–2 extra round trips per request; at any realistic RTT that is tens of milliseconds per send, paid 39 k times, and it lands squarely in the phase that is already thread-wait-bound.

**Fix**: send over a persistent connection with keep-alive — a per-thread/per-worker `Net::HTTP::Persistent` (or a Faraday connection with the persistent adapter, or HTTParty on a persistent backend) reused across requests to the same host. Connections are per-thread (thread-safety), so the pool is naturally bounded by the Sidekiq concurrency.

**Effect**: this is the single biggest sending-phase lever, and it is code, not hardware — it removes the handshake from ~39 k requests. Medium effort (a shared HTTP-connection object, plus care around thread-safety and error/reset handling). Confirm the current per-request cost from the New Relic `Custom/ModifierLoader/create` trace, which is already instrumented (`modifier_loader.rb:13`).

#### B2 — `Account.primary` is queried from Mongo on every request

`ApplicationLoader#initialize` (`app/loaders/application_loader.rb:12`) sets `@account = Account.primary` for every `ModifierLoader`, i.e. one Mongo query per send (~39 k). The account is effectively static config for the run (it carries `api_endpoint` and `api_headers`).

**Fix**: resolve the account once per process/run and reuse it (memoize on the class, or pass it in). 

**Effect**: removes ~39 k Mongo reads from the send phase. Low-medium; easy.

#### B3 — One HTTP request per modifier (batching is a larger, app-side option)

Every modifier is its own POST. If the app's `/api/v3/indicators` endpoint could accept a batch body, the send phase would collapse from ~39 k requests to ~39 k/batch — the largest possible reduction in this phase. This is a cross-service contract change (integrator + app API), so it is out of scope for a quick win and listed as the strategic option once B1/B2 are in and re-measured.

### Not a lever: Redis (evidence-backed)

The engineer asked specifically whether Redis response time is a problem and whether a bigger Redis instance would help. **It is not, and it would not.** Over the Run-3 window (2026-09-17 01:44–02:30 UTC = 22:44–23:30 −03:00), the ElastiCache node reported:

- **EngineCPUUtilization** (the Redis single-thread engine — the true saturation signal): average ~1%, **maximum 5.76%**.
- **CPUUtilization** (whole host): average 3.0%, maximum 7.6%.
- **CurrConnections**: 40–75 (peak 75 during processing, when 3 worker tasks × their Sidekiq/Mongo-adjacent pools were live). A `cache.t3.medium` supports tens of thousands of connections.

Redis is ~95% idle for the whole run. The `Computation`/`Counter` operations are `INCR`/`GET`/`SET` on tiny integer keys — microsecond work for Redis; their cost is network round-trip, not Redis processing, and the worker sits in the same region/VPC (sub-millisecond RTT). A larger node changes none of that — it has the same single engine thread and the same network path. **Recommendation: do not resize Redis.** If anything is ever worth trimming, it is the *number* of Redis round-trips per job (each consumer does `increment_executions` + `done?`), but at this utilization it buys nothing and should not be touched now.

### Infra sizing: 0.5 vCPU is deliberate; re-measure after the code gaps

The 0.5-vCPU task is small on purpose, and the horizontal-scale-out (3 tasks) is what carried Run 3. Raising per-task vCPU is a real lever for the CPU-bound processing phase, but the point of this spike is to exhaust the code gaps first — A1/A2 alone remove CPU from the pegged phase, which is worth more per dollar than a bigger task, and they make any later sizing decision cleaner. The sending phase is I/O-bound, so vCPU does little there regardless (B1 is its lever). **Hold instance sizing until A1–A4 and B1–B2 are in and the run is re-measured.**

---

## Recommended sequence

Order is by impact-per-effort, and it deliberately front-loads the pegged phase:

1. **A1** (hoist `variables.to_h`) and **A2** (load mappings as objects) — trivial/low effort, directly cut the CPU ceiling, no behavior change.
2. **B2** (cache `Account.primary`) and **A4** (gate the S3 restore on first run) — easy, remove clear rework.
3. **B1** (persistent HTTP connection) — medium effort, the biggest sending-phase win.
4. **A3 Stream-reload half** — medium, cheap once scoped per stream.
5. Re-measure a full run. Only then decide on **instance sizing**, the **A3 topology collapse**, or **B3 batch API** — each is a larger change whose value is only legible against the post-fix baseline.

## How to verify (before and after)

New Relic is instrumented on this deployment (`NEW_RELIC_APP_NAME=Integrator Atento CO (Staging)`), with custom tracers already on `ModifierLoader#create/#update/#delete` and `Computation#done?`. The transaction breakdown for `Modifier::CustomCollectionConsumer` (processing) and `Modifier::LoaderConsumer` (sending) is the direct measurement for A1/A2/A4 (self-time in the transform vs. the S3 segment) and B1/B2 (HTTP segment vs. Mongo segment per send). The clean before/after is a matched run at the same shape; the isolated per-job metric in `ANALYSIS.md` is the template for reading the processing win without the task-count effect confounding it.

## Open questions

- The exact wall-clock share of the A4 S3 restore in the CPU-pegged phase — the S3 GETs are overlapped by threads, so the share must be read from the trace, not assumed.
- Whether the app `/api/v3/indicators` endpoint can accept a batch body (decides whether B3 is ever viable).
- Whether the `api_loader_producer` queue weight (10) vs `api_loader_consumer` (1) in `sidekiq.yml` skews thread selection toward the fast producers during the send phase — worth confirming against a live queue-latency read, though the producers are few and drain fast, so it is likely second-order.
