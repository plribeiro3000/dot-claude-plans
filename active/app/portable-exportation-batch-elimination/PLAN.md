# PLAN — Eliminate the portable batch entities; PortableExportation owns portables directly

**Date:** 2026-08-07
**Repo:** `app` — branch `feature/portable-exportation-coordinator` (PR #5289, worktree `.claude/worktrees/portable-exportation-coordinator`)
**Follows:** the CarrierWave delivery rework (already on the branch) and the FK rework SPIKE (`active/spike/portable-plan-statement-relation-rework/`).

## Decision

Eliminate `PlanStatementPortableBatch` and `StatementPortableBatch`. `PortableExportation` becomes the direct owner of `PlanStatementPortable` (rule) and `StatementPortable` (result). The exportation answers "which rule portables / which result portables are mine" directly; the folder each PDF is filed under is a business rule computed at finalize time, never persisted or structured in the database.

## Why the batch can go

The batch is not the aggregator and never sustained the delivery grouping. Two facts settle it:

- The delivery folder is already derived at finalize time from each portable's own graph — the rule folder from `portable.statement.plan.calendar`, the result folder from `portable.statement.commission.plan`. The batch's per-calendar identity is never read to build a path. So grouping is a finalize-time computation, not stored state.
- The batch is only the coordinator's mid-level fan-out + `Computation` anchor, and that role collapses into a single `Computation` on `PortableExportation` counting all portables. The standalone per-audit batch flow that originally justified the entity is dead code (no create mutation, no caller of either standalone `Producer` anywhere in app/lib/config).

## Target topology

One level of fan-out, one `Computation` on the exportation counting rule + result portables together.

- The fan-out worker is a **`Producer`**, not a `Processor` — it fans out into parallel consumers and coordinates completion through `Computation`, which is the Producer role (`DATA-PROCESSING.md`). The current class is misnamed `PortableExportation::Processor`; the rewrite lands it as `PortableExportation::Producer`.
- The `Producer` pulls all matching plan-statement ids and all matching statement ids up front, sets `portable_exportation.computation.increment_queue(by: rule_count + result_count)`, and `push_bulk`s both consumer types keyed on `[portable_exportation_id, statement_id]`. Empty on both → `Finalizer` directly.
- The two consumers create the join record under the exportation (`portable_exportation.plan_statement_portables.find_or_create_by(statement:)` / `.statement_portables.find_or_create_by(statement:)`), generate the PDF, mount the portable's own attachment, increment `portable_exportation.computation`; when done → `Finalizer`.
- `ResultProducer` is deleted — a single Computation over both natures removes the need for the sequential rule-then-result stage.
- `Finalizer` (already CarrierWave/zip on this branch) reads `portable_exportation.plan_statement_portables` / `.statement_portables` instead of walking batches; folder computation stays inline as today.

## Change surface

### Associations / models
- `PortableExportation`: replace `has_many :plan_statement_portable_batches` / `has_many :statement_portable_batches` with `has_many :plan_statement_portables` and `has_many :statement_portables` (role names, no stutter). Keep `has_one :attachment` (the zip). Fix the `belongs_to :user` `inverse_of`: it points at `:owned_portable_exportations`, whose foreign key on `User` is `owner_id` — that inverse belongs to `belongs_to :owner`, not `:user`. The `user` side needs its own `User` association (`foreign_key: :user_id`) and matching `inverse_of`, or drop the `inverse_of` on `user`.
- `PlanStatementPortable` / `StatementPortable`: `belongs_to :portable_exportation` replacing `belongs_to :batch`. Keep `has_one :attachment`, `has_many :downloads`, `file_name(date:)`.
- Delete models: `PlanStatementPortableBatch`, `StatementPortableBatch`, `PlanStatementPortableBatchAttachment`, `StatementPortableBatchAttachment`, `PlanStatementPortableBatchDownload`, `StatementPortableBatchDownload`.
- Remove the batch attachment/download `type` values from `Attachment::TYPES` and the download STI type list.
- Remove batch associations from `Company`, `Calendar`, `Plan`, `User`, `Download`.

### Workers
- Rewrite `PortableExportation::Processor` (single-level fan-out, both natures).
- Rewrite the consumers to hang the portable on the exportation. Where they live is a decision below.
- Delete `PortableExportation::ResultProducer`.
- Delete the standalone workers: `PlanStatementPortableBatch::{Producer,Consumer,Finalizer}`, `StatementPortableBatch::{Producer,Consumer,Finalizer}`.

### Uploaders / workbooks / GraphQL / policies (dead standalone surface)
- Delete uploaders `PlanStatementPortableBatchUploader`, `StatementPortableBatchUploader`.
- Delete workbooks `PlanStatementPortableWorkBook` (+ worksheet), `StatementPortableWorkBook` (+ worksheet).
- Delete GraphQL types `plan_statement_portable_batch_graphql_type`, and the batch download mutation(s); audit `plan_statement_portable_graphql_type` + the portable download mutations for whether the per-audit download surface is kept or dropped (decision below).
- Delete policy `plan_statement_portable_batch_policy`.
- Audit `download_attachment_form`, `attachment_graphql_type`, `download.rb` for batch references.

### Migrations (one action per migration, generated not hand-written)
Adding the reference to a populated table uses the strong_migrations safe form — `index: { algorithm: :concurrently }`, `foreign_key: { validate: false }`, `disable_ddl_transaction!` — not `safety_assured`. `safety_assured` is only for an operation with no safe form, documented at the call site. (The batch tables are empty/purged, so their own reference migrations already on the branch are low-risk, but the pattern for the portable tables below is the safe form.)

1. Add `portable_exportation_id` (`references`, safe concurrent form) to `plan_statement_portables`.
2. Add `portable_exportation_id` to `statement_portables`.
3. Remove `plan_statement_portable_batch_id` from `plan_statement_portables`.
4. Remove `statement_portable_batch_id` from `statement_portables`.
5. Remove `plan_statements.plan_statement_portable_batch_id` — the deferred FK-rework column. **This is the one migration with production weight**: `plan_statements` is a large core table, so it takes the strong_migrations two-step (ship `ignored_columns` first, then `remove_column`). The column is 100% null in production (purged) and the feature is unreleased, which lowers risk but does not remove the two-step requirement on a core table.
6. Drop table `plan_statement_portable_batches`.
7. Drop table `statement_portable_batches`.

`attachments` and `downloads` are single STI tables — no table drop there; the batch rows were purged, so only the models + `type` whitelist entries are removed.

## Open decisions to confirm before execution

1. **Consumer placement / naming.** With the batch gone, the natural home is `PortableExportation::PlanStatementConsumer` and `PortableExportation::StatementConsumer` (or a single parametrized consumer). Naming follows the topology.
2. **The per-audit download surface.** `download_plan_statement_portable_graphql_mutation` + `plan_statement_portable_graphql_type` expose downloading a single portable. Decide whether the coordinator keeps any per-portable download surface or the only deliverable is the exportation zip. If the latter, those go too.
3. **Migration split vs deploy.** Whether the `plan_statements` column drop ships as its own PR ahead of the rest (cleanest for the two-step) or folds into this branch.

## Validation
- rubocop clean on every touched file; model specs green; `bin/rails db:migrate` regenerates `db/schema.rb`; boot-check that the new associations resolve and no dangling constant references remain (grep for every deleted class name across app/).
- Re-run the coordinator flow end to end on a seeded company (rule + result) and confirm the zip has both trees + index.
