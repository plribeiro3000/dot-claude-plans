# PLAN-SPIKE — Signature PDF Export (Urgent Customer Backfill)

> Reference: SPIKE.md (verified 2026-06-01) — codebase facts established there are not re-derived here.
> Revision: engineer review 2026-06-01 — direction decided; document restructured around two-phase architecture.

---

## Objective

A cancelled customer used 4Shark only for declarations. They want all their signed declarations delivered as PDFs, bundled in a ZIP with an XLSX manifest. No PDF is persisted today — the signed document is re-rendered on every view by the Angular SPA.

The architecture is two-phase. Phase 1 ships a frontend feature to `app-webclient`: a URL parameter and UX button that renders the declaration page fully expanded. This is a prerequisite for Phase 2. Phase 2 ships the backend to `app`: a Sidekiq fan-out that navigates Ferrum to the pre-expanded URL, captures PDF, uploads to S3, and finalizes with a ZIP + XLSX manifest.

---

## Scope

### In scope

**Phase 1 — `app-webclient` (ships first, standalone release):**
- A URL parameter that renders the declaration page (`/planStatements/:planStatementId`) fully expanded — all collapsible panels open, pagination fully expanded and stable through page load.
- A user-facing "expand all / collapse all" button that toggles the same expanded state; the URL flag and the button are backed by the same mechanism.
- Any second declaration page is to be confirmed at build time; the SPIKE established the primary route at `/planStatements/:planStatementId` with five `.show-panel` panels (SPIKE.md Findings 2–3).

**Phase 2 — `app` (requires Phase 1 to be deployed):**
- Producer worker: receives a `company_id`, enumerates ACCEPTED `plan_statement` IDs, creates the batch tracking record, fans out one per-declaration job each.
- Per-declaration consumer worker: Ferrum navigates to the pre-expanded URL, waits for page load (no panel-click logic needed — the URL parameter handles expansion), captures PDF, uploads to S3 via existing CarrierWave infrastructure, marks the per-declaration record done, gates on the computation counter.
- Finalizer worker: triggered when `computation.done?`, downloads all PDFs for the batch, generates XLSX manifest with `Axlsx::Package`, creates ZIP, uploads via existing batch uploader infrastructure, marks batch done.
- New low-concurrency Sidekiq queue for Ferrum/Chromium workers.
- `gem 'ferrum'` added to Gemfile.
- Chromium binary added to the worker Docker image (plain build task).

### Out of scope

- Long-term PDF persistence at signing time (the spike's Deliverable 1 — this backfill is the bridge, not the solution).
- New GraphQL mutation or UI for triggering the export (operator triggers via Rails console / rake task for this customer).
- Internal frontend implementation detail of the URL parameter or button (decided at build time).

---

## Phase 1 — Frontend (`app-webclient`)

The declaration page at `/planStatements/:planStatementId` has five collapsible panels controlled by Angular `*ngIf` — when `expanded` is false, the element is absent from the DOM, not just hidden (SPIKE.md Finding 3, verbatim: *"when `expanded` is false, the element is **absent from the DOM**, not just hidden with CSS"*).

The goal of Phase 1 is to make the page arrive at the browser already fully expanded, controlled by a URL parameter. The same mechanism is exposed as a user-facing "expand all / collapse all" button so the feature ships as a real UX improvement, not only as a backend workaround.

**Effect on Phase 2:** the per-declaration worker no longer needs to click `.show-panel` elements and wait for Angular change detection per-panel. It navigates to the pre-expanded URL and waits for page load. This removes the most fragile part of any headless-capture sequence.

**Phase 1 must ship and be deployed before Phase 2 workers are run.** This is a hard dependency — Phase 2 workers navigate to the pre-expanded URL; if Phase 1 has not shipped, the URL parameter has no effect and panels would be collapsed in the captured PDF.

---

## Phase 2 — Backend (`app`)

### Pattern 1: Producer → Consumer → Finalizer (fan-out with Redis computation counter)

**What it does in this system:** Every multi-record batch follows the same three-actor shape. A Producer plucks IDs and calls `Sidekiq::Client.push_bulk`. Each Consumer does per-record work and calls `computation.increment_executions`, then checks `computation.done?`. The last consumer to finish enqueues the Finalizer.

**Closest domain sibling** — `PlanStatementAudit::Producer` / `Consumer` / `Finalizer` at `app/app/workers/plan_statement_audit/`:

```ruby
# app/app/workers/plan_statement_audit/producer.rb:9-17
def perform(audit_id)
  plan_statement_audit = PlanStatementAudit.with_uncached_connection { PlanStatementAudit.find(audit_id) }
  PlanStatementAudit.with_uncached_connection { plan_statement_audit.process! }
  company = Company.with_uncached_connection { plan_statement_audit.company }
  plan_statement_ids = PlanStatement.with_uncached_connection { company.plan_statements.pluck(:id) }
  plan_statement_audit.computation.increment_queue(by: plan_statement_ids.count)
  arguments = plan_statement_ids.map { |plan_statement_id| [audit_id, plan_statement_id] }
  Sidekiq::Client.push_bulk('class' => PlanStatementAudit::Consumer, 'args' => arguments)
end
```

The computation counter is a Redis-backed object:

```ruby
# app/app/models/computation.rb:22-40
def increment_queue(by: 1)
  @queue_value = queue.increment(by: by)
end

def increment_executions(by: 1)
  @executions_value = executions.increment(by: by)
end

def reset_queue
  queue.reset
end

def reset_executions
  executions.reset
end

def done?
  queue_value == executions_value
end
```

The Consumer gates on `done?` and enqueues the Finalizer:

```ruby
# app/app/workers/plan_statement_audit/consumer.rb:65-69
plan_statement_audit.computation.increment_executions

return unless plan_statement_audit.computation.done?

Finalizer.perform_async(audit_id)
```

**Mapping to this feature:**

| Audit pattern | PDF export equivalent |
|---|---|
| `PlanStatementAudit` (model) | `PlanStatementPortableBatch` (already exists) |
| `audit.computation` | `plan_statement_portable_batch.computation` (needs to be added) |
| `PlanStatementAudit::Row` (per-record) | `PlanStatementPortable` (already exists) |
| CSV attachment via `Attachment` + uploader | PDF via `PlanStatementPortableAttachment`, ZIP via `PlanStatementPortableBatchAttachment` |

The `PlanStatementPortableBatch` state machine already has `initial → processing → final`:

```ruby
# app/app/models/plan_statement_portable_batch.rb:34-43
state_machine :status, initial: :initial do
  event :process do
    transition initial: :processing
    transition processing: :processing
  end

  event :finish do
    transition processing: :final
  end
end
```

The `PlanStatementPortable` per-record state machine:

```ruby
# app/app/models/plan_statement_portable.rb:20-24
state_machine :status, initial: :processing do
  event :finish do
    transition processing: :final
  end
end
```

**Note on existing model coupling:** `PlanStatementPortableBatch` has `validates :calendar_id, presence: true` (`plan_statement_portable_batch.rb:12`) and a `before_validation :add_plan_statements` callback (`plan_statement_portable_batch.rb:47, 57-66`) that auto-assigns plan statements from the calendar. This coupling to `calendar_id` does not fit a company-wide export spanning all calendars. A `computation` method also does not exist today on `PlanStatementPortableBatch` — it needs to be added. These are build-time decisions (see "Deferred — decided at build time" section).

See auxiliary: `batch_pattern_excerpts_aux_1.rb` — full verbatim excerpts of all relevant batch/portable model files.

---

### Pattern 2: File generation → CarrierWave assignment → S3 upload

**What it does:** Workers generate a file to `Rails.root.join('tmp', file_name)`, assign it to the attachment's `file` attribute, then call `finish!`. CarrierWave + fog-aws handles the S3 upload transparently.

```ruby
# app/app/workers/commission/report_generator.rb:10-12
report.file = CommissionWorkBook.new(commission).generate
commission_report_creation_event = CommissionReportCreationEvent.with_uncached_connection { report.commission_report_creation_event }
Attachment.with_uncached_connection { report.finish! }
```

The `generate` method returns a `File` object:

```ruby
# app/app/work_books/commission_work_book.rb:9-22
def generate
  @package = Axlsx::Package.new
  @workbook = @package.workbook
  style.add
  summary_work_sheet.add
  deal_work_sheet.add
  indicator_work_sheet.add
  indicator_premium_work_sheet.add
  ranking_work_sheet.add
  limiter_work_sheet.add
  redemption_work_sheet.add
  @package.serialize(file_path)
  File.new(file_path)
end
```

The CarrierWave bucket is `ApplicationConfiguration.aws_bucket` (`ENV['AWS_BUCKET']`):

```ruby
# app/config/initializers/carrierwave.rb:3-12
CarrierWave.configure do |config|
  config.fog_credentials = {
    provider: 'AWS',
    aws_access_key_id: ApplicationConfiguration.aws_access_key,
    aws_secret_access_key: ApplicationConfiguration.aws_secret_access_key
  }

  config.fog_directory = ApplicationConfiguration.aws_bucket
  config.fog_public = false
end
```

The per-declaration upload path (existing uploader, no change needed):

```ruby
# app/app/uploaders/plan_statement_portable_uploader.rb:4-6
def store_dir
  "uploads/plan_statement_portables/#{model.attachable_id}"
end
```

The batch (ZIP) upload path (existing uploader, no change needed):

```ruby
# app/app/uploaders/plan_statement_portable_batch_uploader.rb:4-6
def store_dir
  "uploads/plan_statement_portable_batches/#{model.attachable_id}"
end
```

See auxiliary: `xlsx_zip_pattern_excerpts_aux_2.rb` — full verbatim excerpts.

---

### Pattern 3: ACCEPTED-only enumeration

`plan_statements.status` is an enumerize with `pending: 0, accepted: 1, canceled: 2`:

```ruby
# app/app/models/plan_statement.rb:27-34
enumerize :status,
          in: {
            pending: 0,
            accepted: 1,
            canceled: 2
          },
          default: :pending,
          scope: true
```

The accepted scope:

```ruby
# app/app/models/plan_statement.rb:20
scope :accepted, -> { joins(:acceptment) }
```

The `for_company` scope:

```ruby
# app/app/models/plan_statement.rb:22
scope :for_company, ->(company_id) { where(company_id: company_id) if company_id.present? }
```

Index coverage for this query path — the `plan_statements` table has `index_plan_statements_on_company_id` (`app/db/schema.rb:1562`); the join to `acceptments` uses `index_acceptments_on_plan_statement_id` (`app/db/schema.rb:54`). Both are covered; no missing index.

The `company_id` column on `plan_statements` (`app/db/schema.rb:1554`):

```
# app/db/schema.rb:1553-1568
create_table "plan_statements", id: :serial, force: :cascade do |t|
  t.bigint "company_id"
  t.datetime "created_at", null: false
  t.integer "owner_id"
  t.integer "plan_id"
  t.bigint "plan_statement_portable_batch_id"
  t.integer "status"
  t.datetime "updated_at", null: false
  t.integer "user_id"
  t.index ["company_id"], name: "index_plan_statements_on_company_id"
  t.index ["owner_id"], name: "index_plan_statements_on_owner_id"
  t.index ["plan_id", "user_id"], name: "index_plan_statements_on_plan_id_and_user_id", unique: true
  t.index ["plan_id"], name: "index_plan_statements_on_plan_id"
  t.index ["plan_statement_portable_batch_id"], name: "index_plan_statements_on_plan_statement_portable_batch_id"
  t.index ["user_id"], name: "index_plan_statements_on_user_id"
end
```

The URL the worker navigates to uses `company.primary_webclient_host` (`app/db/schema.rb:520`):

```
# app/db/schema.rb:520
t.string "primary_webclient_host", default: "", null: false
```

Validated at `app/app/models/company.rb:78`:

```ruby
# app/app/models/company.rb:78
validates :primary_webclient_host, presence: true, format: { with: WEBCLIENT_FQDN_REGEX }
```

**Note:** `primary_webclient_host` is validated as present for active companies. A cancelled company may have had this set when active; the worker must guard against a blank value (see Risks).

---

## Authentication — decided

The per-declaration worker authenticates using a dedicated **service-account user** (username + password) created inside 4Shark's internal company that exists in each environment. The password is rotated regularly. The credentials are passed to the worker as a parameter. The worker logs in as that superadmin user, which can read every declaration page regardless of the cancelled company's state.

The exact credential-passing mechanism (env var vs argument) is a build-time detail — not a decision to make now.

**Background from SPIKE.md Finding 5:** the Angular app authenticates with a JWT Bearer token stored in `sessionStorage`/`localStorage` under the key `credentials`. The token is obtained by `POST /sessions` with `{ email, password }`. The headless browser calls `POST /sessions`, receives the token, and injects it into storage before navigating to the declaration URL. Every subsequent GraphQL request from the page picks up the token automatically via the `app.service.ts` auth link (`app-webclient/src/app/app.service.ts:28-34`).

---

## Manifest — decided shape

The XLSX manifest maps a customer-meaningful user identifier to our declaration id, the acceptance status, and the PDF filename. A SHA256 hash of the PDF content is also included (likely as a manifest column). The exact set of columns is a build-time detail — the manifest pattern from `PlanStatementAudit` (which already uses `user_name`, `user_primary_identifier_value`, `user_register_type`, `user_unique_register_id`, `plan_name`, `accepted`, `accepted_at`) is the natural starting point.

---

## Execution order

The following sequence is dependency-constrained:

1. **Phase 1: `app-webclient` PR** — URL parameter + "expand all / collapse all" button. Ships as a standalone release. **Must be deployed before Phase 2 workers are run.**
2. **Add `gem 'ferrum'` to `app/Gemfile`** — no existing Ferrum gem (`grep -n "ferrum" Gemfile` returns no results; `app/Gemfile:23` has `gem 'caxlsx'`, `app/Gemfile:70` has `gem 'rubyzip'` — both needed for manifest, already present; Ferrum is new).
3. **Add Chromium to the worker Docker image** — plain build task, blocks worker from running.
4. **Model layer** — configure batch and item tracking model(s); add `computation` method to batch model (or new model — build-time decision).
5. **New Sidekiq queue config** + ECS service definition (low concurrency, Chromium-bounded).
6. **Producer worker** — enumerate accepted plan statement IDs for company, create batch record, fan out.
7. **Per-declaration consumer worker** — Ferrum navigates to pre-expanded URL, waits for page load, captures PDF, uploads via CarrierWave, gates on `computation.done?`.
8. **Finalizer worker** — XLSX manifest generation (`Axlsx::Package`), ZIP creation (`rubyzip`), upload, `batch.finish!`.

Steps 4 and 5 are independent and can be done in parallel. Step 6 depends on 4. Steps 7 and 8 depend on 6. Step 1 is a separate repo and can be worked in parallel with steps 2–5.

---

## Deferred — decided at build time

These items are settled at implementation time and are not blocking decisions:

- **Batch/item model choice:** reuse `PlanStatementPortableBatch` / `PlanStatementPortable` (no migration, but needs `calendar_id` validation bypassed and `add_plan_statements` callback handled) vs new dedicated models (cleaner, requires two migrations). Either works with the same worker shape.
- **PDF filename convention:** human-readable (e.g. `<user_primary_identifier_value>-<plan_statement_id>.pdf`) vs ID-only. Engineer decides at build time.
- **Exact manifest columns:** start from `PlanStatementAudit` column set; adjust at build time.
- **SHA256 placement:** manifest column vs `.sha256` sidecar vs both. SHA256 is included; placement is a build-time detail.
- **XLSX inside ZIP vs alongside:** both shapes are valid. Decided at build time.
- **Customer delivery mechanism:** presigned URL via `Attachment#presigned_url` (already wired, `PlanStatementPortableBatchDownload` exists) vs manual handoff from S3 console. Decided at build time.
- **Sidekiq concurrency shape:** dedicated low-concurrency config file + new ECS service, or capped queue on an existing service. Either achieves the Chromium memory constraint. Decided at build time.
- **Exact credential-passing mechanism for the service account** (env var vs argument). Decided at build time.

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| Presigned signature PNG URL expires during render | Worker navigates to the declaration page; `temporarySignature` query returns a presigned URL with TTL from `ApplicationConfiguration.signed_url_expiration_time` (`app/lib/application_configuration.rb:77-78`: `Integer(ENV.fetch('SIGNED_URL_EXPIRATION', 10)).minutes.from_now`). If the worker queue runs slowly and a job is delayed past the TTL after the URL was fetched, the signature image will 403 — the PDF will be generated without the signature PNG | Each job navigates fresh (gets a new presigned URL on navigation); avoid batching URL resolution at fan-out time. Keep queue concurrency high enough to run each job within the TTL window after navigation |
| Chromium memory at high Sidekiq concurrency | At ~150–300 MB RAM per Chromium instance × default 25 threads (`app/lib/application_configuration.rb:73-74`: `Integer(ENV.fetch('SIDEKIQ_THREADS', 25))`) = 3.75–7.5 GB — likely OOM on the ECS task | Dedicated low-concurrency queue is a hard prerequisite before deploying Phase 2 workers |
| Phase 1 not deployed before Phase 2 runs | Declaration pages captured with all panels collapsed — PDFs are incomplete | Phase 1 deployment is step 1 in execution order; Phase 2 worker must not be run until Phase 1 is verified deployed |
| `company.primary_webclient_host` blank for a cancelled company | Worker cannot construct the declaration URL | Guard in the producer: if blank, abort with a clear error message before fanning out any jobs |

---

## Sources

- `app/app/workers/plan_statement_audit/producer.rb:9-17` — canonical producer pattern (pluck + push_bulk)
- `app/app/workers/plan_statement_audit/consumer.rb:65-69` — canonical consumer gate pattern
- `app/app/models/computation.rb:22-40` — Redis counter (queue/executions/done?)
- `app/app/models/plan_statement_portable_batch.rb:34-43` — batch state machine
- `app/app/models/plan_statement_portable_batch.rb:12` — `validates :calendar_id, presence: true` (coupling)
- `app/app/models/plan_statement_portable_batch.rb:47, 57-66` — `before_validation :add_plan_statements` callback (coupling)
- `app/app/models/plan_statement_portable.rb:20-24` — per-record state machine
- `app/app/models/plan_statement.rb:20` — `scope :accepted, -> { joins(:acceptment) }`
- `app/app/models/plan_statement.rb:22` — `scope :for_company`
- `app/app/models/plan_statement.rb:27-34` — status enum
- `app/db/schema.rb:1553-1568` — `plan_statements` table + indexes (company_id covered)
- `app/db/schema.rb:38-57` — `acceptments` table + indexes
- `app/db/schema.rb:1969-1979` — `signatures` table
- `app/db/schema.rb:520` — `primary_webclient_host` column
- `app/app/models/company.rb:78` — `validates :primary_webclient_host, presence: true`
- `app/app/workers/commission/report_generator.rb:10-12` — file generation → CarrierWave assignment pattern
- `app/app/work_books/commission_work_book.rb:9-22` — `Axlsx::Package` generate pattern
- `app/app/uploaders/plan_statement_portable_uploader.rb:4-6` — existing PDF upload path
- `app/app/uploaders/plan_statement_portable_batch_uploader.rb:4-6` — existing batch (ZIP) upload path
- `app/config/initializers/carrierwave.rb:3-12` — CarrierWave fog-aws config (single bucket)
- `app/Gemfile:23` — `gem 'caxlsx', require: 'axlsx'`
- `app/Gemfile:70` — `gem 'rubyzip'` (present; no production usage found)
- `app/config/sidekiq_user.yml:5-15` — existing user worker queues
- `app/lib/application_configuration.rb:73-74` — `SIDEKIQ_THREADS` default 25
- `app/lib/application_configuration.rb:77-78` — `signed_url_expiration_time` (default 10 minutes)
- SPIKE.md Finding 2 — route `/planStatements/:planStatementId`
- SPIKE.md Finding 3 — five `*ngIf`-controlled `.show-panel` panels; `expanded` property; DOM-absent when collapsed
- SPIKE.md Finding 4 — presigned signature PNG URL fetched via second async GraphQL call after page load
- SPIKE.md Finding 5 — JWT Bearer token in `localStorage`/`sessionStorage` under key `credentials`; `POST /sessions` login endpoint
- SPIKE.md Finding 8 — required sequence for headless capture of declaration page
- See auxiliary files: `batch_pattern_excerpts_aux_1.rb`, `xlsx_zip_pattern_excerpts_aux_2.rb`, `signature_excerpt_1.ts`, `signature_excerpt_2.html`
- https://rubygems.org/gems/ferrum — version 0.17.2 (2026-03-23); requires Ruby >= 3.1
