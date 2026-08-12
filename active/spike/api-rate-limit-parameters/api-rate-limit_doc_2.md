# Auxiliary source 2 — Rails / Puma throughput and sizing (verbatim excerpts)

Fetched 2026-08-11. Each entry records the URL and the literal strings confirmed present on the page.

---

## Puma deployment documentation

URL: https://github.com/puma/puma/blob/master/docs/deployment.md

- "**TL:DR;**: 80% of Puma apps will end up deploying \"pods\" of 4 workers, 5 threads each, 4 vCPU and 8GB of RAM."
- "Set your config with the following process: Use cluster mode and set `workers :auto`...to match the number of CPU cores on the machine (minimum 2, otherwise use single mode!)."
- "Set the number of threads to desired concurrent requests/number of workers. Puma defaults to 5, and that's a decent number."
- "Worker counts should be somewhere between 4 and 32 in most cases."
- "Don't run less than 4 processes per pod if you can"
- "Most Puma processes will use about ~512MB-1GB per worker, and about 1GB for the master process"
- "Unless you have a very I/O-heavy application (50%+ time spent waiting on IO), use the default thread count (5 for MRI)."

The page carries no requests-per-second capacity figure.

---

## Rails Guides — Tuning Performance for Deployment

URL: https://guides.rubyonrails.org/tuning_performance_for_deployment.html

- "The throughput is the measure of how many requests per second the server can handle"
- "latency is the measure of how long individual requests take (also referred to as response time)"
- "thread-based concurrency allows for increased throughput by concurrently processing web requests whenever they do I/O operations."
- "Increasing the threads will improve throughput up to a point, but worsen latency."

The page carries no concrete throughput numbers, no worked example, and no mention of Little's Law.

---

## Speedshop — "Scaling Ruby Apps to 1000 Requests per Minute"

URL: https://www.speedshop.co/blog/scaling-ruby-apps-to-1000-rpm/

- "At the time, Twitter was still fully a Rails app. In that presentation, the engineer gave the following numbers: * 600 requests/second"
- "In that presentation, he claimed: * Shopify receives 833 requests/second."
- "Here's some numbers from them: * Envato receives 115 requests per second"
- "All of these web servers can handle 1000s of requests per minute, meaning that it takes them less than 1ms to actually handle a request."

---

## Ruby on Rails Foundation — Shopify page

URL: https://rubyonrails.org/foundation/shopify

- "During Black Friday 2025, Shopify's Rails monolith powered $14.6 billion in merchant sales, handling peak loads of **489 million requests per minute** on the edge and over **53 million database queries per second**."
