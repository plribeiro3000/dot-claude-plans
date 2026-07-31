# Auxiliary file — Sidekiq delivery-guarantee and signal-handling quotes

Consolidated because the spike's central claim (recompute-not-increment is forced by at-least-once
delivery, and TSTP/TERM behavior is what makes an interrupted recompute safe) rests on all three
pages together. Every quote below was fetched directly from the cited URL; none is drawn from
training-data memory of Sidekiq's behavior.

## Delivery guarantee — at-least-once, not exactly-once

Source: https://github.com/sidekiq/sidekiq/wiki/Best-Practices

> "Idempotency means that your job can safely execute multiple times."

> "Just remember that Sidekiq will execute your job **at least** once, not **exactly** once."

> "Even a job which has completed can be re-run. Redis can go down between the point where your
> job finished but before Sidekiq has acknowledged it in Redis. Sidekiq makes no exactly-once
> guarantee at all."

## Retries after failure — the default policy

Source: https://github.com/sidekiq/sidekiq/wiki/Job-Lifecycle

> "the default retry policy is 25, a single job can lead to Failed increasing by 25"

> "a single job can increment both the Processed and Failed counters if it fails once or more, but
> succeeds upon retry" — demonstrating a job may run more than once before it is considered done.

## TSTP signal — quiet, finish in-flight work

Source: https://github.com/sidekiq/sidekiq/wiki/Signals

> "It will stop fetching new jobs but continue working on current jobs." (TSTP)

## TERM signal — same in-flight behavior, then a hard timeout

Source: https://github.com/sidekiq/sidekiq/wiki/Signals

> "It will stop fetching new jobs, but continue working on current jobs (as with TSTP)." (TERM)

> "Any jobs that do not finish within the timeout are forcefully terminated and pushed back to
> Redis to be executed again when Sidekiq starts up. The timeout defaults to 25 seconds since all
> Heroku processes must exit within 30 seconds."

## Reliability page — the plain-Sidekiq (non-Pro) baseline

Source: https://github.com/sidekiq/sidekiq/wiki/Reliability

> "if Sidekiq crashes while processing that job, it is lost forever" — describing the plain
> (non-`super_fetch`) fetch strategy 4Shark runs (no Sidekiq Pro reliability add-ons detected in
> `Gemfile.lock`; only `sidekiq (8.0.10)` and `sidekiq-unique-jobs (8.1.0)` are present, and neither
> of the four incentive consumers declares a `sidekiq_options` uniqueness lock).

## Reading together

A job that is mid-recompute when TSTP/TERM arrives either finishes (in-flight work is never cut
off by TSTP/TERM alone) or, on a hard TERM timeout / a Sidekiq-process crash, is pushed back to
Redis and re-run from the start — with no partial state carried over, since the job's own
in-memory state (variables, not-yet-committed writes) is discarded. Combined with "recompute the
full sum, never `+=`", a re-run recomputes the identical target value it would have produced the
first time, PROVIDED the write itself does not race with a concurrent sibling job's write to the
same target row — that race is a separate concern from delivery guarantees and is addressed in
`auxvar-materialization_postgres_1.md`.
