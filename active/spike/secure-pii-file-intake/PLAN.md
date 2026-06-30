# PLAN — Email attachment stripping at LGPD offboarding (Aster Máquinas pilot)

Derived from `SPIKE.md` (same folder). Implements the locked requirement: **never delete an email —
remove only the attachment, keeping the original text.** Runs **on-demand at client cancellation**,
scoped to the cancelling client's domain. Aster Máquinas is the pilot.

## What it does (the accepted mechanism)

For each 4Shark mailbox, find every message with an attachment to/from the client's domain and
**rebuild each message without the attachment** (re-import the original headers + body, drop the
attachment, remove the original). The email text/correspondence stays; only the attachment leaves.
Accepted caveat: it is a reconstructed message, not the byte-identical original — the **original
text remains**, which is the requirement.

Not GAM (GAM deletes whole messages). Not Gmail-native (messages are immutable). Custom Gmail-API
script with domain-wide delegation, run on the 4Shark Workspace by a super-admin.

## Execution phases (Script Discipline: discovery → mutation → verification)

### Phase 0 — Prerequisites (one-time — persistent infra, the only thing we keep)
- **Terraform (`terraform` repo) — GCP side, all IaC:** the GCP project, enable the Gmail API
  (`google_project_service` for `gmail.googleapis.com`), the `google_service_account`, and its key.
- **Manual (Admin console, super-admin — the ONE non-Terraform step):** authorize the service
  account's client ID for domain-wide delegation with scope `https://www.googleapis.com/auth/gmail.modify`
  at Security → Access and data control → API controls → Manage Domain-Wide Delegation. This grant
  is not a GCP resource and is not Terraform-able; it is a one-time admin click.
- Confirm the Workspace edition allows Gmail API access (all paid tiers do).

### The "application" — there is no off-the-shelf product
There is **no ready-made open-source domain-wide attachment stripper**. The open-source examples
(per-account/IMAP tools, Unattach) do not do domain-wide service-account stripping. So the tool is a
**small custom script we write** (Python + Gmail API; impersonate each user via the delegated service
account; strip by query; rebuild MIME without the attachment), ~100–200 lines, using the open-source
gists only as reference for the MIME-rebuild. It is our code, in a 4Shark repo (open decision below).
It is run **on-demand** at cancellation — not a standing service.

### Phase 1 — Backup (mandatory, before any mutation)
- Google Takeout export (Mail, MBOX) of every mailbox in scope — the rollback if anything goes wrong.

### Phase 2 — Discovery (read-only) — "find all emails with attachments"
- Per mailbox, search `(from:CLIENTDOMAIN OR to:CLIENTDOMAIN) has:attachment`.
  For Aster: `from:asteragro.com.br OR to:asteragro.com.br OR from:astermaquinas.com.br OR to:astermaquinas.com.br`, `has:attachment`.
- Output the full list (mailbox, message-id, subject, date, attachment names/sizes). **No mutation.**
- Engineer reviews the list before anything is touched.

### Phase 3 — Pilot test (on a throwaway / seeded mailbox — NOT production)
- Seed a test mailbox with a copy of a few real Aster emails (with attachments).
- Run the strip on the test mailbox only.
- **Verify:** message still present; From / Date / Subject / body / thread intact; attachment gone;
  nothing outside scope touched. The script logs every action (auditable — proves it only stripped).
- Only when the test passes do we touch production.

### Phase 4 — Mutation (per message, logged, continue-on-error)
- For each message from Phase 2: download raw MIME → rebuild MIME **without** the attachment parts
  (keep all headers + body) → `users.messages.import` (preserves From/Date/labels/thread) → delete
  the original. Log each: `mailbox / message-id / ok|FAIL`.

### Phase 5 — Verification
- Re-run the Phase 2 query: **0 messages with attachment** remain for the client domain.
- Spot-check a sample: email present, text intact, attachment gone.
- Trash emptied where the original landed (so the attachment does not linger 30 days in Trash).

## Deliverables
1. The strip script (auditable, logged) — repo TBD (likely `lambda` or a small ops repo).
2. A step in `LGPD-DATA-ERASURE.md` (PR in `dot-claude`): "On cancellation, strip attachments from
   the client domain's emails across all mailboxes, keeping the emails."
3. Pilot run record for Aster (consolidated report per Script Discipline).

## Repository / packaging — the community pattern (adopt, don't invent)
For tooling where **infra and code are tightly coupled**, the community pattern is a **dedicated,
self-contained stack (monorepo style)**: one repo/stack holding **both the Terraform and the script**,
versioned and deployed as a single unit ("a stack is the smallest independently deployable, self-
contained unit, with its own lifecycle"). Concretely:
- The script runs as a **Cloud Run job** (on-demand — not a standing service; matches "run at
  cancellation"), with the service account as the job's identity and the SA key in **Secret Manager**.
- Terraform provisions: GCP project + Gmail API + service account + the Cloud Run job (script image)
  + Secret Manager. Run with `gcloud run jobs execute`.
- This matches 4Shark's existing self-contained-stack convention (e.g. `integrator-X`).
- **Pilot shortcut:** for Aster's pilot validation (Phase 3), the script can be run locally once; the
  Cloud Run job stack is the home when this is standardized into the offboarding runbook.

## Location — DECIDED
Self-contained stack folder **inside the `terraform` repo** (e.g. `terraform/client-offboarding/`),
alongside the other stacks (`integrator-X`).

**Reality flag — this is the FIRST GCP stack in an all-AWS Terraform repo.** Every existing stack
uses the `aws` provider; this introduces the `google` provider + Artifact Registry + Cloud Run +
Secret Manager. That is real new surface for an AWS shop — worth a conscious "yes" before building,
and the stack should follow the existing per-stack layout (providers.tf, main.tf, stack.tm.hcl) so
it reads like its AWS siblings.

**Sequencing — pilot validates BEFORE the stack is built.** The critical risk is "does the strip
work safely (email kept, only attachment gone)". Validate that with the script run **locally once**
on a test mailbox (Phase 3) **before** investing in the full Cloud Run stack. Build the stack only
after the pilot proves the approach. Don't build GCP infra to answer a question a local run answers.

## Open decisions
- Whether to keep a copy of the stripped attachment in a controlled store before dropping it, or
  drop outright (for Aster offboarding: drop outright — the data is being erased).

## Hard guarantees (only after Phase 3 passes)
- Email is never deleted as correspondence — the text always remains.
- Only the attachment is removed.
- Backup exists (Phase 1) as rollback.
- The script's log is the audit trail proving it only stripped attachments.
