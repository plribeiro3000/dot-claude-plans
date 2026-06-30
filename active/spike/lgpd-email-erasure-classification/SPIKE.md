# SPIKE — Classification rule for LGPD e-mail erasure (keep vs delete)

> Question: when fulfilling an LGPD right-to-erasure request from a former client, how should our
> automated triage decide which e-mail attachments to permanently delete vs retain? We need a
> principled, law-grounded rule — not the ad-hoc V1/V2 we iterated into.
> Researched 2026-06-12 (main session, web sources cited inline).

## Why we stopped to research

- **V1 rule** — delete by default; keep anything with a "financial or legal/contractual" signal.
  Failure: over-kept the **client's own internal legal documents** (their collective PPR agreement
  with their union/employees) that we have no reason to retain.
- **V2 rule ("party-based")** — keep only records where **4Shark is a party** (our contracts, our
  invoices, our negotiations). Failure: **brittle** — it can't recognize *our own* documents under a
  different corporate entity, forcing a hardcoded **CNPJ allowlist** of 4Shark's 4 entities. The
  engineer's instinct: an allowlist of our own CNPJs to decide keep/delete is a sign the rule is
  wrong at the root.

## What the law and practice actually say (verified findings)

**F1 — LGPD art. 16: erase by default, with closed-list conservation exceptions.** Personal data is
eliminated after processing ends, EXCEPT conservation for: (I) **cumprimento de obrigação legal ou
regulatória** pelo controlador; (II) estudo por órgão de pesquisa (anonimizado); (III) transferência
a terceiro; (IV) uso exclusivo do controlador, anonimizado. The data subject's erasure request
**cannot be fulfilled** when one of these applies.
Source: ANPD FAQ 6.6 (https://www.gov.br/anpd/pt-br/acesso-a-informacao/perguntas-frequentes/perguntas-frequentes/6-direitos-dos-titulares-de-dados/6-6-2013-em-quais-situacoes)
and https://lgpd-brasil.info/capitulo_02/artigo_16 — *"Os dados pessoais serão eliminados após o
término de seu tratamento... sendo permitida a conservação para... cumprimento de obrigação legal ou
regulatória pelo controlador..."*

**F2 — The override that matters for us is fiscal retention (≈5 years, CTN).** Notas fiscais and the
records behind tax obligations must be kept **5 years** (CTN decadência + prescrição), for both
issuer and recipient — independent of an erasure request. (As of 2025 the *tax authority's* own DF-e
retention went to 11 years, but the **taxpayer rule stays 5 years**.)
Sources: https://www.jusbrasil.com.br/artigos/prazos-para-guardar-os-documentos-fiscais/1298331046 ;
https://oobj.com.br/gestao/por-quanto-tempo-guardar-notas-fiscais/ — *"documentos fiscais devem
permanecer arquivados por cinco anos... tanto para quem emite quanto para quem recebe."*

**F3 — CNPJ / PJ data is NOT "dado pessoal" under LGPD (except MEI/EI).** LGPD protects the *pessoa
natural*. "Dados relacionados a pessoa jurídica, como **razão social (desde que não seja MEI), CNPJ,
telefone comercial, não estão protegidos pela LGPD**." Exception: individual entrepreneurs (MEI/EI),
whose CNPJ data is effectively personal.
Sources: https://www.gov.br/pt-br/lgpd/cadastro-de-pessoas-juricias-cnpj ;
https://tiinside.com.br/20/04/2021/nao-e-so-cpf-cnpj-pode-ser-titular-de-dados-pessoais-a-luz-da-lgpd/
→ **a client's CNPJ card / corporate registration is not the erasure target at all.** (Confirms the
engineer: "CNPJ não é dado pra apagar.")

**F4 — GDPR art. 17(3) mirrors this, with one warning.** Erasure does not apply where retention is
needed for (b) a **legal obligation** (e.g. financial/tax records) or (e) the **establishment,
exercise or defense of legal claims**. BUT: *"A controller cannot point to a tangentially related
legal rule as a pretext for retaining data it wants to keep for commercial reasons."*
Sources: https://gdpr-info.eu/art-17-gdpr/ ;
https://www.exabeam.com/explainers/gdpr-compliance/what-is-gdpr-article-17-right-to-erasure-and-4-ways-to-achieve-compliance/

**F5 — The established instrument is a RETENTION SCHEDULE (tabela de temporalidade), not ad-hoc
judgment.** The keep/delete decision is driven by a document-type → legal-retention-period table
built with legal/compliance; you need a *justificativa legal* to refuse a titular's erasure request.
Source: https://datalege.com.br/tabela-de-temporalidade/ ;
https://br.lexlatin.com/opiniao/lgpd-no-mercado-financeiro-por-quanto-tempo-os-dados-devem-ficar-armazenados
— *"a empresa precisa de uma justificativa legal para responder uma negativa do pedido do titular."*

**F6 — How automated DSAR/erasure tools actually classify.** They (a) discover records by the **data
subject's identifiers**, (b) map them to processing activities, then (c) **filter out what a
retention requirement / legal hold protects** — litigation holds, active contracts, **financial
obligations**, regulatory holds. "Deletion is aligned with legal holds, retention schedules, and
minimization." They classify on **(1) data-subject identity + (2) retention/legal-hold status — NOT
on "who is a party."**
Sources: https://secureprivacy.ai/blog/how-do-companies-automate-dsar-workflows ;
https://www.urmconsulting.com/blog/managing-dsars-and-other-data-subject-rights ; https://bigid.com/data-deletion/

**F7 — LLMs in this space are used for PII *detection*, with retention rules as a separate filter.**
NER/LLM finds the personal data; a retention/legal-hold policy decides what survives; every deletion
is logged as a compliance artifact.
Source: https://predictionguard.com/blog/pii-detection-redaction-llm-pipelines-regulated-industries

## Options comparison

| Approach | How it decides | Verdict |
|---|---|---|
| **A. "Financial/legal signal" (our V1)** | keep if it *looks* legal/financial | ✗ over-keeps the client's own contracts (PPR/union); not law-grounded |
| **B. "Party-based + entity allowlist" (our V2)** | keep only if 4Shark is literally a party / on a CNPJ allowlist | ✗ brittle; needs an allowlist of our own CNPJs; misclassifies our own docs and the client's PJ docs; not how anyone does it |
| **C. Data-subject + retention-basis (industry standard, F1/F4/F6)** | delete = the data subject's (client's people's) **personal data** with **no retention duty**; keep = a **retention duty** applies, or it **isn't a natural person's personal data** at all | ✓ matches LGPD art. 16, GDPR 17(3), and how DSAR tools work; dissolves the allowlist |

## Recommended rule (for the V3 triage prompt)

Decide per attachment, in this order. `keep` always means **escalate to the mailbox owner** (never
auto-delete on doubt).

1. **Does it carry a *natural person's* personal data tied to this client?** (names, CPF, matrícula,
   identifiers of the client's employees / end-users / contacts.) Pure **PJ/corporate data** — a
   company's CNPJ card, corporate bank documents, razão social — is **not** the erasure target
   (LGPD protects the pessoa natural; F3). MEI/EI is the exception.
   - **No personal data** → **keep** (out of erasure scope; e.g. the client's CNPJ card, or 4Shark's
     own corporate/bank docs — kept because they aren't the client's personal data, **no allowlist
     needed**).
   - **Has personal data** → go to 2.
2. **Does a legal-retention duty apply to 4Shark for this record?**
   - **Fiscal/accounting** — notas fiscais 4Shark issued, payment/refund evidence, comprovantes
     (CTN ≈5 years, F2) → **keep**.
   - **Legal defense / contract 4Shark is a party to** — a 4Shark↔client contract, dispute/claim
     evidence (art. 16-I / 17(3)(e), F4) → **keep**.
   - **No retention duty** → **delete** (this is the erasure target: the client's people's personal
     data — user/commission spreadsheets, their PPR rules/indicators, their **collective agreements
     with their union/employees**, internal policies, support exports).
3. **Unsure whose data it is or whether a duty applies** → **keep** (escalate).

**Why this is better than V2.** The discriminator is **"is this a natural person's personal data,
and is there a retention duty?"** — not "is 4Shark named / on the CNPJ allowlist." The 4T Soluções
bank documents are kept not because "4T is one of our CNPJs," but because they carry **no natural
person's personal data** → they were never the erasure target. The allowlist disappears. Worked
examples reconcile cleanly:
- Client's collective PPR agreement (client↔union) → has employees' PF data, no 4Shark duty → **delete**.
- 4Shark's NFSe to the client → fiscal record, 5-yr duty → **keep**.
- Client's CNPJ card → PJ data, not personal → **keep** (out of scope; harmless).
- 4Shark's 4T-Soluções bank docs → our corporate PJ data, not the client's personal data → **keep**.

## Open risks / for the engineer to decide

- **MEI/EI edge (F3):** if any client contact is a MEI/EI, their CNPJ *is* personal data. Rare here;
  flag rather than hardcode.
- **"Pretext" warning (F4):** don't keep things "just in case" — keep only on a real fiscal/legal
  basis, else we under-comply with the erasure.
- **Recordkeeping (F6/F7):** every delete must be logged (we already write a manifest). Keep that.
- This rule still benefits from `inspect_attachment` (open the file) to tell *whose* personal data it
  is and whether a fiscal/legal duty attaches — that machinery stays.

## Recommendation

Adopt **Option C** as the V3 triage rule (steps 1–3 above), drop the CNPJ allowlist, and reframe the
prompt around **personal-data + retention-duty**. This is the version to validate once and ship.
