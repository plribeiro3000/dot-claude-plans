# API Extractor — Duplicate Pagination Cursor

## Summary

The API extractor consumer carries two pagination cursors in its Sidekiq arguments — `page` and `previous_record_id` — and both encode the same thing: the reader's position in the paginated source. One expresses that position as a page number, the other as a record cursor. A single pagination position should be a single argument.

## Current state

The signature is identical across all 25 streams' API extractors:

```ruby
def perform(job_id, stream_id, page = 1, previous_record_id = nil)
```

Reference sites: `app/workers/subsidiary/api_extractor_consumer.rb:10`, `app/workers/goal/api_extractor_consumer.rb:10`, and every other stream. In the parallel-transform pilot this file is `app/workers/user/sales_representative/api_collection_extractor_consumer.rb:11` (renamed from `api_extractor_consumer.rb`); on `develop` it is still `api_extractor_consumer.rb`.

Both values are pushed into the query template variables and advanced on every self-re-enqueue for the next page:

- `Variables.new(job, source, page: page, previous_record_id: previous_record_id, page_size: stream.page_size)`
- next page: `ApiExtractorConsumer.perform_async(job_id, stream_id, page + 1, new_previous_record_id)`

The database extractor, by contrast, carries a single cursor: `def perform(job_id, stream_id, collection_last_id = nil)`.

## Why it is wrong

Two arguments control one concept — the position in the paginated source. `page` is offset / page-number pagination; `previous_record_id` is keyset / cursor pagination. A given source uses one style or the other, so on every call one of the two arguments is dead weight, and a two-argument position invites the two to disagree. Pagination position is one thing and belongs in one argument.

## Recommendation

Consolidate to a single pagination-cursor argument whose meaning is defined per source, matching the single-cursor shape the database extractor already uses.

## Precondition before changing — do not skip

Source APIs paginate either by page number (`?page=N`) or by a record cursor, and which one a stream uses lives in that stream's query template (`stream.render_query` variables) — per-client configuration that is not in this repository. Before removing `page`, confirm whether any live stream's template references the `page` variable. Removing it blindly breaks every page-number-paginated source. The consolidation must keep serving both pagination styles under the one cursor.

## Blast radius

Every stream's `app/workers/**/api_extractor_consumer.rb` (25 files) plus the `Variables` class that reads `page` / `previous_record_id`. This is cross-cutting, not a per-stream change.

## Scope

Out of scope for the parallel-transform pilot (PR #2398). Pick this up after that merges.
