# SPIKE — Application-Managed Refresh: Ticker vs Per-Commission

## Investigation question

The team has already decided to disable ES auto-refresh (`refresh_interval: -1`) on `app-shared-001` (2× `t3.small.search`, 2 vCPU, ~1 GB heap) and manage refresh from the application. The remaining open question is **who triggers the manual refresh and at what cadence**:

- **Option Ticker:** 1 Sidekiq job running every 30 s calls `POST /{index}/_refresh` → ~120 refreshes/h, rate independent of batch volume
- **Option Per-Commission:** each commission's final bulk batch triggers `POST /{index}/_refresh` → ~2,000 refreshes/h during the nightly batch

Eight sub-questions:
1. Which companies have documented this pattern in production (with links and literal quotes)?
2. Which pattern did they choose (Ticker or Per-Event), and where is that stated?
3. What volumetry do they support (docs/s, refreshes/h, instance types, shards, index size)?
4. How do they handle "many refreshes = many segments" (the Ticker advantage)?
5. What trade-offs have been specifically documented for this decision?
6. Are there documented FAILURE cases — companies that tried and abandoned this approach?
7. Does official Elastic/AWS documentation endorse `refresh_interval: -1` as a steady-state production setting (not just initial load)?
8. Is there a documented THIRD pattern beyond Ticker and Per-Event?

**Non-duplication scope:** this spike does not duplicate findings already in `SPIKE.md` (bulk internals, write thread pool, t3.small capacity heuristics, merge pressure) or `SPIKE-INGEST-READ-PATTERNS.md` (mget real-time, wait_for + max_refresh_listeners ceiling, alias swap, People.ai case, force_merge). Findings here are complementary.

---

## Sources consulted

- `https://opensearch.org/blog/optimize-refresh-interval/` — AWS Solutions Architects Chris Sharkey and Samit Kumbhani; official endorsement of batch-end-single-refresh pattern
- `https://www.elastic.co/docs/reference/elasticsearch/rest-apis/refresh-parameter` — Elastic reference documentation; wait_for behavior with refresh_interval=-1
- `https://www.elastic.co/search-labs/blog/elasticsearch-refresh-costs-serverless` — Elastic internal production evidence; per-refresh segment cost in Serverless
- `https://www.elastic.co/blog/refreshing_news` — Nik Everett (Elastic core engineer), 2016; three-strategy trade-off breakdown
- `https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-refresh` — Elastic API reference; resource-intensity warning
- `https://discuss.elastic.co/t/refresh-wait-for-taking-unexpectedly-long/83691` — Elastic community forum; production evidence of wait_for latency under write-heavy load
- Searches for Shopify, Stripe, Discord, GitHub, Slack, Spotify, Cloudflare engineering blog posts about application-managed refresh — no qualifying result found (see Finding G)

---

## Findings

### Finding A — AWS official documentation endorses batch-end single-refresh (not Ticker, not Per-Commission)

**Evidence:**
> "You have the option to disable automatic refreshes prior to initiating a known write-intensive workload and then manually trigger a refresh upon its completion. For instance, if you're uploading new data to OpenSearch daily through a batch process, it might be beneficial to disable automatic refreshes just before the batch process begins. After the process concludes, you can manually initiate a refresh."

**Source:** `https://opensearch.org/blog/optimize-refresh-interval/` — AWS Solutions Architects Chris Sharkey and Samit Kumbhani

**Significance:** The only official AWS/OpenSearch source addressing the nightly-batch scenario explicitly endorses a **single refresh at batch completion**, not a periodic ticker and not a per-event refresh. This is the closest analogue to the `app` batch: upload data for a known window, then refresh once at the end. The pattern maps to the Ticker cadence (infrequent, application-triggered) but is driven by batch completion rather than a fixed wall-clock interval.

**Answers research questions 1, 2, 3, 7, 8:**
- Q1/Q2: AWS is the only named source; the endorsement is implicit (the example is the recommendation, not a case study with volumetry metrics)
- Q3: No instance types or volumetry specified in this source
- Q7: The full AWS OpenSearch Best Practices document (`https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html`, "Tune refresh intervals" section) states only: "We recommend setting the refresh_interval parameter for all of your indexes to 30 seconds or more." No guidance for -1 as steady-state in that document. The batch-disable guidance lives only in the blog post above; it is framed as temporary (disable before batch, re-enable or refresh after).
- Q8: The pattern described is a **third shape** — batch-completion-triggered single refresh — distinct from both the wall-clock Ticker and the per-commission approach.

**Verification block:**
URL fetched: `https://opensearch.org/blog/optimize-refresh-interval/`
Verbatim quote checked: "You have the option to disable automatic refreshes prior to initiating a known write-intensive workload and then manually trigger a refresh upon its completion."
Quote substring confirmed: present in fetched content.

---

### Finding B — `refresh=wait_for` with `refresh_interval: -1` creates indefinite hangs (critical interaction)

**Evidence:**
> "If the refresh interval is set to `-1`, disabling the automatic refreshes, then requests with `refresh=wait_for` will wait indefinitely until some action causes a refresh."

**Source:** `https://www.elastic.co/docs/reference/elasticsearch/rest-apis/refresh-parameter` — Elastic reference documentation

**Significance:** If any indexing call in the `app` codebase currently passes `refresh=wait_for` (or if the gem default or any future code path uses it) while `refresh_interval: -1` is active, the Sidekiq thread will hang permanently until an external refresh fires. With the Ticker pattern, the stuck thread will be rescued at the next 30 s tick. With the Per-Commission pattern, the thread would be rescued at the end of the owning commission — but only if the Per-Commission code path fires a refresh at all. If `refresh_interval: -1` is set without a matching managed-refresh path, `wait_for` creates silent, permanent thread exhaustion.

**Answers research questions 5 (documented trade-off) and 6 (failure scenario):**
- Q5: The interaction between `wait_for` and `refresh_interval: -1` is a documented trade-off that is invisible unless the team audits every indexing call site.
- Q6: Not a documented abandonment case, but a documented mechanical failure mode with production consequences (thread exhaustion).

**Verification block:**
URL fetched: `https://www.elastic.co/docs/reference/elasticsearch/rest-apis/refresh-parameter`
Verbatim quote checked: "If the refresh interval is set to -1, disabling the automatic refreshes, then requests with refresh=wait_for will wait indefinitely until some action causes a refresh."
Quote substring confirmed: present in fetched content.

---

### Finding C — Elastic Serverless production evidence: each refresh creates one segment object with a direct cost (linear with refresh count)

**Evidence:**
> "Every refresh operation created a new object in the object store, resulting in an object store PUT request that incurs associated costs."

> "With enough refreshes, object store costs could surpass the cost of the hardware itself."

**Source:** `https://www.elastic.co/search-labs/blog/elasticsearch-refresh-costs-serverless` — Elastic Search Labs (Elastic's internal production Serverless infrastructure)

**Significance:** This is Elastic's own internal production evidence that refresh count is linearly proportional to infrastructure cost and merge/storage pressure. On Serverless the currency is object store PUT requests; on `t3.small.search` the currency is segment files and merge thread CPU. The principle is identical: more refreshes = more segments = more merge work = more CPU contention on a 2-vCPU machine. The Per-Commission path (~2,000 refreshes/h) creates 2,000 segments/h during the nightly batch; the Ticker (~120 refreshes/h) creates 120 segments/h. The 16.7× difference in segment creation rate is the core Ticker advantage this source corroborates.

**Answers research questions 4 and 5:**
- Q4: The answer to "how do you handle many refreshes = many segments" is: reduce refresh frequency (Ticker) rather than increasing it (Per-Commission). This source provides the production evidence for that asymmetry.
- Q5: The documented trade-off is segment/cost proportionality with refresh rate.

**Note:** The Serverless architecture is structurally different from `t3.small.search` (object store vs local disk), but the underlying Lucene behavior — one new segment per refresh — is identical. The cost manifestation differs; the segment-creation mechanic does not.

**Verification block:**
URL fetched: `https://www.elastic.co/search-labs/blog/elasticsearch-refresh-costs-serverless`
Verbatim quote checked: "Every refresh operation created a new object in the object store, resulting in an object store PUT request that incurs associated costs."
Second quote checked: "With enough refreshes, object store costs could surpass the cost of the hardware itself."
Both substrings confirmed: present in fetched content.

---

### Finding D — Elastic core engineer (Nik Everett, 2016): documented trade-offs of three explicit-refresh strategies

**Evidence:**
> "This has the advantage of being something you can do totally asynchronously." [periodic/implicit refresh]

> "This has the advantage of being pretty quick...it has the disadvantage of creating small segments that are inefficient to create, search, and merge." [refresh=true / force refresh]

> "This has the advantage of being correct without creating inefficient segments. It has the disadvantage of having to wait for the refresh." [refresh=wait_for]

**Source:** `https://www.elastic.co/blog/refreshing_news` — Nik Everett, Elastic core engineer, 2016 (official Elastic engineering blog)

**Significance:** The only official Elastic source that directly documents the trade-off space for choosing between refresh strategies. The Ticker pattern corresponds to "periodic/implicit refresh" made application-controlled: it is asynchronous, predictable, and does not force the caller to wait. The Per-Commission pattern corresponds to "force refresh" per event: the commission caller either blocks (refresh=true, adds latency) or creates a new small segment immediately (also refresh=true, adds merge pressure). Neither the Ticker nor the Per-Commission approach maps exactly to `wait_for`, but the segment-efficiency concern documented for force-true applies directly to Per-Commission.

**Answers research question 5:**
- The trade-offs documented here are the closest official taxonomy available for the Ticker vs Per-Commission choice.

**Verification block:**
URL fetched: `https://www.elastic.co/blog/refreshing_news`
Verbatim quote checked (periodic): "This has the advantage of being something you can do totally asynchronously."
Verbatim quote checked (force): "it has the disadvantage of creating small segments that are inefficient to create, search, and merge."
Verbatim quote checked (wait_for): "This has the advantage of being correct without creating inefficient segments. It has the disadvantage of having to wait for the refresh."
All three substrings confirmed: present in fetched content.

---

### Finding E — Official Elastic API reference: explicit refreshes are resource-intensive; periodic refresh is preferred

**Evidence:**
> "Refreshes are resource-intensive. To ensure good cluster performance, it's recommended to wait for Elasticsearch's periodic refresh rather than performing an explicit refresh when possible."

**Source:** `https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-refresh` — Elastic API reference documentation

**Significance:** The official API reference explicitly cautions against the Per-Commission pattern (explicit `POST /_refresh` per commission event) and recommends periodic refresh — which is the Ticker pattern in application-managed form. The recommendation is "when possible"; in the `app` case with `refresh_interval: -1`, periodic refresh is only possible if the application implements it (Ticker). The Per-Commission approach is the exact anti-pattern this documentation warns against.

**Answers research question 7:**
- Official Elastic documentation does not endorse `refresh_interval: -1` as steady-state. The closest guidance is: use periodic refresh (implicit or application-managed via Ticker), avoid explicit per-event refreshes.

**Verification block:**
URL fetched: `https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-indices-refresh`
Verbatim quote checked: "Refreshes are resource-intensive. To ensure good cluster performance, it's recommended to wait for Elasticsearch's periodic refresh rather than performing an explicit refresh when possible."
Quote substring confirmed: present in fetched content.

---

### Finding F — Production evidence: `refresh=wait_for` 40× slower than configured interval under write-heavy load

**Evidence:**
> "wait_for: 4s"

> "My guess, given that `refresh=true` finishes must faster than `refresh=wait_for`'s time + `refresh_interval` is that the refresh pool is stuffed."

**Source:** `https://discuss.elastic.co/t/refresh-wait-for-taking-unexpectedly-long/83691` — Elastic community forum; production incident report with expert analysis

**Significance:** With `refresh_interval: 100ms` (10× more frequent than any normal configuration), `wait_for` took 4 s — 40× longer than the configured interval. The analysis is refresh thread pool saturation under concurrent write pressure. On `t3.small.search` with `refresh_interval: -1` and Per-Commission refresh (2,000/h), the refresh thread pool would see 2,000 explicit `POST /_refresh` calls per hour during the nightly batch. Under that load, threads queuing on `wait_for` would face indefinite waits per Finding B, and explicit refresh calls would compete for the same thread pool resources. The Ticker (120/h) reduces this contention by a factor of ~16.7×.

**Answers research questions 5 and 6:**
- Q5: Thread pool saturation under concurrent write-refresh interleaving is a documented trade-off specific to explicit per-event refresh.
- Q6: Not a documented abandonment, but a production performance degradation case that maps to the Per-Commission concern.

**Verification block:**
URL fetched: `https://discuss.elastic.co/t/refresh-wait-for-taking-unexpectedly-long/83691`
Verbatim quote checked: "wait_for: 4s"
Verbatim quote checked: "My guess, given that refresh=true finishes must faster than refresh=wait_for's time + refresh_interval is that the refresh pool is stuffed."
Both substrings confirmed: present in fetched content.

---

### Finding G — No hyperscaler case study found for Ticker or Per-Commission as a named production pattern

**Evidence:** Systematic web searches for engineering blog posts from Spotify, Shopify, Stripe, GitHub, Cloudflare, Discord, and Slack specifically addressing `refresh_interval: -1` with application-managed refresh returned no qualifying result.

- Discord's engineering blog covers their migration from MongoDB to Cassandra and their Elasticsearch deployment at 40+ clusters and billions of messages — no mention of `refresh_interval` management strategy.
- SoundCloud's "How SoundCloud Does Large-Scale Indexing" describes using `refresh_interval: -1` for a one-hour reindex operation on a 30-node cluster with 64 GB RAM per node — a temporary bulk-load pattern, not steady-state application-managed refresh.
- No Shopify, Stripe, GitHub, or Slack engineering post was found addressing this specific architectural decision.

**Source:** Multiple web searches (searches performed, no qualifying URL found; the sources above represent the closest results examined)

**Significance:** The community does not document a Ticker vs Per-Event named pattern for ongoing application-managed refresh. The published convergent pattern across official sources (Finding A) is batch-end-single-refresh (disable before batch, single refresh at completion). The absence of hyperscaler case studies is itself informative: no company appears to be running 2,000 explicit refreshes/h as a documented production choice.

**Answers research questions 1, 2, 3, 6:**
- Q1/Q2: No company documented.
- Q3: No volumetry comparison available from public case studies.
- Q6: No documented abandonment cases found — but also no documented adoption of Per-Commission at scale.

**Verification block:**
No URL to verify — this is a negative finding based on search results. Searches conducted for: "refresh_interval -1 application managed steady state production", "Shopify elasticsearch refresh interval engineering blog", "Stripe elasticsearch refresh interval", "Discord elasticsearch refresh_interval", "GitHub elasticsearch refresh interval application", "Slack elasticsearch refresh strategy production".

---

## Responses to the 8 research questions

| # | Question | Finding(s) | Answer |
|---|---|---|---|
| 1 | Companies that documented this pattern | G | None found. The community does not document Ticker vs Per-Event as a named pattern. |
| 2 | Which pattern they chose | A, G | AWS/OpenSearch endorses batch-end-single-refresh (a third shape, Finding A). No case study for Ticker or Per-Commission as an ongoing steady-state choice. |
| 3 | Volumetry they support | G | Not found. SoundCloud used `-1` for a 1h reindex on 30 nodes (64 GB each) — not comparable to `t3.small`. |
| 4 | How they handle many refreshes = many segments | C | Reduce refresh frequency (Ticker). Elastic Serverless internal evidence shows linear segment/cost proportionality with refresh count. |
| 5 | Documented trade-offs | B, C, D, E, F | (a) wait_for + `-1` = indefinite hang; (b) each refresh = one segment = merge pressure; (c) force-true creates small inefficient segments; (d) refresh thread pool saturation under high-frequency explicit refresh. |
| 6 | Documented FAILURE cases | B, F | Not explicit abandonment stories. Documented failure modes: indefinite wait_for hangs (Finding B); 40× latency degradation from thread pool saturation (Finding F). |
| 7 | Official docs endorse `-1` as steady-state | A, E | No. Both AWS (Finding A) and Elastic (Finding E) position `-1` as a temporary setting. The recommended steady-state is periodic refresh (Ticker equivalent at 30 s+). |
| 8 | Third pattern beyond Ticker and Per-Event | A | Yes: **batch-completion-triggered single refresh** — disable before batch, single `POST /_refresh` after batch completes. This is the AWS-endorsed shape and structurally closest to a coordinator job in Sidekiq. |

---

## Trade-offs surfaced

| | Ticker (30 s fixed interval) | Per-Commission (~2,000/h during batch) | Batch-Completion (single refresh at batch end) |
|---|---|---|---|
| **Segment creation rate** | ~120 segments/h (bounded, predictable) | ~2,000 segments/h during batch (16.7× higher) | 1 segment per batch run (minimum possible) |
| **Merge pressure on t3.small** | Low; merge thread (1 per shard on 2-vCPU) has idle windows | High; 2,000 segments/h forces continuous merging, throttles new indexing | Minimal; merge runs after batch, not concurrent |
| **Search freshness during batch** | ~30 s lag per commission (last refresh tick) | ~0 s lag per commission (refresh at commission end) | No freshness during batch; fresh only at batch end |
| **wait_for rescue** | All stuck threads rescued at next 30 s tick (Finding B) | Rescued per-commission — only if that commission fires a refresh | Only rescued at batch end; intermediate wait_for hangs for full batch duration |
| **Operational complexity** | 1 additional Sidekiq periodic job; must track if batch is running to suppress or pass through | Must ensure every commission code path that terminates fires exactly 1 refresh; no short-circuit paths | Requires a batch-completion detector (coordinator job); batch must signal when it is fully done |
| **Official alignment** | Closest to "wait for periodic refresh" (Finding E, recommended) | Closest to "force refresh per event" (Finding D, explicitly cautioned against) | Exactly endorsed by AWS (Finding A) |
| **Interaction with `wait_for`** | Safe: Ticker fires every 30 s; stuck threads rescued | Risky: threads on `wait_for` for commission N wait until commission N fires its own refresh (may never happen if commission errors before its refresh call) | Risky for intermediate threads: full batch duration hang if any path uses `wait_for` |
| **Source** | Findings C, D, E, F | Findings C, D, E, F | Finding A |

---

## What remains uncertain

- Whether any current `app` indexing call site uses `refresh=wait_for` — needs a codebase audit before disabling auto-refresh (Finding B is a hard blocker if any such call exists and is not accounted for).
- The exact nightly batch topology: whether all commissions are dispatched in parallel (all ~2,000 at once) or sequentially (one at a time). The Per-Commission refresh rate of ~2,000/h assumes parallel dispatch; sequential dispatch would lower the instantaneous segment creation rate.
- Whether a "coordinator job" (Finding A's batch-completion shape) is architecturally feasible given the current Sidekiq job structure — requires the coordinator to reliably know when all ~2,000 commission jobs have finished.
- How long the nightly batch takes end-to-end: if it completes in 20 min rather than 1 h, the effective refresh rates are all proportionally higher during that window.
- Whether OpenSearch (the AWS fork) has diverged from Elasticsearch in any refresh-internals behavior covered by these sources — all official Elastic sources were confirmed against Elastic documentation, not OpenSearch-specific documentation.

---

## Suggested options for the engineer

Three architecturally distinct options surface from the evidence:

**Option A — Ticker (Sidekiq periodic job, 30 s)**
A single Sidekiq periodic job calls `POST /{index}/_refresh` every 30 s regardless of batch state. Rate: ~120 refreshes/h (bounded). Segment creation bounded at ~120/h. `wait_for` calls rescued at most 30 s after any hang. Directly aligned with Elastic's "wait for periodic refresh" recommendation (Finding E). Does not require knowledge of batch topology or per-commission signaling. Trade-off: 30 s maximum search lag per commission; Ticker fires even when no batch is running (wasted refreshes at night when idle).

**Option B — Per-Commission refresh**
Each commission job calls `POST /{index}/_refresh` after its final bulk. Rate: ~2,000 refreshes/h during nightly batch. Segment creation at ~2,000/h — directly warned against by Findings C, D, and E. Rescue for `wait_for` depends on per-commission code path completeness (Finding B). The trade-off: best search freshness per commission; worst merge pressure; highest risk on t3.small.

**Option C — Batch-completion-triggered single refresh (AWS-endorsed shape)**
A coordinator job detects when all ~2,000 commission jobs have finished, then fires exactly 1 `POST /{index}/_refresh`. Rate: 1 refresh per batch run. Segment creation: 1 per batch (minimum possible). Aligned with Finding A (AWS official guidance). Trade-off: zero search freshness during the batch window (~1 h); the coordinator must be reliable (if it fails, no refresh fires); `wait_for` hangs for the full batch duration for any intermediate paths using it. Requires solving the "how does the coordinator know the batch is done?" problem.

(No recommendation — options surface the documented trade-offs; the engineer decides.)
