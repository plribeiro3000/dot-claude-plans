# Spike — `portable_exportation` renders time out on `shared-001`

## Question

Why does `Browser::Page#wait_until_settled` exhaust its 60-second budget on every
`PortableExportation::PlanStatementConsumer` job in `shared-001`, when the same code path
completed on `atento-001`?

Nothing is changed until the cause is confirmed. This document records what the evidence
establishes, what it rules out, and the experiment that closes the remaining gap.

## State at the time of writing

The `shared-001` `worker-portable-exportation` fleet is quieted (TSTP sent to all 5 tasks) and its
autoscaling schedule `Lambda-shared-001-worker-portable-exp-schedule` is `DISABLED`. The queue
holds 5,040 `PlanStatementConsumer` jobs. Nothing drains while the quiet holds, and the jobs
resume the moment a task is recycled.

`atento-001` holds 0 tasks and an empty queue.

## The failing run

Times are BRT, from the ECS service events and the worker log group.

| Time | Event |
|---|---|
| 13:16:09 | ASG cold: "No Container Instances were found in your capacity provider" |
| 13:16:44 | first task started (`c0b1dfad`) |
| 13:17:31 | the batch of 5,040 jobs is enqueued |
| 13:18:14 | "insufficient CPU units available" — a task could not be placed |
| 13:18:35 | first `Ferrum::TimeoutError` |
| 13:18:49 | remaining 4 tasks started |
| 13:19:32 | service reached steady state |
| 13:33:28 | schedule disabled, TSTP sent to all 5 tasks |
| 13:36:25 | last `Ferrum::TimeoutError`; the in-flight batch had drained |

The first timeout landed on the first task, roughly two minutes after it started, on a browser that
had rendered almost nothing. Browser accumulation is therefore not required to reproduce the
failure.

## What the evidence establishes

**The failure is a tail, not a block.** Across the run the consumer logged **686 successes and 95
failures** — 781 attempts, a **12.2% failure rate**. The system was producing statements the whole
time, at roughly 36 per minute across five tasks.

**Every failure is the same failure.** All 95 are `Ferrum::TimeoutError`, with no
`UnexpectedPageException` among them, so the browser always reached the expected URL. A successful
render takes about 5.8 seconds; a failing one burns the full 60-second budget, which is a tail more
than ten times the median.

**The exception is 4Shark's own, not Ferrum's.** `Browser::Page#wait_until_settled`
(`app/app/models/browser/page.rb:29`) raises `Ferrum::TimeoutError` when its deadline passes. The
deadline is `ApplicationConfiguration.browser_timeout`.

**The timeout budget is identical in both stacks.** No `BROWSER_*` variable is declared in the
Terraform for `app-shared-001` or `app-atento-001`, and none appears on the live
`shared-001-worker-portable-exportation` task definition. Both run the code defaults from
`app/lib/application_configuration.rb:473-487`:

| Setting | Value |
|---|---|
| `BROWSER_TIMEOUT` | 60 seconds |
| `BROWSER_NETWORK_SETTLE_DURATION` | 0.5 seconds |
| `BROWSER_NETWORK_POLL_INTERVAL` | 0.05 seconds |
| `BROWSER_PAGE_LIMIT` | 200 pages per browser |

The difference between the two stacks is not configuration.

**`atento-001` never ran this at scale.** Its only recorded scale-up since 2026-08-19 took the
service from 0 to 1 task, with 1 job in the queue. The comparison "it worked on atento" therefore
compares a single render against ten concurrent ones.

**The backend was fast throughout.** The `shared-001-lb` ALB served the run at an average
`TargetResponseTime` of 30–50 ms, maximum 3.2 s, while `RequestCount` rose from a baseline near 30
per 5-minute period to 3,336 at the peak and collapsed once the workers were quieted.

**The worker hosts were not exhausted.** ECS `MemoryUtilization` for the service peaked at 38%.
EC2 `CPUUtilization` across the ASG averaged 43–52% with a maximum of 86%. High, not saturated.
No task was replaced during the run — the repeated Sidekiq boot lines at 13:19 are the four
remaining tasks starting, which the service events confirm.

**Concurrency is 10 simultaneous renders.** `SIDEKIQ_THREADS` is `2` on the task definition, the
browser pool is one browser per Sidekiq thread (`app/config/initializers/browser.rb:4`), and the
service ran 5 tasks.

**Each render performs three full page loads.** `PlanStatement::WebPage#to_pdf`
(`app/app/models/plan_statement/web_page.rb:24-36`) navigates to `/session/create`, then to the
statement path, then reloads — each followed by `wait_until_settled`.

**Every failure re-enqueues.** `PlanStatementConsumer` carries Sidekiq's default `retry: true`, so
a timed-out job repeats all three page loads. Statement ids observed timing out (`4029856`,
`4029866`, `4029873`, `4029924`) reappear in the queue afterwards.

**Cloudflare is not in the request path.** `operador.app4shark.com` — the host these renders load —
is a DNS-only CNAME to `fourshark-app-client.netlify.app`
(`terraform/dns/public_dns_app4shark_com.tf:498-506`, `proxied = false`). Cloudflare answers DNS and
nothing else, so any request-volume limiter reached by these renders belongs to **Netlify**.

## What the evidence rules out

**The statement itself is not broken.** A single isolated render of `4029978`, with the same browser
pool and the same blocklist, reached 48 exchanges with **0 pending** and landed on the expected URL.

**An unhandled paused request under Fetch interception is not the cause.** Setting `blocklist` puts
the page in interception mode (`ferrum-0.17.2/lib/ferrum/network.rb:460-477`), and a request left
paused there would hang deterministically, at any concurrency. The isolated render used the same
blocklist and left nothing pending.

**The `googletagmanager.com` blocklist entry is not the cause.** A request aborted by the blocklist
counts as finished, so it cannot hold the pending counter above zero
(`ferrum-0.17.2/lib/ferrum/network/exchange.rb:101-103`):

```ruby
def finished?
  blocked? || response&.loaded? || !error.nil? || ping? || blob? || unknown
end
```

**A long-lived connection in the front is not the cause.** `app-webclient` declares no `WebSocket`,
no `EventSource`, no ActionCable and no socket.io anywhere under `src/`.

**Backend saturation is not the cause.** An API answering in 30 ms does not leave a request pending
for 60 seconds.

**A challenge redirect is not the cause.** A challenge would land the browser on a URL failing the
`expected_path` check and raise `UnexpectedPageException`
(`app/app/models/plan_statement/web_page.rb:39`). None was logged.

**Memory exhaustion and task restarts are not the cause.** See the host metrics above.

**Per-host resource contention is not the cause.** Four concurrent renders on the runner left 0
pending across 46–48 exchanges each, and every measurable difference favours the runner being the
weaker environment:

| | worker | runner |
|---|---|---|
| Instance type | `c6a.large` (dedicated) | `t3a.medium` (burstable) |
| Task memory | 3584 MB | 2048 MB |
| Task CPU units | 2048 | 2048 |
| Subnets | `subnet-09e0e8af3a645815b`, `subnet-0734a7c02cf80e13c` | identical |
| Concurrent renders | 2 | 4 |
| Outcome | every job timed out | 0 pending |

Two renders on the stronger host failed while four on the weaker one succeeded, so neither CPU nor
memory contention explains it.

**A different egress path is not the cause.** Both auto-scaling groups place instances in the same
two subnets, so the runner and the workers reach Netlify from the same NAT address.

**The worker container and instance are not the cause.** Two renders executed inside the surviving
production task, on its `c6a.large`, left 0 pending across 47 exchanges each and reached the
expected URLs. From that same container Netlify answered five consecutive requests with HTTP 200 at
roughly 20 ms total and 6 ms connect, so neither throttling nor latency is present on that egress
path.

## The cause

**A request for a favicon hosted on the public S3 assets bucket stays pending, and one pending
request is enough to exhaust the whole budget.** Twenty instrumented renders reproduced it twice,
and both failures are identical in shape:

```
4029919 TIMEOUT em passo 1 session/create apos 60.0s - 1 pendentes de 32
  PENDENTE https://4shark-assets.s3.amazonaws.com/logomarca/favicon-pb.png
```

Exactly one exchange out of thirty-two is outstanding, the wait consumes exactly its 60-second
budget, and the failure lands on the first navigation. The asset is the front's
`FAVICON_PNG_URL` (`app-webclient/src/environments/.env.ts.sample:11`) — a browser tab icon, absent
from the rendered PDF.

`wait_until_settled` requires `pending_connections` to reach zero and hold there
(`app/app/models/browser/page.rb:22-24`), so it cannot distinguish an asset the document needs from
one it does not. A single stalled decoration blocks a render that is otherwise complete.

**The endpoint is healthy; only Chrome stalls on it.** Three hundred sequential requests for that
exact object, issued with `curl` from the production container, returned HTTP 200 three hundred
times — DNS in 0.7 ms, connect in 1.5 ms, slowest response 90 ms. Neither S3 nor the network path
is at fault.

**Request interception is protective, not causal.** With `blocklist` set, twenty renders produced
two failures; with `blocklist` removed — which disables interception entirely
(`ferrum-0.17.2/lib/ferrum/network.rb:460-462`) — six renders produced five. Enabling the Fetch
domain routes every request through Ferrum's `continue`, which evidently gets the low-priority
request dispatched instead of leaving it queued.

**The behaviour is known upstream and has a prescribed remedy.** Ferrum's maintainer describes the
mechanism in [rubycdp/ferrum#122](https://github.com/rubycdp/ferrum/issues/122): *"Chrome doesn't
provide details about such resources. I remember one bug because of such behavior, Chrome was
waiting for such connection even more than 30s [...] and thus didn't send a crucial event Ferrum
was relying on. I tried to find any setting for such behaviour without any luck."* His remedy is to
exclude them — *"If request is to external server try to block such if it's not vital part of your
app"* — and another user in the same thread reports the identical workaround for images that a
headless render does not need.

The favicon is precisely that: an external, non-vital resource absent from the output.

The render depends on four objects from `4shark-assets.s3.amazonaws.com` — the two favicons, the
avatar and the logos — so the exposure is the host, not the one file. The logo entries are declared
over plain `http://` while the page is served over `https://`, which is a separate defect worth
checking on its own.

## What Chrome actually reports for the stuck exchange

Measured on a quieted `shared-001` task against a statement from the failing queue, with the render
instrumented to subscribe to `Network.loadingFinished` independently:

```
TIMEOUT 4109857 62.0s reported_finished=29
  pending id=4057.201 reported=false request=true response=false error=false unknown=false
  url=https://4shark-assets.s3.amazonaws.com/logomarca/favicon-pb.png
TIMEOUT 4109858 61.5s reported_finished=29
  pending id=4086.201 reported=false request=true response=false error=false unknown=false
  url=https://4shark-assets.s3.amazonaws.com/logomarca/favicon-pb.png
ok 4109860 7.1s 63705b
ok 4109865 6.3s 63576b
ok 4109869 5.5s 64024b
{ok: 3, timeout: 2, other: 0}
```

Both failures are the same resource with the same signature, and the three successes complete every
navigation in 5.5–7.1s producing a 63–64KB document. **Elapsed time separates the two populations by
a factor of eight**, which is what makes a stale window a usable discriminator: no legitimate request
in a render that finishes in seven seconds approaches fifteen, and the abandoned one sits until the
sixty-second budget expires.

**Chrome sends nothing at all for it.** The exchange carries a request and never receives
`responseReceived`, `loadingFinished` or `loadingFailed`. The `reported_finished=29` on the same
line is what makes this trustworthy rather than an instrumentation failure: twenty-nine other
exchanges on that page did produce `loadingFinished` and were recorded, so the subscription works
and this one exchange is genuinely silent.

That settles the mechanism. The exchange is indistinguishable from a legitimately in-flight request
by any field Ferrum exposes — only elapsed time separates them. Recording Chrome's completion
reports therefore cannot fix this render, because there is no report to record.

The maintainer's description in [#122](https://github.com/rubycdp/ferrum/issues/122) is literal:
*"Chrome doesn't provide details about such resources [...] and thus didn't send a crucial event
Ferrum was relying on."* The remedy proposed in that same thread and never built is the one the
measurement points at — *"close open/stale connections after xx seconds"*.

## The per-request timeout, measured against the same statements

Same five statements, same quieted task, with the wait patched in the console to abandon a request
left unanswered past fifteen seconds:

```
ok 4109857 12.8s 59921b
ok 4109858 11.8s 60006b
ok 4109860 22.7s 63705b
ok 4109865 11.1s 63576b
ok 4109869 7.7s 64024b
{ok: 5, timeout: 0, other: 0}
```

**`4109860` is the proof, and it is the one that did not fail before.** Its 22.7s decomposes as a
normal render plus the fifteen-second abandon, and its document is **byte-identical** to the 63,705
bytes it produced on its healthy run — so exercising the abandon path cost the output nothing. That
is the early-capture risk answered by measurement rather than by argument.

Which statement hangs varies per run: the two that timed out before rendered normally here, and one
that rendered normally before hung here. The hang is a per-render probability, not a property of a
statement.

**The 59,921 and 60,006 byte documents are NOT evidence of truncation.** Those two statements had
never completed, so no healthy baseline exists for them; the ~63.5KB figures belong to the other
three statements and are different documents. Reading one against the other would repeat the
sampling error this investigation already made once.

## A latent Ferrum gap, adjacent but not this cause

## The mechanism, at the protocol level

Chrome does not always emit `Network.responseReceived` for a request it completes. The behaviour is
Chromium's own, tracked as crbug.com/883475, and both major CDP clients carry the citation in their
source. Ferrum's is in `ferrum-0.17.2/lib/ferrum/network/response.rb:113-114`: *"See
https://crbug.com/883475 / Sometimes we never get the Network.responseReceived event."*

**Puppeteer treats `Network.loadingFinished` as terminal regardless of whether a response arrived.**
Its `NetworkManager` carries the same citation — *"Under certain conditions we never get the
Network.responseReceived event from protocol. @see https://crbug.com/883475"* — and then resolves
the body only if a response exists before finalising the request unconditionally:

```javascript
if (request.response()) {
  request.response()?._resolveBody();
}
this.#forgetRequest(request, true);
this.emit(NetworkManagerEvent.RequestFinished, request);
```

**Ferrum does not.** `subscribe_loading_finished` (`network.rb:416-428`) marks the exchange loaded
only when a response object is already present, and sets `unknown = false` on the way through:

```ruby
@page.on("Network.loadingFinished") do |params|
  exchange = select(params["requestId"]).last
  next unless exchange

  exchange.unknown = false

  if (response = exchange.response)
    response.loaded = true
    response.body_size = params["encodedDataLength"]
  end
end
```

`Exchange#finished?` (`exchange.rb:101-103`) is `blocked? || response&.loaded? || !error.nil? ||
ping? || blob? || unknown`. An exchange that receives `loadingFinished` without a prior
`responseReceived` satisfies none of those terms — and line 421 clears the one flag that could
otherwise rescue it. It stays pending for the remaining life of the page, and `pending_connections`
never returns to zero.

**The rescue that exists fires only on navigation.** `classify_pending_exchanges`
(`network.rb:509-516`) marks earlier pending exchanges `unknown` when the main frame navigates,
which is the upstream fix for [#420](https://github.com/rubycdp/ferrum/issues/420) and
[#426](https://github.com/rubycdp/ferrum/issues/426). A resource left stuck on the **final** page is
followed by no further navigation, which is why the last of the three `wait_until_settled` calls is
the one that burns the full budget.

That mechanism is indifferent to which URL is involved, so a per-URL blocklist bounds the observed
instance and not the failure. The favicon's prominence is nevertheless structural rather than
accidental: Chromium issue 40705143 reports the favicon being fetched by the browser process rather
than by blink, leaving DevTools without the renderer-side event sequence. That last point rests on a
search summary — the issue tracker page itself could not be retrieved — so it is weaker evidence
than the rest of this section and should be re-checked before being relied on.

## The header comment on `Browser::Page` is stale

The class comment attributes permanent pending state to requests that `go_to` cuts mid-flight.
Ferrum 0.17.2 handles that case through `classify_pending_exchanges`, so the custom
`wait_until_settled` rests partly on a premise the gem already satisfies. What the gem does not
handle is the case above.

## The community abandoned network-idle as a readiness signal

Playwright's own documentation marks `networkidle` **DISCOURAGED** and states: *"Don't use this
method for testing, rely on web assertions to assess readiness instead."* Biome ships a lint rule,
`noPlaywrightNetworkidle`, whose rationale is *"The `networkidle` event is unreliable and can lead
to flaky tests"*, recommending *"web-first assertions or wait for specific elements instead."*

The transferable conclusion is that a render is better gated on a signal the document itself
produces than on the absence of network traffic, which no page guarantees will ever occur.

## Ferrum 0.18.0

Released 2026-08-20. Three entries bear on this: `:pending_connection_errors` now defaults to
`false`; `Frame#idle?`, `#lifecycle_events` and `#loader_id` expose Chrome's own lifecycle events
including `networkIdle`; and `Page#idling?` no longer blocks on `loading="lazy"` iframes Chrome never
starts loading ([#583](https://github.com/rubycdp/ferrum/issues/583)) — the same class of defect
against a different never-completing object.

None of its notes claims the `loadingFinished`-without-`responseReceived` gap is closed. The release
is zero days old against the seven-day quarantine in `DEPENDENCY_MINIMUM_RELEASE_AGE_DAYS`, so it is
not adoptable yet regardless.

## What remains open

To exhaust the budget, at least one exchange must stay sent-but-unfinished for that whole window.
Which exchange, on a failing render, is still uncaptured — the logs record that `wait_until_settled`
raised, never which of the three calls raised nor what was outstanding when it did. The mechanism
above predicts what the instrumented run should show: an exchange carrying a request, no response,
no error, `unknown == false`.

**Failures are spread evenly across all five tasks.** Per task, successes against failures: 95/24,
88/12, 75/19, 73/18, 69/22. No task is healthy while another is broken, and none stops producing,
so the tail behaves like a per-render probability rather than a property of a host, a browser, or a
moment in time.

That shape weakens both environmental explanations. A rate limiter tripping on aggregate volume
would produce failures clustered after a threshold, not scattered from the first minute; and 600
sequential requests for the main bundle from a production container returned HTTP 200 six hundred
times at roughly 50 requests per second, above the per-task production rate. A transient condition
would produce a band of failures in one interval rather than a steady fraction across nineteen
minutes.

## The discriminating experiment

Run the instrumented full sequence in a loop over statements drawn from the failing queue, on the
quieted production container, and print what is pending whenever one times out.

At a 12% failure rate, twenty renders should catch two or three failures. Each success costs about
six seconds and each failure sixty, so the loop finishes in minutes. It releases no jobs, persists
nothing, and runs where the failures actually happened.

The output names the failing step and the outstanding URLs, which is the fact every prior
experiment was structurally unable to produce: isolated reproduction cannot distinguish a healthy
render from an unhealthy one when seven of eight renders are healthy.

## Consequence for the queue

Whatever the cause, the 5,040 queued jobs cannot be released until it is fixed. Releasing the quiet
restores 10 concurrent renders against the front, each retrying on failure.

Raising `BROWSER_TIMEOUT` is not a fix: it lengthens the time each job holds a vCPU without removing
a single request, and it does nothing about a request that never completes.

## Sources

- `app/app/models/browser/page.rb`, `app/app/models/browser.rb`
- `app/app/models/plan_statement/web_page.rb`, `app/app/workers/portable_exportation/plan_statement_consumer.rb`
- `app/lib/application_configuration.rb`, `app/config/initializers/browser.rb`, `app/config/sidekiq_portable_exportation.yml`
- `ferrum-0.17.2/lib/ferrum/network.rb`, `ferrum-0.17.2/lib/ferrum/network/exchange.rb`
- `terraform/dns/public_dns_app4shark_com.tf`
- CloudWatch logs: `/ecs/shared-001-worker-portable-exportation`, `/aws/lambda/Lambda-shared-001-worker-portable-exportation-autoscaling`
- CloudWatch metrics: `AWS/ApplicationELB` on `app/shared-001-lb/9e5da09dcedcd8ae`; `AWS/ECS` and `AWS/EC2` on the portable-exportation service and ASG
- ECS service events for `shared-001-worker-portable-exportation-service`
