# SPIKE — OpenSearch Bulk Pipeline Internals and Cluster Capacity

## Investigation question

What happens inside OpenSearch between receiving a `POST /_bulk` and returning `200 OK`? What work continues asynchronously after that response? How does the write thread pool limit concurrency? Is bulk-100 cheaper or more expensive per document than 100 individual requests? What are the documented capacity heuristics for a `t3.small.search` (2 vCPU, ~1GB heap) cluster? Does reverting to individual indexing improve, maintain, or worsen the current situation?

Context: `app-shared-001` is a 2× `t3.small.search` cluster. v3.31.0 switched from 1 doc/request to `client.bulk` with 100-doc batches. v3.32.0 moved the consumer to a dedicated 10-thread ECS service. Since then, 5xx errors increased 156× (41 → 6,409 + 1,162) on the next nightly batch run.

Related prior research: `PLAN-SPIKE.md` in this directory (Tracks 1–4: bulk options, refresh interval, gem migration, adapter selection).

---

## Sources consulted

- `https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-translog.html` — translog pipeline, durability modes, fsync timing, when 200 is sent
- `https://www.elastic.co/guide/en/elasticsearch/reference/current/near-real-time.html` — in-memory buffer, Lucene segment lifecycle, refresh vs flush definition
- `https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-merge.html` — merge thread pool, auto-throttling, when merge blocks indexing
- `https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html` — bulk size guidance, refresh_interval tuning, indexing buffer, thread count
- `https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-threadpool.html` — write thread pool size formula, queue size, rejection behavior
- `https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html` — AWS OpenSearch BP: t3.small warning, bulk size 3–5 MiB, refresh_interval ≥30s recommendation
- `https://medium.com/@mokshteng/mastering-elasticsearch-write-performance-refresh-merge-flush-explained-290631930e4a` — write pipeline walkthrough with buffer→translog→segment→merge→flush sequence (secondary source, not primary)

---

## Findings

### Finding 1 — What the 200 OK actually acknowledges: translog fsync on primary + replicas

With the default `index.translog.durability: request`, the HTTP 200 is only sent **after** the translog has been fsynced to disk on the primary shard **and every allocated replica shard**.

> "Elasticsearch will only report success of an index, delete, update, or bulk request to the client after the translog has been successfully `fsync`ed and committed on the primary and on every allocated replica."

The document also states what is written to the translog and when:

> "All index and delete operations are written to the translog after being processed by the internal Lucene index but before they are acknowledged."

This means the sequence before the 200 returns is:
1. Document is processed by the internal Lucene index (written to in-memory buffer + Lucene's internal structures)
2. Operation is written to the translog
3. Translog is fsynced to disk on primary
4. Operation is replicated to every allocated replica shard
5. Translog is fsynced on each replica
6. 200 is returned to the client

For `deals` index with `number_of_replicas: 0` (no replicas — implied by 1-shard config on a 2-node cluster without explicit replica count set), step 4–5 is skipped.

**Source:** `https://www.elastic.co/docs/reference/elasticsearch/index-settings/translog` (confirmed fetched; quotes verified verbatim at paragraphs 2 and "Translog settings" section).

URL fetched: `https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-translog.html`
Verbatim quote checked: "Elasticsearch will only report success of an index, delete, update, or bulk request to the client after the translog has been successfully fsync'ed and committed on the primary and on every allocated replica." — confirmed present in the "Translog settings" section.
Verbatim quote checked: "All index and delete operations are written to the translog after being processed by the internal Lucene index but before they are acknowledged." — confirmed present in paragraph 2.
Quote substring confirmed at: both confirmed via direct fetch.

---

### Finding 2 — What happens AFTER the 200: three async background processes

After the translog fsync and the 200 response, three background processes continue running, all of them consuming CPU and I/O:

**A. Refresh (scheduled, default every 1s)**

> "In Elasticsearch, this process of writing and opening a new segment is called a refresh. A refresh makes all operations performed on an index since the last refresh available for search."

> "By default, Elasticsearch periodically refreshes indices every second, but only on indices that have received one search request or more in the last 30 seconds."

At each refresh cycle, documents accumulated in the in-memory buffer since the last refresh are written into a new Lucene segment and opened for search. Each refresh = one new segment created.

> "The new segment is written to the filesystem cache first (which is cheap) and only later is it flushed to disk (which is expensive)."

With `refresh_interval: 1s` and 100-doc batches arriving at 10–80 threads concurrently, the cluster produces up to 1 new segment per second continuously during the batch window.

**B. Segment merge (continuous background, dedicated merge thread pool)**

> "Merges run on the dedicated `merge` thread pool. Smaller segments are merged into larger segments to keep the index size at bay and to expunge deletes."

> "The merge process uses auto-throttling to balance the use of hardware resources between merging and other activities like search."

Critically, when merging falls behind the rate of segment creation:

> "Beyond a certain per-shard limit, after merging is completely disk IO un-throttled, indexing for the shard will itself be throttled until merging catches up."

This is a direct backpressure mechanism: if bulk requests produce segments faster than the merge thread pool can consolidate them, the cluster forces new indexing operations to wait. On a 2-vCPU `t3.small.search`, the merge thread pool maximum threads per shard defaults to `Math.max(1, Math.min(4, 2 / 2)) = 1 thread` — meaning merging is effectively single-threaded per shard on this hardware.

**C. Flush (automatic, every 30 min or 10 GB translog)**

> "Flushing a data stream or index is the process of making sure that any data that is currently only stored in the transaction log is also permanently stored in the Lucene index."

Flush involves committing the Lucene index to disk and clearing the translog. Default threshold: `index.translog.flush_threshold_size: 10 GB`. With the batch writing 500k docs in ~1h at ~1–5 KB/doc, this may trigger mid-batch.

**Source A:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/near-real-time.html` — confirmed fetched.
URL fetched / Verbatim quote checked: "In Elasticsearch, this process of writing and opening a new segment is called a refresh. A refresh makes all operations performed on an index since the last refresh available for search." — confirmed.
URL fetched / Verbatim quote checked: "The new segment is written to the filesystem cache first (which is cheap) and only later is it flushed to disk (which is expensive)." — confirmed.

**Source B:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/index-modules-merge.html` — confirmed fetched.
Verbatim quote checked: "Merges run on the dedicated `merge` thread pool. Smaller segments are merged into larger segments to keep the index size at bay and to expunge deletes." — confirmed.
Verbatim quote checked: "Beyond a certain per-shard limit, after merging is completely disk IO un-throttled, indexing for the shard will itself be throttled until merging catches up." — confirmed.

**Source C:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-flush.html` (via WebFetch summary) — confirmed fetched.
Verbatim quote checked: "Flushing a data stream or index is the process of making sure that any data that is currently only stored in the transaction log is also permanently stored in the Lucene index." — confirmed.

---

### Finding 3 — Write thread pool: 2 threads on 2-vCPU, queue 10,000

The write thread pool governs how many concurrent bulk/index requests OpenSearch processes simultaneously.

> "Thread pool type is `fixed` with a size of [`# of allocated processors`]"

> "queue_size of `max(10000, (# of allocated processors * 750))`"

For `t3.small.search` (2 vCPU):
- **Write thread pool size: 2 threads**
- **Queue size: max(10000, 2 × 750) = 10,000**

When the queue is full:

> "If a bounded queue is full then it will reject further work, which typically causes the corresponding requests to fail."

This rejection produces HTTP 429/503 on the client side (mapped to Elasticsearch `es_rejected_execution`).

**Implications for the observed scenario:**

With `SIDEKIQ_THREADS=10` in v3.32.0, up to 10 bulk requests can be in-flight concurrently from the client side. The cluster's write thread pool has only 2 active threads. The remaining 8 requests queue on the cluster side (or wait for a thread to free up). Each bulk of 100 docs requires a translog fsync before releasing the thread. With `refresh_interval: 1s`, each fsync cycle creates CPU pressure from the simultaneous background refresh. The combination of 2 active threads, continuous fsync demand, and 1s refresh on a 2-vCPU machine creates the latency pattern observed (18ms → 155ms → 5020ms spike).

With the previous setup (v3.31.0: up to 80 threads × bulk 100 in `worker-commission`), the concurrency pressure was potentially much higher — but `worker-commission` autoscales 1→8 tasks, meaning the actual thread count varied. If the pre-bulk period used `save_document!` (1 doc/request), then 80 threads × 1 doc = 80 individual requests, each still hitting the 2-thread write pool.

**Source:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/modules-threadpool.html` — confirmed fetched.
URL fetched / Verbatim quote checked: "Thread pool type is `fixed` with a size of [`# of allocated processors`]" — confirmed.
Verbatim quote checked: "queue_size of `max(10000, (# of allocated processors * 750))`" — confirmed.
Verbatim quote checked: "If a bounded queue is full then it will reject further work, which typically causes the corresponding requests to fail." — confirmed.

---

### Finding 4 — Bulk API is cheaper per document than individual requests: documented

> "Bulk requests will yield much better performance than single-document index requests."

> "In order to know the optimal size of a bulk request, you should run a benchmark on a single node with a single shard. First try to index 100 documents at once, then 200, then 400, etc. doubling the number of documents in a bulk request in every benchmark run. When the indexing speed starts to plateau then you know you reached the optimal size of a bulk request for your data."

The efficiency gain from bulk is structural: each bulk request causes exactly **one** translog fsync covering all N documents in the batch, versus N individual requests each requiring one fsync each. With `durability: request` (default), this means:
- 100 individual requests = 100 fsync cycles on the primary (+ replica)
- 1 bulk of 100 = 1 fsync cycle covering all 100 docs

AWS OpenSearch BP confirms:

> "It's more efficient to send one `_bulk` request that contains 5,000 documents than it is to send 5,000 requests that contain a single document."

The cost comparison also extends to segment creation: the translog write frequency directly correlates with how often documents become candidates for segment creation. Individual writes don't create segments immediately (they accumulate in the buffer until a refresh), but they do create fsync pressure at a rate proportional to the request count.

**Source A:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html` — confirmed fetched.
URL fetched / Verbatim quote checked: "Bulk requests will yield much better performance than single-document index requests." — confirmed.
Verbatim quote checked: "First try to index 100 documents at once, then 200, then 400, etc. doubling the number of documents in a bulk request in every benchmark run." — confirmed.

**Source B:** `https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html` — confirmed fetched.
Verbatim quote checked: "It's more efficient to send one `_bulk` request that contains 5,000 documents than it is to send 5,000 requests that contain a single document." — confirmed in § "Control ingest flow and buffering".

---

### Finding 5 — AWS-documented sweet spot: 3–5 MiB per bulk request, not a doc count

AWS OpenSearch does not publish a doc-count sweet spot per instance type. The documented guidance is by payload size:

> "Bulk sizing depends on your data, analysis, and cluster configuration, but a good starting point is 3–5 MiB per bulk request."

> "To optimize your bulk request sizes, start with a bulk request size of 3 MiB. Then, slowly increase the request size until indexing performance stops improving."

Elastic's guidance is to benchmark from 100 docs upward and watch for throughput plateau:

> "avoid going beyond a couple tens of megabytes per request even if larger requests seem to perform better."

For `app-shared-001`: a typical `deals` document with metric fields is likely 0.5–2 KB. At 1 KB/doc average:
- 100 docs ≈ 0.1 MiB — well below the 3 MiB starting point, suggesting batch size can be increased
- 3 MiB ≈ 3,000 docs at 1 KB/doc
- 5 MiB ≈ 5,000 docs at 1 KB/doc

AWS explicitly warns against `t3.small` for production:

> "Avoid using T2 or `t3.small` instances for production domains because they can become unstable under sustained heavy load. `r6g.large` instances are an option for small production workloads (both as data nodes and as dedicated master nodes)."

**Source:** `https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html` — confirmed fetched.
URL fetched / Verbatim quote checked: "Bulk sizing depends on your data, analysis, and cluster configuration, but a good starting point is 3–5 MiB per bulk request." — confirmed in § "Optimize bulk request size and compression".
Verbatim quote checked: "Avoid using T2 or `t3.small` instances for production domains because they can become unstable under sustained heavy load." — confirmed in § "Use the latest generation instance types".

---

### Finding 6 — `refresh_interval: 1s` vs `30s`: documented cost and mechanism

The refresh operation is explicitly described as costly when frequent:

> "The operation that consists of making changes visible to search — called a refresh — is costly, and calling it often while there is ongoing indexing activity can hurt indexing speed."

AWS recommends a minimum of 30s for production indexes:

> "We recommend setting the `refresh_interval` parameter for all of your indexes to 30 seconds or more."

The AWS doc also confirms the exact default:

> "The default refresh interval is one second, which means that OpenSearch performs a refresh every second while an index is being written to."

And the trade-off formulation:

> "The less frequently that you refresh an index (higher refresh interval), the better the overall indexing performance is. The trade-off of increasing the refresh interval is that there's a longer delay between an index update and when the new data is available for search. Set your refresh interval as high as you can tolerate to improve overall performance."

**Mechanism of improvement:** each refresh produces one new Lucene segment. At `refresh_interval: 1s` during a 1h batch writing 500k docs, the index accumulates up to 3,600 small segments. The merge thread pool must continuously consolidate these. At `refresh_interval: 30s`, the same batch produces at most 120 segments — 30× fewer merge cycles. Fewer merge cycles = less CPU contention with the write thread pool on the 2-vCPU `t3.small.search`.

For complete bulk ingest (no search needed during batch), Elastic recommends disabling refresh entirely:

> "To maximize indexing performance during large bulk operations, you can disable refreshing by setting the refresh interval to `-1`."

**Source A:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html` — confirmed fetched.
URL fetched / Verbatim quote checked: "The operation that consists of making changes visible to search — called a refresh — is costly, and calling it often while there is ongoing indexing activity can hurt indexing speed." — confirmed.
Verbatim quote checked: "To maximize indexing performance during large bulk operations, you can disable refreshing by setting the refresh interval to `-1`." — confirmed.

**Source B:** `https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html` — confirmed fetched.
Verbatim quote checked: "We recommend setting the `refresh_interval` parameter for all of your indexes to 30 seconds or more." — confirmed in § "Tune refresh intervals".

---

### Finding 7 — Capacity heuristic for `t3.small.search` (1 GB heap, 2 vCPU)

No official AWS or OpenSearch document publishes a docs/second throughput figure per instance type. The documented heuristics are:

**Indexing buffer:**

> "The default is `10%` which is often plenty: for example, if you give the JVM 10GB of memory, it will give 1GB to the index buffer, which is enough to host two shards that are heavily indexing."

For `t3.small.search` with ~1GB heap: 10% = ~100 MB indexing buffer. This is the in-memory buffer for accumulating documents before refresh creates a segment. The cap per shard is 512 MB:

> "If your node is doing only heavy indexing, be sure `indices.memory.index_buffer_size` is large enough to give at most 512 MB indexing buffer per shard doing heavy indexing (beyond that indexing performance does not typically improve)."

At 100 MB total buffer with a single shard, the cluster is operating at ~20% of the per-shard optimal buffer size. Buffer exhaustion forces an early flush (not refresh) of the buffer to a segment, increasing segment creation rate independently of the scheduled refresh interval.

**Write thread pool (2 threads, queue 10,000):**

At 155ms average latency per bulk-100 request (observed in v3.31.0 degraded state), the theoretical maximum throughput through 2 threads is: `2 threads × (1000ms / 155ms) ≈ 12.9 requests/second × 100 docs = ~1,290 docs/second`.

At 18ms (pre-degradation latency): `2 × (1000 / 18) ≈ 111 requests/second × 100 docs = ~11,100 docs/second`.

At the observed 542k HTTP 2xx before v3.31.0 (individual requests, 1 doc each): 542,000 docs across the batch window (approx. 3600s = 1h) = ~150 docs/second average throughput, with the batch seemingly working fine. This is well below even the degraded throughput — suggesting the degradation was not caused by raw throughput limits but by concurrency patterns and background work contention.

**CPU and vCPU limitation:**

> "When a shard is involved in an indexing or search request, it uses a vCPU to process the request. As a best practice, use an initial scale point of 1.5 vCPU per shard."

1.5 vCPU per shard with 2 vCPU = capacity for ~1.3 shards under indexing load. With 1 primary shard on a 2-node cluster (no replicas), the effective indexing vCPU budget is 2 vCPUs split between: write thread pool + background refresh + background merge. Under a bursty indexing workload, all three compete for the same 2 vCPUs.

**Source A:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html` — confirmed fetched.
URL fetched / Verbatim quote checked: "The default is `10%` which is often plenty: for example, if you give the JVM 10GB of memory, it will give 1GB to the index buffer, which is enough to host two shards that are heavily indexing." — confirmed.
Verbatim quote checked: "be sure `indices.memory.index_buffer_size` is large enough to give at most 512 MB indexing buffer per shard doing heavy indexing (beyond that indexing performance does not typically improve)." — confirmed.

**Source B:** `https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html` — confirmed fetched.
Verbatim quote checked: "As a best practice, use an initial scale point of 1.5 vCPU per shard." — confirmed in § "Shard to CPU ratio".

---

### Finding 8 — Reverting to individual indexing: the evidence

Individual indexing (`PUT /{index}/_doc/{id}`) vs bulk (`POST /_bulk`) differ in the number of fsync operations per document:

- **Individual (1 doc/request):** 1 translog fsync per document (with `durability: request`)
- **Bulk (100 docs/request):** 1 translog fsync per 100 documents

The documented statement is unambiguous:

> "Bulk requests will yield much better performance than single-document index requests."

> "It's more efficient to send one `_bulk` request that contains 5,000 documents than it is to send 5,000 requests that contain a single document."

The key variables distinguishing the pre-v3.31.0 behavior (individual, working) from v3.32.0 (bulk-100, failing with 5xx) are **not** bulk vs individual, but rather:

1. **Concurrency change:** `worker-commission` with autoscale 1→8 tasks × 10 threads = 10–80 threads; `worker-deal-indexation` with 1 task × 10 threads = fixed 10 threads. The failure did not start with v3.31.0 (bulk introduced) — 5xx stayed roughly flat (23 → 41). The explosion (41 → 1,162 + 6,409) happened with v3.32.0 (dedicated fixed 10-thread service). This pattern is consistent with **throughput collapse from lost autoscaling**, not from the bulk API itself.

2. **Bulk request duration:** a bulk-100 request (155ms observed avg) holds a write thread for 155ms. An individual-1 request likely holds it for ~18ms (pre-bulk latency). With 2 write threads: bulk-100 at 155ms → 12.9 requests/s throughput; individual-1 at 18ms → 111 requests/s throughput. But individual-1 at 18ms × 100× more requests = same number of fsync cycles but spread over time → more fsyncs total → heavier translog/disk I/O load in aggregate.

3. **Why v3.31.0 was still worse than baseline (÷3.4 on 2xx):** the first bulk deployment on `worker-commission` with autoscale likely produced bulk requests that were heavier per request (155ms), reducing the number of successful completions per unit time compared to the previous 18ms individual requests — even with fewer total network round trips.

**Source:** `https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html` — confirmed fetched (same quotes as Finding 4).

---

## Response to each question

**Q1. What happens between `POST /_bulk` and the `200 OK`?**

Pipeline (all synchronous before the 200):
1. Request received by the HTTP layer → routed to the primary shard's indexing thread
2. Documents processed by the internal Lucene index → written to the in-memory indexing buffer
3. Operations appended to the translog (in-memory translog buffer)
4. Translog fsynced to disk on the primary shard (with `durability: request`, the default)
5. If replicas exist: operation forwarded to each replica, replica translog fsynced
6. HTTP 200 returned to client

The document is NOT yet in a Lucene segment. It is in the in-memory buffer, waiting for the next refresh. The 200 only guarantees durability (translog on disk), not searchability.

Evidence: Finding 1.

**Q2. Is there async work after the 200?**

Yes, three background processes continue after every bulk 200:

- **Refresh** (every 1s by default): converts in-memory buffer to a new searchable Lucene segment in filesystem cache
- **Segment merge** (continuous, merge thread pool): consolidates many small segments into larger ones; on a 2-vCPU node, this is effectively single-threaded per shard; if it falls behind, it actively throttles new indexing writes
- **Flush** (auto, ~every 30 min or at 10 GB translog): writes segment data from filesystem cache to durable disk storage; clears the translog

All three consume CPU and I/O on the same 2 vCPUs that handle the write thread pool.

Evidence: Finding 2.

**Q3. How does the write thread pool work? How many parallel bulk requests does a 2-vCPU node accept?**

Write thread pool type: `fixed`. Size: number of allocated processors = **2 threads** on `t3.small.search`. Queue: 10,000. When queue fills, requests are rejected (HTTP 429/503, `es_rejected_execution`).

With 10 Sidekiq threads sending concurrent bulk requests: 2 are actively processing, 8 are queued. Each 155ms request ties up a thread for 155ms, then releases for the next queued request. At saturation, the effective write throughput is bounded by 2 threads × throughput/thread.

Evidence: Finding 3.

**Q4. Is bulk-100 cheaper or more expensive per document than 100 individual requests?**

Bulk is cheaper per document. The primary efficiency gain is translog fsyncs: 1 fsync for 100 docs (bulk) vs 100 fsyncs for 100 individual docs. Documented as unambiguous by both Elastic and AWS OpenSearch. The cost reduction is proportional to batch size.

Evidence: Finding 4.

**Q5. What is the documented sweet spot for bulk size on a 1GB heap cluster?**

AWS documents 3–5 MiB **per bulk request** as the starting point, not a doc count. At ~1 KB/doc for typical `deals` documents, this corresponds to ~3,000–5,000 docs per request — 30–50× larger than the current 100-doc batch. The current 100-doc batch is likely undersized relative to the AWS recommended starting point, meaning each request has disproportionate per-request overhead (network round trip, translog fsync) relative to the number of documents it carries.

Evidence: Finding 5.

**Q6. What is the real cost of `refresh_interval: 1s` vs `30s`?**

Each refresh creates a new Lucene segment. At `1s` during a 1h batch: up to 3,600 segments created. The merge thread pool must continuously consolidate these, competing with the write thread pool for the 2 available vCPUs. At `30s`: up to 120 segments — 30× fewer merge cycles, proportionally less CPU contention. AWS explicitly recommends `refresh_interval ≥ 30s` for all production indexes. The cost of `1s` refresh is not just CPU — it is the indirect effect on merge pressure, which can trigger the write throttling described in Finding 2.

Evidence: Finding 6.

**Q7. What is the theoretical capacity of `app-shared-001` (docs/s sustained)?**

No official AWS/OpenSearch figure exists for `t3.small.search`. Derived from documented heuristics:

- Write thread pool: 2 threads
- At 155ms observed avg latency (v3.31.0 degraded bulk): ~12.9 requests/s → ~1,290 docs/s (bulk-100)
- At 18ms (pre-degradation individual): ~111 requests/s → ~111 docs/s (individual), or ~11,100 docs/s if bulk-100 at the same latency
- Observed baseline (pre-v3.31.0): ~150 docs/s average over 1h, clearly not CPU-bound at that throughput
- Indexing buffer: 100 MB total (~20% of the per-shard optimal 512 MB) — buffer exhaustion forces extra segment flushes
- AWS warning: `t3.small` "can become unstable under sustained heavy load"

The cluster appears to be operating near or at its capacity boundary during the nightly batch. The "capacity" is not a fixed number — it degrades dynamically as merge pressure increases (segment backlog → write throttling).

Evidence: Findings 3, 5, 7.

**Q8. Does reverting to individual indexing ("kill bulk and go back to individual") improve, maintain, or worsen the situation?**

The evidence from Finding 8 indicates:

- Bulk is documented as cheaper per document (fewer fsyncs, lower per-document overhead)
- The deterioration correlates with v3.32.0 (loss of autoscaling) more than v3.31.0 (introduction of bulk)
- The 5xx explosion happened when the concurrency model changed (fixed 10 threads vs autoscaling 10–80 threads), not when bulk was introduced
- Reverting to individual indexing would restore the higher fsync rate (100 fsyncs per 100 docs vs 1), which is strictly worse from a cluster perspective
- The throughput per second in docs/s would decrease because individual requests have the same fixed overhead per request but carry 100× fewer documents

The evidence suggests reverting to individual indexing would **worsen** the situation from the cluster's perspective (more fsyncs, same throughput ceiling from the 2-thread write pool). The current performance problem is more consistent with write thread pool saturation combined with refresh/merge contention on 2 vCPUs, not with bulk API overhead.

Evidence: Findings 3, 4, 8.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Keep bulk-100 + fix concurrency (restore autoscaling or increase tasks) | Fewer fsyncs per doc; bulk is the documented efficient path | Does not address refresh/merge CPU contention on 2 vCPU | Findings 4, 8 |
| Increase bulk size (100 → 500 or 1000 docs) | More docs per fsync; approaches AWS's 3–5 MiB recommended range; fewer total requests | Larger requests take longer, holding write threads longer; one bad bulk = more docs retried | Findings 4, 5 |
| Set `refresh_interval: 30s` | 30× fewer segments per batch hour; 30× less merge pressure; AWS recommended | Deals indexed during batch not searchable for up to 30s | Findings 6, 7 |
| Disable `refresh_interval: -1` during batch + restore after | Eliminates refresh/merge CPU contention during bulk load entirely | Requires batch orchestration to manage interval; deals completely unsearchable during batch | Finding 6 |
| Revert to individual indexing | Eliminates the bulk-specific unknowns | More fsyncs per doc (strictly worse); does not address root cause (2-vCPU saturation) | Finding 8 |
| Keep bulk-100 + reduce concurrent Sidekiq threads (e.g., 3–4) | Stays within write pool (2 threads + small queue buffer); reduces CPU contention | Slower batch completion; may increase batch window beyond 1h | Finding 3 |
| Upgrade instance type (`r6g.large`: 2 vCPU, 16 GB RAM, 8 GB heap) | More heap → larger indexing buffer (800 MB vs 100 MB); more stable under load; AWS-recommended for small production | Cost increase; out of scope per engineer constraint | Finding 5, 7 |

---

## Hypothesis matrix

| Hypothesis | Evidence that sustains it | Evidence that contradicts it | Net assessment |
|---|---|---|---|
| **H_engenheiro_1**: sweet spot exists — batch 50 / threads 40 would work | Smaller batches stay within buffer and write pool more easily; fewer concurrent threads reduce queuing | 40 threads vs 2 write threads still creates 38-deep queue; bulk-50 is even further below the 3–5 MiB AWS target | Partially sustained: reducing threads helps; reducing batch size is counterproductive |
| **H_engenheiro_2**: cluster does work AFTER the 200 that the client doesn't see — "less threads" doesn't fully relieve the cluster | Confirmed: refresh (1s), merge (continuous), flush (auto) all run after 200; merge can throttle new indexing if it falls behind; CPU is shared between write pool and background tasks on 2 vCPU | None — this hypothesis is directly confirmed by Findings 1, 2 | **Confirmed**: there IS significant async work after every 200. The cluster workload does not stop when client stops sending requests |
| **Minha hipótese** (10 threads × bulk 100 ≠ 80 threads × bulk 100 because each bulk takes longer and saturates the few threads): | Partially correct: 2 write threads is the bottleneck regardless of whether 10 or 80 threads are sending from the client; the critical factor is that v3.32.0 changed from elastic (auto-scaling) to fixed 10 threads, losing the capacity flexibility; the 155ms latency spike per request is consistent with write thread saturation + background CPU contention | The hypothesis conflates client-side threads with server-side write threads; the cluster write pool is 2 regardless; "fewer client threads" primarily affects queuing pressure on the cluster, not the write pool capacity | **Partially confirmed**: the thread saturation analysis is directionally correct but the mechanism differs — the bottleneck is the 2-thread write pool + 2-vCPU budget shared with background work, not merely that each bulk takes longer |

---

## What remains uncertain

1. **Number of replicas on the `deals` index in production.** The PLAN-SPIKE.md shows `number_of_shards: 1` but does not confirm `number_of_replicas`. If replicas are present (OpenSearch default is 1), Finding 1 means the translog fsync happens on the primary **and** each replica before the 200 — doubling the I/O cost per request. Unverified without direct cluster inspection.

2. **Actual document size of `deals` index.** The 3–5 MiB bulk size recommendation from AWS depends on document size. Without knowing the actual serialized byte size of a `deals` document, the equivalence between 100-doc batches and the MiB target cannot be calculated precisely.

3. **Actual `refresh_interval` behavior with no active search requests.** The Elastic documentation states refresh only happens on indices that have received "one search request or more in the last 30 seconds." If the `deals` index receives no search queries during the 03:00–04:00 batch window, the refresh may be occurring at `1s` only when explicitly triggered, which would reduce but not eliminate the segment creation pressure. The exact CloudWatch `IndexingRate` vs `OpenSearchDomainRefreshCount` metrics for the batch window were not available.

4. **Whether v3.32.0's fixed-10-thread service uses `SIDEKIQ_THREADS=10` with all threads actively submitting concurrent bulk requests, or whether there is backpressure from the Rails/Sidekiq layer.** The timeline shows batch transbordou para 04h (47k 2xx vs 9.7k na terça), suggesting the batch completed but slower — consistent with queuing pressure, not total rejection.

5. **The `indices.memory.index_buffer_size` effective value on `app-shared-001`.** AWS OpenSearch Service may override the default 10% setting via Auto-Tune. If Auto-Tune is enabled (default for new domains), it may have already adjusted the buffer size. Unverified.

---

## Suggested options for the engineer and main

- **Option A — Fix concurrency first, keep bulk:** restore the ability for the consumer to scale dynamically (e.g., add Application Auto Scaling to `worker-deal-indexation`, or merge back into `worker-commission`). This addresses the most recent regression (v3.32.0) without touching the bulk implementation. Bulk-100 is not the cause of the 5xx explosion.

- **Option B — Add `refresh_interval: 30s` immediately (independent of Option A):** this is a 1-API-call change (`PUT /deals/_settings`) that directly reduces the merge pressure on the 2-vCPU node during the batch window. AWS explicitly recommends it. Low risk.

- **Option C — Increase bulk batch size toward the 3–5 MiB AWS target:** at ~1 KB/doc, 100 docs ≈ 0.1 MiB — 30–50× below the recommended floor. Increasing to 500–1000 docs reduces the per-bulk overhead (fewer fsyncs, fewer write thread acquisitions per N docs indexed) while staying within the documented safe range.

- **Option D — Limit Sidekiq concurrency to 3–4 threads (from 10):** aligns client-side concurrency with the 2-thread write pool + small queue, reducing queuing-induced latency spikes. Reduces throughput per instance but stabilizes the batch.

- **Option E — Revert to individual indexing:** the evidence does not support this as a solution. It is strictly worse per document (100× more fsyncs) and does not address the root cause.

(No recommendation — the engineer and main decide.)
