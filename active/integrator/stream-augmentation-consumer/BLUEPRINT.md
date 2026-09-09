# BLUEPRINT — Enrich stage replication across all 25 resources

Detailed mechanical plan for replacing the legacy in-place `StreamAugmentation` mechanism with a generic per-external-id `Enrichment` stage inserted between Extract and Transform. `PLAN.md` (sibling) holds the strategy and rationale; this file holds the per-resource maps, the verbatim templates, and the resumable checklist. Worktree: `~/Projects/4Shark/integrator/.claude/worktrees/stream-augmentation-consumer` (branch `feature/stream-augmentation-consumer`, PR #2385).

## Stage shape

The enrich stage sits between end-of-extract (Goal) and start-of-transform (Subsidiary). Each resource gets a trio: `EnricherProducer` (single paginated producer, `LoaderProducer` mold), `DatabaseEnricherConsumer`, `ApiEnricherConsumer` (terminal, per external_id). Workers chain directly, no coordinator. Counting is self-paced: the producer counts `total_consumers + 1` per cycle (the `+1` is the re-enqueued next self cycle), then `increment_executions`; whichever of the producer's final cycle or the last terminal consumer drains last advances to the next resource with `increment_queue(by: 1)` + `Next::EnricherProducer.perform_async(job_id)`.

## Entry / exit boundaries

- **Entry**: Goal's extract boundary (`goal/{database_extractor_consumer,api_extractor_consumer,extractor_producer}.rb`) advances to the enrich stage with `increment_queue(by: 1)` + `Subsidiary::EnricherProducer.perform_async(job_id)`. (Currently targets `Client::EnricherProducer` — MUST be retargeted to `Subsidiary`, the first pipeline resource.)
- **Exit**: Goal (last enrich resource) advances to `Subsidiary::TransformerProducer.perform_async(job_id)` with NO `increment_queue` — the transform entry is an uncounted router.

## Chain order (resource → next EnricherProducer)

```
subsidiary            → Hierarchy
hierarchy             → User::Admin
user/admin            → User::President
user/president        → User::VicePresident
user/vice_president   → User::Director
user/director         → User::Superintendent
user/superintendent   → User::GeneralManager
user/general_manager  → User::Manager
user/manager          → User::Coordinator
user/coordinator      → User::Supervisor
user/supervisor       → User::SalesRepresentative
user/sales_representative → User::Unknown
user/unknown          → ParentUpdate
parent_update         → UserIdentifier
user_identifier       → Client
client                → Product
product               → Group
group                 → Groupification
groupification        → UserField
user_field            → UserActivity
user_activity         → Deal
deal                  → DealExtraField
deal_extra_field      → Modifier
modifier              → Goal
goal                  → Subsidiary::TransformerProducer  (transform entry, NO increment_queue)
```

## Per-resource maps (verified against live code 2026-09-08)

| resource | namespace | pool (`job.<x>_collections`) | ResourceType lookup |
|---|---|---|---|
| subsidiary | `class Subsidiary < Resource` | subsidiary_collections | `find_by(name: 'Subsidiary')` |
| hierarchy | `class Hierarchy < Resource` | hierarchy_collections | `find_by(name: 'Hierarchy')` |
| user/admin | `class User < Resource; module Admin` | user_collections | `find_by(name: 'Admin')` |
| user/president | `…module President` | user_collections | `find_by(name: 'President')` |
| user/vice_president | `…module VicePresident` | user_collections | `find_by(name: 'VicePresident')` |
| user/director | `…module Director` | user_collections | `find_by(name: 'Director')` |
| user/superintendent | `…module Superintendent` | user_collections | `find_by(name: 'Superintendent')` |
| user/general_manager | `…module GeneralManager` | user_collections | `find_by(name: 'GeneralManager')` |
| user/manager | `…module Manager` | user_collections | `find_by(name: 'Manager')` |
| user/coordinator | `…module Coordinator` | user_collections | `find_by(name: 'Coordinator')` |
| user/supervisor | `…module Supervisor` | user_collections | `find_by(name: 'Supervisor')` |
| user/sales_representative | `…module SalesRepresentative` | user_collections | `find_by(name: 'SalesRepresentative')` |
| user/unknown | `…module Unknown` | user_collections | `find_by(name: 'Unknown')` |
| parent_update | `module ParentUpdate` | user_collections | `find_by(name: 'ParentUpdate')` |
| user_identifier | `class UserIdentifier < Resource` | user_identifier_collections | split: `where(resource: 'UserIdentifier')` |
| client | `class Client < Resource` | client_collections | `find_by(name: 'Client')` |
| product | `class Product < Resource` | product_collections | `find_by(name: 'Product')` |
| group | `class Group < Resource` | group_collections | `find_by(name: 'Group')` |
| groupification | `class Groupification < Resource` | groupification_collections | `find_by(name: 'Groupification')` |
| user_field | `class UserField < Resource` | user_field_collections | split: `where(resource: 'UserField')` |
| user_activity | `class UserActivity < Resource` | user_activity_collections | `find_by(name: 'UserActivity')` |
| deal | `class Deal < Resource` | deal_collections | `find_by(name: 'Deal')` |
| deal_extra_field | `class DealExtraField < Resource` | deal_extra_field_collections | `find_by(name: 'DealExtraField')` |
| modifier | `class Modifier < Resource` | modifier_collections | `find_by(name: 'Modifier')` |
| goal | `class Goal < Resource` | goal_collections | `find_by(name: 'Goal')` |

**Standard RT lookup** (producer line):
`downstreams = ResourceType.find_by(name: '<Name>').streams.enabled.downstreams.to_a`

**Split RT lookup** (user_field, user_identifier — mirror the extractor's `where(resource:).pluck(:id)` shape, but `.downstreams`):
```ruby
resource_type_ids = ResourceType.where(resource: '<Name>').pluck(:id)
downstreams = Stream.enabled.downstreams.in(resource_type_id: resource_type_ids).to_a
```

## Reference templates (verified rubocop-clean)

The **Subsidiary trio** is the verified reference — copy it verbatim, substituting namespace, pool, RT-lookup line, and next-resource:
- `app/workers/subsidiary/enricher_producer.rb`
- `app/workers/subsidiary/database_enricher_consumer.rb`
- `app/workers/subsidiary/api_enricher_consumer.rb`

Style decisions already made and locked:
- `perform(job_id, collection_cursor = nil)` — only the pagination cursor is optional; every consumer gets a concrete `[job_id, downstream_id, external_id]`.
- Advance guard: `return unless job.computation.done?` (matches `goal/api_extractor_consumer` sibling; NO-UNLESS deviation accepted, rubocop-clean).
- Blank line before every `next` guard.
- `connection.execute(Sequel.lit(query))` in DB consumers — sanctioned customer-DB SQL.
- `UnexpectedResponseStatusCodeException.new(` multi-line block in api consumers — matches the Client template, leave it.

## Migration parts

1. **Enrich trios** — one trio per resource (75 files: 25 × 3). Producer + DB consumer + API consumer.
2. **Extract-consumer cleanup** — remove the `if stream.downstream?` StreamAugmentation branch from every `{database,api}_extractor_consumer.rb`.
3. **Transformer swap** — replace `StreamAugmentation.find_by(job_id, downstream_id)` in-memory lookup with per-record `Enrichment.find_by(job_id, downstream_id, external_id: record[source_field])` in every `transformer_consumer.rb`.
4. **Boundary fixes** — Goal extract boundary target → `Subsidiary::EnricherProducer` (keep `increment_queue(by: 1)`); Client trio re-chain → `Product::EnricherProducer` (currently → `Subsidiary::TransformerProducer`, wrong).
5. **StreamAugmentation model removal** — once nothing references it.

## Validation (deferred to the very end — ALL-OR-NOTHING)

The enrichers reference forward in the chain, so nothing eager-loads or pushes until every resource + edit exists. Run only at the end:
- rubocop on touched files
- eager-load: `bin/rails runner "Rails.application.eager_load!; Zeitwerk::Loader.eager_load_all; puts 'EAGER_LOAD_OK'"`
- amend onto the single PR commit, `git push --force-with-lease`.

## Checklist — enrich trios (P=producer, D=db consumer, A=api consumer)

- [x] subsidiary — P D A (reference, rubocop-clean)
- [x] hierarchy — P D A
- [x] user/admin — P D A
- [~] user/president — P D, **A missing**
- [ ] user/vice_president — P D A
- [ ] user/director — P D A
- [ ] user/superintendent — P D A
- [ ] user/general_manager — P D A
- [ ] user/manager — P D A
- [ ] user/coordinator — P D A
- [ ] user/supervisor — P D A
- [ ] user/sales_representative — P D A
- [ ] user/unknown — P D A
- [ ] parent_update — P D A
- [ ] user_identifier — P D A (split RT lookup)
- [x] client — P D A (exists; **re-chain to Product::EnricherProducer**)
- [ ] product — P D A
- [ ] group — P D A
- [ ] groupification — P D A
- [ ] user_field — P D A (split RT lookup)
- [ ] user_activity — P D A
- [ ] deal — P D A
- [ ] deal_extra_field — P D A
- [ ] modifier — P D A
- [ ] goal — P D A (last; advances to `Subsidiary::TransformerProducer`, NO increment_queue)

## Checklist — other parts

- [ ] Goal extract boundary → `Subsidiary::EnricherProducer` (3 files)
- [ ] Client trio re-chain → `Product::EnricherProducer` (3 files)
- [ ] Remove StreamAugmentation branch from ~24 remaining extract consumers
- [ ] Swap StreamAugmentation→Enrichment in ~24 remaining transformer consumers
- [ ] Remove StreamAugmentation model
- [ ] rubocop + eager-load
- [ ] amend + force-push
