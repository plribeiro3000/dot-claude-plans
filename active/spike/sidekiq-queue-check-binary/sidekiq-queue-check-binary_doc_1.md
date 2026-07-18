# Auxiliary — Sidekiq wiki API page (fetched excerpts)

Source: https://github.com/sidekiq/sidekiq/wiki/API

Fetched fresh this revision (two passes: initial survey, then a substring-verification
self-check per Citation Discipline rule 5). Scope narrowed from the prior revision — this
spike's settled design uses only queue depth (`Stats#enqueued`) and busy count
(`Stats#workers_size`/`ProcessSet`), not retry/scheduled sets or `WorkSet`, so those
quotes are dropped here.

## Verified quotes

> "`Sidekiq::ProcessSet` gets you access to near real-time (updated every 5 sec) info about the current set of Sidekiq processes running."

Confirmed present verbatim on two separate fetches of the URL (initial survey and the
self-check re-fetch). Relevant to the sampling design: the underlying process/heartbeat
data itself only refreshes every 5 seconds, so a sampling interval below 5s would poll
faster than the data changes.

> "Gets the number of jobs enqueued in all queues (does NOT include retries and scheduled jobs)."

Confirmed present verbatim, describing `Sidekiq::Stats#enqueued` — the exact accessor
backing the queue-depth aggregate this binary reads (see `sidekiq-queue-check-binary_excerpt_1.rb`
for the underlying `fetch_stats_slow!` implementation, verified against the pinned-tag
source directly, not this wiki page).

## Notes for future revision

- This page is a GitHub wiki, not tied to a release tag — its content can change
  independently of the `sidekiq` gem version. If revisiting this spike, re-fetch fresh
  rather than trusting this file as current; it is a point-in-time capture from 2026-07-17.
- No quote in this file attributes a "coining" or "naming" of a term to this source
  (Citation Discipline rule 3) — both quotes describe existing Sidekiq API behavior.

---

## Prior art on ramp detection (Mann-Kendall test) — optional finding, not a redesign

Source: https://diogoribeiro7.github.io/time-series%20analysis/detecting_trends_timeseries_data/

Fetched during this revision in response to the engineer's explicit invitation to report
prior art on "is this series ramping" statistics, if found. This is reported as
information only — the verdict rule itself (variation across the 10-sample series, not a
magic threshold) is the engineer's and is not redesigned here.

> "The Mann-Kendall Test is a non-parametric method used to detect trends in time-series data" and is "sensitive to monotonic trends, meaning it can detect a consistent upward or downward movement over time."

> "For each pair of observations (x_i, x_j) where i < j, the test evaluates whether x_j > x_i, x_j < x_i, or x_j = x_i." The S statistic sums the sign function across all pairwise comparisons: a +1 for increasing pairs, -1 for decreasing pairs, and 0 for equal values.

This fetched source did not discuss a minimum sample size for reliability — no claim is
made here about whether 10 samples is or is not sufficient for this test; that would
require a separate, dedicated source and is out of scope (the sample count is already
fixed by the engineer at 10 reads / ~100s).
