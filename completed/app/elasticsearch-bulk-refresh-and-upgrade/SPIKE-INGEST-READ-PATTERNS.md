# SPIKE — Ingest/Read Patterns: Reconciling Bulk Throughput with Immediate Read Visibility

## Investigation question

The `app` system uses a producer-consumer pipeline: during the nightly batch, ~2,000 commissions are processed in parallel. Each commission writes N bulk batches of ~2,000 deals to OpenSearch, then `Metric::Producer` immediately reads those docs back via search queries (`bool/must/range/match`) to compute aggregated metrics. The cluster is a 2× `t3.small.search` (2 vCPU, ~1 GB heap).

The architectural tension: `refresh_interval=1s` (current default) creates extreme merge pressure on the 2-vCPU node (documented in SPIKE.md, Findings 2 and 6). Increasing `refresh_interval` to 30s or disabling it (`-1`) fixes the merge pressure — but then `Metric::Producer.search` does not see the docs the Consumer just indexed, because search is a near-real-time operation (requires refresh). Forcing a per-commission refresh trades merge pressure relief for a different cost.

The engineer explicitly ruled out per-commission refresh and does not want to dismantle the producer-consumer pattern. The question: **how do practitioners reconcile high-throughput bulk ingest with immediate post-ingest reads, at what cost, and which options are viable here?**

This spike is a complement to `SPIKE.md` (which covers bulk internals, merge/thread-pool behavior, and capacity heuristics). It does not duplicate those findings.

---

## Sources consulted

- `https://www.elastic.co/guide/en/elasticsearch/reference/8.17/docs-get.html` — GET API realtime parameter default and behavior
- `https://www.elastic.co/guide/en/elasticsearch/reference/8.17/docs-multi-get.html` — mget API realtime parameter table with explicit default=true
- `https://www.elastic.co/guide/en/elasticsearch/guide/current/translog.html` — translog mechanism for real-time CRUD (GET/mget reads from translog before segment)
- `https://www.elastic.co/docs/reference/elasticsearch/rest-apis/refresh-parameter` — wait_for parameter, max_refresh_listeners, forced_refresh behavior
- `https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html` — refresh_interval=-1 + restore pattern; force_merge recommendation after bulk
- `https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-forcemerge.html` — force_merge cost, read-only restriction, blocking behavior
- `https://www.elastic.co/docs/manage-data/data-store/aliases` — atomic alias swap, downtime guarantees, is_write_index
- `https://bigdataboutique.com/blog/index-aliases-in-elasticsearch-and-opensearch-66636d` — staging index + alias promotion pattern
- `https://www.elastic.co/blog/changing-mapping-with-zero-downtime` — versioned index + atomic alias swap in production
- `https://www.elastic.co/blog/found-elasticsearch-from-the-bottom-up` — refresh_interval tuning during batch indexing
- `https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html` — AWS BP: t3.small warning, refresh_interval ≥30s recommendation (also cited in SPIKE.md)
- `https://medium.com/people-ai-engineering/maintaining-performance-during-bulk-indexing-in-elasticsearch-7aa839e6204d` — People.ai production case: nightly batch indexing problem and solution

---

## Findings

### Finding 1 — `GET /_doc/{id}` is documented as real-time by default: reads from the translog

The GET API returns a document without waiting for a refresh. The reference documentation states:

> "By default, the get API is realtime, and is not affected by the refresh rate of the index (when data will become visible for search)."

The `realtime` query parameter defaults to `true`. The guide documentation explains the mechanism:

> "When you try to retrieve, update, or delete a document by ID, it first checks the translog for any recent changes before trying to retrieve the document from the relevant segment. This means that it always has access to the latest known version of the document, in real-time."

The sequence is: translog lookup → if found, return immediately; if not (e.g., old doc already flushed to segment), read from segment. Either way the caller gets the current version without triggering a refresh.

**Caveats from the documentation:**
- If `stored_fields` are requested and the document has been updated but not yet refreshed, "the API will have to parse and analyze the source to extract the stored fields."
- Routing: "The document is not fetched if the correct routing is not specified." (if custom routing was used during indexing, the same routing value must be passed to GET)
- Setting `realtime=false` downgrades to near-real-time (segment-only, subject to refresh cycle)

**Source:** `https://www.elastic.co/guide/en/elasticsearch/reference/8.17/docs-get.html`
URL fetched / Verbatim quote checked: "By default, the get API is realtime, and is not affected by the refresh rate of the index (when data will become visible for search)." — confirmed present.
**Source (mechanism):** `https://www.elastic.co/guide/en/elasticsearch/guide/current/translog.html`
URL fetched / Verbatim quote checked: "When you try to retrieve, update, or delete a document by ID, it first checks the translog for any recent changes before trying to retrieve the document from the relevant segment." — confirmed present.
Quote substring confirmed at: translog page, paragraph on real-time CRUD.

---

### Finding 2 — `_mget` is also real-time by default: same translog-awareness as GET

The multi-get API (`_mget`) supports the same real-time read behavior as the single GET. From the 8.17 parameter table:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `realtime` | Boolean | `true` | "If `true`, the request is real-time as opposed to near-real-time." |

The default is explicitly `true`. This means an `_mget` call issued immediately after a `_bulk` call will return the freshly indexed documents — because the translog lookup path is the same as for single GET.

`_mget` accepts a list of `{_index, _id}` pairs and returns the corresponding documents in one HTTP round-trip — O(N) reads in 1 request, where N is the number of IDs.

**Caveat:** if routing was specified during indexing, the same `routing` value must be provided per item in the `_mget` body. The documentation states the `routing` parameter is "Custom value to route operations to specific shard."

**Source:** `https://www.elastic.co/guide/en/elasticsearch/reference/8.17/docs-multi-get.html`
URL fetched / Verbatim quote checked: parameter table row for `realtime`: "If `true`, the request is real-time as opposed to near-real-time." with Default = `true` — confirmed present.
Quote substring confirmed at: mget 8.17 query parameters table.

---

### Finding 3 — `Metric::Producer` conversion to `_mget`: technically viable when IDs are known, not viable for aggregations

The current `Metric::Producer` uses search queries with `bool/must/range/match` to aggregate over deals. These queries are near-real-time (they require a refresh to see new documents). Conversion to `_mget` is viable in exactly one scenario: when the set of document IDs to read is fully known at the time of reading, and the metrics can be computed from individual document fields.

**Where it is viable:**
- The Consumer has just indexed 2,000 deals in a bulk. It has all 2,000 deal IDs.
- If the `Metric::Producer` can compute its metrics by fetching and summing fields across those 2,000 docs (e.g., total deal value = sum of `deal.value` field), `_mget` returns all 2,000 docs in one real-time call — no refresh needed.
- Adapters like `Metric::TotalAdapter` (total of a field) and `Metric::QuantityAdapter` (count of records) are candidates for this conversion: both can be computed by iterating over the returned documents.

**Where it is not viable:**
- Queries that filter by fields not known at write time (e.g., `range` on a computed or updated field, `match` on a derived value).
- Queries that require aggregations across index-wide data beyond the just-indexed batch (e.g., "total deals for this user across all time" — requires searching the full index, not just the current batch).
- Any query that joins or cross-references documents from other indices or time windows.

The Elastic documentation does not discuss `_mget` as a replacement for search in producer-consumer pipelines. This is an architectural observation derived from Findings 1 and 2.

**Source (basis for viability):** Findings 1 and 2 (GET and mget real-time behavior).
Not found: no official Elastic or AWS documentation explicitly discusses mget as a read-after-write substitute for search in producer-consumer patterns. This finding is derived from the documented API behavior.

---

### Finding 4 — `refresh=wait_for` on bulk: works but risks hitting max_refresh_listeners under concurrent load

The Elastic reference for the `?refresh` parameter describes the `wait_for` value:

> "Wait for the changes made by the request to be made visible by a refresh before replying."

The documentation explains the difference from `refresh=true`:

> "The more changes being made to the index the more work `wait_for` saves compared to `true`."
> "`true` creates less efficient indexes constructs (tiny segments) that must later be merged into more efficient index constructs (larger segments)."
> "`refresh=wait_for` only affects the request that it is on, but, by forcing a refresh immediately, `refresh=true` will affect other ongoing request."

However, there is a ceiling:

> "If a `refresh=wait_for` request comes in when there are already `index.max_refresh_listeners` (defaults to 1000) requests waiting for a refresh on that shard then that request will behave just as though it had `refresh` set to `true` instead: it will force a refresh."
> "If a request forced a refresh because it ran out of listener slots then its response will contain `"forced_refresh": true`."

In the 4Shark scenario: ~2,000 commissions completing concurrently, each issuing a bulk with `refresh=wait_for` on the last batch. If more than 1,000 such requests arrive before the shard refreshes, they automatically escalate to `refresh=true`, which forces immediate refresh — creating exactly the segment-creation pressure the engineer wants to avoid. With `refresh_interval=30s` and high concurrency, this ceiling can be hit.

**Source:** `https://www.elastic.co/docs/reference/elasticsearch/rest-apis/refresh-parameter`
URL fetched / Verbatim quote checked: "If a `refresh=wait_for` request comes in when there are already `index.max_refresh_listeners` (defaults to 1000) requests waiting for a refresh on that shard then that request will behave just as though it had `refresh` set to `true` instead: it will force a refresh." — confirmed present.
Quote substring confirmed at: refresh parameter page, "Choosing which setting to use" section.

---

### Finding 5 — `refresh_interval=-1` during batch + single explicit refresh at end: the documented pattern for full-batch ingest

Elastic documentation explicitly describes the `refresh_interval=-1` pattern:

> "To maximize indexing performance during large bulk operations, you can disable refreshing by setting the refresh interval to `-1`."

And the restore step:

> "To disable the refresh interval, run the following request:" (sets `-1`)
> "When bulk indexing is complete, consider running a force merge to optimize search performance."

The full documented workflow for large initial loads (from tune-for-indexing-speed):
1. Set `index.number_of_replicas = 0`
2. Set `refresh_interval = -1`
3. Perform bulk indexing
4. Restore replicas and refresh interval to production values
5. Optionally, run force merge

A 2014 Elastic engineering blog post (still the authoritative reference) states:

> "When indexing throughput is important, e.g. when batch (re-)indexing, it is not very productive to spend a lot of time flushing and merging small segments. Therefore, in these cases it is usually a good idea to temporarily increase the refresh_interval-setting, or even disable automatic refreshing altogether. One can always refresh manually, and/or when indexing is done."

**The key limitation for 4Shark:** this pattern requires knowing when "the batch is done" as a global event — a moment when no more docs are being written and a single `POST /deals/_refresh` can safely run. The 4Shark system processes ~2,000 commissions in parallel, each completing at a different time. There is no single "batch end" event unless one is explicitly added (e.g., a coordinator job that knows all commissions are done and issues the one refresh).

**Source A:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html`
URL fetched / Verbatim quote checked: "To maximize indexing performance during large bulk operations, you can disable refreshing by setting the refresh interval to `-1`." — confirmed present.
URL fetched / Verbatim quote checked: "When bulk indexing is complete, consider running a force merge to optimize search performance." — confirmed present.
Quote substring confirmed at: tune-for-indexing-speed page, "Disable refresh and replicas for initial loads" section.

**Source B:** `https://www.elastic.co/blog/found-elasticsearch-from-the-bottom-up`
URL fetched / Verbatim quote checked: "When indexing throughput is important, e.g. when batch (re-)indexing, it is not very productive to spend a lot of time flushing and merging small segments. Therefore, in these cases it is usually a good idea to temporarily increase the refresh_interval-setting, or even disable automatic refreshing altogether. One can always refresh manually, and/or when indexing is done." — confirmed present.
Quote substring confirmed at: blog article, section on refresh interval optimization.

---

### Finding 6 — `force_merge` is only safe on read-only indexes; it blocks and is expensive

The Elastic reference states:

> "We recommend force merging only a read-only index (meaning the index is no longer receiving writes)."

Force merge on an actively written index creates oversized segments (>5 GB) that are ineligible for normal merge — causing soft-deleted documents to accumulate, increasing disk usage, and degrading search performance.

The blocking behavior:

> "Calls to this API block until the merge is complete (unless request contains `wait_for_completion=false`)."

Cost note: force merge can temporarily triple the shard's storage requirement (original data + new merged segments + old segments before deletion).

**Operational viability for 4Shark:** `force_merge` would be viable only if the `deals` index is completely quiesced — no writes, no updates. Given the nightly batch writes aggressively for ~1 hour, a `force_merge` scheduled at 04:00 (batch end) would be safe only if the batch is confirmed complete. The gain is consolidated segments → faster subsequent searches. The cost is a potentially hours-long blocking operation on a 2-vCPU node (force merge is CPU/IO intensive).

**Source:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-forcemerge.html`
URL fetched / Verbatim quote checked: "We recommend force merging only a read-only index (meaning the index is no longer receiving writes)." — confirmed present.
URL fetched / Verbatim quote checked: "Calls to this API block until the merge is complete (unless request contains `wait_for_completion=false`)." — confirmed present.
Quote substring confirmed at: indices-forcemerge page, warnings section.

---

### Finding 7 — Dual-index with alias swap: documented production pattern for batch ingest + zero-downtime promotion

BigData Boutique documents a production pattern using nightly batch jobs:

> "One such use case is using a nightly batch job to index data from a database in a separate index from the currently queryable index, running validations on the copied data, then switching the read alias from the current index to the new index created by the batch job."

The article confirms atomicity of alias operations:

> "Add and remove actions are transactional, when executed on the same request."

Elastic's official aliases documentation confirms:

> "You can use the aliases API to perform multiple actions in a single atomic operation."
> "During this swap, the `logs` alias has no downtime and never points to both streams at the same time."

The versioned-index pattern from Elastic's zero-downtime reindex article shows the mechanics:

```json
{
  "actions": [
    { "remove": {"alias": "my_index", "index": "my_index_v1"} },
    { "add":    {"alias": "my_index", "index": "my_index_v2"} }
  ]
}
```

**For 4Shark:** the dual-index pattern would work as: (1) write batch to `deals_staging` with `refresh_interval=-1`; (2) after all commissions complete, set `refresh_interval=30s`, run explicit refresh, run `Metric::Producer` against `deals_staging`; (3) atomically swap `deals` alias from `deals_current` to `deals_staging`; (4) rename `deals_staging` → next cycle. **Critical constraint:** `Metric::Producer` still needs to read after the docs are searchable in `deals_staging` — this means the staging index needs at least one refresh before `Metric::Producer` runs. This only solves the problem if `Metric::Producer` can run after the full batch is complete, not per-commission.

**Source A:** `https://bigdataboutique.com/blog/index-aliases-in-elasticsearch-and-opensearch-66636d`
URL fetched / Verbatim quote checked: "One such use case is using a nightly batch job to index data from a database in a separate index from the currently queryable index, running validations on the copied data, then switching the read alias from the current index to the new index created by the batch job." — confirmed present.
URL fetched / Verbatim quote checked: "Add and remove actions are transactional, when executed on the same request." — confirmed present.
Quote substring confirmed at: bigdataboutique.com alias article.

**Source B:** `https://www.elastic.co/docs/manage-data/data-store/aliases`
URL fetched / Verbatim quote checked: "You can use the aliases API to perform multiple actions in a single atomic operation." — confirmed present.
URL fetched / Verbatim quote checked: "the `logs` alias has no downtime and never points to both streams at the same time." — confirmed present.
Quote substring confirmed at: Elastic aliases documentation.

---

### Finding 8 — People.ai production case: hot/cold index split to isolate batch from search

People.ai Engineering documented a scenario structurally similar to 4Shark — an hourly batch indexing job causing degraded search latency on the same cluster:

> "We implemented a 'hot/cold' index structure strategy alongside two supporting optimizations."
> "Changed from 32 concurrent indexing processes to 1"
> "Reduced indexing volume from 2 million to ~600k documents hourly by excluding unchanged records"

Their solution: "Concentrating updates to one or just a few shards, where possible, is a generalization of this approach that may be more widely applicable."

The structural similarity to 4Shark: concurrent indexing processes saturating the cluster, degraded search performance as a result. Their fix combined (a) reduced concurrency and (b) separated hot (frequently updated) and cold (read-only) indexes. The cold index was never written to during the batch — only the hot index received updates, isolating merge pressure to a smaller surface.

**Relevance:** the People.ai case does not use `_mget` or alias swap. It directly reduced the problem via (a) concurrency reduction and (b) writing less. The outcome aligns with what SPIKE.md Finding 8 inferred about v3.32.0 — the concurrency change (autoscaling → fixed 10 threads) was the major regression, not the bulk API itself.

**Source:** `https://medium.com/people-ai-engineering/maintaining-performance-during-bulk-indexing-in-elasticsearch-7aa839e6204d`
URL fetched / Verbatim quote checked: "Changed from 32 concurrent indexing processes to 1" — confirmed present.
URL fetched / Verbatim quote checked: "Concentrating updates to one or just a few shards, where possible, is a generalization of this approach that may be more widely applicable." — confirmed present.
Quote substring confirmed at: People.ai Medium article.

---

### Finding 9 — t3.small.search: 2 vCPU, 2 GiB RAM; AWS explicitly recommends against it for production

From the CloudZero advisor spec sheet, confirmed: `t3.small.search` is 2 vCPU, 2 GiB RAM, EBS-only storage. The JVM heap for OpenSearch is ~1 GB (50% of RAM per best practice).

AWS explicitly states:

> "Avoid using T2 or `t3.small` instances for production domains because they can become unstable under sustained heavy load. `r6g.large` instances are an option for small production workloads (both as data nodes and as dedicated master nodes)."

The indexing buffer on `t3.small.search` is ~100 MB (10% of 1 GB heap). From SPIKE.md Finding 7: per-shard optimal buffer is 512 MB; 100 MB is ~20% of optimal. Buffer exhaustion forces extra segment flushes independent of the scheduled `refresh_interval`.

The AWS capacity planning guidance states: "use an initial scale point of 1.5 vCPU per shard" — with 2 vCPU and 1 primary shard, the available budget after meeting the shard's baseline is 0.5 vCPU for background work (refresh, merge, flush). Under a nightly batch with 2,000 concurrent commissions, this budget is exhausted.

**Source A:** `https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html`
URL fetched / Verbatim quote checked: "Avoid using T2 or `t3.small` instances for production domains because they can become unstable under sustained heavy load." — confirmed present. (This quote also appears in SPIKE.md Finding 5 — citing here for completeness given question 8's scope.)
Quote substring confirmed at: AWS BP page, § "Use the latest generation instance types".

**Source B:** `https://advisor.cloudzero.com/aws/opensearch/t3.small.search`
URL fetched: 2 vCPU, 2 GiB RAM confirmed as specs for t3.small.search.
Verbatim: no explicit production guidance on this page — spec facts only.

---

## Responses to the 8 investigation questions

**Q1. `GET /_doc/{id}` and `_mget`: are they real-time (translog-aware)?**

Yes — both are real-time by default (Finding 1, Finding 2). The GET API documentation states: "By default, the get API is realtime, and is not affected by the refresh rate of the index." The mechanism is translog-first lookup: "it first checks the translog for any recent changes before trying to retrieve the document from the relevant segment." `_mget` has `realtime=true` as explicit default per the 8.17 parameter table. Caveats: routing value must match if custom routing was used at index time; `stored_fields` requests may require source parsing if not yet refreshed to a segment.

**Q2. Can `Metric::Producer` be converted to use `_mget` instead of search?**

Technically viable for adapters that aggregate over field values of a known set of document IDs (e.g., `TotalAdapter`, `QuantityAdapter` — if the IDs are passed from the Consumer). Not viable for queries that filter by fields not known at write time, require cross-batch aggregations, or need index-wide scans beyond the just-indexed IDs. The conversion requires the Consumer to pass IDs downstream to the Producer and the Producer to iterate over the returned docs to compute its metrics. (Finding 3)

**Q3. Bulk ingest with refresh tuned for batch-end — how do real systems do it?**

The canonical pattern is documented by Elastic: set `refresh_interval=-1` during ingest, then restore and optionally run explicit refresh + `force_merge` at the end. The Elastic engineering blog (2014, still current) states: "temporarily increase the refresh_interval-setting, or even disable automatic refreshing altogether. One can always refresh manually, and/or when indexing is done." AWS OpenSearch BP recommends `refresh_interval ≥ 30s` for production but does not document the `-1` + explicit-refresh pattern. The People.ai case (Finding 8) solved the same class of problem via concurrency reduction rather than refresh tuning. The pattern is well-established for ETL/initial-load scenarios; its applicability to an ongoing batch depends on detecting "batch end" (Finding 5).

**Q4. `force_merge` post-batch: viability as an operational tool?**

Force merge is viable as a post-batch cleanup only if: (a) the batch is confirmed complete and no further writes are expected; (b) a maintenance window is acceptable (the operation blocks until complete on a 2-vCPU node — duration unknown without benchmarking). Documentation explicitly restricts it to read-only indexes: "We recommend force merging only a read-only index (meaning the index is no longer receiving writes)." Running it nightly at 04:00 post-batch would consolidate the ~3,600 segments created by `1s` refresh (or far fewer with tuned refresh) into a smaller set — improving subsequent search performance and reducing merge overhead for the next batch. It is not a substitute for fixing refresh_interval during the batch itself; it is a cleanup step. (Finding 6)

**Q5. `refresh_interval=-1` during batch + 1 refresh at batch end: does this solve it?**

Yes — if the system can detect "the entire nightly batch is done." The documented pattern (Finding 5) eliminates refresh/merge pressure entirely during bulk. The cost: all docs are unsearchable until the single `POST /deals/_refresh` fires at batch end. For the 4Shark architecture this requires a "batch completion" event that today does not exist — the current flow is commission-scoped, not batch-scoped. Adding a coordinator that tracks `commission.computation.done?` across all commissions and fires the refresh + `Metric::Producer` run once all are complete would enable this pattern. The tradeoff is latency: `Metric::Producer` runs after the full batch (say 04:30) rather than continuously throughout (03:00–04:00).

**Q6. Dual-index with alias swap: viable?**

The pattern is documented and production-tested (Finding 7): write to `deals_staging` with `refresh_interval=-1`, refresh once at end, run `Metric::Producer` against staging, atomically swap `deals` alias. Pros: completely decouples ingest from the queryable index; search traffic goes to `deals_current` unaffected during batch. Cons: requires 2× storage (current + staging); requires application-level awareness of two index names or consistent alias usage everywhere; requires "batch end" detection same as Q5; adds operational complexity (what if batch fails mid-way — is staging partial?). The atomic swap itself is a single API call with zero-downtime guarantee: "During this swap, the `logs` alias has no downtime and never points to both streams at the same time."

**Q7. How do practitioners with Elasticsearch rajadas in large systems reconcile throughput vs read latency?**

The documented patterns converge on three approaches:
1. **Decouple write and read paths** — write to one index/alias, read from another; promote via atomic alias swap after validation (Finding 7)
2. **Reduce ingest-time refresh pressure** — `refresh_interval=-1` during batch, single refresh at end (Finding 5); or increase refresh interval to 30s+ as AWS recommends
3. **Reduce write concurrency** — People.ai reduced from 32 to 1 concurrent indexing processes; this is the same axis as SPIKE.md's concurrency analysis

No verified blog post from Spotify, Netflix, Shopify, or Stripe was found discussing this specific pattern for nightly batch indexing. The "hot/cold" index split from People.ai (Finding 8) and the versioned-index alias swap from Elastic's own engineering content (Finding 7) are the best-cited production cases. The absence of hyperscaler case studies for this specific pattern is documented — it is not an artifact of incomplete search.

**Q8. Is `t3.small.search` underdimensioned for "2,000 commissions × bulk 2,000 × immediate read", even with perfect tuning?**

AWS explicitly states t3.small should not be used for sustained production load (Finding 9). The 2-vCPU budget at 1.5 vCPU/shard leaves ~0.5 vCPU for background work (refresh, merge, flush). At 2,000 concurrent commissions, even with `refresh_interval=30s`, merge pressure from ~120 segments/hour will compete with write threads for that 0.5 vCPU. The indexing buffer (100 MB) is 20% of the per-shard optimal (512 MB) — buffer exhaustion forces extra flushes independently of the refresh interval. The evidence from SPIKE.md (Findings 3, 5, 7) and from AWS's own capacity guidance converges: at the 4Shark batch volume, t3.small operates at or beyond its capacity boundary regardless of refresh tuning. Refresh tuning reduces the pressure but does not eliminate it on this hardware.

---

## Patterns surfaced (no recommendation — engineer decides)

### Pattern A — Convert `Metric::Producer` read to `_mget` (read-after-write via real-time API)

The Consumer passes its batch of deal IDs to the Producer. The Producer calls `_mget` with those IDs — real-time, no refresh required, no search. The Producer iterates over the returned documents and computes metrics from field values.

**Pros:**
- No refresh required — completely decouples `Metric::Producer` from `refresh_interval`
- Works with any `refresh_interval` value (30s, -1, 1s)
- Does not require a "batch end" event — works commission-by-commission as today
- Scales with the number of IDs: `_mget` is O(N) in 1 HTTP round-trip

**Cons:**
- Requires `Metric::Producer` adapters to be rewritten from search queries to ID-based aggregation
- Not applicable to adapters that need cross-batch queries (aggregations beyond the current commission's deals, range filters on derived fields, etc.)
- If any adapter's logic cannot be expressed as "iterate over these N docs and sum/count a field," it cannot be converted
- Coupling: Consumer must provide IDs to Producer (currently may not — requires data flow change)

**Sustaining findings:** 1, 2, 3

---

### Pattern B — `refresh_interval=30s` (or higher) + keep current search-based Producer

Set `refresh_interval=30s` on the `deals` index. `Metric::Producer` search waits up to 30s for docs to be visible. Consumer does not trigger any refresh.

**Pros:**
- Simple 1-line change: `PUT /deals/_settings { "refresh_interval": "30s" }`
- 30× fewer segments per batch hour (SPIKE.md Finding 6) — major reduction in merge pressure
- AWS-documented recommendation for production
- `Metric::Producer` still uses the same search queries with no code change
- No architectural changes to producer-consumer pattern

**Cons:**
- `Metric::Producer` sees docs up to 30s after they were indexed — if any downstream process depends on metrics being computed immediately post-commission, there is a 30s window of invisibility
- Does not eliminate merge pressure — reduces it by 30×. On a 2-vCPU node with 100 MB indexing buffer, buffer exhaustion can still force extra flushes (SPIKE.md Finding 7)
- Does not solve the root capacity problem if the cluster is already operating beyond its effective ceiling (Finding 9)

**Sustaining findings:** SPIKE.md Finding 6, Finding 9 (this spike)

---

### Pattern C — `refresh_interval=-1` during batch + batch-end coordinator refresh + batch-scope `Metric::Producer`

Add a "batch coordinator" job. All commissions report completion to the coordinator. When the coordinator detects all commissions are done, it: (1) calls `POST /deals/_refresh`, (2) triggers `Metric::Producer` for all commissions, (3) restores `refresh_interval` to production value.

**Pros:**
- Eliminates refresh/merge pressure entirely during the ~1h batch window
- Single refresh produces exactly 1 segment — no segment accumulation
- `Metric::Producer` runs on a consistent post-batch snapshot
- After `force_merge` (optional), the index has optimal structure for search
- Matches the Elastic-documented best practice for large initial loads

**Cons:**
- Requires new infrastructure: a coordinator that tracks commission completion globally
- `Metric::Producer` runs once at batch end instead of progressively — total batch time may increase (all metrics computed in one burst at 04:30 vs spread 03:00–04:30)
- If the batch is interrupted (e.g., partial failure) and `refresh` is never called, docs remain invisible until someone manually restores `refresh_interval`
- Operational complexity: `refresh_interval=-1` + a crash = invisible data
- Does not change the read pattern (still search-based) — `Metric::Producer` must wait for the coordinator's refresh before running

**Sustaining findings:** 5, SPIKE.md Finding 6

---

### Pattern D — Dual-index with alias swap (staging → production promotion)

Write the entire nightly batch to `deals_staging_{date}` with `refresh_interval=-1`. After all commissions complete: refresh `deals_staging`, run `Metric::Producer` against `deals_staging`, atomically swap the `deals` alias from `deals_current` to `deals_staging`.

**Pros:**
- Search traffic on `deals` (via alias) is completely unaffected during batch — no refresh pressure on the live index
- Post-batch refresh on staging produces exactly 1 segment per shard — cleanest possible state
- Atomic alias swap has zero downtime guarantee
- Allows data validation before promotion (staging can be queried before it goes live)
- Documented production pattern (Finding 7)

**Cons:**
- Requires 2× storage (live + staging) — cost
- Requires the application to always reference the index via alias (if any code hardcodes the index name, it breaks)
- Requires "batch end" detection (same dependency as Pattern C)
- Does not handle incremental updates well: if some deals are updated between batch runs, the old `deals_current` becomes stale and needs careful handling
- Adds operational surface: failed batch = staging partially written, no swap yet, live index may be stale
- Most complex to implement of the four patterns

**Sustaining findings:** 7

---

### Pattern E — `refresh=wait_for` on last bulk per commission (current SPIKE.md proposal)

The last `_bulk` call in each commission uses `?refresh=wait_for`. This blocks the Consumer thread until the next refresh cycle makes the docs visible. Then `Metric::Producer` can search immediately.

**Pros:**
- No coordinator required — works commission-by-commission
- `Metric::Producer` reads immediately after Consumer finishes
- Does not require `_mget` or adapter rewrites
- Does not require a "batch end" event

**Cons (documented in SPIKE.md and reinforced by Finding 4):**
- Holds a Sidekiq thread for up to `refresh_interval` seconds (up to 30s with Pattern B's settings)
- Under 2,000 concurrent commissions, the `index.max_refresh_listeners=1000` ceiling is likely hit: requests >1,000 auto-escalate to `refresh=true`, creating tiny segments — the same merge pressure the engineer explicitly rejected
- Even below the ceiling, `wait_for` does not actively trigger a refresh — it waits for the next scheduled one, which means the Sidekiq thread is idle for up to `refresh_interval` seconds

**Sustaining findings:** 4, SPIKE.md Findings 2, 6

---

## Trade-offs between the patterns

| Pattern | Code change required | Refresh pressure during batch | `Metric::Producer` reads when? | Batch-end event required? | Risk |
|---|---|---|---|---|---|
| **A — mget** | High (Producer adapters rewritten) | None — independent of refresh | Immediately after Consumer (real-time) | No | Adapter conversion may not cover all cases |
| **B — refresh=30s** | None (1 settings call) | 30× reduced | Up to 30s after indexing | No | 30s visibility gap; t3.small still near capacity |
| **C — -1 + batch coordinator** | Medium (coordinator job) | Zero during batch, 1 spike at end | After full batch completes | Yes | Operational risk if refresh never fires; later metric computation |
| **D — dual-index alias swap** | High (infrastructure + alias convention) | Zero on live index | After full batch + validation | Yes | Storage × 2; complexity; incremental update handling |
| **E — wait_for** | Low (bulk call parameter only) | Scales with concurrency; >1000 commissions → forced refresh | Immediately after Consumer | No | max_refresh_listeners ceiling at 2,000 commissions; thread holding |

---

## What remains uncertain

1. **Whether `Metric::Producer` adapters can be converted to `_mget`**: this requires reading the actual adapter code (`Metric::TotalAdapter`, `Metric::QuantityAdapter`, etc.) in the `app` codebase to determine which queries are expressible as ID-based field iteration vs which require index-wide search.

2. **Whether routing is used on the `deals` index**: if custom routing was applied during `_bulk` indexing, `_get` / `_mget` calls must specify the same routing value. If no routing is used (default: hash of `_id` to shard), `_get` and `_mget` work with just the ID. Not verifiable without reading the Consumer code.

3. **The actual `Metric::Producer` query structure**: the investigation description says "bool/must/range/match" — but the specific fields and filters are not known. Whether those queries can be replaced by ID-based reads depends entirely on what those queries compute. Not verifiable without reading the code.

4. **What "batch end" looks like in the current codebase**: Pattern C and Pattern D both require knowing when all ~2,000 commissions are done. Whether there is already a mechanism for this (e.g., a nightly Sidekiq job that waits for all Consumer jobs to finish) or whether it needs to be built is unknown.

5. **Whether `force_merge` duration is acceptable on t3.small.search**: force merge on a large index on a 2-vCPU node can take hours. Without knowing the current index size and segment count, the operational cost cannot be estimated.

6. **The exact `realtime` behavior in OpenSearch vs Elasticsearch**: the translog-as-real-time-GET mechanism is documented in the Elasticsearch guide (a legacy but authoritative source). The current Elasticsearch reference documentation confirms real-time default behavior but does not specify the mechanism. AWS OpenSearch documentation does not document the translog-GET relationship explicitly. The behavior is likely identical (OpenSearch is a fork of Elasticsearch 7.10), but no AWS OpenSearch-specific confirmation was found.
