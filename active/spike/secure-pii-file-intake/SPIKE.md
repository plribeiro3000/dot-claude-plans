# SPIKE — Sensitive client files by email under the LGPD (startup-pragmatic)

**Question.** Email is the practical channel for receiving client spreadsheets with personal data,
and it will not go away (the realistic alternative is WhatsApp — worse for retention and audit).
Email attachments cannot be selectively purged (`LGPD-DATA-ERASURE.md` R6). So: **what does the law
actually require here, and what do companies at our size (startup, not enterprise) actually do** —
not what a giant with a privacy team does?

**Date.** 2026-06-02 · **Status.** Research complete; decision is the team's.

---

## Why the obvious fixes do NOT apply to 4Shark

(constraints from the team — these rule out the "platform upload" recommendation in the prior draft)

- **Files arrive raw, not import-ready.** During onboarding the client sends sample spreadsheets and
  rule examples; the team **studies them and encodes the rules** into the system. It is a
  collaborative analysis loop, not a clean upload — so "upload it in the platform" does not fit.
- **The senders are non-technical.** SFTP/FTP is too much friction for the client-side people who
  send these files. Force a harder process and they fall back to WhatsApp.
- **Email is the most practical channel and ties into the support thread.** Removing it makes the
  client experience worse, not better.

So the question is not "replace email" — it is "**how do we stay defensible while email remains the
channel**".

---

## The legal reality — the law does not require the impossible

The right to erasure is real (LGPD arts. 15/16/18; GDPR art. 17), **but both laws bake in
proportionality and reasonableness**:

- LGPD's principles include **necessity** and **adequacy/proportionality**, and anonymization is
  defined as using *"reasonable and available technical means"*
  ([Opice Blum](https://opiceblumacademy.com.br/proporcionalidade-razoabilidade-tratamento-dados-pessoais-lgpd/)).
  Art. 16 itself bounds elimination to *"no âmbito e nos limites técnicos das atividades"*.
- GDPR's erasure duty is explicitly a **reasonableness** test — controllers are **not required to
  undertake measures that are technically or economically disproportionate** — *but* they are
  expected to have a **documented process** for handling erasure, including backups/archives
  ([ICO](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/individual-rights/individual-rights/right-to-erasure/),
  [GDPR art. 17](https://gdpr-info.eu/art-17-gdpr/)). "Delete from the live DB but not the backup"
  is a known **grey area** the regulator accepts **when there is a process**.

**The consequence for email.** Gmail cannot remove an attachment while keeping the message (R6).
Selective purging is therefore **outside the technical limits** of the activity — the law does not
demand it. **What closes the gap is not deletion — it is a documented retention/handling process.**
The deliverable that makes 4Shark compliant is a *policy*, not a mailbox sweep.

---

## Enterprise vs. startup — two different playbooks

| Control | Enterprise (Tempo-scale) | Startup-grade (us) |
|---|---|---|
| Outbound/inbound PII in email | **DLP** (Microsoft Purview, Proofpoint) blocks/quarantines | Awareness + minimize; DLP optional later |
| File intake channel | Secure portal / MFT (GoAnywhere, Moxo, SmartVault) | Email kept; lightweight expiring-link offered for big cases |
| Email retention/purge | **Vault**/eDiscovery retention rules, legal hold | Retention/auto-expiry policy (Vault **or** a scheduled GAM/Apps Script job) |
| Governance | Dedicated DPO + privacy team | **One written data-handling + retention policy**, reviewed annually |

The enterprise stack assumes headcount and budget 4Shark does not have. The startup answer is **not
a tool — it is a documented policy** plus data minimization. Sources converge on this exact shape
([Secure Privacy — data minimization & retention](https://secureprivacy.ai/blog/data-minimization-retention-policies),
[Material Security — email retention](https://material.security/workspace-resources/mastering-email-retention-policy-to-protect-sensitive-data),
[FTC — protecting personal information](https://www.ftc.gov/business-guidance/resources/protecting-personal-information-guide-business)).

## What startups our size actually do (the pragmatic set)

1. **A written retention + data-handling policy.** The single most important artifact. States: what
   client data we receive by email, how long it is kept, that it auto-expires, and that selective
   attachment removal is technically infeasible so retention is the control. When questioned, you
   point to the policy — that *is* the "documented process" the law expects.
2. **Email retention / auto-expiry.** Purge client-data email older than N (e.g. 12–24 months).
   Mechanism: Google Vault retention rule (paid add-on) **or** a free scheduled GAM/Apps Script that
   deletes mail older than N matching a label/query. (Which one = open question — Vault is the
   rejected "expensive" path; the script is the free startup path.)
3. **Data minimization.** Don't keep what you don't need. Once the rules are encoded in the system,
   the source email/attachment has no further purpose — let the retention policy age it out. "Data
   no longer needed shifts from asset to liability."
4. **A label/category for client-data email** so the retention rule targets it precisely instead of
   one-size-fits-all.
5. **Employee awareness** — a short norm: client data files are received, used to configure, and
   then left to the retention policy; never forwarded out, never re-sent.
6. **(Optional, not mandated) a lightweight expiring-upload link** offered for the heaviest/most
   sensitive files — a pre-signed S3 URL into a lifecycle bucket. Use it as a *nudge*, not a
   requirement, so it never becomes the WhatsApp-pushing friction.

This is **enterprise-grade intent at startup cost**: the legal posture (documented process +
retention + minimization) without the DLP/MFT/Vault/privacy-team spend.

---

## The resolution that keeps the client's email UX intact — the intake mailbox

The hollow answer is "don't send PII by email" (then the file goes *where*? — the client will not
adopt FTP or a portal). The real pattern that companies use **keeps email as the client interface
but changes the destination**:

- The client emails the spreadsheet **to a dedicated address** (e.g. `dados@4shark.com.br`) — same
  act as emailing a person, zero new tool, zero training, zero trust friction (it is still a
  `@4shark` address).
- Behind that address there is **no human inbox**. An automated pipe **extracts the attachment into
  a lifecycle-managed S3 bucket** (auto-expiry + audit log) and the intake mailbox is purged —
  nothing of value is lost there because it was never a person's inbox.
- The team works the file **from the bucket**. Routine correspondence (questions, corrections)
  stays in normal email **without data attachments** → the discussion is preserved for legal
  defense, with no PII.

This resolves all three pressures at once: **client experience unchanged**, **PII never accumulates
in employee mailboxes** (kills R6 at the source), and the data is **born inside a controlled,
erasable, lifecycle-managed store**. It also realizes the "separate the attachment from the
correspondence" idea automatically, without asking the client to do anything.

**How to stand it up:**
- **Build (fits 4Shark — already on AWS with a Lambda repo):** SES inbound receipt rule → S3, a
  Lambda extracts the attachment into a lifecycle bucket. Serverless, ~zero ongoing cost
  ([SES → S3](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-action-s3.html),
  [Lambda attachment extraction](https://aws.amazon.com/blogs/publicsector/automatically-extracting-email-attachment-data-local-public-health-departments/)).
- **Buy:** a managed intake-mailbox service (e.g. Couchdrop) gives a ready address that auto-files
  attachments to storage ([Couchdrop Mailboxes](https://www.couchdrop.io/mailboxes)) — near-zero
  build, recurring cost, one more processor to contract.

**Not the answer: encrypted-email gateways (Paubox/Virtru).** They secure email *in transit* with
little/no sender friction, but the attachment still lands in the human inbox — they do not solve the
retention/erasure problem that triggered this spike
([Paubox vs Virtru](https://www.virtru.com/blog/email-encryption/software/virtru-vs-paubox)).

This is the **go-forward channel** the policy should name — not a hollow "no email" prohibition.

## CHOSEN DIRECTION — on-demand attachment strip at cancellation (simplest)

No standing infrastructure. The email-attachment cleanup becomes **a step in the LGPD offboarding
runbook**: when a client cancels, strip attachments from the emails of that client's domain,
**keeping the emails**. Nothing runs for active clients; nothing runs continuously.

- **Scope query (both directions):** `(from:CLIENTDOMAIN OR to:CLIENTDOMAIN) has:attachment` — also
  catches spreadsheets 4Shark sent back to the client for correction.
- **Tool A — Unattach (per mailbox):** browser app, OAuth to one Gmail account, processes locally
  (no data to their servers), removes the attachment by query **keeping the email**, leaves a
  changelog link. Install: nothing (web app + login). Cost: free tier / annual / pay-as-you-go.
  Limit: per mailbox — run on each employee mailbox that corresponded with the client. Fine for a
  small team. (<https://unattach.com/pricing>)
- **Tool B — Gmail-API strip script (domain-wide):** a small script with super-admin domain-wide
  delegation iterates users, finds `from:CLIENTDOMAIN has:attachment`, strips via
  `users.messages.import` (re-import the message **without** the attachment) + removes the original.
  Cost: $0 (dev only); squarely in 4Shark's skill set. It is "GAM but strips the attachment instead
  of deleting the whole message" (GAM only deletes whole messages). (<https://gist.github.com/davidair/cac8a7fb130959b3110ef29aa7d0bbac>)
- **Honest caveats:** both **rewrite the message** to drop the attachment (original → Trash / replaced
  by an imported copy). The email/history is kept (requirement met) but it is a reconstructed
  message, not the byte-identical original. **Back up first** (Google Takeout); run in batches.
- **Recommendation:** start with **Unattach per mailbox** for Aster now (few mailboxes); standardize
  with the **domain-wide script** as a documented step in the offboarding runbook.

## HARD REQUIREMENT (locked by the team): never delete email — strip the attachment only

Email is historical evidence and is **never** deleted, under any circumstance. The only operation
allowed is **removing the attachment while keeping the message**. Email retention/auto-delete is
**off the table** (it would destroy legal-defense evidence). Every option below respects this.

This requirement **is** satisfiable — "keep the email, remove only the attachment" is a supported
operation, both going forward and for the backlog:

### Going forward (new email) — native, automatic, no email deletion
A Gmail **content / attachment compliance** rule (Admin → Gmail → Compliance) supports the
**"remove attachments"** modification on **inbound** mail: the message is delivered **without the
attachment, body intact**. The email stays (history preserved); the attachment leaves the mailbox.
To avoid losing the file the team needs, pair it with a **routing rule that sends a copy (with the
attachment) to a controlled store** (intake mailbox → bucket). End state: user inbox = email
**without** attachment; file = in the controlled store; **email never deleted**.
([content compliance — remove attachments](https://support.google.com/a/answer/1346936?hl=en),
[attachment compliance](https://support.google.com/a/answer/2364580?hl=en))

### Backlog (existing email that already has an attachment) — tool, keeps the email
Native Gmail cannot strip an attachment in place (R6), but Marketplace tools do it **without
deleting the message**: **Attachment Manager for Gmail** — *"remove attachments from a message
without removing the content of the message itself"* — or **Unattach.app** (bulk)
([Attachment Manager](https://workspace.google.com/marketplace/app/attachment_manager_for_gmail/1057782280387)).
**Honest caveat:** these **rewrite the message** (the attachment becomes a placeholder/link) — the
body and thread are kept (satisfies the requirement) but it is technically a modified copy, not
untouched. Going-forward strip-on-delivery is cleaner (the email is *born* without the attachment).

### The only gate
Confirm the **Workspace edition** — content/attachment compliance is more broadly available than
DLP (not Enterprise-only), but the "remove attachments" + routing actions must be on 4Shark's plan.

**This supersedes the email-retention idea earlier in this spike** — that idea is rejected because
it deletes email, which the team forbids.

## What this unlocks for the client response (the defense line)

With a documented retention policy in place, a future erasure reply can honestly say, only if asked:

> "Os dados nos sistemas operacionais foram anonimizados/eliminados. Arquivos eventualmente
> recebidos por e-mail não admitem remoção seletiva por limitação técnica do próprio e-mail; por
> isso aplicamos uma **política de retenção** que os expira automaticamente, e **aprimoramos o
> processo de recebimento** desde então. Lamentavelmente, esse aprimoramento é posterior ao seu
> período de contrato."

True, within the law (art. 16 technical-limits + proportionality), and exposes nothing. Per the
top-of-runbook client-response principle: say this **only if the client raises email** — do not
volunteer it.

---

## Open questions — to decide

1. **Retention mechanism:** Vault retention rule (paid) vs. a free scheduled GAM/Apps Script job?
2. **Retention window** for client-data email (12 / 24 months?).
3. **Do we adopt the optional expiring-link** for heavy files, or email-only with the policy?
4. **Who owns the written policy** (DPO/Paulo) and where it lives.

If the team picks a direction, this promotes to a **PLAN.md** — most of the work is writing the
policy + standing up the retention mechanism, not building software.

---

## Sources

- Opice Blum — proporcionalidade e razoabilidade na LGPD: <https://opiceblumacademy.com.br/proporcionalidade-razoabilidade-tratamento-dados-pessoais-lgpd/>
- ICO — Right to erasure (reasonableness, backups, beyond use): <https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/individual-rights/individual-rights/right-to-erasure/>
- GDPR art. 17 — Right to erasure: <https://gdpr-info.eu/art-17-gdpr/>
- Secure Privacy — data minimization & retention policies: <https://secureprivacy.ai/blog/data-minimization-retention-policies>
- Material Security — email retention policy for sensitive data: <https://material.security/workspace-resources/mastering-email-retention-policy-to-protect-sensitive-data>
- FTC — Protecting Personal Information: a guide for business: <https://www.ftc.gov/business-guidance/resources/protecting-personal-information-guide-business>
- Kiteworks — sending PII over email (why it is unsuitable): <https://www.kiteworks.com/secure-email/send-pii-over-email/>
- AWS — pre-signed URLs (optional expiring-link mechanism): <https://aws.amazon.com/blogs/security/how-to-securely-transfer-files-with-presigned-urls/>
