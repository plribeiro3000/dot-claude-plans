# SPIKE — Ruby web server: stay on Puma, or migrate to Falcon / Pitchfork?

## Investigation question

4Shark serves its Rails backends with Puma. Falcon (fiber-based, `socketry/falcon`) and Pitchfork (Shopify's reforking Unicorn fork) are the two modern alternatives being discussed. What is the Ruby community using and recommending as of September 2026, where is each server strong, and does anything justify moving 4Shark off Puma?

## Context

- Trigger: an engineer noticed `socketry/falcon` and asked whether the community is migrating to it.
- 4Shark shape that bears on the answer: the Rails backends push heavy work to Sidekiq workers (the `Computation` chained-processing pattern), so the web tier serves relatively light HTTP. This is the workload profile where Puma's threads-plus-processes balance is the intended fit and where neither alternative pays for itself.

## Sources consulted

- https://www.deployhq.com/blog/ruby-application-servers-in-2025-a-complete-performance-and-architecture-guide — recommends Puma as the default; provides a synthetic benchmark table.
- https://blog.codeminer42.com/what-puma-falcon-and-pitchfork-teach-you-about-ruby-concurrency/ — concurrency model of each server (threads / processes / fibers), strengths and weaknesses; deliberately gives no recommendation.
- https://byroot.github.io/ruby/performance/2025/03/04/the-pitchfork-story.html — Pitchfork's author (Jean Boussier / byroot, Shopify Ruby core) on who should and should not adopt Pitchfork.
- https://github.com/Shopify/pitchfork/blob/master/docs/WHY_MIGRATE.md — Shopify's own "why you probably should not migrate" document.
- https://railsatscale.com/2023-10-23-pitchfork-impact-on-shopify-monolith/ — measured production impact of Pitchfork reforking at Shopify (~30% memory, ~9% latency).
- https://www.rubyevents.org/talks/understanding-ruby-web-server-internals-puma-falcon-and-pitchfork-compared — RailsConf 2025 talk framing the three as three architectural choices.
- https://jetthoughts.com/blog/falcon-web-server-async-ruby-in-production/ — Falcon production-maturity concerns (ActiveRecord per-thread pool contention, async debugging skill).
- https://github.com/socketry/falcon/discussions/186 — Falcon/Rails/ActiveRecord limitations discussion.
- https://blog.saeloun.com/2026/05/09/rails-8-thruster-http2-proxy-server/ — Rails 8 adds Thruster in front of Puma; Puma stays the app server.

## Findings

### Finding 1: Puma remains the default and the community baseline

Puma is the default application server generated in the Rails Gemfile and the most widely deployed in the ecosystem. The 2025 DeployHQ guide states it directly and frames every other server as measured against it.

**Source:** https://www.deployhq.com/blog/ruby-application-servers-in-2025-a-complete-performance-and-architecture-guide — "Puma is the default application server for Rails and the most widely deployed in the ecosystem."

**Significance:** There is no community migration away from Puma. Puma is the reference point the alternatives are compared to, not a legacy option being replaced.

**Verification:** URL fetched via WebFetch / quote returned by the fetch as the guide's stated default recommendation.

### Finding 2: The three servers are three concurrency models for three workload shapes

The consistent 2025/2026 framing: Puma is the case for threads, Pitchfork the case for processes, Falcon the case for fibers. Puma forks one worker per core and runs a thread pool inside each worker; Pitchfork forks single-request processes and adds reforking to cut memory; Falcon runs an event loop spawning a fiber per connection that suspends on I/O.

**Source:** https://blog.codeminer42.com/what-puma-falcon-and-pitchfork-teach-you-about-ruby-concurrency/ — Puma "Forks one worker per CPU core, then runs a thread pool inside each worker"; Falcon "uses an event loop to spawn fibers per connection with automatic scheduler-based suspension on I/O"; Pitchfork "Uses 'refork' to promote warmed workers into molds".

**Significance:** Choosing a server is choosing for a workload profile, not upgrading to a newer product. CPU-bound work parallelizes under Puma and Pitchfork; a single Falcon worker runs one fiber of Ruby at a time, so it does not help CPU-bound requests.

**Verification:** URL fetched via WebFetch / concurrency-model descriptions returned per server.

### Finding 3: Falcon's advantage is I/O-bound concurrency, and its ecosystem is still uneven

Falcon can outperform Puma by 3–4x at 500+ concurrent connections doing external I/O, because fibers do not block during I/O waits. The reservations are consistent across sources: the async win only materializes if the I/O actually yields, and ActiveRecord's per-thread connection pool creates contention under fibers (worst case, one connection per thread with every fiber on that thread contending for it). Operating Falcon also requires async/fiber debugging skill that Puma does not.

**Source (performance):** https://www.deployhq.com/blog/ruby-application-servers-in-2025-a-complete-performance-and-architecture-guide — Falcon 9,800 req/s vs Puma 7,200 req/s in the synthetic benchmark (AWS c5.xlarge, Ruby 3.3); recommended for "I/O-heavy applications, real-time features (WebSockets, streaming)".

**Source (maturity):** https://jetthoughts.com/blog/falcon-web-server-async-ruby-in-production/ — ecosystem maturity is uneven, and ActiveRecord's explicit per-thread resource pools create contention under fibers.

**Significance:** Falcon is the right tool for a web tier bottlenecked on many concurrent connections waiting on external I/O (mass WebSocket, per-request external-API waits). It is not a general Puma replacement, and on a conventional ActiveRecord Rails backend much of the theoretical gain does not appear.

**Verification:** Both URLs fetched via WebFetch / benchmark figures and ActiveRecord-contention statement returned.

### Finding 4: Pitchfork's own author says most applications should not migrate

Pitchfork is a Shopify fork of Unicorn adding reforking. Its author states he never intended it as more than an opinionated Unicorn fork for specific needs, and wrote a document explaining why most teams should not migrate. Reforking's benefit comes with fork-safety bugs that are hard to debug; the target is large monoliths with dedicated infrastructure teams.

**Source:** https://byroot.github.io/ruby/performance/2025/03/04/the-pitchfork-story.html — byroot: "never really intended Pitchfork to be more than a very opinionated fork of Unicorn, for very specific needs"; "I even wrote a long document essentially explaining why you probably don't want to migrate to Pitchfork"; reforking's "fork-safety issues can lead to pretty catastrophic bugs that can be very hard to debug".

**Significance:** Pitchfork is a memory-optimization for large monoliths, not a general recommendation. Adopting it below that scale takes on reforking's operational complexity without the memory pressure that justifies it.

**Verification:** URL fetched via WebFetch / the three quotes returned as the author's stated position.

### Finding 5: Pitchfork's measured production gain at Shopify is memory, and it depends on frequent deploys

At Shopify, migrating from Unicorn to Pitchfork produced roughly 30% memory reduction and about 9% latency reduction — but the memory reduction dropped to 10–12% on weekends, when the application is deployed infrequently. Reforking depends on frequent deploys re-warming the worker molds.

**Source:** https://railsatscale.com/2023-10-23-pitchfork-impact-on-shopify-monolith/ — "~9% latency reduction across the board"; memory "reduction is roughly 30%, but only 10-12% during weekends when the application is infrequently deployed".

**Significance:** The headline memory number is conditional on Shopify's deploy cadence and monolith size. A smaller application with fewer deploys realizes less of it, which further weakens the case for adopting Pitchfork outside that context.

**Verification:** URL fetched via WebFetch / both figures and the weekend caveat returned.

### Finding 6: Rails 8's direction is Thruster in front of Puma, not a new app server

Rails 8 ships Thruster in the default Docker setup, giving Puma HTTP/2, asset caching, compression, and X-Sendfile support. Puma stays the application server; Thruster is a reverse-proxy layer in front of it.

**Source:** https://blog.saeloun.com/2026/05/09/rails-8-thruster-http2-proxy-server/ — Rails 8 adds Thruster as the default HTTP/2 proxy in front of Puma; Puma remains the app server.

**Significance:** The framework's own answer to "Puma needs more" in 2026 is a proxy layer in front of Puma, not a replacement server. For 4Shark, Thruster is the first thing to evaluate if the web tier ever needs HTTP/2 or compression — before considering a server change.

**Verification:** URL fetched via WebSearch summary / Thruster-in-front-of-Puma role stated.

## Trade-offs surfaced

| Server | Model | Strong at | Weak at | Maturity | Source |
|--------|-------|-----------|---------|----------|--------|
| Puma | Threads + processes | General-purpose, balanced memory/throughput | Thousands of long-lived connections (thread-pool ceiling) | Highest; Rails default | deployhq, codeminer42 |
| Falcon | Fibers | Massive I/O-bound concurrency (WebSocket, streaming, external-API waits) | CPU-bound work; ActiveRecord per-thread pool contention; async debugging | Evolving, uneven ecosystem | deployhq, jetthoughts, falcon#186 |
| Pitchfork | Processes + reforking | Memory + latency on large monoliths | Fork-safety debugging complexity; gains depend on deploy frequency | Niche (large-monolith tool) | byroot, railsatscale |
| Unicorn | Processes | Simple isolation; proven at scale (GitHub) | High memory, no in-process concurrency | Legacy; superseded by Pitchfork for new work | codeminer42, byroot |

## Conclusion for 4Shark

Stay on Puma. The community has not moved off it; it is the baseline the alternatives are benchmarked against and the Rails 8 default. Falcon and Pitchfork are workload-specific tools:

- Falcon would only pay off if the 4Shark web tier were bottlenecked on many concurrent connections held open waiting on I/O — which the Sidekiq-offloaded architecture does not produce — and the ActiveRecord per-thread contention would erode the gain anyway.
- Pitchfork is a large-monolith memory tool whose own author recommends against migrating below that scale.

If web-container memory pressure ever appears, the first steps are tuning Puma workers/threads and evaluating Thruster (Rails 8) in front of Puma — before changing servers.

## What remains uncertain

- The DeployHQ benchmark is synthetic (AWS c5.xlarge, Ruby 3.3) and does not model a real Rails app with a database; treat its figures as order-of-magnitude only. No 4Shark-specific benchmark was run.
- Falcon's ecosystem is described as "improving but uneven" — the exact set of gems that are fiber-safe today was not enumerated in this spike.

## Suggested options for the engineer

- Option A: Keep Puma; revisit only if a concrete I/O-bound-concurrency or memory-pressure symptom appears on the web tier.
- Option B: If HTTP/2 / compression / asset-serving needs arise, evaluate Thruster in front of Puma (Rails 8 direction) before any server change.
- Option C: Reserve Falcon for a future, isolated real-time/streaming service if one is ever built — as a purpose-fit choice for that service, not a fleet-wide migration.

---

> **Authoring:** time-boxed research to reduce uncertainty. Surfaces findings + options; the engineer chooses. Every claim cites its source (URL + quote). Written by the main session from research conducted in-session, not delegated to a subagent.
