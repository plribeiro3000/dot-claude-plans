# SPIKE — API rate limit parameters: 150 req/s per client, 10 s block

## Investigation question

Two questions, and nothing else:

1. **Is a per-client limit of 150 requests/second reasonable for a Rails application?** Two halves: (1a) what a Rails/Puma application typically sustains in requests per second, so the 150 figure can be placed on an order-of-magnitude scale against the application's own capacity; (1b) what per-caller rate limits real, named public APIs actually publish, so the 150 figure can be placed against industry practice.
2. **Is a 10-second block duration something people actually use** after a client breaches a rate limit?

The configuration these numbers come from is a Cloudflare rate-limiting rule on `/api`, keyed on client IP: 1500 requests per 10-second period (150 req/s), block action, 10-second block duration. The application behind it is a Rails JSON API. The rule as captured is in `api-rate-limit_excerpt_1.tf`.

## Sources consulted

- `api-rate-limit_doc_1.md` — verbatim published per-caller limits from GitHub, Stripe, Shopify, Slack, Discord, Atlassian and Cloudflare's own API
- `api-rate-limit_doc_2.md` — verbatim Rails/Puma throughput and sizing statements (Puma deployment doc, Rails Guides, Speedshop, Ruby on Rails Foundation)
- `api-rate-limit_doc_3.md` — verbatim Cloudflare rate-limiting duration values and published example configurations
- `api-rate-limit_doc_4.md` — verbatim Rack::Attack examples and fail2ban shipped defaults
- `api-rate-limit_doc_5.md` — verbatim nginx `limit_req` and AWS WAF rate-based rule behavior
- `api-rate-limit_excerpt_1.tf` — the rule under review, copied for reference

---

## Question 1 — Is 150 req/s per client reasonable for a Rails application?

### 1a. What a Rails application sustains

**Finding 1 — Published whole-application throughput for three named Rails applications.** A Speedshop article citing conference presentations reports, verbatim: *"At the time, Twitter was still fully a Rails app. In that presentation, the engineer gave the following numbers: * 600 requests/second"*; *"In that presentation, he claimed: * Shopify receives 833 requests/second."*; and *"Here's some numbers from them: * Envato receives 115 requests per second"*.

**Significance:** these are the *entire application's* throughput, not one client's. 150 req/s is larger than the total request rate of one of the three (Envato, 115 req/s) and roughly a quarter of each of the other two as reported.

*Verification — URL fetched: https://www.speedshop.co/blog/scaling-ruby-apps-to-1000-rpm/ · Verbatim quotes checked by re-fetch against the four literal strings · All four confirmed present in the body of the article.*

---

**Finding 2 — The typical Puma deployment carries 20 concurrent request slots per pod.** Puma's own deployment documentation states, verbatim: *"**TL:DR;**: 80% of Puma apps will end up deploying \"pods\" of 4 workers, 5 threads each, 4 vCPU and 8GB of RAM."* On sizing it adds *"Worker counts should be somewhere between 4 and 32 in most cases."* and, on threads, *"Set the number of threads to desired concurrent requests/number of workers. Puma defaults to 5, and that's a decent number."*

**Significance:** the documented unit of Puma capacity is *concurrent requests* (workers × threads), not requests per second. The page carries no requests-per-second figure at all, so Puma's own documentation gives no direct answer to "how many req/s does a Rails app serve" — it answers "how many requests can be in flight at once", and for the shape it calls typical that is 20 per pod.

*Verification — URL fetched: https://github.com/puma/puma/blob/master/docs/deployment.md · Verbatim quotes checked by re-fetch against the literal strings "80% of Puma apps will end up deploying", "Worker counts should be somewhere between 4 and 32", "Puma defaults to 5" · All three confirmed present.*

---

**Finding 3 — Rails' own performance guide defines throughput but publishes no number.** The Rails Guides state, verbatim: *"The throughput is the measure of how many requests per second the server can handle"*, *"latency is the measure of how long individual requests take (also referred to as response time)"*, and *"Increasing the threads will improve throughput up to a point, but worsen latency."*

**Significance:** the framework's official tuning guidance is entirely qualitative. There is no published Rails baseline requests-per-second figure to compare 150 against — the comparison has to come from applications reporting their own numbers (Finding 1) and from the ceiling case (Finding 4).

*Verification — URL fetched: https://guides.rubyonrails.org/tuning_performance_for_deployment.html · Verbatim quotes checked · Confirmed in the guide's throughput/latency definitions section; the page contains no numeric throughput example.*

---

**Finding 4 — The upper end of what a Rails application has been reported to serve.** The Ruby on Rails Foundation's Shopify page states, verbatim: *"During Black Friday 2025, Shopify's Rails monolith powered $14.6 billion in merchant sales, handling peak loads of **489 million requests per minute** on the edge and over **53 million database queries per second**."*

**Significance:** 489 million requests/minute is roughly 8.15 million req/s, at the edge, for the largest publicly-reported Rails deployment in existence. It marks the ceiling of the scale: against that number 150 req/s is negligible, and against Findings 1 it is not. Which end of that range a given application sits at is what decides whether 150 is a rounding error for it.

*Verification — URL fetched: https://rubyonrails.org/foundation/shopify · Verbatim quote checked by re-fetch against the literal string "489 million requests per minute" · Confirmed present in the Black Friday 2025 paragraph.*

---

### 1b. What real APIs publish per caller

Every figure below traces to a fetched quote in `api-rate-limit_doc_1.md`. The req/s column is a unit conversion of the published figure, done only where the source states a rate over a stated interval.

| API | Published limit (verbatim figure) | Normalized | Scope |
|---|---|---|---|
| GitHub REST (authenticated) | "5,000 requests per hour" | ≈ 1.4 req/s | per user |
| GitHub REST (unauthenticated) | "60 requests per hour" | ≈ 0.017 req/s | per caller |
| GitHub REST (Enterprise Cloud install) | "15,000 requests per hour" | ≈ 4.2 req/s | per installation |
| GitHub REST (secondary) | "No more than 100 concurrent requests are allowed." | — (concurrency) | per caller |
| Stripe (global, live mode) | "100 requests per second" | 100 req/s | per Stripe account |
| Stripe (per endpoint) | "25 requests per second" | 25 req/s | per Stripe account |
| Slack Web API Tier 4 (highest) | "100+ per minute" | ≈ 1.7 req/s | per workspace/app |
| Slack Web API Tier 1 (lowest) | "1+ per minute" | ≈ 0.017 req/s | per workspace/app |
| Discord | "All bots can make up to 50 requests per second to our API." | 50 req/s | per bot |
| Atlassian Jira Cloud (GET, POST) | "100" requests per second | 100 req/s | per tenant |
| Atlassian Jira Cloud (PUT, DELETE) | "50" requests per second | 50 req/s | per tenant |
| Cloudflare API | "1,200 requests per five minute period per user" | 4 req/s | per user |
| Shopify GraphQL Admin (Standard) | "100 points/second" | not requests | per app per store |
| Shopify GraphQL Admin (Plus) | "1000 points/second" | not requests | per app per store |
| Shopify GraphQL Admin (Enterprise) | "2000 points/second" | not requests | per app per store |

Two entries resist normalization and are marked as such rather than converted. Shopify meters **calculated query cost**, not request count — its own documentation says *"Calls to the GraphQL Admin API are limited based on calculated query costs, which means you should consider the cost of requests over time, rather than the number of requests."* GitHub's concurrency cap is a limit on requests in flight, not a rate.

*Verification — URLs fetched: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api · https://docs.stripe.com/rate-limits · https://shopify.dev/docs/api/usage/limits · https://docs.slack.dev/apis/web-api/rate-limits · https://docs.discord.com/developers/topics/rate-limits · https://developer.atlassian.com/cloud/jira/platform/rate-limiting/ · https://developers.cloudflare.com/fundamentals/api/reference/limits/ · Verbatim quotes checked by re-fetch, each against its own literal string · Every figure in the table confirmed present on its source page; full excerpts in `api-rate-limit_doc_1.md`.*

---

### Verdict on Question 1

**150 req/s per client is HIGH — it is above every published per-caller limit found, and it is the same order of magnitude as an entire mid-size Rails application's total traffic.**

Against published industry practice (table above, sustained by Finding 5's sources in `api-rate-limit_doc_1.md`): the verified per-caller limits span 0.017 req/s to 100 req/s, and the two highest — Stripe's live-mode global limit and Atlassian's default GET/POST burst limit — both land at exactly 100 req/s. Nothing found publishes a higher per-caller request rate. 150 req/s sits above the top of that range; most of the range sits one to two orders of magnitude below it.

Against Rails application capacity (Findings 1, 2, 3, 4): there is no single Rails throughput baseline to compare against, because the framework publishes none (Finding 3) and Puma measures capacity in concurrent slots rather than requests per second (Finding 2). What exists is reported application throughput, and it splits the answer. Against the reported figures for named Rails applications (Finding 1) — 115, 600 and 833 req/s for whole applications — a single client allowed 150 req/s is not a rounding error; it exceeds one of those applications' entire traffic. Against Shopify's reported edge peak (Finding 4) it is negligible. Where a given application sits between those two references is what determines whether one client at 150 req/s can plausibly consume it.

---

## Question 2 — Is a 10-second block duration something people use?

Observed durations, each with its source:

- **10 seconds** — the lowest non-zero value Cloudflare offers. Its parameter documentation states, verbatim: *"The available API values are: `0`, `10`, `60` (one minute), `120` (two minutes), `300` (five minutes), `600` (10 minutes), `3600` (one hour), or `86400` (one day)."* — https://developers.cloudflare.com/waf/rate-limiting-rules/parameters/
- **0 (no timed block)** — also offered by Cloudflare; setting the mitigation timeout to `0` throttles the excess requests instead of blocking all requests for a fixed window. Same page.
- **10 minutes** — Cloudflare's own OTP-endpoint protection example uses, verbatim: *"Action | Block for 10 minutes"* — https://developers.cloudflare.com/waf/rate-limiting-rules/best-practices/
- **1 day** — Cloudflare's own credential-stuffing example uses, verbatim: *"Action | Block for 1 day"* — same page.
- **10 minutes** — Cloudflare's complexity-based rate-limiting use case sets Duration to *"`10 minutes`"* against a 1-minute counting period — https://developers.cloudflare.com/waf/rate-limiting-rules/use-cases/
- **5 minutes** — Rack::Attack's Fail2Ban example: `maxretry: 3, findtime: 10.minutes, bantime: 5.minutes` — https://raw.githubusercontent.com/rack/rack-attack/main/README.md
- **1 hour** — Rack::Attack's Allow2Ban example: `maxretry: 20, findtime: 1.minute, bantime: 1.hour` — same README.
- **10 minutes** — fail2ban's shipped default, verbatim: `bantime  = 10m`, alongside `findtime  = 10m` and `maxretry = 5` — https://raw.githubusercontent.com/fail2ban/fail2ban/master/config/jail.conf
- **No ban duration at all** — nginx's `limit_req` module documents five directives (`limit_req`, `limit_req_dry_run`, `limit_req_log_level`, `limit_req_status`, `limit_req_zone`), none of which configures a period during which a client stays blocked. Its behavior is stated verbatim: *"If the requests rate exceeds the rate configured for a zone, their processing is delayed such that requests are processed at a defined rate. Excessive requests are delayed until their number exceeds the maximum burst size in which case the request is terminated with an error."* — https://nginx.org/en/docs/http/ngx_http_limit_req_module.html
- **No configurable duration; stops within roughly 30 seconds of compliance** — AWS WAF rate-based rules expose no block-duration setting; the action lifts once the observed rate drops. Verbatim: *"the request rate can be below the limit for a period of time before AWS WAF detects the decrease and discontinues the rate limiting action. Usually, this delay is below 30 seconds."* — https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html

Rack::Attack's plain `throttle` examples (`limit: 5, period: 2`, `limit: 6, period: 60`) carry a counting period and no ban duration — they belong to the "no persistent block" family alongside nginx, not to the ban-duration list.

*Verification — URLs fetched: https://developers.cloudflare.com/waf/rate-limiting-rules/parameters/ · https://developers.cloudflare.com/waf/rate-limiting-rules/best-practices/ · https://developers.cloudflare.com/waf/rate-limiting-rules/use-cases/ · https://raw.githubusercontent.com/rack/rack-attack/main/README.md · https://raw.githubusercontent.com/fail2ban/fail2ban/master/config/jail.conf · https://nginx.org/en/docs/http/ngx_http_limit_req_module.html · https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html · Verbatim quotes checked by re-fetch against the literal strings "Block for 1 day", "Block for 10 minutes", "10 seconds", "maxretry: 3, findtime: 10.minutes, bantime: 5.minutes", "maxretry: 20, findtime: 1.minute, bantime: 1.hour", "bantime  = 10m" and the nginx and AWS WAF sentences · All confirmed present; full excerpts in `api-rate-limit_doc_3.md`, `api-rate-limit_doc_4.md` and `api-rate-limit_doc_5.md`.*

---

### Verdict on Question 2

**10 seconds is at the very bottom of the range people use — legal, offered, and shorter than every explicit ban duration found.**

It is a supported value: Cloudflare lists `10` as its lowest non-zero duration, so the configuration is not exotic. But every source that names a *concrete* ban duration names a longer one — 5 minutes (Rack::Attack Fail2Ban), 10 minutes (fail2ban's shipped default, and two of Cloudflare's own examples), 1 hour (Rack::Attack Allow2Ban), 1 day (Cloudflare's credential-stuffing example). The shortest of those is 30× longer than 10 seconds.

The other family of tools does not disagree with 10 seconds so much as decline to have the setting at all: nginx's `limit_req` has no ban-duration directive and stops rejecting as soon as the rate falls back, and AWS WAF exposes no duration either, lifting the action once the rate drops — *"Usually, this delay is below 30 seconds."* Read against that family, a 10-second block is close to their behavior; read against the family that does configure a ban, it is far below anything published.

---

## Not found

No source was found publishing a per-caller request rate above 100 req/s, and no source was found recommending a block duration in the 10-second range on its own terms.
