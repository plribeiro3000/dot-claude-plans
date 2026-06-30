# SPIKE — When should 4Shark anonymize a cancelled client's data? (auto vs manual)

> Question raised before writing more code: the current flow anonymizes a deactivated
> company's data **automatically 30 days after cancellation**. Is that legally right and
> operationally safe, or should anonymization be a **deliberate, manual** action?

## The trigger for the doubt

A cancelled client may legitimately need their data **later** — e.g., "Virtual Connection"
cancelled, asked for nothing, and two years later wants the **PDF of each statement
(declaração)**. If we auto-anonymized, those PDFs come out redacted — the data is gone,
**irreversibly**. Auto-anonymizing on a blind timer destroys data the client may still need
and that we may be **obligated to keep**.

## Legal findings (LGPD)

1. **Art. 16 — elimination after término, but with retention exceptions.** Data *should* be
   eliminated after the end of treatment, **unless** one of the exceptions applies:
   (I) compliance with a **legal/regulatory obligation** of the controller; (II) research;
   (III) transfer to a third party; (IV) exclusive use by the controller (anonymized).
   Tax/fiscal records are the textbook (I) example. → Retention is *allowed* under a legal basis.
   Source: [LGPD art. 16](https://lgpd-brasil.info/capitulo_02/artigo_16).

2. **No fixed deletion deadline.** The LGPD sets **no specific period**; it depends on the
   purpose and the data lifecycle, which the organization itself evaluates. There is no legal
   basis for "30 days" — that number is arbitrary.
   Source: [ANPD FAQ 5.5 — Por quanto tempo os dados podem ser tratados](https://www.gov.br/anpd/pt-br/acesso-a-informacao/perguntas-frequentes/perguntas-frequentes/5-adequacao-a-lgpd/5-5-por-quanto-tempo).

3. **Cancellation ≠ deletion request.** Ending the contract ends the *service*. It is **not**
   the data subject exercising the right to elimination (art. 18, VI). After a contract ends,
   data is eliminated **unless a legal basis justifies keeping it** — the controller assesses;
   it is not an automatic, immediate must-delete. A client cancelling is not asking us to delete.
   Source: [Get Privacy — término do tratamento](https://getprivacy.com.br/lgpd-entenda-as-regras-para-o-termino-do-tratamento-de-dados/),
   [TOTVS — armazenamento posterior ao cancelamento](https://centraldeatendimento.totvs.com/hc/pt-br/articles/360049262094-Privacidade-de-Dados-LGPD-Tempo-de-armazenamento-de-dados-posterior-ao-cancelamento-de-contrato).

4. **Counter-principle — storage limitation.** We also **cannot keep forever** without a basis;
   data is kept only as long as necessary for the purpose. So "keep indefinitely until someone
   asks" is not fully compliant either — there must be a defined retention period, after which
   eliminate.
   Source: [heyData — GDPR retention periods](https://heydata.eu/en/magazine/gdpr-data-retention-periods-overview-requirements-best-practices/).

## Industry practice (SaaS)

- **30–90 day grace period** after termination for the client to **export/retrieve** their
  data, *then* deletion — not immediate destruction.
- Retention period **specified in the DPA**, aligned with legal/regulatory requirements.
- **Backups**: a documented 30–90 day cycle; expired data simply isn't restored to active use.
- Deletion is **deliberate and policy-driven**, not a blind timer that fires on cancellation.

Sources: [Bodle Law — SaaS data retention & deletion](https://www.bodlelaw.com/saas/saas-agreements-data-retention-and-deletion),
[TechTarget — SaaS retention policies](https://www.techtarget.com/searchdatabackup/tip/Compare-SaaS-data-retention-policies-from-4-major-providers),
[Uprightor — post-termination data handling](https://uprightor.com/post-termination-data-handling/).

## Answers to the specific questions

- **Am I obligated to delete after cancellation?** No — not immediately, and not just because
  the contract ended. You eliminate when the data is no longer necessary **and** no retention
  exception (legal obligation, defense of rights, client's own need) applies. You **may** retain
  under a legal basis; you **must not** keep forever without one.
- **How long must I keep?** LGPD gives no single number. It is per data category: fiscal/financial
  ~5 years (legal obligation), contractual records through the statute of limitations, etc.
- **Does "cancel" mean "delete"?** No. If a client cancels and a week (or two years) later asks
  for their statements, with a retain-then-delete-deliberately design the data is still there and
  we serve it. With a blind auto-anonymize, it is gone — the failure mode we must avoid.

## Implication for our implementation

- **Auto-anonymize 30 days after company cancellation is the wrong default**: 30 days has no
  legal basis, it conflates cancellation with a deletion request, and it is irreversible.
- **Important — this behaviour is pre-existing, not something we just added.** The company-level
  user anonymization (`Company::UserAnonymizer`, cron `anonymization:company`,
  `COMPANY_ANONYMIZING_WINDOW=30`) **already existed** — it is why Aster's 897 users were already
  anonymized. Our recent PRs (#5101, #5102) **extended** that same auto-flow to documents and
  identifier actions. So "disable the cron" changes a long-standing behaviour, not just our work.
- The **mechanism** (the workers: `Company::Anonymizer` orchestrator → user/document/action
  anonymizers) is good and reusable. The problem is the **automatic trigger**, not the code.

## Recommended direction (to decide with DPO/legal — not code yet)

1. **Make anonymization deliberate, not automatic** — keep the workers, remove the automatic
   trigger. A console-invoked, no-input flow (`Company::Anonymizer` for a given company) run
   **when we decide**: on an explicit client erasure request, or when a defined retention period
   has lapsed.
2. **Disable the `anonymization:company` cron** (EventBridge, terraform) — this stops the
   pre-existing 30-day company auto-anonymization too; confirm that is intended.
3. **Define a retention policy** (with DPO): grace/retention window per data category, export
   path for a returning client, what is kept under legal obligation (fiscal) and for how long.
4. The **individual-user anonymizer** (`User::Anonymizer::Producer`, `USER_ANONYMIZING_WINDOW`
   ≈ 2590 days ≈ 7 years) is a separate flow for long-inactive users in *active* companies —
   decide separately whether it stays (7 years is a defensible retention period).
5. Update `LGPD-DATA-ERASURE.md` to describe the **manual** process once decided.

## Open decisions for the engineer

- Confirm pivot: **manual on-request** (+ retention policy) vs keep the 30-day auto.
- Confirm disabling the pre-existing company cron (affects user anonymization that has been live).
- Retention window + export path — needs DPO/legal; this spike grounds the discussion, it is not
  a legal opinion.
