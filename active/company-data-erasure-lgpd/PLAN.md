# PLAN — Company Data Erasure (LGPD right-to-erasure)

> Trigger: Aster Máquinas (Aster Agro) contract distrato + formal LGPD erasure request
> (e-mail Rodrigo Seabra, 2026-05-04). Goal: erase / anonymize all personal data of a
> company **completely and irreversibly**, so a formal "data eliminated/anonymized"
> statement to the client is factually true — and make the procedure repeatable for the
> next offboarding.

## 1. Problem

The existing per-user anonymizer (`User::Anonymizer::Consumer`) only overwrites the
`users` row and destroys `user_identifiers`. It leaves personal data (name, e-mail, CPF,
registration identifiers) in **plaintext** in audit/action tables and in the **Excel/CSV
files stored in S3**. Answering a client "everything was anonymized" after running only the
anonymizer would be false.

This recurs on every client offboarding, so it must become a repeatable feature + a runbook,
not a one-off console session.

## 2. PII footprint (evidence)

What the per-user anonymizer **already handles** (irreversible — overwrites with a constant,
no reverse map; destroys identifiers):

```ruby
# app/app/workers/user/anonymizer/consumer.rb:12
user.anonymized = true
user.email = "#{REDACTED_VALUE}@#{REDACTED_VALUE}.com"
user.unique_register_id = REDACTED_VALUE   # CPF
user.first_name = REDACTED_VALUE
user.last_name  = REDACTED_VALUE
user.save!
user.identifiers.update_all(primary: false)
user.identifiers.destroy_all
```

What it does **NOT** touch (the gap this plan closes):

| # | Location | Personal data held | Encrypted? | Cleanup |
|---|---|---|---|---|
| 1 | `user_audit_rows` (`db/schema.rb:2052`) | `user_name`, `user_email`, `user_unique_register_id` (CPF), `user_primary_identifier_value`, `user_parent_name`, `senior_manager_name` | No | Destroy parent `UserAudit` (cascades rows via `has_many :rows, dependent: :destroy` — `app/models/user_audit.rb:4`) |
| 2 | `user_identifier_actions` (`db/schema.rb:2161`) | `user_identifier_value`, `new_user_identifier_value` (matrícula) | No | Delete rows for company **before** their document (parent uses `dependent: :restrict_with_exception` — `app/models/user_identifier_action_document.rb:4`) |
| 3 | `Document` rows (`UserDocument`, `UserIdentifierActionDocument`) | the attached **Excel/CSV** in S3 + `filename` metadata | file is plaintext spreadsheet | Remove the attachment (deletes S3 object), do NOT destroy the Document (see Risk R1) |
| 4 | S3 (`aws_bucket`, `uploads/document/#{id}...` — `app/models/document.rb:91`) | the spreadsheets themselves (everyone's name/CPF/e-mail) | No | CarrierWave `attachment.destroy` removes the object (`app/models/document_attachment.rb:4` → `mount_uploader :file, DocumentUploader`) |

Confirmed NOT a concern: `user_histories` (`db/schema.rb:2148`) stores only status/`from`/`owner` — no PII. Razão social ("Aster Máquinas") is a PJ name, not personal data under LGPD.

## 3. Risks / pitfalls (these become the runbook's "pegadinhas")

- **R1 — `UserDocument has_many :users, dependent: :destroy`** (`app/models/user_document.rb:4`).
  Destroying a user import document **destroys the users created from it** — exactly the
  anonymized users we must keep (commissions, history, referential integrity). ⇒ Never destroy
  user documents. Remove only the attachment (S3 file) and flag the document.
- **R2 — `Company::UserAnonymizer#perform` is NOT company-scoped** (`app/workers/company/user_anonymizer.rb:9`).
  It processes every disabled company in the window. ⇒ Never call it to target a single client;
  iterate the company's users and call `User::Anonymizer::Consumer` per user.
- **R3 — No `removed`/erasure status on `Document`** (`app/models/document.rb:50` — enum is
  `initial/processing/erasing/final/failed`; only route is `failed → erasing`). ⇒ Either truly
  delete the file (operational), or add a proper status (feature).
- **R4 — `restrict_with_exception`** on `UserIdentifierActionDocument#actions`. ⇒ Delete actions
  before any attempt to remove that document.
- **R5 — Audit/action tables are transient but bug-prone** (per engineer). ⇒ Only clean when
  nothing is processing for the company; check in-flight audits/documents first.
- **R6 (LGPD) — Anonymization ≠ deletion.** Defensible under LGPD art. 12 (anonymized data
  leaves the law's scope) only if **irreversible**. Must be communicated transparently, not as
  "we deleted everything" when we anonymized.
- **R7 (LGPD) — The right is statutory, not contractual.** Do not argue "not in the contract".
  LGPD arts. 15/16/18 grant it regardless. Fiscal/financial data has a legal retention basis —
  inform base legal + prazo instead of deleting blindly.

## 4. Technical decisions

- **Sync, not async.** Run `User::Anonymizer::Consumer.new.perform(id)` synchronously in the
  operational script — the client's Sidekiq may be scaled to zero during offboarding, and sync
  gives immediate verification.
- **Target by `company_id`**, never the batch worker (R2).
- **Documents: erase attachment, keep row** (R1). Feature formalizes via a new `removed` status.
- **ActiveRecord-first** (no raw SQL — these tables have callbacks/dependents). Pluck IDs,
  iterate per record (Data Processing Pattern).

## 5. Execution phases

### Phase 0 — Discovery (read-only, distrust the premise)
Confirm the real footprint for the company before mutating. Count, per company:
non-anonymized users; `UserAudit` rows; `UserIdentifierAction` rows; `UserDocument` and
`UserIdentifierActionDocument` with attachments; in-flight (pending) documents/audits.
Agree the buckets with the engineer. No mutation until this is confirmed.

### Phase 1 — Aster operational erasure (console, Script Discipline)
Per bucket, three scripts (pre-flight → mutation → verification), variables not constants,
log each iteration, continue past per-record errors. Order:
1. **Pre-flight** — confirm nothing processing; confirm counts match Phase 0.
2. **Anonymize users** — iterate non-anonymized users → `User::Anonymizer::Consumer` (sync).
3. **Clean audits** — destroy `UserAudit` for the company (cascades rows).
4. **Delete identifier actions** — `UserIdentifierAction` for the company (before docs, R4).
5. **Erase document files** — for `UserDocument` + `UserIdentifierActionDocument` of the
   company: `document.attachment&.destroy` (removes S3 object); mark the document (status).
   Do NOT destroy the document rows (R1).
6. **Verification** — re-query 1–5: zero non-anonymized users, zero audit/action PII rows,
   zero attachments, S3 objects gone.
7. **Consolidated report** (`~/Downloads/*.xlsx`) — per-bucket counts targeted/preflight/
   mutated/verified/unresolved.

### Phase 2 — Reusable feature in `app`
A company-scoped erasure flow so the next offboarding is a button/rake, not a console session:
- Add `removed` status + transition to `Document` state machine (R3), erasing the attachment
  without destroying the row (R1).
- A company-erasure entry point (worker/service) that runs the Phase 1 steps safely and
  idempotently, scoped to one `company_id`, skipping user destruction.
- Tests per `~/.claude/docs/TESTING-PHILOSOPHY.md` (anonymization irreversibility, document
  attachment removal, user non-destruction invariant).
- **Pattern Priming required before writing any code** (sibling workers/models) — ASK before coding.

### Phase 3 — Runbook (final deliverable)
`RUNBOOK.md` for "client requests data deletion / LGPD erasure". Must contain:
- **Process**: distrato/offboarding steps; teardown order (VPN, integrator, base, backups);
  run the erasure feature; verify; produce the client confirmation.
- **Pegadinhas**: R1–R5 above (the destroy-cascade, the non-scoped batch worker, the missing
  status, restrict_with_exception, transient tables).
- **What to tell the client** (LGPD): anonymization art. 12 (irreversible) vs deletion;
  operational data + backups deleted; fiscal retention with base legal + prazo; razão social
  is PJ data; the right is statutory not contractual (R6/R7). Response is formal, reviewed
  before sending.
- **Verification checklist** that proves "no residual PII" before any statement goes out.

## 6. Out of scope (for now)
- Integrator (Mongoid) side erasure — already torn down for Aster (base + backup deleted).
  The feature may later extend there; not part of this plan.
- Automatic periodic cleanup of transient audit/document tables (separate maintenance task).

## 7. Open questions for the engineer
- Phase 2 status name: `removed` vs reuse `erasing`? (state-machine design decision — ASK.)
- Should the erasure feature also hard-delete `Document` rows for non-user types, or only
  user-PII documents?
- Runbook home: `app/docs/RUNBOOK-*.md` (repo) or team-wide location? → **Resolved: dot-claude**
  (`docs/runbooks/compliance/LGPD-DATA-ERASURE.md`, team-wide).

## 8. Progress — what was done, how (updated 2026-06-03)

The Aster offboarding split into three tracked workstreams; this plan is the **app/backend** one.

**Trigger / approach** (spike `lgpd-erasure-trigger`). The "auto-anonymize 30 days after
cancellation" default was challenged and changed: keep the `Company::Anonymizer` workers, **re-tune
the window from 30 days to ~5.5 years** (`USER_ANONYMIZING_WINDOW` = 2008 days; the old
`COMPANY_ANONYMIZING_WINDOW` is gone), and treat early erasure as a deliberate, on-request manual
run. Source: `lgpd-erasure-trigger/SPIKE.md`; reflected in `LGPD-DATA-ERASURE.md` §1.

**Phase 0 — Discovery.** Footprint confirmed (users, audit rows, identifier actions, documents +
S3). Captured in §2 here and in the runbook §2.

**Phase 1 — Aster operational erasure.** **Done** (engineer-confirmed 2026-06-03). Aster's **897
users were anonymized**; **documents and identifier actions erased**. Nothing left to clean on the
app/backend — only email remains. PRs **#5101 / #5102** extended the auto-anonymization to documents
(S3 attachment removed) and identifier actions (`lgpd-erasure-trigger/SPIKE.md`).

**Phase 2 — Reusable feature.** The company-scoped mechanism is live: `Company::Anonymizer`
orchestrator → user / document / action anonymizers (runbook §1); the document-attachment removal
keeps the row (R1) as planned. Effectively delivered via #5101 / #5102.

**Phase 3 — Runbook.** Done — landed as **`dot-claude` `docs/runbooks/compliance/LGPD-DATA-ERASURE.md`**
(team-wide, not `app/docs`). PR **#219** merged. Carries the footprint, pitfalls R1–R6, verification
checklist, client templates, and **§7 — email attachment erasure**.

**Adjacent workstream — email erasure.** The client's PII-attachment e-mails are erased by the
**`email-erasure`** tool (restricted **`4shark/data-privacy`** repo), whose access is provisioned by the
**`workspace-access`** Terraform stack (GCP project `fourshark-workspace-access`). Design: `plan` triages
every client e-mail with an attachment via **Claude (Opus)** (`delete` vs `keep` + reason) and writes a
per-account `review.html`; `delete` **permanently** removes the `delete`-marked ones and writes a
content-free manifest. Auth is **keyless** (the operator's own Google identity impersonates the SA via
`tokenCreator`) with **just-in-time domain-wide delegation** (granted per run, revoked after). Full
procedure: runbook **§8**. Validated on `paulo@4shark.com.br`. **Aster `plan` already run** (the prior
tool, ~$20 Claude triage) — the output was saved to the engineer's home; no new e-mails since, so it is
**reused rather than re-run**.

> History: the email tool first shipped as **strip-and-keep** (#477), then was **redesigned to delete
> outright** (#479) — strip-and-keep needs a chain-of-custody backup only **Google Vault** gives, and
> Vault is not in 4Shark's Workspace plan. Later renamed (`client-offboarding` → `workspace-access` infra
> + `email-erasure` tool) and moved to keyless + JIT-DWD (plans `email-erasure-rename`,
> `email-erasure-hardening`).

## 9. Remaining (why this is not yet `completed`)

App/backend ✅ (§8, Phase 1) — formal LGPD response already sent (we send nothing further). Integrator
✅ (base + backup deleted on cancellation). `ANTHROPIC_API_KEY` configured. The Aster `plan`/triage
already ran (output in `~/offboarding-aster` — reused, not re-run).

**Zendesk (runbook §9): DONE (2026-06-05).** ~75 tickets (tag `aster_maquinas`) deleted by hand;
archived (>120 days), so the delete is effectively **permanent** (no recoverable queue, no API to
recover). Search by tag and by requester for **both** client domains (`*@asteragro.com.br`,
`*@astermaquinas.com.br`) returns zero. The **ticket content** (messages + spreadsheet attachments) is
the PII that was erased. The **end-user contacts (name + e-mail) were NOT erased** — an e-mail address
is not sensitive data and, by proportionality (LGPD art. 16; runbook §2 — we do not chase the scattered
e-mail address), removing the content is what the erasure requires. (Runbook §9 Step 4 "Forget user"
over-reaches vs §2 — flagged to align.) Two gotchas documented in the runbook (#237 archived ticket
skips the trash; search tab count lags the index).

**Email — the only open trail.** Per-account owner-review e-mails, each carrying that account's
`review.html` (santiago → `review-es.html`). `elisio` (ex-employee → account deletion) and `meajuda`
(Zendesk intake box) get **no review e-mail** — deleted directly per the runbook §8 no-owner exception
(#238).

**OK status (2026-06-11)** — 7 review e-mails were sent on 2026-06-08 (camila, danilo, emerson, ione,
patrick, paulo, sergio; **santiago was NOT sent** — the batch was 7, not 8):
- ✅ Paulo, Camila, Patrick, Ione, Emerson — approved.
- ✅ Sérgio — responded: his "Pendente" hits are billing/NFSe/financial (fiscal retention) → keep. This
  review surfaced the classifier gap below.
- ✅ **Santiago [ES]** — trained 1:1 in ES on 2026-06-11; `review-es.html` sent that day and **approved**.
- ⏳ **Danilo — no reply yet: the ONLY outstanding OK in the e-mail flow.**

**Classifier hardening — settled on RULE B (`data-privacy` PR #15, MERGED 2026-06-11), after two earlier
iterations.** The triage originally decided on subject+body only and never opened the attachment,
mis-classifying by **filename**. It went through three rule versions:
- **(#11) party-based** — keep only where 4Shark is a party; brittle, forced a hardcoded **CNPJ allowlist**.
- **(v3) personal-data + retention** — correct on the law but **too conservative**: escalated the client's
  own non-personal config (groups, indicators, CNPJ card) to owners instead of deleting it.
- **(#15) RULE B (final)** — one test: *does 4Shark have a reason or duty to **KEEP** this?* (1) a natural
  person's **personal data** → **delete** (the target); (2) non-personal data 4Shark needs/must retain
  (nota fiscal / comprovante fiscal ~5yr, a contract 4Shark is party to, our own record) → **keep**; (3) the
  client's own non-personal data **useless to us** (groups, indicators, CNPJ card, config) → **delete** in
  good faith; (4) **unsure** → **keep** (escalate to owner). This **dissolved the CNPJ allowlist** — the
  model recognizes 4Shark's billing entities (4T Soluções etc.) from context, no list needed. PR #15 also
  added **Anthropic prompt caching** (system + first user message `cache_control: ephemeral`) to cut Opus
  cost. Mechanics unchanged: filenames fed to triage; `inspect_attachment` opens the file (PDF via pypdf /
  zip listing / spreadsheet via openpyxl); review.html **"Seguro para apagar" / "Revisar"** + "Nada é apagado
  sem o seu OK". Research basis: spike `lgpd-email-erasure-classification/SPIKE.md`.

**Content-validation of the flagged delete items (2026-06-11, opened the actual files):**
`Acordo PPR 2022.pdf` = Áster's **collective PPR agreement with SINDRECAUTO**; `Acordo PPR 2023.pdf` /
`01 - TERMO ADITIVO - TANGARA.pdf` = Áster's **PPR indicators/rules**; `Fatura_Prev/Real_*.csv` = Áster
**commission data with CPF + customer names**. All **client-internal → DELETE (correct)**. 4Shark's NFSe
invoices to Áster → **KEEP** (fiscal). The old per-account plans already mark these the same way, so they
**align with the corrected rule** on the audited items. (Earlier alarm that these were "legal docs to
keep" was the filename trap — opening the files resolved it.)

**V4 run (rule B + caching) — DONE & validated (2026-06-12).** Re-ran `plan` on a fresh out-dir with DWD
granted just-in-time; output preserved at `~/offboarding-aster-run4-ruleB`. **Cost $27.91** (Anthropic
balance $130.45 → $102.54) — prompt caching made the full ~442-thread Opus run cheaper than the uncached
v3. Totals **DELETE 346 / KEEP 96** (run-1 was 348/94; the over-conservative v3 was 283/159). Key items
validated by **opening file content**: client CNPJ card → delete; 4Shark's own CNPJ / 4T bank docs / NFSe
(81) → keep (recognized from context, **no allowlist**); client groups/variables/indicators → delete;
client PPR / TERMO ADITIVO collective agreements → delete; 4Shark POC `SCRIPTS ASTER.zip` → keep. Rule B
confirmed working. **DWD revoked after the run.**

**Re-send scope — decided by diffing V4 against the run-1 owners already approved (NOT "all owners").** The
owner review is an **internal risk control**, not an LGPD requirement; the legal duty is to execute the
erasure and keep the record (accountability, art. 6º X). Owners approve **the message list in their box**,
not the prompt — so the question is "did the list change?", not "did the rule change?". V4's list is
**byte-identical to the approved run-1 for 5 of 8 owner boxes**. Re-confirm only where it materially changed:
- **danilo** — never replied with an OK (the only outstanding one) → full review.
- **patrick** (42→43 delete) — a **new deletion** (revisar→apagar) he never approved → re-confirm.
- **paulo** (65→64 delete) — one item devolved apagar→revisar; the deletion set is a **subset** of what he
  approved (no over-deletion risk), but that item now sits on his review awaiting his call → re-confirm.
- **camila, emerson, ione, santiago, sergio** — list identical → **prior OK carries forward, no re-send**.
- **meajuda** (no-owner intake box) — **always full-delete, no per-item review**: everything in this box was
  mirrored to **Zendesk**, where the actual involved parties already received it and decide there (runbook
  §8). So the V4 "revisar" flip on the 1 item ("PSC", Áster's `Transacoes_Faturamento_pecas.xlsx`) is
  **overridden → delete** — meajuda stays **30/0 full delete**. (DPO-confirmed 2026-06-12.)

Remaining (PR #15 merged; the email `delete` has NOT run):
1. **Send v2 review to danilo, patrick, paulo** (review.html in `~/offboarding-aster-run4-ruleB/<box>/`);
   carry forward the other owners' OK. Santiago [ES] identical → no re-send.
2. **Collect the 3 OKs** + resolve meajuda's 1 item (DPO).
3. **Grant DWD just-in-time**, then **delete** per account after each owner confirms (+ `elisio` + `meajuda`
   directly, no-owner exception). Pilot on a seeded test mailbox before any real delete.
4. **Recordkeeping** — manifests → `s3://4shark-backups/email-erasure/aster/<date>/` + one row in the
   "Registro de Exclusões LGPD" register (note which boxes were direct-deleted and why).
5. **Delete the local outputs** (`~/offboarding-aster*`) (runbook §8 Step 5).
6. **Revoke DWD** (runbook §8 Step 6).

Once these are done, this plan moves to `completed`.

**Runbook gaps surfaced this session are all closed:** keyless/JIT-DWD + post-rename names (#234),
local-output cleanup step (#235), training register (#236), archived-ticket note (#237), no-owner
mailbox exception (#238).

The earlier productionization items (S3 backup, Glacier lifecycle, Object Lock, review-HTML timing)
are **obsolete** — the delete+triage design has no backup and no copy-review.

## 10. LGPD awareness training — DONE (PT turma 2026-06-08, ES Santiago 2026-06-11)

**PT group (2026-06-08).** Delivered in the alignment meeting on 2026-06-08 (topic "Conscientização LGPD
— processo de eliminação de dados"). Attendees (7): Danilo Assis, Sérgio Ajimura, Patrick Mares, Ione
Ruguzina, Camila Bergamasco, Emerson Silva, Leandro Almeida. Conducted by Paulo Ribeiro (DPO). Recorded
as a row in the **"Registro de Treinamentos LGPD"** sheet
(https://docs.google.com/spreadsheets/d/1zoJGcsZWfPbSPJ1ZTBbKT6Hm__4SrUjr1SXvB32fX7o) — the LGPD art. 41
(§2º, III) / art. 50 governance evidence (rule in runbook §8). The deck used was saved to **Compliance › Decks**
(`LGPD - Conscientização - Eliminação de Dados - pt-br - 2026-06-11.html`, renamed with the pt-br suffix).
Material link (view form — HTML has no Drive preview):
https://drive.google.com/file/d/1F1Xqn-uTXg_IMMM0zdK7MHWYGfz4DZaA/view

**ES (Santiago, 2026-06-11).** Santiago Velásquez (Spanish-speaking) was not in the PT group; he got a
1:1 session in Spanish on 2026-06-11, conducted by Paulo Ribeiro (DPO), using the translated deck
`LGPD - Concientización - Eliminación de Datos - es - 2026-06-11.html` (Compliance › Decks, alongside the
PT version). Material link: https://drive.google.com/file/d/1DAUyEnp-78R5x_twYZ9nFxWskmlUsltE/view —
recorded as its own row in the "Registro de Treinamentos LGPD" sheet. Training evidence is complete for
all staff with Aster mailbox hits.
