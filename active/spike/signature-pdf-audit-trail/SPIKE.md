# SPIKE — Signature PDF Audit Trail (extends Signature PDF Export)

## Investigation question

For the cancelled-customer declaration backfill already planned in `~/Projects/4Shark/dot-claude-plans/active/spike/signature-pdf-export/PLAN.md`, what evidentiary trail can accompany each delivered PDF so the simple electronic signature (drawn PNG + login authentication) remains defensible if a participant later disputes the acceptance? Specifically: what acceptance/authentication evidence does the `app` codebase actually persist today (does the engineer's belief that IP + time are stored hold up), where does a broader access history live and how far back does it reach, how does a per-declaration PDF hash fit the existing Consumer/Finalizer flow, what are the packaging options for this evidentiary metadata, and how does adding it preserve the existing completeness guarantee (the `Computation` Redis counter)?

This spike does not replace the existing plan — it extends it. Everything in `PLAN.md`'s Chosen Approach, End-to-end flow, and Phase 2.1–2.2 stands unchanged. Only Phase 2.3 (Consumer) and Phase 2.4 (Finalizer) gain new evidentiary-metadata steps, and the "Deferred — decided at build time" section gains new open items (this spike's Findings 3 and 4).

---

## Sources consulted

- `app/app/models/acceptment.rb` — the `Acceptment` model; `from` (IP) and `signed` fields, validations
- `app/app/models/signature.rb` — the `Signature` model; drawn-PNG storage, no auditing fields
- `app/app/models/plan_statement.rb` — `sign_by`/`accept_by`, `forced_acceptance?`
- `app/app/graphql_mutations/accept_plan_statement_v2_graphql_mutation.rb` — the mutation that calls `sign_by`, and what request context it forwards
- `app/app/graphql_mutations/application_mutation.rb` — `method_missing` delegating to GraphQL `context`
- `app/app/controllers/graphql_controller.rb:52-59` — what request context (`remote_ip`, `user_agent`, `channel`) is placed into every GraphQL mutation's context
- `app/db/schema.rb` — `acceptments` (lines 38-57), `signatures` (2058-2068), `security_events` (2034-2056), `plan_statement_audit_rows` (1548-1571) table definitions
- `app/app/models/security_event.rb` — the `SecurityEvent` model, `TYPES`, `channel_for`
- `app/app/controllers/sessions_controller.rb` — where `SecurityEvent.create` is called on login success/failure, with what fields
- `app/docs/architecture/SECURITY_EVENTS.md` — the design doc for the security-events platform (opt-in history, TYPES catalog)
- `app/db/migrate/2026/05/20260528120001_create_security_events.rb` and the seven other migrations touching `security_events`/`security_events_module` — see auxiliary `signature-pdf-audit-trail_migration_log_1.txt`
- `app/app/workers/plan_statement_audit/consumer.rb` — the sibling Consumer pattern (per-declaration `Row` model population), used as the reference shape for where new evidentiary fields would be written
- `app/Gemfile` — checked for an existing PDF-merge gem (none found) and an existing SHA256/hashing pattern in `app/app/` (none found)
- `~/Projects/4Shark/dot-claude-plans/active/spike/signature-pdf-export/PLAN.md` — the existing engineer-approved plan this spike extends
- `~/Projects/4Shark/dot-claude-plans/active/spike/signature-pdf-export/SPIKE.md` — the existing research this spike builds on
- https://ajuda.clicksign.com/article/230-log-presente-nos-documentos-assinados — ClickSign's own description of what its audit log contains
- https://www.clicksign.com/validade-juridica — ClickSign's legal-validity explainer
- https://geracontratos.com.br/recursos/lei-assinatura-eletronica-brasil — MP 2.200-2 art. 10 §2º text
- https://supersign.com.br/blog/validade-juridica-assinatura-digital/ — SuperSign's audit-trail elements

---

## Findings

### Finding 1: The engineer's belief holds — IP and acceptance timestamp ARE persisted per declaration; no user agent, device fingerprint, or session identifier is

**Evidence:**
```ruby
# app/app/models/plan_statement.rb:83-105
def sign_by(user_id:, from:, signature:)
  transaction do
    create_acceptment!(
      user_id: user_id,
      from: from,
      signed: true,
      company_id: company_id,
      signature_attributes: {
        raw_file: { name: "ps_#{id}#{user_id}", base64_content: signature },
        company_id: company_id,
        user_id: user_id
      }
    )
    accept!
  end
  ...
```
```ruby
# app/db/schema.rb:38-49 (acceptments table)
t.integer "acceptment_document_id"
t.bigint "acceptment_reason_id"
t.bigint "company_id"
t.datetime "created_at", null: false
t.integer "document_line"
t.string "from", limit: 8000
t.bigint "plan_statement_id", default: 0
t.boolean "signed", default: true, null: false
```
`Acceptment` validates `from` as an IP: `validates :from, ip: true, allow_blank: true` and `validates :from, presence: true` (`app/app/models/acceptment.rb:14-15`). `created_at` is the acceptance timestamp — `PlanStatement#accepted_at` reads it directly: `acceptment.created_at` (`app/app/models/plan_statement.rb:60-64`).

The `from` value traces to the real client IP, not a placeholder: the GraphQL mutation that signs a declaration calls `sign_by(user_id: current_user.id, from: remote_ip, signature: base64_signature)` (`app/app/graphql_mutations/accept_plan_statement_v2_graphql_mutation.rb:13`), and `remote_ip` resolves via `ApplicationMutation#method_missing` to `context[:remote_ip]` (`app/app/graphql_mutations/application_mutation.rb:36-40`), which `GraphqlController` sets from `request.remote_ip` (`app/app/controllers/graphql_controller.rb:57`) — the same Rack-standard IP resolution the platform's `SecurityEvent` login capture uses.

The `signatures` table (`app/db/schema.rb:2058-2068`) has no auditing columns of its own — `acceptment_id`, `company_id`, `created_at`, `file`, `updated_at`, `user_id`. `Signature` (`app/app/models/signature.rb`) exposes only file-handling logic (`raw_file=`, `extension`, `presigned_url`) — no capture of user agent, device, or session.

**A gap in the raw material vs. what is persisted**: `GraphqlController` places `user_agent: request.user_agent` into the same context object as `remote_ip` (`app/app/controllers/graphql_controller.rb:58`), and `ApplicationMutation#method_missing` would resolve `user_agent` the same way `remote_ip` resolves — but `AcceptPlanStatementV2GraphqlMutation#execute` never reads it, and `sign_by`'s signature has no parameter to carry it (`app/app/models/plan_statement.rb:83`). The user agent is available in-request at the moment of signing; it is simply not passed through or persisted.

**Source:** `app/app/models/plan_statement.rb:83-105`, `app/db/schema.rb:38-49`, `app/app/models/acceptment.rb:14-15`, `app/app/graphql_mutations/accept_plan_statement_v2_graphql_mutation.rb:13`, `app/app/graphql_mutations/application_mutation.rb:36-40`, `app/app/controllers/graphql_controller.rb:52-59`, `app/db/schema.rb:2058-2068`

**Significance:** For every ACCEPTED `PlanStatement` the Producer's scope already selects (`PlanStatement.for_company(company_id).accepted`, `app/app/models/plan_statement.rb:20`), the `acceptment` record gives an authenticated user id, an IP address, and a timestamp for free — no schema change needed to read these three. A user-agent/device value does not exist on any past row and cannot be backfilled; it can only be captured going forward if the mutation is changed to persist it.

---

### Finding 2: A broader "histórico de acesso" exists (`SecurityEvent`), captures IP + user agent on login, is unconditional today for every company — but only from 2026-05-28 onward, and is not linked to any declaration

**Evidence:**
```ruby
# app/app/controllers/sessions_controller.rb:17-34
if valid_credentials
  channel = SecurityEvent.channel_for(request)
  metadata = {}
  metadata[:app_version] = request.user_agent[/ - Mobile - ([\d.]+)\z/, 1] if channel == 'mobile'

  SecurityEvent.create(
    event_type: 'authentication.login_success',
    severity: SecurityEvent::SEVERITY_BY_TYPE.fetch('authentication.login_success'),
    outcome: 'success',
    auth_method: 'password',
    channel: channel,
    ip_address: request.remote_ip,
    user_agent: request.user_agent,
    company_id: user.company_id,
    user_id: user.id,
    metadata: metadata,
    occurred_at: Time.current
  )
```
There is no company-flag check anywhere in this controller — the capture runs unconditionally on every successful (and failed) login. This is confirmed by the migration history: `security_events_module` was added on `companies` as an opt-in flag defaulting to `false` (`app/db/migrate/2026/05/20260528120005_add_security_events_module_to_companies.rb:5`), then its default was flipped to `true` (`20260529130001`), then every existing company was backfilled to `true` (`20260529130002: Company.update_all(security_events_module: true)`), then the column was **removed entirely** (`app/db/migrate/2026/06/20260603200012_remove_security_events_module_from_companies.rb:5`: `safety_assured { remove_column :companies, :security_events_module }`). Confirmed absent from the live schema: `grep -n "security_events_module" app/db/schema.rb` returns zero matches. Full migration list and the exact diffs are in the auxiliary file.

`SecurityEvent` is queryable per user via `scope :for_user, ->(user_id) { where(user_id: user_id) if user_id.present? }` and by date via `scope :after_date` / `scope :before_date` (`app/app/models/security_event.rb:49-56`), and carries `ip_address` and `user_agent` (`app/db/schema.rb:2034-2050`). But the `TYPES` catalog is authentication + user-lifecycle + API-token events only — `login_success`, `login_failure`, `logout`, `session_refresh`, `password_changed`, `account_locked/unlocked`, `user.disabled/reactivated`, `api.token_created/revoked` (`app/app/models/security_event.rb:30-34`). No event type exists for "declaration accepted" or "declaration signed" — a `SecurityEvent` row records that a user logged in from IP X with user agent Y at time T, not that a specific `PlanStatement` was signed. Correlating a login event to a specific acceptance requires matching `security_events.user_id` + proximity of `occurred_at` to `acceptments.created_at` — there is no foreign key or `resource_id` linkage (the `resource_type`/`resource_id` columns exist on the table but are used only by the API-token event types, per `docs/architecture/SECURITY_EVENTS.md` Scenario 3).

**Source:** `app/app/controllers/sessions_controller.rb:17-34`, `app/db/migrate/2026/05/20260528120005_add_security_events_module_to_companies.rb:5`, `app/db/migrate/2026/05/20260529130001_change_security_events_module_default_to_true.rb`, `app/db/migrate/2026/05/20260529130002_enable_security_events_module_for_all_companies.rb`, `app/db/migrate/2026/06/20260603200012_remove_security_events_module_from_companies.rb:5`, `app/app/models/security_event.rb:30-34,49-56`, `app/db/schema.rb:2034-2056`; auxiliary `signature-pdf-audit-trail_migration_log_1.txt`

**Significance:** For any acceptance signed after 2026-05-28, a correlating login-audit row likely exists (same user, IP, and a plausible time window) and could corroborate the `acceptments.from`/`created_at` pair with an independent capture that also has the user agent. For any acceptance signed **before** 2026-05-28 — which, for a customer already cancelled and being backfilled, is the more likely case for at least some of their declarations — no `security_events` row exists at all; `SecurityEvent`'s own table did not exist yet. This spike found no way to establish, from the codebase alone, which of the customer's declarations fall on which side of that date — see "What remains uncertain."

---

### Finding 3: A per-declaration PDF hash has no existing precedent in the codebase; it is a straightforward stdlib addition, and it proves a different thing than the acceptance evidence in Finding 1

**Evidence of absence:** `grep -rln "Digest::SHA256\|Digest::SHA2" app/app/` returns no matches — no existing hashing pattern to follow. Ruby's `Digest::SHA256` is standard-library, requiring no new gem.

**Where it fits the existing flow:** the existing `PLAN.md` already names the addition (`"XLSX manifest shape ... SHA256 hash of PDF content included"`, `PLAN.md:54`) and leaves its exact placement Deferred (`"SHA256 placement: manifest column vs .sha256 sidecar vs both"`, `PLAN.md:220`). Two points in the existing flow can compute it:

- **Inside the Consumer** (Phase 2.3, `PLAN.md:147-166`), right after Ferrum captures the PDF to `Rails.root.join('tmp', ...)` and before the CarrierWave upload discards the local temp file (`PLAN.md:155`) — the file is on local disk at that moment, so `Digest::SHA256.file(local_path).hexdigest` costs one file read, no extra I/O.
- **Inside the Finalizer** (Phase 2.4, `PLAN.md:168-184`), which already downloads each PDF from S3 to build the ZIP (`"Fetches all completed per-declaration records for the batch; downloads each PDF from S3"`, `PLAN.md:172`) — the hash could be computed there instead, on the already-downloaded copy, at the cost of the Consumer's per-declaration tracking record needing no new field.

**A distinction worth keeping explicit:** the PDF hash proves the *delivered artifact* was not altered after generation (integrity of the export) — it says nothing about who accepted the declaration, from where, or when. That evidence is Finding 1's `acceptments.from`/`created_at` (and, where available, Finding 2's `security_events` row). A customer disputing "I never signed this" is answered by Finding 1/2; a customer disputing "this PDF was tampered with after 4Shark generated it" is answered by Finding 3's hash. Both are useful; neither substitutes for the other.

**Source:** `app/PLAN.md:54,147-166,168-184,220` (cited from `~/Projects/4Shark/dot-claude-plans/active/spike/signature-pdf-export/PLAN.md`), grep result for `Digest::SHA256` in `app/app/` (no matches — absence confirmed, not assumed)

**Significance:** The hash-placement choice (Consumer vs Finalizer) is orthogonal to the evidentiary-metadata packaging choice in Finding 4 below — a hash of the PDF and a record of who-accepted-from-where can be computed and stored independently, and both can land in whichever packaging option the engineer picks.

---

### Finding 4: Four packaging options exist for the evidentiary metadata; none is precluded by the existing Consumer/Finalizer/uploader infrastructure

The existing `PLAN.md` already establishes the Finalizer's packaging tools — `Axlsx::Package` for the XLSX manifest (present at `Gemfile:23`, pattern at `app/app/work_books/commission_work_book.rb:9-22`) and `rubyzip` for the ZIP (present at `Gemfile:70`) — and the sibling `PlanStatementAudit::Consumer` shows the concrete shape of writing one row of fields per declaration during the fan-out (`app/app/workers/plan_statement_audit/consumer.rb:20-63`, e.g. `row.accepted_at = plan_statement.accepted_at`, `row.accepted_by = user.name`). Each option below reuses that same machinery differently.

| Option | What it looks like | What RedeBrasil could present as proof | Fit with existing Consumer/Finalizer |
|---|---|---|---|
| **(a) Sidecar file per declaration** (engineer's leaning) | A `<id>.txt` or `<id>.json` alongside `<id>.pdf` in the ZIP, same basename, containing `ip`, `accepted_at`, `signed_by`, `sha256` | A standalone, per-declaration artifact that travels with its PDF even if the PDF is extracted from the ZIP and handed to a third party (lawyer, auditor) in isolation | Consumer already writes the PDF to `Rails.root.join('tmp', ...)` before CarrierWave upload (`PLAN.md:155`) — writing a second small file next to it, then uploading both, is an additive step in the same worker. The Finalizer's ZIP-build step (`PLAN.md:174`) adds the sidecar into the archive alongside each PDF, no new dependency |
| **(b) XLSX manifest columns** | New columns on the existing manifest sheet — e.g. `accepted_ip`, `accepted_at`, `sha256` — alongside the columns `PLAN.md:54` already plans (`user_name`, `plan_name`, `accepted`, `accepted_at`, ...) | One spreadsheet the customer can filter/sort across every declaration at once — good for a bulk audit, weaker as a standalone artifact per PDF (loses the 1:1 pairing if the PDF is separated from the manifest) | Zero new packaging machinery — it is the same `Axlsx::Package` build already planned (`PLAN.md:173`, `commission_work_book.rb:9-22` pattern), just more columns on the row the Finalizer already writes |
| **(c) Audit page appended to each PDF** | A second page rendered into the same PDF file, listing the evidentiary fields, visible whenever anyone opens the PDF | Self-contained — the proof travels inside the artifact itself, cannot be separated from it, closest in spirit to the ClickSign log page described in Finding 3 below | Requires either a second Ferrum-rendered HTML page merged into the first, or a PDF-merge library — `grep -n "pdf\|hexapdf\|combine_pdf\|origami" Gemfile` returns no matches, so this is a **new gem dependency**, unlike (a)/(b)/(d). Also couples the audit content's rendering to the same Angular-page-navigation flow Phase 1 already built for the declaration itself, or requires a second, separate rendering path |
| **(d) Embedded PDF metadata (XMP/Info dictionary)** | The evidentiary fields written into the PDF's own metadata fields (e.g. `Keywords`, a custom XMP field) — invisible unless the viewer inspects document properties | Weakest as visible proof (most viewers do not surface custom metadata to an end user without extra tooling) but preserves a 1:1, tamper-evident-if-hashed pairing without a second visible page | Ferrum's CDP `Page.printToPDF` does not expose a metadata-injection parameter in the option surface this spike found; writing custom PDF metadata after generation needs a PDF-manipulation library — same new-dependency cost as (c) |

**Source:** `PLAN.md:54,155,173,174` (`signature-pdf-export/PLAN.md`), `app/app/workers/plan_statement_audit/consumer.rb:20-63`, `Gemfile:23,70`, grep result for `pdf\|hexapdf\|combine_pdf\|origami` in `Gemfile` (no matches — absence confirmed)

**Significance:** (a) and (b) reuse existing infrastructure with no new dependency and are the two lowest-cost options; (c) and (d) both require a new PDF-manipulation gem the codebase does not currently have, for different reasons (visible embedded page vs invisible metadata). (a) and (b) are not mutually exclusive with each other or with (c)/(d) — a manifest column AND a sidecar file is a legitimate combination, not a forced choice. **Round 3 grounds each of these four options against what real e-signature platforms actually do — see below. The engineer subsequently settled on separate-file delivery (Round 4 header note); this Finding's table is preserved as the record of the full option space that decision was made against.**

---

### Finding 5: Adding evidentiary-metadata generation to the Consumer keeps the existing `Computation` completion guarantee intact; adding it only to the Finalizer also works but changes what "done" means for a single record

**Evidence — the existing completion gate, unmodified by this addition:**
```ruby
# app/app/workers/plan_statement_audit/consumer.rb:63-70 (sibling pattern cited in PLAN.md)
PlanStatementAudit::Row.with_uncached_connection { row.save! }

plan_statement_audit.computation.increment_executions

return unless plan_statement_audit.computation.done?

Finalizer.perform_async(audit_id)
```
The existing `PLAN.md` already places the equivalent gate in the planned `PlanStatementExport::Consumer`: `"Call computation.increment_executions; if computation.done?, enqueue Finalizer"` (`PLAN.md:157`), matching this exact pattern.

**Where the new step goes, and what each placement means for the guarantee:**

- **Inside the Consumer, before `increment_executions`** — if the evidentiary-metadata write (Finding 1's IP/timestamp read, Finding 3's hash computation, and, per Finding 4's chosen packaging, either a sidecar-file write/upload or a tracking-record field write) happens before the counter increments, then a declaration only counts as "done" once its evidence is captured. This is the same shape the existing plan already uses for the PDF capture itself (`PLAN.md:157`) — no new failure mode is introduced, because a failure in the new step fails the whole Consumer job the same way a Ferrum capture failure already would, and Sidekiq's existing retry behavior covers it. This placement keeps the "every ACCEPTED declaration gets a PDF" guarantee and extends it to "every ACCEPTED declaration gets a PDF **and** its evidence" as one atomic unit per record.
- **Inside the Finalizer, after `computation.done?`** — the Finalizer already fetches all completed per-declaration records and downloads each PDF from S3 (`PLAN.md:172`); reading `acceptment.from`/`created_at` per record and building the manifest columns or sidecar files there is equally possible, since by that point every Consumer has already finished and the completion gate has already fired. This placement means a Finalizer failure after `computation.done?` (but before the ZIP finishes) has to be retried at the batch level rather than the per-record level — the same retry granularity difference that already exists between Consumer-level and Finalizer-level failures in the current plan, not a new one this addition introduces.

Either placement is compatible with the Deferred "Batch/item model choice" decision in the existing plan (`PLAN.md:216`, reusing `PlanStatementPortableBatch`/`PlanStatementPortable` vs new dedicated models) — a new dedicated model has room for new columns without touching a shared table; reusing the existing models would need new columns added to those shared tables regardless of which worker writes them. **Round 5 (below) is the full reuse-vs-new investigation this Deferred item calls for.**

**A correctness nuance that affects Finding 1's evidence, independent of placement:** `PlanStatement#forced_acceptance?` returns true when `accepted? && user_id != acceptment.user_id` (`app/app/models/plan_statement.rb:107-109`) — an admin can accept/sign a declaration on behalf of the plan's owner. When this happened, the IP/timestamp on `acceptments.from`/`created_at` belongs to the **acting** admin, not the plan's owner. Whichever worker reads Finding 1's evidence should read `acceptment.user_id` (the actual signer) rather than assume it always equals `plan_statement.user_id`, or the packaged evidence will misattribute authorship for any forced-acceptance record. The sibling `PlanStatementAudit::Consumer` already handles this distinction explicitly (`row.accepted_by = user.name` sourced from `acceptment.user` when `forced_acceptance?`, `app/app/workers/plan_statement_audit/consumer.rb:52-61`) — the same conditional would need to carry over. **This nuance is fully resolved with citations in Round 2 below (Findings 6-9).**

**Source:** `app/app/workers/plan_statement_audit/consumer.rb:52-70`, `PLAN.md:157,172,216`, `app/app/models/plan_statement.rb:107-109`

**Significance:** Completeness for the new evidentiary data follows the same mechanism completeness for the PDF itself already follows — the `Computation` counter gates the Finalizer regardless of which worker generates the new evidence, so no new completeness risk is introduced by this addition. The choice between Consumer-time and Finalizer-time generation is a placement decision, not a correctness one; the `forced_acceptance?` nuance is correctness-relevant regardless of placement.

---

## Legal context — what the engineer's premise rests on (external, not codebase)

The engineer's premise — that a bare rendered PDF is weak proof and the legal weight lives in an audit trail — is grounded in the platform's own status as a **simple electronic signature** platform, not an ICP-Brasil digital-certificate signature.

MP 2.200-2/2001 art. 10 §2º, quoted verbatim from geracontratos.com.br: *"Outros métodos de assinatura eletrônica (sem ICP-Brasil) também são válidos, desde que as partes concordem em utilizá-los."* — a non-ICP-Brasil signature method is valid when the parties agree to use it, which is the statutory basis for 4Shark's drawn-PNG + login flow being usable at all.

ClickSign — a commercial e-signature platform used here only as an industry reference point for what an audit artifact conventionally contains, not as a legal authority — describes its own audit log verbatim: *"É nela que fica registrado de forma detalhada todo o processo de identificação e responsabilidades dos signatários (quem assina) do documento, com informações como nomes, endereços de IP, e-mails, métodos de autenticação e assinatura e dia e horários em que foram assinados."* (ajuda.clicksign.com). This maps directly onto what Finding 1 confirms 4Shark already has (IP, signer, timestamp) and what it does not have (email/auth-method detail beyond password login, which the platform does not track per acceptance either).

SuperSign, a second commercial reference, names the same elements: *"Rastreabilidade completa (IP, dispositivo, data, hora)"* (supersign.com.br) — device is the one element in this list that 4Shark's `acceptments` table does not carry (Finding 1), and that `security_events` can only sometimes supply (Finding 2, date-bounded from 2026-05-28).

**None of this is a legal recommendation** — it is industry practice cited to give the engineer a concrete external reference point for what "the audit trail" conventionally contains, to compare against what Findings 1–5 show the codebase already has, does not have, and could add.

**Verification:** all three quotes above were confirmed present verbatim on a second, targeted re-fetch of each URL (self-check per Citation Discipline) before inclusion here.

---

## What remains uncertain

- **Whether the cancelled customer's declarations were signed before or after 2026-05-28.** This spike found no way to determine this from the codebase — it depends on when this specific customer's declarations were created, which is production data this spike does not have access to. It directly decides how much of Finding 2's `security_events` corroboration is actually available for this backfill, versus how many declarations only have Finding 1's `acceptments.from`/`created_at`.
- **Whether the Consumer or the Finalizer should read the evidentiary data**, per Finding 5 — both are viable; the choice affects failure-retry granularity, not correctness.
- ~~**Which of Finding 4's four packaging options (or combination) the engineer wants**~~ — **resolved by the engineer in Round 4: separate file (Option (a)-shaped), because appending changes the final PDF's image hash.**
- **Whether `user_agent` should be captured going forward** on new acceptances (Finding 1's gap) — this is a change to the live signing mutation, out of scope for a backfill of already-signed historical declarations, but worth the engineer's attention as a related, separate follow-up.
- ~~**Whether the "Batch/item model choice" Deferred decision in the existing `PLAN.md` (`PLAN.md:216`) should be resolved in favor of a new dedicated model specifically because this spike's evidentiary metadata needs somewhere to live**~~ — **investigated in full in Round 5, below (options surfaced, not decided).**

---

## Suggested options for main and the engineer

**Packaging (Finding 4):** ~~Option A — sidecar file per declaration (engineer's stated leaning), no new gem / Option B — additional XLSX manifest columns, no new gem, can combine with A / Option C — audit page appended to each PDF, requires a new PDF-merge gem / Option D — embedded PDF metadata, requires a new PDF-manipulation gem, weakest visibility~~ — **decided in Round 4: separate file, not appended (see header note there for the reason — appending changes the final PDF's image hash).**

**Hash placement (Finding 3):**
- Compute in Consumer (before CarrierWave discards the local temp file) — one extra file read per declaration, no Finalizer re-download needed
- Compute in Finalizer (on the already-downloaded copy) — no new Consumer-side field, but ties the hash to whatever the Finalizer's per-record tracking already carries

**Evidentiary-generation placement (Finding 5):**
- Inside Consumer, before `increment_executions` — evidence and PDF become one atomic per-record unit, matching the sibling `PlanStatementAudit::Consumer` shape
- Inside Finalizer, after `computation.done?` — evidence generation moves to batch-level retry granularity

(No recommendation — the options above surface the trade-offs and their fit with the existing plan; main and the engineer decide.)

---

## Round 2 — Forced-acceptance actor and reason (engineer-resolved open question)

The engineer resolved the "What remains uncertain" item on `forced_acceptance?` from Round 1 with three confirmed domain facts. This round verifies each against the `app` repo and maps the exact data path from a forced acceptance's real actor and its `AcceptmentReason` back to the exported declaration.

### Sources consulted (Round 2 additions)

- `app/app/models/acceptment_reason.rb` — the `AcceptmentReason` model, its validated columns, and its two associations from `Acceptment`
- `app/db/schema.rb:21-36` — `acceptment_reasons` table definition
- `app/app/workers/acceptment_document/processor.rb` — `AcceptmentDocument::Processor`, the CSV-driven bulk/forced-acceptance worker
- `app/app/graphql_mutations/create_acceptment_document_graphql_mutation.rb` — how an `AcceptmentDocument`'s `owner` is set to the uploading manager
- `app/app/graphql_mutations/accept_plan_statement_graphql_mutation.rb` and `app/app/graphql_mutations/accept_plan_statement_v2_graphql_mutation.rb` — the single-declaration acceptance mutations, both keyed on `current_user.id`
- `app/app/policies/plan_statement_policy.rb` — the `accept?` policy gate that determines who may call the single-declaration path
- `app/app/models/document.rb` — the `Document` STI base class `AcceptmentDocument` inherits from, confirming the `owner` association's shape
- `app/app/workers/plan_statement_audit/consumer.rb:52-61` (already cited in Round 1 Finding 5) — re-examined here specifically for what it reads off `acceptment.user` and `acceptment.reason`

### Finding 6: `AcceptmentReason` has a `name` and a `description` column — the engineer's "title" maps to the model's `name`, not a `title` column

**Evidence:**
```ruby
# app/app/models/acceptment_reason.rb:3-19
class AcceptmentReason < ApplicationRecord
  belongs_to :company, optional: true, inverse_of: :acceptment_reasons
  belongs_to :disabler, class_name: 'User', inverse_of: :disabled_acceptment_reasons, optional: true
  belongs_to :owner, class_name: 'User', inverse_of: :owned_acceptment_reasons, optional: true
  belongs_to :plan_acceptment, inverse_of: :acceptment_reason, optional: true
  has_many :acceptments, dependent: :destroy, inverse_of: :acceptment_reason

  validates :company_id, presence: true
  validates :description, presence: true
  validates :key, presence: true, format: { with: /\A[a-z0-9_]*\z/ }
  validates :name, presence: true
  validates :owner_id, presence: true
```
```ruby
# app/db/schema.rb:21-36 (acceptment_reasons table)
t.bigint "company_id"
t.datetime "created_at", null: false
t.text "description"
t.datetime "disabled_at"
t.bigint "disabler_id"
t.string "key", limit: 8000
t.string "name", limit: 8000
t.bigint "owner_id"
t.bigint "plan_acceptment_id"
```
There is no `title` column on `acceptment_reasons`. The two text fields are `name` (`t.string`, both presence-validated) and `description` (`t.text`, also presence-validated) — both mandatory on every `AcceptmentReason` row, which matches the engineer's description of a title-like field and a description-like field both being required. There is also a `key` column (`format: { with: /\A[a-z0-9_]*\z/ }`), an internal slug distinct from the human-readable `name`, used for lookup rather than display (see Finding 7).

**Source:** `app/app/models/acceptment_reason.rb:3-19`, `app/db/schema.rb:21-36`

**Significance:** wherever this spike or a future implementation refers to "the reason's title", the codebase's actual field is `name`. The output requirement ("title + description verbatim as stored") maps onto `acceptment_reason.name` and `acceptment_reason.description` with no other column standing in for "title".

---

### Finding 7: Choosing an `AcceptmentReason` is enforced by a validation that fires exactly when the actor differs from the declarant — the mandatory-reason rule from the engineer's premise, found in code

**Evidence:**
```ruby
# app/app/models/acceptment.rb:13,64-69
validates :acceptment_reason_id, presence: true, if: :acceptment_reason_required?
...
def acceptment_reason_required?
  return false if statement?
  return false if plan_statement.nil?

  user_id != plan_statement.user_id
end
```
`acceptment_reason_required?` returns `true` exactly when the `Acceptment`'s `user_id` (the actor) differs from the `PlanStatement`'s `user_id` (the declarant) — the identical condition `PlanStatement#forced_acceptance?` uses to detect a forced acceptance (`app/app/models/plan_statement.rb:107-109`, already cited in Round 1 Finding 5: `accepted? && user_id != acceptment.user_id`). When these two ids match (the declarant accepting their own declaration), no reason is required. When they differ (someone else accepting on the declarant's behalf), `acceptment_reason_id` presence is enforced by the model validation — a forced `Acceptment` with no resolvable reason fails to save.

This validation is exercised concretely inside the bulk/forced-acceptance worker (Finding 8): when a CSV row's reason key does not resolve to an existing `AcceptmentReason`, `acceptment_reason_id` comes back `nil` (`app/app/workers/acceptment_document/processor.rb:85-91`, `rescue ActiveRecord::RecordNotFound` → `nil`), the subsequent `Acceptment.new(...).save` fails validation, and the row is recorded as a `document_error` instead of an accepted declaration (`app/app/workers/acceptment_document/processor.rb:38,47-61`).

**Source:** `app/app/models/acceptment.rb:13,64-69`, `app/app/models/plan_statement.rb:107-109`, `app/app/workers/acceptment_document/processor.rb:22,85-91`

**Significance:** the engineer's "a manager is REQUIRED to choose one reason on forced/mass acceptance" is not a UI-only convention — it is enforced at the model layer by a validation whose trigger condition is exactly "the actor is not the declarant". Any forced-acceptance `Acceptment` the exported declarations include is therefore guaranteed by this validation to carry a non-null `acceptment_reason_id` — there is no code path that persists a forced acceptance with a missing reason.

---

### Finding 8: The real actor on a forced acceptance is the `AcceptmentDocument`'s uploading manager, stored directly on `Acceptment#user_id` — and this path is the ONLY way a forced acceptance can exist, because the single-declaration mutation is gated to the declarant alone

**Evidence — the bulk/forced-acceptance worker sets the actor:**
```ruby
# app/app/workers/acceptment_document/processor.rb:9-36
def perform(acceptment_document_id)
  acceptment_document = AcceptmentDocument.with_uncached_connection { AcceptmentDocument.find(acceptment_document_id) }
  AcceptmentDocument.with_uncached_connection { acceptment_document.process! }
  from = acceptment_document.from
  company = Company.with_uncached_connection { acceptment_document.company }
  owner_id = acceptment_document.owner_id
  ...
  ACSV::CSV.foreach(local_cached_file, headers: true, col_sep: column_separator).with_index(2) do |row, line|
    ...
    acceptment_reason_id = acceptment_reason_id(company, row[2].to_s.strip)
    user_id = user_id(company, row[3].to_s.strip, row[1].to_s.strip)
    plan_statement_id = plan_statement_id(row[0].to_s.strip, user_id)

    acceptment =
      Acceptment.new(
        plan_statement_id: plan_statement_id,
        user_id: owner_id,
        acceptment_reason_id: acceptment_reason_id,
        from: from,
        document: acceptment_document,
        document_line: line,
        signed: false,
        company_id: company.id
      )
```
The local variable `user_id` (from the CSV row, `row[3]`/`row[1]`) is used ONLY to look up which `plan_statement_id` the row targets (`plan_statement_id(row[0].to_s.strip, user_id)`, line 24) — it is the **declarant**, never written to the `Acceptment`. The `Acceptment#user_id` actually persisted is `owner_id` (line 14: `owner_id = acceptment_document.owner_id`) — the id of whoever uploaded the CSV, i.e. `AcceptmentDocument#owner`. This is set at upload time:
```ruby
# app/app/graphql_mutations/create_acceptment_document_graphql_mutation.rb:7-15
def execute
  authorize(AcceptmentDocument, :create?)
  acceptment_document = AcceptmentDocument.new(document_params)
  acceptment_document.company = current_user.company
  acceptment_document.owner = current_user
  acceptment_document.from = remote_ip
  acceptment_document.save
  respond_with(acceptment_document)
end
```
`AcceptmentDocument < Document` (`app/app/workers/acceptment_document/processor.rb:5`), and `Document` declares `belongs_to :owner, class_name: 'User', inverse_of: :owned_documents, optional: true` (`app/app/models/document.rb:16`) — so "the owner of the acceptance/upload document" the engineer described is exactly `AcceptmentDocument#owner`, the `current_user` (the manager) who called this mutation to upload the CSV. `AcceptmentDocument::Processor` also links each created `Acceptment` back to that document (`document: acceptment_document`, `processor.rb:32`), via `Acceptment belongs_to :document, class_name: 'AcceptmentDocument', foreign_key: :acceptment_document_id` (`app/app/models/acceptment.rb:6`) — so `acceptment.document.owner` and `acceptment.user` resolve to the same manager for every forced-acceptance record created this way, giving two equivalent, independently-traceable paths to the same actor.

**Evidence — this is the ONLY path that can produce a forced acceptance:**
```ruby
# app/app/policies/plan_statement_policy.rb:15-24
def accept?
  return false if company.client? && user.company_id != record.company_id
  return false if record.user_id != user.id
  return false unless record.pending?
  ...
```
`record.user_id != user.id` rejects any `accept?` authorization where the acting `user` is not the declaration's own owner. Both single-declaration mutations authorize through this exact policy before calling `accept_by`/`sign_by` with `user_id: current_user.id` (`app/app/graphql_mutations/accept_plan_statement_graphql_mutation.rb:11-12`, `app/app/graphql_mutations/accept_plan_statement_v2_graphql_mutation.rb:12-13`) — so neither single-declaration path can ever produce an `Acceptment` whose `user_id` differs from the `PlanStatement`'s `user_id`; a manager literally cannot click "accept" on someone else's declaration through this UI/API surface. The `AcceptmentDocument::Processor` bulk path (Finding 8, above) constructs its `Acceptment` directly via `Acceptment.new(...)` with no `accept?` policy check at all, and is the only code path this spike found that writes an `Acceptment#user_id` different from `PlanStatement#user_id`.

**Source:** `app/app/workers/acceptment_document/processor.rb:9-36`, `app/app/graphql_mutations/create_acceptment_document_graphql_mutation.rb:7-15`, `app/app/models/document.rb:16`, `app/app/models/acceptment.rb:6`, `app/app/policies/plan_statement_policy.rb:15-24`, `app/app/graphql_mutations/accept_plan_statement_graphql_mutation.rb:11-12`, `app/app/graphql_mutations/accept_plan_statement_v2_graphql_mutation.rb:12-13`

**Significance:** for a NORMAL acceptance, the actor is the operator/declarant themselves, read directly off `plan_statement.user` (equivalently `acceptment.user`, since the policy guarantees they match) — no forced-acceptance handling needed. For a FORCED acceptance, the actor is `acceptment.user` (the manager), which is provably never the declarant for a record on this path, and is independently corroborated by `acceptment.document.owner` when the `Acceptment` originated from a CSV upload. A worker reading Finding 1's evidence (Round 1) must read `acceptment.user`, not `plan_statement.user`, to get the real actor on a forced record — reading `plan_statement.user` unconditionally would misattribute every forced acceptance to the declarant instead of the manager who actually performed it. Also worth noting plainly: `signed: false` is hardcoded on every `Acceptment` the bulk processor creates (`processor.rb:34`) — a forced/mass-accepted declaration has no drawn-signature PNG at all, only the reason and the manager's identity as evidence, which raises the stakes of getting the actor and reason right for exactly these records.

---

### Finding 9: `PlanStatementAudit::Consumer` already reads the actor and the reason on a forced acceptance — but surfaces only `name`, never `description`

**Evidence:**
```ruby
# app/app/workers/plan_statement_audit/consumer.rb:52-61 (re-examined from Round 1 Finding 5)
if plan_statement.forced_acceptance?
  acceptment = Acceptment.with_uncached_connection { plan_statement.acceptment }
  user = User.with_uncached_connection { acceptment.user }
  acceptment_reason = AcceptmentReason.with_uncached_connection { acceptment.reason }
  row.accepted_by = user.name
  row.acceptment_reason = acceptment_reason.name
elsif plan_statement.accepted?
  user = User.with_uncached_connection { plan_statement.user }
  row.accepted_by = user.name
end
```
The sibling worker already branches on `forced_acceptance?` exactly as Finding 8 describes: on the `true` branch it reads `acceptment.user` (`plan_statement.rb:8`'s `belongs_to :user`) — the real actor — rather than `plan_statement.user`, and `acceptment.reason` (the `AcceptmentReason` association aliased `:reason`, `acceptment.rb:8`) for the chosen reason. Both assignments (`row.accepted_by = user.name`, `row.acceptment_reason = acceptment_reason.name`) are direct attribute reads with no `.humanize`, `.strip`, or other transformation applied — unlike the neighboring `row.accepted = ... .humanize` a few lines above it (`consumer.rb:33`, Round 1 quote), which transforms a different field (the accepted/pending/canceled status), not the reason or the actor's name. So this existing pattern already satisfies "verbatim as stored" for the two fields it does capture.

What it does NOT capture: `acceptment_reason.description` never appears anywhere in this worker — confirmed by reading the full method body above, and by the `plan_statement_audit_rows` schema (`app/db/schema.rb:1548-1571`, cited in Round 1 Finding 4), which has an `acceptment_reason` string column and no `acceptment_reason_description` (or equivalent) column at all.

**Source:** `app/app/workers/plan_statement_audit/consumer.rb:33,52-61`, `app/app/models/plan_statement.rb:8`, `app/app/models/acceptment.rb:8`, `app/db/schema.rb:1548-1571`

**Significance:** the sibling `PlanStatementAudit::Consumer` is direct precedent that this exact actor-plus-reason read is both possible and already done once elsewhere in the codebase, using `with_uncached_connection`-wrapped reads consistent with the Data Access rules a new evidence-generation worker would also need to follow. The residual gap against the engineer's output requirement is narrow and specific: the sibling reads `acceptment_reason.name` but never `acceptment_reason.description` — a new evidence worker following this exact pattern would need one additional attribute read (`acceptment_reason.description`) to satisfy "title and description, both verbatim" in full.

---

### How this plugs into the existing Producer → Consumer → Finalizer + `Computation` flow

Round 1 Finding 5 already established that evidence-generation can happen either inside the planned `PlanStatementExport::Consumer` (per-record, before `computation.increment_executions`) or inside the Finalizer (batch-level, after `computation.done?`), and that either placement preserves the existing completion guarantee. Nothing in this round changes that conclusion — the actor/reason read is additional per-record data, not a new coordination mechanism. What this round adds is the concrete per-record logic that placement would execute, mirrored directly from `PlanStatementAudit::Consumer` (Finding 9):

For every declaration the Producer's `PlanStatement.for_company(company_id).accepted` scope selects (`app/app/models/plan_statement.rb:20`, cited in the existing `PLAN.md`), the same `plan_statement.forced_acceptance?` branch used in Finding 9 determines which read path applies — `plan_statement.user` for a normal acceptance, `plan_statement.acceptment.user` for a forced one — and since `forced_acceptance?` only ever evaluates against an `Acceptment` the `.accepted` scope's `joins(:acceptment)` (`plan_statement.rb:20`) already guarantees is present, there is no declaration in the exported set for which this branch is undeterminable. This is the same completeness argument Round 1 Finding 5 made for the PDF itself, extended to the actor and reason: because the branch condition is always evaluable on every record the Producer selects, no declaration can silently fall through with missing actor/reason data — a record either resolves to "normal, actor = declarant" or "forced, actor = acceptment.user + acceptment.reason.name + acceptment.reason.description", never neither.

---

## What remains uncertain (Round 2 additions)

- **Whether every forced-acceptance record in the customer's actual data resolves to a non-null `acceptment.reason`.** Finding 7 shows the validation makes this true by construction for any `Acceptment` that successfully saved — but this spike has no access to the cancelled customer's production data to confirm none of their forced acceptances are pre-validation-era rows or otherwise anomalous. This is the same category of gap as Round 1's "declarations before/after 2026-05-28" uncertainty — a fact about this customer's specific data, not about the code path.
- **Whether the CSV-driven `AcceptmentDocument::Processor` is the only forced-acceptance-producing code path in the whole codebase**, or only the only one this spike found via the mutations and workers it inspected. The policy-level argument in Finding 8 (`accept?` rejects any non-owner) is strong evidence for the two GraphQL mutations checked, but this spike did not exhaustively enumerate every path that can call `Acceptment.new`/`create_acceptment!` directly (e.g. a console script, a rake task, or the `Company::Cleansing::AcceptmentProducer`/`AcceptmentConsumer` workers found alongside `AcceptmentDocument::Processor` during the file search but not opened in this round). **Closed in Round 3, Finding 16, below — those two workers cannot create a forced acceptance; they only destroy existing `Acceptment` rows.**

---

## Suggested options for main and the engineer (Round 2 additions)

- Whichever packaging option (Finding 4, Round 1) the engineer chooses, the actor-plus-reason read for each declaration can follow the exact `PlanStatementAudit::Consumer` pattern (Finding 9) with one addition — also reading `acceptment.reason.description`, which the sibling does not — rather than being designed from scratch.
- Field set per declaration, mirroring Finding 9's shape: for a normal acceptance, `actor = plan_statement.user` (the declarant); for a forced acceptance, `actor = plan_statement.acceptment.user` (the manager), `reason_name = plan_statement.acceptment.reason.name`, `reason_description = plan_statement.acceptment.reason.description` — all four values read and packaged with no cleaning, normalization, or inference, per the engineer's explicit requirement.

(No recommendation — the mapping above is a description of what the codebase already does and already enforces, not a design choice; the packaging and placement decisions remain the engineer's, per Round 1.)

---

## Round 3 — industry packaging conventions, the unsigned-declaration rendered UI, and closing the forced-acceptance path question

Three tasks from the coordinator: (A) ground Round 1 Finding 4's four packaging options against what real e-signature platforms actually do, sourced and verified per Citation Discipline; (B) read the exact rendered behavior of the declaration page when there is no drawn signature; (C) confirm whether `Company::Cleansing::AcceptmentProducer`/`AcceptmentConsumer` can create a forced acceptance, closing the Round 2 open question.

### Sources consulted (Round 3 additions)

- `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.html:376-395` — the signature/description block, read in full for Task B
- `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts:216-230,48-131` — `getSignature()` and the GraphQL query fields, read for Task B
- `app/app/workers/company/cleansing/acceptment_producer.rb` — read in full for Task C
- `app/app/workers/company/cleansing/acceptment_consumer.rb` — read in full for Task C
- https://community.docusign.com/esignature-111/download-document-inlcuding-certificates-2332 — DocuSign community discussion on Certificate of Completion packaging (fetched and self-checked)
- https://ajuda.clicksign.com/article/230-log-presente-nos-documentos-assinados — re-fetched with a packaging-specific prompt, self-checked
- https://www.nutrient.io/guides/web/signatures/digital-signatures/standards/ — PAdES B-LT description (fetched and self-checked)
- https://www.docupilot.com/blog/electronic-signature-audit-trail — "keep the trail with the document" best practice (fetched and self-checked)
- https://experienceleague.adobe.com/en/docs/document-cloud-learn/sign-learning-hub/admin-set-up/getting-started-admin/audit-reports — fetched; only a general "milestones" quote confirmed, packaging-format claim NOT confirmed
- https://helpx.adobe.com/sign/config/global/attach-audit-report.html — **UNVERIFIED**: every fetch attempt (four total, across this round) timed out; no claim from this page is used
- https://helpx.adobe.com/sign/using/sign-download-audit-report.html — **UNVERIFIED**: fetch timed out twice; no claim from this page is used
- https://helpx.adobe.com/sign/kb/how-to-download-signed-document-along-with-audit-report-and-supporting-document-through-Adobe-Sign-rest-api-adobe-sign.html — **UNVERIFIED**: fetch timed out; no claim from this page is used
- https://pdfa.org/long-term-validation-of-signatures/ — **UNVERIFIED**: fetch returned HTTP 403 Forbidden; no claim from this page is used
- https://support.docusign.com/s/document-item?language=en_US&bundleId=oeq1643226594604&topicId=xrk1578456342917.html&_LANG=enus — **UNVERIFIED**: fetched, but the returned content was an error/loading-state page with no relevant text; no claim from this page is used

### Task A — Finding 10: DocuSign delivers the Certificate of Completion as a SEPARATE file by default; combining it into the same PDF is an opt-in setting, and is unavailable at all when the signature uses a digital certificate

**Evidence:**

From community.docusign.com, verbatim: *"There is an option to download the signed documents and the Certificate of Completion (CoC) as a package. In DocuSign this is called 'Combined' download and it will give you a single PDF with the merged documents."* — this confirms a combine option exists, and that it is not the default (email delivery keeps them separate; a user has to actively use the "Combined" download).

The same source, verbatim, on why the combine option is not universal: *"Combined download works only with the standard electronic signature accounts, which do not have Standard Based Signatures (digital certificates for e.g. AES or QES) enabled."*

And on how a user reaches the combined form: *"after checking the 'Attach certificate of completion to envelope' I was able to combine into one pdf file."*

**Source:** https://community.docusign.com/esignature-111/download-document-inlcuding-certificates-2332

**Significance:** DocuSign's default shape is closest to Round 1 Finding 4's **Option (a)** (separate file, paired by envelope) — the Certificate of Completion is its own PDF, delivered alongside the signed document, not merged into it. Combining into a single PDF (closer to **Option (c)**) exists only as an explicit setting, and DocuSign's own stated reason for withholding it on digitally-certificated envelopes is that merging could invalidate the certificate — a constraint that does not apply to 4Shark's case (Ferrum-rendered PDFs carry no PAdES/digital certificate to invalidate), so this specific restriction is not a transferable concern, only the general fact that a major platform treats "separate" as its default and "combined" as an opt-in. **This is the option the engineer chose in Round 4.**

**Verification:** re-fetched; all three quotes above confirmed present verbatim in the same community thread.

---

### Task A — Finding 11: ClickSign's audit log is ALWAYS an appended page on the same signed PDF — never a separate file, by design

**Evidence:**

From ajuda.clicksign.com, verbatim, re-fetched with a packaging-specific prompt: *"Na Clicksign, todos os documentos assinados possuem uma página anexa com o histórico completo das assinaturas."* ("At Clicksign, every signed document has an attached page with the complete signature history.") The same source states where: *"Você poderá encontrar o Log do documento na última página do arquivo assinado."* ("You can find the document Log on the last page of the signed file.")

**Source:** https://ajuda.clicksign.com/article/230-log-presente-nos-documentos-assinados

**Significance:** ClickSign implements Round 1 Finding 4's **Option (c)** unconditionally — there is no separate-file mode for its audit log at all; it is always the final page of the one PDF file the signer downloads. This is the strongest real-world precedent for Option (c) among the sources this spike could verify, though it comes at the cost Finding 4 already named: producing it requires generating a second page and merging it into the same PDF, which needs tooling 4Shark's Gemfile does not currently have (Round 1 Finding 4, no PDF-merge gem present). **The engineer weighed this option against Option (a) and chose separate-file delivery in Round 4 — appending a page to the PDF changes the final rendered image's hash, which the engineer identified as undesirable for this backfill's evidentiary purpose.**

**Verification:** re-fetched with a prompt asking specifically to confirm these two substrings; both confirmed present (the second confirmed via the full sentence containing it, exact character-for-character).

---

### Task A — Finding 12 (UNVERIFIED claim excluded): Adobe Acrobat Sign's audit-report packaging format could not be confirmed from a primary source in this round

**What was attempted:** four separate fetch attempts against three different `helpx.adobe.com` pages (the general audit-report page, the "Attach Audit Report to Emails and Downloads" configuration page, and the API-download knowledge-base article) all timed out (60s) without returning content. A fifth fetch, against `experienceleague.adobe.com`, succeeded and returned one confirmed general statement — verbatim: *"Every document in Acrobat Sign passes through a series of event 'milestones' that define the progress of a transaction. These milestones are thoroughly documented in an audit report for every transaction."* This confirms Acrobat Sign has an audit-report mechanism that logs event milestones, but says nothing about whether that report is delivered as a separate file, appended to the signed PDF, or embedded.

**What is explicitly NOT claimed:** an earlier `WebSearch` (not a fetched, quote-verified source) surfaced a page titled "Attach Audit Report to Emails and Downloads", whose title alone suggests Adobe offers an append option similar to ClickSign's. Per Citation Discipline rule 4 (UNVERIFIED tag for failed fetches — "may NOT sustain candidates or derivations"), this spike does **not** assert that Adobe appends its audit report, because the page that would confirm it could not be fetched. This is stated as a gap, not filled with the plausible-sounding search-summary text.

**Source:** https://experienceleague.adobe.com/en/docs/document-cloud-learn/sign-learning-hub/admin-set-up/getting-started-admin/audit-reports (verified quote); the three `helpx.adobe.com` URLs listed above are UNVERIFIED and excluded from any claim

**Significance:** Adobe is a third major e-signature vendor and its inclusion was explicitly requested, but this spike can only confirm that it has an audit-report concept at all — not which of Round 1 Finding 4's four options it maps to. This gap should not be read as "Adobe does X" by default; it is an honest "not confirmed" per the Research-First Policy's instruction to say "I did not find this" rather than fill the gap with a guess.

---

### Task A — Finding 13: PAdES/LTV, the PDF signature standard, embeds cryptographic validation proof directly inside the PDF file — a different kind of "embedding" from Round 1 Finding 4's Option (d), but the closest standards-level precedent for self-contained proof

**Evidence:**

From nutrient.io (a PDF-technology vendor's technical guide, not the PDF Association standards body itself — the pdfa.org page returned HTTP 403 and could not be fetched), verbatim, re-fetched and confirmed: *"PAdES B-LT — T-level signatures, plus LTV information containing values of certificates and values of certificate revocation status (CRL and OCSP responses) used to validate a signature. This makes it possible to validate a signed document using the contents of the file itself. These are ideally suited for long-term storage of PDFs in way that the validation remains intact through LTV, making the level ideal for archiving and use as court evidence."*

**Source:** https://www.nutrient.io/guides/web/signatures/digital-signatures/standards/

**Significance:** this is a genuinely different mechanism from Round 1 Finding 4's Option (d) (writing evidentiary fields like IP/actor/reason into XMP/Info-dictionary metadata) — PAdES-LTV embeds *cryptographic* validation material (certificates, revocation status) so a signature's mathematical validity can be checked without any external server, not human-readable audit facts. No source this spike could fetch describes a standard or vendor practice of embedding IP-address/actor/reason data as PDF metadata specifically for e-signature evidentiary purposes — that specific practice (Option (d) as written in Round 1) is **not found**, distinct from the cryptographic LTV embedding this Finding does confirm. The transferable idea from PAdES is directional, not mechanical: the standard's design goal is "the file proves itself without external lookups" — a goal Option (c) (appended human-readable page) and Option (a) (paired sidecar with its own hash) both also serve, in a form that does not require 4Shark to implement a PDF signature stack.

**Verification:** re-fetched with a targeted prompt asking to confirm the exact sentence; confirmed present verbatim, including the full surrounding sentence.

---

### Task A — Finding 14: no primary or vendor source in this round documents a convention specific to BULK export at customer offboarding; the closest available guidance is a general best practice to keep the audit trail co-located with its document

**Evidence:**

From docupilot.com (a vendor blog, not a standards body), verbatim, re-fetched and confirmed, listed as best practice #4 of a "7 best practices" list: *"Keep the trail with the document so they never get lost, separated, or mismatched"*

**Source:** https://www.docupilot.com/blog/electronic-signature-audit-trail

**Significance:** this is general single-document guidance (do not let a document and its audit trail drift apart), not a documented convention for the specific scenario this backfill faces — bulk-exporting many historical declarations at once for an offboarding customer, where a manifest spanning multiple documents (Option (b)) is a legitimate and different shape from single-document co-location. This spike did not find a source addressing the bulk/manifest case directly; per the Research-First Policy, that gap is reported as "not found" rather than extrapolated from the single-document guidance above. The one directional data point this quote does support: whichever packaging option the engineer picks, keeping the evidentiary data from drifting apart from its PDF (whether via Option (a)'s sidecar, Option (b)'s manifest row referencing the same filename, or Option (c)'s appended page) tracks a real, if generically-stated, industry concern. **This concern is satisfied by the separate-file sidecar chosen in Round 4 as long as the filename pairing (same basename as the PDF) is preserved — a packaging detail, not a re-opening of the settled decision.**

**Verification:** re-fetched with a prompt asking to confirm the exact substring; confirmed present verbatim, attributed to best practice item 4 in the source's own numbered list.

---

### Task A — mapping table: Round 1 Finding 4's four options against what this round could verify

| Option | Real-world precedent found (verified) | Real-world precedent NOT found / unverified |
|---|---|---|
| (a) Sidecar file, same basename — **chosen in Round 4** | DocuSign's default (separate Certificate of Completion PDF per envelope) — Finding 10 | — |
| (b) XLSX manifest columns | — (no source addresses bulk multi-document manifests; single-envelope tools do not need this shape) | Bulk/offboarding-specific convention — Finding 14 (reported not found) |
| (c) Audit page appended to PDF | ClickSign's unconditional default — Finding 11; DocuSign's optional "Combined PDF" — Finding 10 | Adobe Acrobat Sign's exact packaging — Finding 12 (UNVERIFIED, excluded) |
| (d) Embedded PDF metadata | PAdES-LTV embeds *cryptographic* proof in the PDF itself (a different kind of embedding) — Finding 13 | Embedding human-readable evidentiary fields (IP/actor/reason) as PDF metadata specifically — not found |

---

### Task B — Finding 15: for a declaration with NO drawn signature (a forced/unsigned acceptance), the rendered page shows the actor's name, id, and acceptance timestamp, and the reason's `description` — but does NOT show the IP address, does NOT show any drawn-signature image, and shows no "forced acceptance" label

**Evidence — the signature/description block, read in full:**
```html
<!-- app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.html:376-395 -->
<div class="d-flex-ju-end mg-t-30 mg-b-30" *ngIf="planStatement?.acceptment">
  <div class="description">
    <div *ngIf="signature" class="signature">
      <span class="signed-by">{{ 'acceptment.signed_by' | translate }}</span>
      <img [src]="signature?.url" alt="signature" />
      <span class="ip">IP: {{ planStatement?.acceptment?.from }}</span>
    </div>
    <div class="mg-t-15">
      <b>{{ planStatement?.acceptment?.user?.name }}</b>
    </div>
    <span>{{ 'user.id' | translate }} {{ planStatement?.acceptment?.user?.id }}</span>
    <div class="font-size-small">
      {{ planStatement?.acceptment?.createdAt | date: 'full' : '' : translateService.currentLang }}
    </div>
    <div class="font-size-small" *ngIf="planStatement?.acceptment?.acceptmentReason">
      {{ 'acceptment_reason.one' | translate }}:
      {{ planStatement?.acceptment?.acceptmentReason?.description }}
    </div>
  </div>
</div>
```
The outer block renders whenever `planStatement.acceptment` exists — true for both a normal (signed) and a forced (unsigned) acceptance, since both create an `Acceptment` record (Round 1 Finding 1, Round 2 Finding 8). Inside it, the **entire** `"signature"`-labeled sub-block — the *"Assinado por"*-style label (`acceptment.signed_by` translation key), the drawn-signature `<img>`, and the `IP: {{ ... from }}` text — is wrapped in its own `*ngIf="signature"` (component property, not `planStatement.acceptment.signature`). Per the DOM-absent-when-false pattern already established for the collapsible panels (existing `signature-pdf-export/SPIKE.md` Finding 3, re-confirmed here for this block), when `signature` is falsy this whole `<div class="signature">` — including the IP line — is **absent from the DOM**, not merely hidden.

**Evidence — why `signature` is falsy for a forced acceptance:**
```typescript
// app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts:216-221
getSignature() {
  const signatureId = this.planStatement?.acceptment?.signature?.id;

  if (!signatureId) {
    return;
  }
  ...
```
`AcceptmentDocument::Processor` (Round 2 Finding 8) creates every forced acceptance with `signed: false` and no `signature_attributes` — no `Signature` row is ever created for that `Acceptment`. So `planStatement.acceptment.signature` is `null` in the GraphQL response, `signatureId` is falsy, `getSignature()` returns immediately at line 219, and the component's `signature` property (initialized `null` at `plan-statement-show.component.ts:30`) is never set. The `*ngIf="signature"` in the template therefore never renders for a forced/unsigned declaration.

**Evidence — the GraphQL query only ever requests the reason's `description`, never its `name`:**
```typescript
// app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts:57-70
acceptment {
  acceptmentReason {
    description
  }
  createdAt
  from
  signature {
    id
  }
  user {
    id
    name
  }
}
```
`from` (the IP) is fetched into the client-side data model regardless of whether a signature exists — but as shown above, the template only ever displays it inside the `*ngIf="signature"` block. So for a forced acceptance, the IP is present in the underlying page data but never rendered on screen. Separately, `acceptmentReason` here requests only `description` — `name` (Round 2 Finding 6's "title") is never fetched by this component at all, confirming that today's UI shows the reason's description only, never its name/title.

**Source:** `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.html:376-395`, `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts:30,57-70,216-221`

**Significance:** this determines exactly what a Ferrum full-page capture of a forced-acceptance declaration already looks like today, before any new evidentiary-metadata work: the captured PDF would show the manager's name and id (per Round 2 Finding 8, the real actor — not the declarant), the acceptance date/time, and the reason's description — but would show **no** IP address (present in data, never rendered), **no** drawn signature image (none exists), and **no** explicit "esta foi uma aceitação forçada" / forced-acceptance indicator of any kind — the page looks identical in shape to a normal declaration's description block, minus the signature sub-block. Anyone reading the captured PDF alone, without also knowing to compare the displayed name against the plan's original participant, would not visually notice that the declaration was force-accepted by someone else. This is a factual description of current rendered behavior, not a design proposal. **The engineer has since decided (Round 4 header note) to fix this gap directly in the frontend text and code, rather than compensate for it in the evidentiary-metadata packaging — this Finding is the factual basis that decision was made against and is preserved unchanged.**

---

### Task C — Finding 16: `Company::Cleansing::AcceptmentProducer` and `AcceptmentConsumer` only DESTROY existing `Acceptment` rows tied to `AcceptmentDocument`s — neither can create an `Acceptment`, so neither can produce a forced acceptance; `AcceptmentDocument::Processor` remains the only path found

**Evidence:**
```ruby
# app/app/workers/company/cleansing/acceptment_producer.rb (full file)
class Company < ApplicationRecord
  module Cleansing
    class AcceptmentProducer < ApplicationWorker
      sidekiq_options queue: :cleansing

      def perform(company_id)
        company = Company.with_uncached_connection { Company.find(company_id) }

        acceptment_document_ids =
          AcceptmentDocument.with_uncached_connection do
            company.documents.where(type: AcceptmentDocument).pluck(:id)
          end

        acceptment_ids =
          Acceptment.with_uncached_connection do
            Acceptment.where(acceptment_document_id: acceptment_document_ids).limit(10_000).pluck(:id)
          end

        if acceptment_ids.any?
          company.computation.increment_queue(by: acceptment_ids.count)
          Sidekiq::Client.push_bulk('class' => Company::Cleansing::AcceptmentConsumer, 'args' => acceptment_ids.zip)
        else
          Company::Cleansing::AcceptmentDocumentProducer.perform_async(company_id)
        end
      end
    end
  end
end
```
```ruby
# app/app/workers/company/cleansing/acceptment_consumer.rb (full file)
class Company < ApplicationRecord
  module Cleansing
    class AcceptmentConsumer < ApplicationWorker
      sidekiq_options queue: :cleansing

      def perform(acceptment_id)
        acceptment = Acceptment.with_uncached_connection { Acceptment.find(acceptment_id) }
        acceptment_reason = AcceptmentReason.with_uncached_connection { acceptment.reason }
        company = Company.with_uncached_connection { acceptment_reason.company }
        Acceptment.with_uncached_connection { acceptment.destroy! }
        company.computation.increment_executions

        return unless company.computation.done?

        Company::Cleansing::AcceptmentProducer.perform_async(company.id)
      end
    end
  end
end
```
The Producer's entire job is to `pluck(:id)` **existing** `Acceptment` rows already linked to one of the company's `AcceptmentDocument`s (`acceptment_document_ids`, `Acceptment.where(acceptment_document_id: acceptment_document_ids)`) and fan them out to the Consumer. There is no `Acceptment.new`, `Acceptment.create`, or `create_acceptment!` call anywhere in either file. The Consumer's only mutation is `acceptment.destroy!` — it reads the `Acceptment`, resolves its `reason` and `company` for downstream routing purposes, and deletes it. Both files are namespaced under `Company::Cleansing`, and the Producer's else-branch (`Company::Cleansing::AcceptmentDocumentProducer.perform_async`, once no more acceptments remain) confirms this pair is one stage of a larger data-cleansing/anonymization pipeline (consistent with the `LGPD Data Erasure` company-wide policy's `Company::Anonymizer` machinery) — not a signing or acceptance-creation flow.

**Source:** `app/app/workers/company/cleansing/acceptment_producer.rb` (full file, 30 lines), `app/app/workers/company/cleansing/acceptment_consumer.rb` (full file, 21 lines)

**Significance:** this closes the open question from Round 2's "What remains uncertain" list. `Company::Cleansing::AcceptmentProducer`/`AcceptmentConsumer` cannot create an `Acceptment` at all, let alone a forced one — they are a pure deletion pipeline, the reverse operation of what Round 2 Finding 8 investigated. Combined with the policy-level argument already established in Round 2 Finding 8 (`PlanStatementPolicy#accept?` rejects any single-declaration acceptance where the actor is not the declarant), `AcceptmentDocument::Processor` (Round 2 Finding 8) remains the only code path this spike has found — across both rounds — capable of writing an `Acceptment` whose `user_id` differs from its `PlanStatement`'s `user_id`. This spike did not exhaustively grep every remaining call site of `Acceptment.new`/`create_acceptment!`/`create_acceptment` in the codebase (e.g. a console script or rake task outside the mutations/workers actually opened) — so "only path found" reflects the paths this spike traced, not a claim of exhaustive enumeration of the entire codebase. **Round 4 confirms the equivalent statement-side conclusion: `Statement` has no forced-acceptance path at all, by any mechanism — see Round 4 Finding 19.**

---

## What remains uncertain (Round 3 additions)

- **Whether any console script, rake task, or code path this spike did not open can call `Acceptment.new`/`create_acceptment!` directly**, bypassing both the single-declaration policy gate (Round 2 Finding 8) and the bulk CSV processor (Round 2 Finding 8). Finding 16 closes the two specific workers the engineer named; it does not claim an exhaustive audit of every call site in the codebase.
- **Adobe Acrobat Sign's actual audit-report packaging format** — separate file, appended page, or something else — could not be confirmed from a primary source in this round (Finding 12). A future attempt might succeed with a different fetch mechanism or a cached/mirrored copy of the `helpx.adobe.com` pages.
- ~~**Whether the engineer wants the captured PDF itself to visually indicate a forced acceptance**~~ — **resolved by the engineer in Round 4: the frontend rendering gap (Finding 15) will be fixed directly in `app-webclient` text and code, not compensated for in the evidentiary-metadata packaging.**
- **Whether a bulk/multi-document manifest packaging convention (Option (b)) exists anywhere in the e-signature industry** — this round's search did not surface one; Finding 14 reports this as not found rather than inferred from single-document guidance.

---

## Suggested options for main and the engineer (Round 3 additions)

- ~~**Packaging, now grounded (Finding 10-14, mapping table above)**~~ — **decided in Round 4: separate file (Finding 10's DocuSign-default shape).**
- ~~**On Finding 15 (unsigned-declaration rendered UI)**~~ — **decided in Round 4: fixed in the frontend, not compensated for in the evidentiary metadata.**
- **On Finding 16:** the Round 2 open question is closed for the two named workers; if the engineer wants a full-codebase audit of every `Acceptment`-creating call site (beyond the two GraphQL mutations, the one CSV processor, and these two cleansing workers already traced), that would be a new, explicitly-scoped follow-up.

(No recommendation — Round 3, like Rounds 1 and 2, surfaces grounded options and verified facts; main and the engineer decide.)

---

## Round 4 — the second declaration kind: "declaração de resultado" (`Statement`)

**Two decisions the engineer already made are reflected as struck-through/annotated text above (Finding 4's table, the "What remains uncertain" and "Suggested options" sections in Rounds 1 and 3) — they are not re-opened here:** (1) the evidentiary trail is delivered as a **separate file**, not appended to the PDF, because appending changes the final PDF's image hash; (2) the Round 3 Finding 15 forced-acceptance-rendering gap is fixed **directly in the `app-webclient` frontend** (text + code), not compensated for in the evidentiary-metadata packaging. Round 4 is scoped only to mapping the second declaration kind the engineer introduced — the "declaração de resultado" — which everything in Rounds 1-3 did not cover.

Everything researched in Rounds 1-3 covers the **"declaração de regra"** — `PlanStatement` — the rules a participant accepts/signs (incentive structure: deal/indicator/ranking/limiter/redemption *rules*). This customer also needs the **"declaração de resultado"** exported — a second, distinct entity this round maps for the first time.

### Sources consulted (Round 4 additions)

- `app/app/models/statement.rb` — the `Statement` model, read in full
- `app-webclient/src/app/statement/statement-routing.module.ts` — the `/statements/:statementId` route, read in full
- `app-webclient/src/app/statement/statement-show/statement-show.component.html` — the results-declaration page template, read in full (563 lines)
- `app-webclient/src/app/statement/statement-show/statement-show.component.ts` — the results-declaration page component, read in full (934 lines)
- `app/db/schema.rb:2070-2081` — `statements` table definition
- `app/app/policies/statement_policy.rb` — the `StatementPolicy#accept?` gate, read in full
- `app/app/graphql_mutations/accept_statement_v2_graphql_mutation.rb`, `app/app/graphql_mutations/accept_statement_graphql_mutation.rb` — the single-declaration acceptance mutations for `Statement`
- `app/app/workers/acceptment/statement_migration/consumer.rb` — a legacy data-migration worker touching `Statement` + `Acceptment`, read in full to rule it out as a forced-acceptance path
- `app/app/workers/statement_audit/processor.rb` — the existing `Statement`-side "audit" worker, read in full, as the closest existing sibling to compare against `PlanStatementAudit`
- `app/app/work_books/statement_audit_work_book.rb` — the manifest generator `StatementAudit::Processor` calls, read in full

### Finding 17: `Statement` is the "declaração de resultado" and `PlanStatement` is the "declaração de regra" — confirmed by what each model is actually built from, not assumed by name similarity

**Evidence — `PlanStatement` (the rules declaration, already established in Rounds 1-3) is structured around `Plan` and its incentive *rules*:** `PlanStatement belongs_to :plan` and the page (`plan-statement-show.component.html`, cited throughout Rounds 1-3) renders `dealIncentive`/`indicatorIncentive`/`rankingIncentive`/`limiterIncentive`/`redemptionIncentive` panels — the incentive *definitions* a participant is agreeing to.

**Evidence — `Statement` is structured around `Commission`, via `UserCommission`, and its content is money/points *results*, not rules:**
```ruby
# app/app/models/statement.rb:3-33
class Statement < ApplicationRecord
  belongs_to :company, optional: true, inverse_of: :statements
  belongs_to :owner, class_name: 'User', inverse_of: :owned_statements, optional: true
  belongs_to :user, optional: true, inverse_of: :owned_statements
  belongs_to :user_commission, optional: true, inverse_of: :statement
  has_many :user_field_snapshots, dependent: :nullify, inverse_of: :statement
  has_many :user_statement_histories, dependent: :restrict_with_exception, inverse_of: :statement
  has_one :acceptment, dependent: :destroy, inverse_of: :statement

  # Keep through associations defined after the regular ones
  has_one :commission, through: :user_commission
  ...
  delegate :commission, to: :user_commission
  delegate :name, to: :commission
```
`Statement` has no `belongs_to :plan` at all — it reaches `Commission` through `user_commission`, and `Commission` is a computed payout record, not a rule set. The frontend confirms this concretely: the results page's final summary block (`statement-show.component.html:473-531`) displays `statement.userCommission.dealMoney`, `indicatorMoney`, `rankingMoney`, `limiterMoney`, `redemptionMoney`, and `billableMoney` — all currency totals — under the heading `'statement.total'`. Compare this to the rules page, which never displays a money total at all; it displays rule/formula text (`'plan_statement.page.formula'`, per Round 1's original `signature-pdf-export/SPIKE.md`). The results page's panels are similarly result-shaped: `dealCommissionings`, `indicatorCommissionings`, `rankifierCommissionings`, `limiterCommissionings`, `redemptionCommissionings`, and `rankings` (`statement-show.component.html:160-472`) — each showing `points`/`money` achieved, not a rule definition.

**Source:** `app/app/models/statement.rb:3-33`, `app-webclient/src/app/statement/statement-show/statement-show.component.html:160-531`

**Significance:** the mapping is not a naming coincidence — `PlanStatement` is literally built from `Plan` (the rule set: incentives), and `Statement` is literally built from `Commission` via `UserCommission` (the computed payout: money and points). The "declaração de regra" (what was agreed to) is `PlanStatement`; the "declaração de resultado" (what was earned) is `Statement`. Nothing in either model's structure supports the reverse mapping.

---

### Finding 18: The results-declaration page (`/statements/:statementId`) has the SAME collapsible-panel and async-load hazards as the rules page — and more of them, plus a pagination pattern the rules page does not have

**Evidence — the route:**
```typescript
// app-webclient/src/app/statement/statement-routing.module.ts:17-22
{
  path: 'statements/:statementId',
  component: StatementShowComponent,
  canActivate: [RouteGuardService],
  data: { permissionGuard: ['statementsListing'] },
},
```

**Evidence — six collapsible panel groups, all using the identical `*ngIf="X.expanded"` DOM-absent pattern already established for the rules page in the existing `signature-pdf-export/SPIKE.md` Finding 3:**
```html
<!-- app-webclient/src/app/statement/statement-show/statement-show.component.html:163,201 (dealCommissionings, one of six) -->
<div class="show-panel" (click)="dealCommissioning.expanded = !dealCommissioning.expanded">
  ...
  <div class="show-panel-body" *ngIf="dealCommissioning.expanded">
```
The same shape repeats for `indicatorCommissionings` (line 264), `rankings` (line 300), `rankifierCommissionings` (line 368), `limiterCommissionings` (line 406), and `redemptionCommissionings` (line 445) — six panel groups total, versus the rules page's five.

**Evidence — the component fires NINE sequential async GraphQL calls after the initial statement load, versus the rules page's ONE (`getSignature()` only):**
```typescript
// app-webclient/src/app/statement/statement-show/statement-show.component.ts:215-227
this.statement = response.data.statements.nodes[0];
this.loadingStatement = false;
this.getGoals();
this.getCollaborativeDealCommissionings();
this.getDealCommissionings();
this.getAccumulatedDeals();
this.getIndicatorCommissionings();
this.getRankifierCommissionings();
this.getRankings();
this.getLimiterCommissionings();
this.getRedemptionCommissionings();
this.getSignature();
```
The component does track a combined `loading` getter that ANDs together every one of these load flags (`statement-show.component.ts:75-86`: `loadingStatement`, `loadingAccumulatedDeals`, `loadingCollaborativeDealCommissionings`, `loadingDealCommissionings`, `loadingLimiterCommissionings`, `loadingIndicatorCommissionings`, `loadingRankifierCommissionings`, `loadingRedemptionCommissionings`) — but `getGoals()`, `getRankings()`, and `getSignature()` are conspicuously absent from that list, so the template's `*ngIf="loading; else statementShowTemplate"` (`statement-show.component.html:1`) can flip to "not loading" before those three calls resolve.

**Evidence — a "load more" pagination pattern that does not exist on the rules page at all:**
```html
<!-- app-webclient/src/app/statement/statement-show/statement-show.component.html:246-259 -->
<button
  class="has-more"
  *ngIf="hasMoreAccumulatedDeals()"
  (click)="getAccumulatedDeals()"
  [disabled]="loadingMore"
>
```
`getAccumulatedDeals()` fetches 9 records per page (`statement-show.component.ts:485`: `variables: Record<string, any> = { first: 9 }`) and exposes `hasMoreAccumulatedDeals()` (`ts:542`) to render a "load more" button — a participant (or a company) with more than 9 accumulated deals for the period requires additional clicks to see them all. No equivalent pagination exists anywhere in the rules-declaration page.

**Source:** `app-webclient/src/app/statement/statement-routing.module.ts:17-22`, `app-webclient/src/app/statement/statement-show/statement-show.component.html:1,163-472,246-259`, `app-webclient/src/app/statement/statement-show/statement-show.component.ts:75-86,215-227,478-542`

**Significance:** answering the research question directly — the results page does NOT get to skip the Phase-1 pre-expansion treatment; it needs it MORE than the rules page did. A URL-parameter pre-expansion mechanism built for `PlanStatementShowComponent`'s five panels does not automatically cover `StatementShowComponent`'s six, and the nine-async-call sequence (versus one) means a Ferrum capture waiting on "page load" alone is more likely to race ahead of data that has not arrived yet — Round 1's original spike Finding 4 already flagged this exact race for the rules page's single second call; here there are eight more chances for it. The accumulated-deals pagination is a genuinely new hazard with no rules-page analogue at all: a full, complete results PDF for a participant with more than 9 accumulated deals cannot be captured by navigating to one URL and waiting — the page requires an explicit additional interaction to reveal the rest of the data, which Phase 1's pre-expansion approach (as scoped in the existing `PLAN.md`, built around toggling `.expanded` flags) does not address on its own.

---

### Finding 19: `Statement` IS signed/accepted, through the identical `Acceptment` model and mutation shape as `PlanStatement` — but has NO forced-acceptance path at all, confirmed both by the same policy gate and by the absence of any CSV-bulk equivalent

**Evidence — `Statement` has its own `accept`/`sign` methods, structurally identical to `PlanStatement`'s (Round 1 Finding 1):**
```ruby
# app/app/models/statement.rb:44-65
def accept(from: '1.1.1.1')
  create_acceptment!(
    user_id: user_id,
    from: from,
    signed: false,
    company_id: company_id
  )
end

def sign(from:, signature:)
  create_acceptment(
    user_id: user_id,
    from: from,
    signed: true,
    company_id: company_id,
    signature_attributes: {
      raw_file: { name: "s_#{id}#{user_id}", base64_content: signature },
      company_id: company_id,
      user_id: user_id
    }
  )
end
```
`has_one :acceptment, dependent: :destroy, inverse_of: :statement` (`statement.rb:10`) is the same association shape as `PlanStatement`'s. `Acceptment belongs_to :statement, optional: true, inverse_of: :acceptment` and validates via `statement_redundancy`/`statement_absence` that an `Acceptment` has exactly one of `plan_statement_id`/`statement_id` set (`app/app/models/acceptment.rb:9,42-54`, already cited in Round 1). The `acceptments` table's `statement_id` column (`app/db/schema.rb:47`, cited in Round 1 Finding 1) is the FK this uses. So every piece of Round 1's evidentiary apparatus — `acceptments.from` (IP), `acceptments.created_at` (timestamp), the `signed` flag, the `Signature` PNG — applies to a `Statement`'s acceptance identically to a `PlanStatement`'s, with no schema difference.

**Evidence — the mutation and policy gate are the same shape, and forbid a forced acceptance the same way:**
```ruby
# app/app/graphql_mutations/accept_statement_v2_graphql_mutation.rb:10-16
def execute
  statement = Statement.find(id)
  authorize(statement, :accept?)
  acceptment = statement.sign(from: remote_ip, signature: base64_signature)
  statement_dataset.accept! if statement_dataset && acceptment.present? && acceptment.persisted?
  respond_with(acceptment)
end
```
```ruby
# app/app/policies/statement_policy.rb:15-23
def accept?
  return false if company.client? && user.company_id != record.company_id
  return false if record.user_id != user.id
  return false unless record.pending?
  return false if record.commission.plan.canceled?
  return false if record.commission.plan.disabled?

  role.permission?('statement_acceptance') || user.permission?('statement_acceptance')
end
```
`record.user_id != user.id` is the identical gate Round 2 Finding 8 already established for `PlanStatementPolicy#accept?` — no user other than the statement's own owner can call this mutation successfully.

**Evidence — no CSV-bulk equivalent to `AcceptmentDocument::Processor` exists for `Statement`:** searching every worker referencing statement acceptance found exactly one: `Acceptment::StatementMigration::Consumer`, and it is a one-time legacy-data migration, not a forced-acceptance creator:
```ruby
# app/app/workers/acceptment/statement_migration/consumer.rb:8-15 (full method)
def perform(statement_id)
  statement = Statement.with_uncached_connection { Statement.find(statement_id) }
  acceptment = statement.build_acceptment
  acceptment.user_id = statement.user_id
  acceptment.from = statement.accepted_from
  acceptment.created_at = statement.updated_at
  acceptment.updated_at = statement.updated_at
  acceptment.save!
end
```
`acceptment.user_id = statement.user_id` — always the declarant's own id, backfilling `Acceptment` rows from a pre-`Acceptment` legacy `accepted_from`/status column on `Statement` itself. It never sets an actor different from the declarant, so it cannot produce a forced acceptance even in principle.

**Source:** `app/app/models/statement.rb:10,44-65`, `app/app/models/acceptment.rb:9,42-54`, `app/db/schema.rb:2070-2081` (`statements` table), `app/app/graphql_mutations/accept_statement_v2_graphql_mutation.rb:10-16`, `app/app/policies/statement_policy.rb:15-23`, `app/app/workers/acceptment/statement_migration/consumer.rb:8-15`

**Significance:** this confirms the engineer's stated premise exactly. `Statement` has real acceptance evidence — the full Round 1 apparatus (IP, timestamp, `signed` flag, optional drawn signature) applies unmodified — but forced acceptance is categorically impossible for it: the single-record path is gated the same way `PlanStatement`'s is (Round 2 Finding 8), and unlike `PlanStatement`, there is no bulk CSV path at all (`AcceptmentDocument::Processor`, Round 2 Finding 8, only ever looks up a `plan_statement_id` — it has no code path that touches `statement_id`). Consequently, everything Round 2 and Round 3 built for the forced case — `AcceptmentReason` capture (Findings 6-9), the actor-substitution read (`acceptment.user` vs `plan_statement.user`), and the rendering-gap fix (Finding 15, being fixed in the frontend per the engineer's Round 4 decision) — is **inapplicable to `Statement`** by construction, not by omission. A `Statement`'s evidentiary worker only ever needs the "normal acceptance" branch.

---

### Finding 20: No existing PDF-capable export infrastructure exists for `Statement` — the only sibling is a single-worker XLSX-only `Processor`, structurally different from the `PlanStatementAudit` fan-out the planned `PlanStatementExport` reuses

**Evidence — the full `StatementAudit::Processor`, a single non-fan-out worker:**
```ruby
# app/app/workers/statement_audit/processor.rb (full file)
class StatementAudit < Audit
  class Processor < ApplicationWorker
    sidekiq_options queue: :audit

    def perform(audit_id)
      statement_audit = StatementAudit.with_uncached_connection { StatementAudit.find(audit_id) }
      StatementAudit.with_uncached_connection { statement_audit.process! }
      attachment = Attachment.with_uncached_connection { statement_audit.build_attachment }
      attachment.file = StatementAuditWorkBook.new(statement_audit).generate
      Attachment.with_uncached_connection { attachment.save }
      StatementAudit.with_uncached_connection { statement_audit.finish! }
    end
  end
end
```
This is a single `Processor` (per Round 1's cited topology naming from `~/.claude/docs/DATA-PROCESSING.md` — "a single job for one bounded/indivisible unit of work", not a Producer/Consumer fan-out). It generates one `Axlsx::Package` workbook directly (`StatementAuditWorkBook`, confirmed by reading the full file — `app/app/work_books/statement_audit_work_book.rb`) and attaches it — no PDF, no Ferrum, no per-declaration parallelization, no `Computation` counter. `ls app/app/workers/statement_audit/` returns exactly one file, `processor.rb` — there is no `statement_audit/producer.rb` or `statement_audit/consumer.rb` at all, confirmed by directory listing. This contrasts with `plan_statement_audit/`, which holds the `producer.rb`/`consumer.rb`/`finalizer.rb` triad the existing `PLAN.md` explicitly reuses as its pattern source (`PLAN.md:41,51`, Round 1 citations).

Searching the codebase for a `Statement`-side equivalent of `PlanStatementPortable`/`PlanStatementPortableBatch` (the per-declaration PDF + ZIP models the existing `PLAN.md` reuses for CarrierWave upload paths, `PLAN.md:216`) found none — no `statement_portable`-named model, uploader, or GraphQL type exists anywhere in `app/app/`. **Round 5 (below) is the full investigation of this absence and of the `Portable` family itself.**

**Source:** `app/app/workers/statement_audit/processor.rb` (full file), `app/app/work_books/statement_audit_work_book.rb:1-37` (full file), directory listing of `app/app/workers/statement_audit/` (one file) vs `app/app/workers/plan_statement_audit/` (three files, per Round 1's citations), grep for `statement_portable` in `app/app/` (no matches — absence confirmed)

**Significance:** answering the research question directly — the existing Producer → Consumer (Ferrum render → S3) → Finalizer (ZIP + XLSX) + `Computation` flow does NOT already have a `Statement`-side counterpart to extend; it would need to be built new, mirroring the `PlanStatementExport` design the existing `PLAN.md` describes rather than reusing any existing `Statement`-specific fan-out infrastructure (there is none at that scale). Concretely, a `StatementExport::{Producer,Consumer,Finalizer}` triad would differ from the planned `PlanStatementExport` triad in exactly these ways: (a) **no forced-acceptance branch** in the Consumer — Finding 19 establishes this case cannot occur, so the `forced_acceptance?` conditional logic built for `PlanStatementExport` (Round 2/3) has nothing to check for `Statement`; (b) **enumeration scope** is `Statement.for_company(company_id).accepted` rather than `PlanStatement.for_company(company_id).accepted` (Finding 21, below); (c) **target URL** is `/statements/:statementId` rather than `/planStatements/:planStatementId`, and needs its own Phase-1-equivalent pre-expansion work covering six panels, nine async loads, and the accumulated-deals pagination (Finding 18) — none of which the rules-page Phase 1 work automatically covers; (d) **manifest/evidentiary field set** differs — `Statement`'s business content is money/points totals (`dealMoney`, `indicatorMoney`, `rankingMoney`, `limiterMoney`, `redemptionMoney`, `billableMoney`, per Finding 17) rather than incentive-rule text, so a shared manifest across both declaration kinds would need either a differing column set per kind or two separate sheets/manifests — a packaging decision, not something this spike resolves. What carries over unchanged and generically: the `Computation` Redis counter mechanism, the S3/CarrierWave upload pattern, the `Digest::SHA256` hashing approach (Finding 3), and the separate-file evidentiary-trail packaging the engineer already chose (Round 4 header note) — none of that machinery is `PlanStatement`-specific.

---

### Finding 21: Enumerating all result declarations for a company uses the identical scope shape as the rules declarations, and the required indexes are confirmed present

**Evidence:**
```ruby
# app/app/models/statement.rb:20,26
scope :accepted, -> { joins(:acceptment) }
...
scope :for_company, ->(company_id) { where(company_id: company_id) if company_id.present? }
```
So `Statement.for_company(company_id).accepted` is the direct analogue of `PlanStatement.for_company(company_id).accepted`, which the existing `PLAN.md` already confirmed indexed and uses as the Producer's enumeration (`PLAN.md:52,134`, Round 1 citations).

**Evidence of the covering indexes:**
```ruby
# app/db/schema.rb:2070-2081 (statements table)
create_table "statements", id: :serial, force: :cascade do |t|
  t.bigint "company_id"
  t.datetime "created_at", null: false
  t.integer "owner_id"
  t.datetime "updated_at", null: false
  t.integer "user_commission_id"
  t.integer "user_id"
  t.index ["company_id"], name: "index_statements_on_company_id"
  t.index ["owner_id"], name: "index_statements_on_owner_id"
  t.index ["user_commission_id"], name: "index_statements_on_user_commission_id", unique: true
  t.index ["user_id"], name: "index_statements_on_user_id"
end
```
`index_statements_on_company_id` covers the `for_company` filter. The `.accepted` scope's `joins(:acceptment)` is covered by `index_acceptments_on_statement_id` (already cited in Round 1 Finding 1's schema excerpt, `app/db/schema.rb:38-57`).

**Source:** `app/app/models/statement.rb:20,26`, `app/db/schema.rb:2070-2081`, `app/db/schema.rb:38-57` (acceptments, cited Round 1)

**Significance:** enumeration for the results-declaration export has the exact same shape and the exact same index coverage as the already-confirmed rules-declaration enumeration — no schema gap here. A `StatementExport::Producer` can pluck `Statement.for_company(company_id).accepted.pluck(:id)` with the same confidence `PlanStatementExport::Producer`'s enumeration already has.

---

## What remains uncertain (Round 4 additions)

- **Whether the two declaration kinds (regra and resultado) are delivered in one combined ZIP+manifest or two separate deliverables.** Finding 20 notes the manifest column sets differ in kind (rule text vs. money/points totals); this spike surfaces the difference without deciding how the engineer wants it packaged.
- **Whether a single Phase-1 pre-expansion mechanism can be generalized to cover both `PlanStatementShowComponent` and `StatementShowComponent`, or whether `StatementShowComponent` needs its own dedicated pre-expansion work** given it has six panels (not five), nine async calls (not one), and the accumulated-deals pagination that has no rules-page analogue (Finding 18). This spike maps the hazard; it does not design the fix.
- **Whether the accumulated-deals "load more" pagination (Finding 18) can be bypassed entirely** — e.g. by having Ferrum request a larger page size via a different GraphQL query shape than the one the UI itself uses, rather than simulating repeated button clicks — is an implementation question outside this spike's scope.
- **How many result declarations exist for this specific cancelled customer**, and whether their commission periods and acceptance dates fall inside or outside the `security_events` coverage window (the same class of uncertainty as Round 1's date-boundary question, now applying to a second entity).

---

## Suggested options for main and the engineer (Round 4 additions)

- **Entity confirmed, no options to surface** — Finding 17 establishes `Statement` = "declaração de resultado" and `PlanStatement` = "declaração de regra" as a fact about the codebase, not a design choice.
- **Frontend pre-expansion approach for `StatementShowComponent`** — build a second, dedicated pre-expansion mechanism (six panels + nine async waits + pagination) as its own Phase-1-equivalent work, versus attempting to generalize a shared mechanism across both `*ShowComponent`s. This spike surfaces the two paths without choosing.
- **Manifest/packaging shape across the two declaration kinds** — one combined ZIP+XLSX with two column sets or sheets, versus two fully separate export flows (two Producer/Consumer/Finalizer triads, two ZIPs). Both are consistent with everything confirmed in Findings 17-21; the choice is the engineer's.
- **`StatementExport::{Producer,Consumer,Finalizer}` as new, dedicated workers** mirroring `PlanStatementExport`'s design (per the existing `PLAN.md`) rather than extending `StatementAudit::Processor` (Finding 20) — extending the latter would mean adding fan-out, Ferrum, `Computation`, and PDF capability to a worker that today does none of those things, which is a larger change to an existing single-purpose worker than building a fresh sibling. This spike surfaces the two shapes without recommending between them.

(No recommendation — Round 4, like Rounds 1-3, surfaces verified facts and maps the second declaration kind; main and the engineer decide how the two kinds are packaged, delivered, and built.)

---

## Round 5 — the 2017-era "export to Excel / printed version" remnants, and whether they can be reused

The engineer recalled that around 2017, 4Shark built an "export to Excel / printed version" feature for this same customer (RedeBrasil), because the customer disputed the legal validity of digital signature acceptance and wanted a printed alternative — a feature the customer never actually used. The engineer believed the models/tables/associations were never dropped. This round finds and dates the remnant, establishes exactly what is alive versus dead in it today, and surfaces reuse-vs-build-new as options.

### Sources consulted (Round 5 additions)

- `app/app/models/plan_statement_portable.rb`, `app/app/models/plan_statement_portable_batch.rb` — read in full (re-examined from Round 1)
- `app/app/models/plan_statement_portable_attachment.rb`, `app/app/models/plan_statement_portable_batch_attachment.rb` — read in full
- `app/app/uploaders/plan_statement_portable_uploader.rb`, `app/app/uploaders/plan_statement_portable_batch_uploader.rb` — read in full
- `app/app/graphql_types/plan_statement_portable_graphql_type.rb` — read in full
- `app/app/graphql_mutations/download_plan_statement_portable_graphql_mutation.rb`, `app/app/graphql_mutations/download_plan_statement_portable_batch_graphql_mutation.rb` — read in full
- `app/db/schema.rb:1573-1595` — `plan_statement_portable_batches` and `plan_statement_portables` table definitions
- `git -C app log --diff-filter=A --format=%ad --date=short -- <path>` — used per-file to find each remnant's addition date (both the model files directly, and, where `--follow` was used, the rename chain of the migration files)
- `git -C app show --stat` on commits `3d9d4e964935bda708602ce9ed4eaa45deb8a260` (2020-05-15, "fix(PlanStatement): PDF Generation"), `25516c5cb1996cf02c1ebe07df1aa256f291f374` (2020-05-25, "fix(PlanStatementBatch): Generation"), `87cd836022f1214abd2c25c5b98231921f11d252` (2022-04-18, "chore(PlanStatement): Drop Portable"), and `64c18d8edff3e300bd401cf58ed9936837a249f0` (2025-12-10, "fix(Download): Add secure file downloads with audit trail for all report types") — full commit stats saved to `/tmp/commit_*.log` during research, quoted below
- `git -C app log --diff-filter=D` on the deleted controller, views, and worker files, to date the feature's removal
- `git -C app log --all --diff-filter=A -- 'db/migrate/*statement_portable*'` — full-history search for any `Statement`-side (non-`PlanStatement`) portable migration, across all branches
- grep for `StatementPortable` (excluding `PlanStatementPortable`) across `app/app/` — absence check for a result-side remnant
- grep for `PlanStatementPortable` across `app-webclient/src` — absence check for any frontend caller

### Finding 22: The remnant is real, and it is exactly what the engineer described — but the commit dates are 2020, not 2017, and the character of the code (server-rendered ERB views, `wicked_pdf`, no Angular) confirms it predates the current Angular frontend by design, matching the engineer's account of the era even though the specific year is off

**Evidence — the originating commit, in full, is a wicked_pdf-based server-rendered PDF/print feature, not the Ferrum-based approach the current backfill plan uses:**
```
# git show --stat 3d9d4e964935bda708602ce9ed4eaa45deb8a260 (saved to /tmp/commit_3d9d4e9_stat.log)
3d9d4e964935bda708602ce9ed4eaa45deb8a260
Fri May 15 11:16:19 2020 -0300
fix(PlanStatement): PDF Generation

 app/controllers/plan_statements/portable_batches_controller.rb |  33 ++
 app/models/plan_statement_portable.rb              |  11 +
 app/models/plan_statement_portable_attachment.rb   |  13 +
 app/models/plan_statement_portable_batch.rb        |  27 ++
 app/views/layouts/pdf.html.erb                     |  13 +
 app/views/plan_statements/pdf.html.erb              | 337 +++++++++++++++++++++
 app/views/plan_statements/portable_batches/index.html.erb | 68 +++++
 app/workers/plan_statement_portable/consumer.rb    |  54 ++++
 app/workers/plan_statement_portable/finalizer.rb   |  35 +++
 app/workers/plan_statement_portable/producer.rb    |  30 ++++
 config/initializers/wicked_pdf.rb                  |  23 ++
 51 files changed, 1169 insertions(+), 6 deletions(-)
```
The follow-up commit ten days later confirms the same feature being restructured, not a different one:
```
# git show --stat 25516c5cb1996cf02c1ebe07df1aa256f291f374 (saved to /tmp/commit_25516c5_stat.log)
25516c5cb1996cf02c1ebe07df1aa256f291f374
Mon May 25 01:52:09 2020 -0300
fix(PlanStatementBatch): Generation
Fixes associations between models by creating separated tables for each responsibility.

fixes https://rollbar.com/4Shark/App-Poc/items/178

 db/migrate/20200525014313_create_plan_statement_portable_batches.rb | 15 ++++++
 db/migrate/20200525014739_create_plan_statement_portables.rb        | 13 +++++
 51 files changed, ...
```
This is the commit that created the two migrations naming the tables `plan_statement_portable_batches` and `plan_statement_portables`, confirmed matching the live schema (`app/db/schema.rb:1573,1587`).

**A methodological caveat on dating, stated explicitly:** a `git log --follow` trace on the migration file's current path (`db/migrate/2020/05/20200525014313_create_plan_statement_portable_batches.rb`) reported a rename chain reaching back to a 2018-11-17 commit titled "eat(Commission): Audit" (likely a truncated "feat"). This is treated as **UNRELIABLE and not used as a claim** — git's `--follow` rename detection is a content-similarity heuristic, and two unrelated migration files sharing boilerplate structure can trigger a false "rename" match. The dates this Finding relies on instead are the direct, non-`--follow` `diff-filter=A` results on the model files themselves (`app/models/plan_statement_portable.rb`, `app/models/plan_statement_portable_batch.rb`, both `2020-05-15`) and the full commit content shown above, which is unambiguous.

**Source:** `/tmp/commit_3d9d4e9_stat.log`, `/tmp/commit_25516c5_stat.log` (both full `git show --stat` output, quoted above), `app/db/schema.rb:1573-1595`

**Significance:** the engineer's "around 2017" is off by roughly 2.5–3 years against what git actually records (2020-05-15 / 2020-05-25) — this spike states that discrepancy plainly rather than rounding it away. But the *character* of the engineer's account is fully corroborated: this is a legacy, pre-Angular, server-rendered (ERB) "PDF generation" / print feature, built with `wicked_pdf` (a tool this same investigation's earlier round, `signature-pdf-export/SPIKE.md` Finding 10, already found does not execute Angular JS and renders SPA content blank — so this old feature could never have worked against the current Angular declaration pages even if reused as-is; it was designed against server-rendered ERB, a fundamentally different rendering path than today's app). Whether the specific year is 2017 or 2020, the feature's referenced Rollbar ticket (`App-Poc/items/178`, visible in the commit message) is independent evidence that this was a real, ticketed piece of work, not a scratch experiment.

---

### Finding 23: The regra-side (`PlanStatement`) remnant is DEAD on its creation path — the entire generation pipeline (Producer/Consumer/Finalizer, the ERB views, `wicked_pdf`) was deleted 2022-04-18 — but the models/uploaders/associations survive, and a GraphQL download surface was recently (re-)added in 2025 as generic infrastructure, not as a reactivation

**Evidence — nothing today creates a new `PlanStatementPortable`/`PlanStatementPortableBatch` record:** `grep -rln "PlanStatementPortableBatch\.new\|PlanStatementPortable\.new\|PlanStatementPortableBatch\.create\|PlanStatementPortable\.create" app/app/` returns zero matches. The generation pipeline that once created them no longer exists — confirmed both by `find app/app/workers/plan_statement_portable` returning "No such file or directory" and by the deletion commit itself:
```
# git show --stat 87cd836022f1214abd2c25c5b98231921f11d252 (saved to /tmp/commit_87cd836_stat.log)
87cd836022f1214abd2c25c5b98231921f11d252
Mon Apr 18 00:05:17 2022 -0300
chore(PlanStatement): Drop Portable

 app/graphql_types/plan_statement_portable_batch_graphql_type.rb  | 16 -------
 app/graphql_types/plan_statement_portable_graphql_type.rb        | 12 -----
 app/views/layouts/pdf.html.erb                                   | 13 ------
 app/workers/plan_statement_portable/consumer.rb                  | 52 ---------------------
 app/workers/plan_statement_portable/finalizer.rb                 | 53 ----------------------
 app/workers/plan_statement_portable/producer.rb                  | 23 ----------
 23 files changed, 13 insertions(+), 276 deletions(-)
```
This commit removed the Producer/Consumer/Finalizer worker triad, the `pdf.html.erb` layout, and (at the time) the two GraphQL types. `wicked_pdf` is confirmed gone from the current Gemfile: `grep -n "wicked_pdf" app/Gemfile` returns nothing. The original `portable_batches_controller.rb` (the Rails-admin-style UI to trigger a batch) was separately deleted earlier — `git log --diff-filter=D` on it dates the deletion to 2022-04-14 ("chore(*): Remove internal routes"), four days before the "Drop Portable" commit.

**Evidence — the models, uploaders, and CarrierWave S3 paths from the original feature DO still exist, unchanged in shape:** (already established in Round 1 Finding 4 and re-confirmed by re-reading in this round) `PlanStatementPortable`/`PlanStatementPortableBatch` (`app/app/models/plan_statement_portable.rb`, `app/app/models/plan_statement_portable_batch.rb`), their `Attachment` subclasses (`PlanStatementPortableAttachment`, `PlanStatementPortableBatchAttachment`), and their uploaders storing to `uploads/plan_statement_portables/#{model.attachable_id}` and `uploads/plan_statement_portable_batches/#{model.attachable_id}` (`app/app/uploaders/plan_statement_portable_uploader.rb:4-6`, `app/app/uploaders/plan_statement_portable_batch_uploader.rb:4-6`) are all present and unmodified in structure since the original 2020 feature.

**Evidence — a GraphQL download surface for these models was (re-)added in December 2025, but as part of a blanket security-hardening pass across EVERY downloadable report type in the platform, not as a reactivation of this specific feature:**
```
# git show --stat 64c18d8edff3e300bd401cf58ed9936837a249f0 (saved to /tmp/commit_64c18d8_stat.log)
64c18d8edff3e300bd401cf58ed9936837a249f0
Wed Dec 10 12:01:03 2025 -0300
fix(Download): Add secure file downloads with audit trail for all report types

 app/graphql_mutations/download_commission_report_creation_event_graphql_mutation.rb | 30 ++
 app/graphql_mutations/download_payment_exportation_graphql_mutation.rb              | 30 ++
 app/graphql_mutations/download_plan_statement_portable_batch_graphql_mutation.rb    | 30 ++
 app/graphql_mutations/download_plan_statement_portable_graphql_mutation.rb          | 30 ++
 app/models/plan_statement_portable_batch_download.rb                                |  6 +++
 app/models/plan_statement_portable_download.rb                                      |  6 +++
 42 files changed, 474 insertions(+), 32 deletions(-)
```
The title and the file list ("for all report types" — `commission_report_creation_event`, `payment_exportation`, `payment_report`, `deal_extraction`, `plan_statement_portable`, `plan_statement_portable_batch`, all touched in the same commit) show this is a generic, polymorphic-`Downloadable`-interface hardening pass, not work targeted at `PlanStatementPortable` specifically — it happened to sweep in the leftover 2020 models because they still implement the same `Downloadable`/`Attachment` interface every other report type does. `git log --diff-filter=A` on `app/app/graphql_types/plan_statement_portable_graphql_type.rb` shows it was added twice — 2020-07-09 (original feature) and again 2025-02-05 ("feat(*): commission report creation batch", a separate, also-generic API-surface commit) — meaning the GraphQL type was deleted in the 2022 "Drop Portable" commit and only reappeared as a byproduct of later, unrelated platform-wide work.

**Evidence — no frontend caller exists for any of this:** `grep -rln "planStatementPortable\|PlanStatementPortable" app-webclient/src` returns zero matches. `app-webclient` never queries the GraphQL type, never calls either download mutation, and has no route or component referencing any of these models.

**Source:** `/tmp/commit_87cd836_stat.log`, `/tmp/commit_64c18d8_stat.log` (both full `git show --stat` output, quoted above), grep results as cited inline, `app/Gemfile` (absence of `wicked_pdf`)

**Significance:** this is "dead code with live edges", stated precisely: the creation path (what would make new records) has been gone since 2022; the download path (what would let someone fetch an existing record's file) exists today only because a 2025 platform-wide security commit swept it in incidentally, not because anyone reactivated the RedeBrasil print feature; and no frontend anywhere calls that download path. Nothing in the codebase this spike traced creates a `PlanStatementPortable`/`PlanStatementPortableBatch` record today — so even the "live" download mutations would, on the current codebase, only ever find rows if some still exist in the database from 2020-2022 (a production-data question this spike cannot answer — see "What remains uncertain").

---

### Finding 24: The resultado-side (`Statement`) has NO remnant at all — the 2020 feature was built exclusively for `PlanStatement`; a full-history, all-branches search finds zero `Statement`-side portable migration ever existed

**Evidence:**
```
# git -C app log --all --diff-filter=A --format=%ad%x09%s --date=short --name-only -- 'db/migrate/*statement_portable*'
2020-05-25	fix(PlanStatementBatch): Generation

db/migrate/20200525014313_create_plan_statement_portable_batches.rb
db/migrate/20200525014739_create_plan_statement_portables.rb
```
This search covers every migration file, across every branch in the local repository, whose name matches `*statement_portable*` — both `plan_statement_portable` and a hypothetical bare `statement_portable` would match. Only the two known `plan_statement_portable*` migrations appear; no `statement_portables`/`statement_portable_batches` migration exists or ever existed in this repository's history. Separately, `grep -rln "StatementPortable" app/app/` (excluding matches on `PlanStatementPortable`) returns zero results — no model, uploader, controller, GraphQL type, or worker anywhere references a bare `StatementPortable`.

**Source:** `git -C app log --all --diff-filter=A -- 'db/migrate/*statement_portable*'` output (quoted above), grep result for `StatementPortable` excluding `PlanStatementPortable` in `app/app/` (no matches)

**Significance:** this directly answers the "result-side symmetry" question. The 2017/2020-era print/export feature was built ONLY for the rules declaration (`PlanStatement`) — the results declaration (`Statement`) never had an equivalent, at any point in this repository's recorded history. Whatever reuse decision the engineer makes for the `PlanStatement` side of this backfill, it has nothing to reuse on the `Statement` side — that side needs new models/workers built from scratch regardless (already established independently in Round 4 Finding 20, which found no `Statement`-side portable infrastructure without yet explaining why; this Finding is the historical confirmation that "why" is "it was never built", not "it was built and later removed more thoroughly than the `PlanStatement` side").

---

### Finding 25: What the `Portable` family already provides toward a reuse, and what stands in the way — enumerated concretely, without choosing

**What already exists and could be reused, concretely:**

- **A two-level batch/item state machine.** `PlanStatementPortableBatch`: `initial → processing → final` (`app/app/models/plan_statement_portable_batch.rb:34-43`, cited Round 1). `PlanStatementPortable` (the per-declaration item): `processing → final` (`app/app/models/plan_statement_portable.rb:20-24`, cited Round 1). Both are `state_machine`-gem-backed, matching the pattern the existing `PLAN.md` already cites as the target shape (`PLAN.md:126`, Round 1).
- **CarrierWave uploaders with S3 paths already scoped per-record.** `uploads/plan_statement_portables/#{model.attachable_id}` and `uploads/plan_statement_portable_batches/#{model.attachable_id}` (`app/app/uploaders/plan_statement_portable_uploader.rb:4-6`, `app/app/uploaders/plan_statement_portable_batch_uploader.rb:4-6`) — the exact CarrierWave-to-S3 pattern the existing `PLAN.md` already plans to reuse generically (`PLAN.md:55`, Round 1 citation: `"Existing CarrierWave pattern... No new upload infrastructure required"`).
- **Polymorphic `Attachment` association**, already wired: `has_one :attachment, as: :attachable, class_name: 'PlanStatementPortableAttachment'` (`app/app/models/plan_statement_portable.rb:7`) — the same `Attachment` STI base class (`app/app/models/document.rb`-adjacent, cited Round 1 Finding 1 context) other export features use.
- **Owner/company/calendar associations already present on the batch**: `belongs_to :calendar`, `belongs_to :company`, `belongs_to :owner` (`app/app/models/plan_statement_portable_batch.rb:4-6`) — the batch already carries the metadata a new model would also need to declare.
- **A download-audit trail, added most recently (Dec 2025)**: `PlanStatementPortableDownload`/`PlanStatementPortableBatchDownload` (Finding 23) — polymorphic `Download` records tracking who downloaded what, when, from what IP, already wired via `has_many :downloads, class_name: 'PlanStatementPortableDownload', as: :downloadable` (`app/app/models/plan_statement_portable.rb:6`). This is itself a small piece of "evidentiary trail" machinery (a download audit, not the signing audit Rounds 1-3 built) that already exists and works today, independent of whether the batch/item models themselves are reused.

**What is missing or actively in the way, concretely:**

- **`PlanStatementPortableBatch` is hard-coupled to exactly one `calendar`, which conflicts with a company-wide backfill.** `validates :calendar_id, presence: true` (`app/app/models/plan_statement_portable_batch.rb:12`) and the `before_validation :add_plan_statements` callback populate the batch's `plan_statement_ids` by querying `calendar.plans.joins(:statements).where('plan_statements.plan_statement_portable_batch_id': nil).pluck('plan_statements.id')` (`app/app/models/plan_statement_portable_batch.rb:57-66`, verbatim as written in the model, including its own `joins(:statements)` call). This backfill needs every ACCEPTED declaration for a company across however many calendars the cancelled customer had — the existing callback has no path to "every calendar for this company" without either looping the batch-creation call once per calendar or rewriting the callback.
- **No `computation` method exists on either model.** `grep -n "def computation" app/app/models/plan_statement_portable_batch.rb app/app/models/plan_statement_portable.rb` returns nothing — confirmed again in this round, matching Round 1 Finding 5's original observation. The `Computation` Redis-counter completion guarantee this whole spike's evidentiary work depends on (Round 1 Finding 5) is not present on these models and would need to be added.
- **No PDF-capture step survives.** The Ferrum-equivalent of 2020 (`wicked_pdf` against server-rendered ERB) is gone along with the Consumer/Finalizer that drove it (Finding 23) — any reuse of the `Portable` models still needs an entirely new Consumer written against Ferrum + the Angular declaration pages, matching what the existing `PLAN.md`'s Phase 2.3 already specifies from scratch. Reuse, if chosen, buys the storage/tracking layer, not the rendering layer.
- **A unique-name constraint on the batch.** `t.index ["name"], name: "index_plan_statement_portable_batches_on_name", unique: true` (`app/db/schema.rb:1583`) — a naming collision to account for if batches are created programmatically rather than through the (now-deleted) admin form that presumably enforced uniqueness at the UI level.
- **No `Statement`-side counterpart exists to reuse at all (Finding 24)** — reuse, in any of its forms, only ever helps the `PlanStatement` half of this two-kind deliverable.

**Source:** `app/app/models/plan_statement_portable_batch.rb:4-6,12,34-43,57-66` (re-read in full this round), `app/app/models/plan_statement_portable.rb:6-7,20-24` (re-read in full this round), `app/db/schema.rb:1573-1595`, `app/app/uploaders/plan_statement_portable_uploader.rb:4-6`, `app/app/uploaders/plan_statement_portable_batch_uploader.rb:4-6`, grep for `def computation` in both model files (no matches), Finding 24 above

**Significance:** the reuse question is genuinely two-sided, not a simple yes/no — the storage/tracking/upload layer is substantially present and would save real work; the two things this whole spike centers on (a completion guarantee and a rendering step) are both absent and would need to be built regardless of the reuse decision; and the coupling to a single `calendar_id` is a real structural mismatch against "export everything for a company" that a reuse path has to resolve one way or another. None of this determines the answer — it is the complete list of what a reuse decision would be trading against.

---

## What remains uncertain (Round 5 additions)

- **Whether any `PlanStatementPortable`/`PlanStatementPortableBatch` rows actually exist in production today** from the 2020-2022 window when the creation pipeline was live, and if so, whether any of them belong to the cancelled customer (RedeBrasil) specifically. This spike has no production database access to check; it is stated as a fact this backfill's implementation would need to confirm before deciding whether "reuse the existing rows" is even a real option versus "reuse only the model/table shape and start fresh".
- **The git `--follow` rename-chain result pointing to a 2018-11-17 commit** (Finding 22) is explicitly flagged as unreliable and not used as a claim in this spike — but it was not independently disproven either, only set aside per Citation Discipline's caution against unverifiable derivations. If the engineer wants certainty on whether an even-earlier, since-renamed version of this feature existed, that would need direct inspection of that 2018 commit's actual diff content, which this round did not do.
- **Whether the engineer's "around 2017" refers to a different, earlier attempt at the same idea** that predates what git records for the `PlanStatementPortable` family specifically (2020-05-15 onward) — this spike found no earlier remnant under any name search performed, but a differently-named 2017 attempt (e.g., under a name not containing "portable" or "statement") would not have been found by the searches this round ran.

---

## Suggested options for main and the engineer (Round 5 additions)

**Reuse the `Portable` family for the `PlanStatement`/regra side of this backfill:**

- **Option 1 — Reuse as-is.** Accept the single-calendar batch scoping (Finding 25) by creating one `PlanStatementPortableBatch` per calendar rather than one per company, add a `computation` method to both models, and write an entirely new Consumer against Ferrum (the old one is gone). Lowest schema-change footprint; highest workflow complexity (N batches instead of one company-wide batch) and a change to a model that already survived one full feature generation.
- **Option 2 — Reuse with changes.** Relax `validates :calendar_id, presence: true` and rewrite `before_validation :add_plan_statements` to accept a company-wide scope instead of (or in addition to) a per-calendar one, add `computation`, write the new Consumer. One company-wide batch, matching the existing `PLAN.md`'s stated shape more closely; costs a schema/model change to a table whose only surviving purpose today is the incidental Dec-2025 download surface (Finding 23) — a change to old, thinly-used infrastructure rather than to something actively depended on.
- **Option 3 — Build new, dedicated models.** What the existing `PLAN.md`'s own Deferred section already lists as the alternative to reusing `Portable` (`PLAN.md:216`, Round 1 citation) — no legacy coupling, no `calendar_id` mismatch to resolve, at the cost of two new migrations and a from-scratch batch/item state machine (though the `Portable` family's own state-machine shape, Finding 25, is a proven reference to copy from even when not reused directly).

**For the `Statement`/resultado side, there is no reuse option** — Finding 24 establishes no remnant exists. Whichever of the three options above the engineer picks for the regra side, the resultado side is new-model territory regardless, which is itself a data point relevant to choosing among the three: picking Option 3 for consistency across both declaration kinds (rather than reusing old models for one kind and building fresh for the other) is a coherence argument the engineer may want to weigh, not a recommendation this spike is making.

(No recommendation — Round 5, like Rounds 1-4, surfaces what exists, when it was built, whether it is alive, and the concrete trade-offs of reusing it; main and the engineer decide.)
