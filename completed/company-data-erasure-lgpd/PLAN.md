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

## 9. Completion status — COMPLETE (2026-07-17)

**All fronts closed.** App/backend anonymization, integrator teardown, Zendesk (§9), and the e-mail
erasure (§8, executed 2026-07-17 — 319 deleted / 93 kept, manifests in S3, register row filled, DWD
revoked) are all done. The formal LGPD confirmation to the client was already sent at the backend stage
(recorded below, "we send nothing further"). Two runbook-improvement TODOs (the `meajuda` full-delete
named exception in §8; the §9 Step 4 vs §2 alignment) are spun off as a separate dot-claude follow-up —
they improve the shared runbook and are NOT part of this client's offboarding. This plan moves to
`completed/`.



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

**`elisio` box — DONE (cleared 2026-07-17).** The ex-employee's account was kept active on purpose for
a period after his departure because he held client-facing responsibilities, so that any mail a client
still sent to his address would be received rather than bounced. That reason has now lapsed: the account
was cleared on 2026-07-17, which erases the Aster PII it held via the §8 no-owner exception (ex-employee
→ account/inbox deletion). Nothing pending for this box. Record it in the manifest/register (Remaining
item 3) as "elísio → cleared via account deletion 2026-07-17, account previously kept active for
client-facing continuity."

**OK status (2026-06-11)** — 7 review e-mails were sent on 2026-06-08 (camila, danilo, emerson, ione,
patrick, paulo, sergio; **santiago was NOT sent** — the batch was 7, not 8):
- ✅ Paulo, Camila, Patrick, Ione, Emerson — approved.
- ⚠️ Sérgio — did **NOT** approve run-1. His reply (that his "Pendente" hits are billing/NFSe/financial,
  fiscal retention → keep) was the **correction that surfaced the classifier gap and triggered the whole
  run-2/3/4 rework**. This is a **rejection, not an OK** — there is no prior approval to carry forward.
  He must re-confirm the final rule-B list (see re-send scope).
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
not the prompt — so the question is "did the list change?", not "did the rule change?". V4's decision set is
**byte-identical to run-1 for 5 of 8 owner boxes** (camila, emerson, ione, santiago, sergio) — but an identical
list only carries a **prior OK** where run-1 was actually approved. Re-confirm where the list materially changed
OR where there was no genuine prior approval:
- **danilo** — never replied with an OK (the only originally-outstanding one) → full review.
- **patrick** (42→43 delete) — a **new deletion** (revisar→apagar) he never approved → re-confirm.
- **paulo** (65→64 delete) — one item devolved apagar→revisar; the deletion set is a **subset** of what he
  approved (no over-deletion risk), but that item now sits on his review awaiting his call → re-confirm.
- **sergio** — **re-confirm (was wrongly grouped as "no re-send")**. The V4 decision set is byte-identical to
  run-1 (52 delete / 57 keep, **0 item flips**), so the "did the list change?" test alone would wave him
  through — but the "prior OK" premise is **false for him**: his run-1 review was the **correction that broke
  run-1 and forced the rework**, not an approval, and **109/109 triage reasons were rebuilt** under rule B (his
  box swung 52→53→40→52 across the four runs). He is the reviewer most invested in this box and never approved
  a final list → full re-review of the V4 list. (Evidence: `~/offboarding-aster*/sergio@4shark.com.br/plan.json`.)
- **camila, emerson, ione, santiago** — list identical AND run-1 genuinely approved → **prior OK carries forward, no re-send**.
- **meajuda** (no-owner intake box) — **STANDING RULE: delete everything, no review, ever. Nothing to resolve
  here.** `meajuda` is not a person's mailbox — it is the intake address whose sole purpose is to receive tickets,
  and every message in it is mirrored to **Zendesk**, where the actual involved parties already received it and
  decide there (runbook §8). There is therefore no owner to consult and no per-item judgement to make: the whole
  box is deleted wholesale. Any classifier "revisar"/keep flip on a meajuda item (e.g. the V4 flip on "PSC",
  Áster's `Transacoes_Faturamento_pecas.xlsx`) is **overridden → delete** by this rule — meajuda is **full delete
  (30/0)**. This is a property of the box, not a per-run decision; it does not depend on any reply. (DPO-confirmed
  2026-06-12.) **TODO: this rule belongs in runbook §8 as an explicit named exception, not just a plan note —
  it keeps resurfacing as a false pendency.**

**V2 review sent — DONE (2026-07-10).** The 4 v2 reviews were sent to **danilo, patrick, paulo, sergio** (in-thread
replies on the original "Encerramento Aster (LGPD)" e-mails, each with its box's `review-v2.html` attached — the
run-4/rule-B list). Camila / emerson / ione / santiago carried forward their run-1 OK (lists identical AND genuinely
approved) → no re-send.

**V2 replies — status (2026-07-10):**
- ✅ **Danilo** — replied 12:59, "OK". Approved.
- ✅ **Patrick** — replied 12:44, "meu tem 0 para revisar, pode prosseguir apagando". Approved (his box has no "revisar" items).
- ✅ **Paulo (own box)** — replied 14:52, "nenhum dos dois e-mails devem ser apagados" (the 2 "revisar" items: "Fluxo de como criar planos e calendário" and "[4shark] Desenvolvimento de Controle de Dados na Base Normatizada"). Confirms **keep** on both — identical to what rule B already classified (keep=2), so the delete set is unchanged: box resolves at **64 delete / 2 keep**.
- ✅ **Sérgio — replied 21:56 on 2026-07-10, box now closed (updated 2026-07-17).** He took three hedged rounds earlier that day (13:16 / 14:59 — describes the "revisar" items and bounces the call back with a counter-question, never a clean verdict), then Paulo's 15:05 message reframed it to a yes/no: we only delete emails/attachments carrying personal sensitive data, the AI marks them and escalates doubts to the box owner, **the final OK is yours**, keep the "revisar" ones if you want. Sérgio's 21:56 reply, verbatim: *"Podemos manter os e-mails de solicitações de faturamento."* This is read as **consent-with-scope**, not a literal "ok": he exercised exactly the choice Paulo offered (named what to keep, raised no objection to the delete set), and he is the reviewer who proved he objects when he disagrees — his run-1 correction is what forced the whole rework. His reply does not literally name the 57th keep item (`[4shark] Desenvolvimento de Controle de Dados na Base Normatizada`, the integration/dev thread he flagged at 13:16), but rule B already classifies it **keep**, so both the generous and the strict reading produce the same result — it stays. No delete action depends on interpreting his sentence.

**Email erasure — EXECUTED 2026-07-17.** The `delete` ran across all 9 mailboxes (the 8 owner boxes +
`meajuda`; `elisio` was already cleared via account deletion). **319 e-mails permanently deleted, 93
kept** — the kept set is the NFSe/faturamento fiscal-retention documents. Per-box deleted counts:
`meajuda` 30, `camila` 71, `danilo` 16, `paulo` 64, `patrick` 43, `ione` 38, `emerson` 2, `santiago` 2,
`sergio` 53.

**Verification method — count reconciliation, not a pilot.** The seeded-test-mailbox pilot was dropped
as impractical (a client-domain e-mail cannot be forged to seed a fake box). Instead a fresh full-domain
`plan` (both client domains) was reconciled per-account against the run-4 approved counts: 5 boxes matched
exactly, 4 came in +1 (`camila`, `danilo`, `meajuda`, `sergio`). The extra item in each was pinpointed by a
message-id diff and confirmed legitimate Aster PII — three were keep→delete triage flips on 2022–2023 client
data (the triage is not deterministic run-to-run), and one was a new post-approval item on Sérgio's box: a
third-party invoice from **Locações Dolce Aroma to Áster Máquinas**, deleted on the DPO's LGPD call (Áster's
data, no 4Shark retention basis — a third party's nota fiscal is not 4Shark's fiscal record).

**Incident during the run (resolved).** The first `delete` (`meajuda`) removed all 30 e-mails and then
crashed writing the manifest, because `--out`'s directory did not exist — an irreversible deletion with no
record. The manifest was **reconstructed** from the reviewed `plan.json` after a follow-up `plan` confirmed 0
remaining (`/tmp/aster-manifests/meajuda.json`, `reconstructed: true`). Root cause fixed in **data-privacy
PR #29 (merged)**: the tool now creates the manifest directory BEFORE the delete loop, so an unwritable
`--out` aborts before any e-mail is deleted (fail-before-delete).

**Recordkeeping done.** The 9 manifests (proof of action) are in
`s3://4shark-backups/email-erasure/aster/2026-07-17/`. Local outputs deleted (§8 Step 5) and the
domain-wide-delegation grant revoked (§8 Step 6). **Authorizing request:** the formal LGPD erasure request
from **Rodrigo Seabra (Áster Agro), `rodrigo.seabra@asteragro.com.br`, 2026-05-04**, "Distrato" thread
(Gmail msg `19df36d440c129e0`) — asks for definitive elimination "de seus sistemas, bases de dados, backups
e quaisquer outros meios" and for the legal basis + retention term of anything kept (answered by the
NFSe fiscal-retention keep set).

**Sole remaining item — the register row (engineer's Google Sheet).** One row in the **"Registro de
Exclusões LGPD"**: cliente Áster; pedido 2026-05-04 (Rodrigo Seabra); execução 2026-07-17; 9 caixas +
`elisio` (via exclusão de conta); 319 apagados / 93 mantidos; S3 path above; owner-OK evidence = the
"Encerramento Aster (LGPD)" threads; Zendesk (§9) done.

**Classification basis — the `triage_reason` text is NOT authoritative; the delete decision is (engineer-confirmed 2026-07-17).** A groups / metas / indicadores / recebimentos export from the platform carries user rows — name, sometimes CPF — so those files ARE personal data and are correctly in the delete set. The classifier is incoherent in its *justification* on ~103 of the 346 delete items (across all boxes) it wrote `"sem dados pessoais"` while other items of the same file type are correctly labelled `"contém nomes e CPFs"`. The DECISION (delete) is right on all of them; only the classifier's stated reason on those ~103 is wrong, and that reason is a working-file artifact — it lives only in `plan.json` (deleted at §8 Step 5) and in the `review.html` already sent to owners. The durable record does NOT carry it: the manifest logs only id/subject/mailbox/timestamp/`authorized_by`/`request_ref` (§8 Step 3–4) and the register row is client/date/counts/paths/evidence (§8 Step 4) — neither stores a per-item reason. So there is nothing in the kept record to contradict; no register-text fix is needed. The 57 keep items in Sérgio's box stay clean under this same test: 56 are NFSe/faturamento (4Shark's own fiscal doc — PJ data: CNPJ/endereço/valores, no natural-person data) and 1 is the internal dev thread.

Once the register row is added, this plan moves to `completed` — the integrator (base + backup deleted),
Zendesk (§9), backend/anonymization, and now the email erasure are all closed.

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
