# SPIKE — LGPD Policy & Document Gap Analysis for 4Shark

## Investigation question

What is the standard set of privacy and information-security policies/documents that a Brazilian SaaS company operating as an LGPD **operadora** (processor) should have, and which of those documents does 4Shark not yet have? For each gap, is the document legally required or best-practice, and what priority should it receive?

**Scope constraints:** 4Shark is a small remote team, AWS cloud, Google Workspace SSO, 1Password. DPO = Paulo Ribeiro. It treats NO sensitive data (art. 5 II). It functions as operadora for client companies (controladoras) and as controladora of its own employee/contractor data.

---

## Sources consulted

- [ANPD — RIPD page](https://www.gov.br/anpd/pt-br/canais_atendimento/agente-de-tratamento/relatorio-de-impacto-a-protecao-de-dados-pessoais-ripd) — governing articles and applicability to operators vs. controllers
- [LGPD Brasil — Art. 37](https://lgpd-brasil.info/capitulo_06/artigo_37) — verbatim RoPA obligation text
- [LGPD Brasil — Art. 39](https://lgpd-brasil.info/capitulo_06/artigo_39) — operator obligation to follow controller instructions
- [Legrow Law — LGPD 2026 tech companies](https://legrowlaw.com/gpd-2026-empresas-tecnologia/) — common audit gaps
- [Bcompliance — ANPD enforcement May 2026](https://blog.bcompliance.com.br/2026/05/09/sancoes-anpd-canal-lgpd-fiscalizacao/) — documents ANPD checks in inspections
- [LGPDPro — Fiscalização 2025](https://lgpdpro.com.br/fiscalizacao-lgpd-2025/) — inspection checklist and common gaps
- [ANPD — Resolução 19/2024](https://www.gov.br/anpd/pt-br/assuntos/noticias/resolucao-normatiza-transferencia-internacional-de-dados) — international transfer SCCs, grace period ended Aug 2025
- [GoAdopt — ANPD Cookie Guide](https://goadopt.io/blog/anpd-cookies-guia-orientativo-cookies-protecao-dados-pessoais/) — cookie policy mandatory scope
- [Migalhas — BCP e LGPD](https://www.migalhas.com.br/depeso/338658/nem--so--de-privacidade-vive-a-lgpd--a-importancia-do-plano-de-continuidade-de-negocios) — BCP as best-practice, not explicit mandate
- [Conjur — Gestão de Fornecedores (Feb 2024)](https://www.conjur.com.br/2024-fev-21/a-importancia-da-gestao-de-fornecedores-para-o-cumprimento-da-lgpd/) — vendor management as risk management
- [Perallis — Classificação da Informação](https://www.perallis.com/news/o-que-e-classificacao-da-informacao-e-como-ela-se-torna-critica-com-a-lgpd) — classification as ISO 27001 best-practice, not a direct LGPD requirement
- [LGPDBrasil — Canal de atendimento](https://lgpdbrasil.com.br/canal-de-atendimento-aos-titulares-e-garantia-dos-direitos-fundamentais/) — DSR channel mandatory for controllers under art. 18 and 41
- [Farina & Antunes — Contrato controlador-operador](https://farinaeantunes.com.br/blog/contrato-entre-controlador-e-operador-na-lgpd-uma-salvaguarda-para-a-protecao-de-dados/) — DPA described as "legally mandatory" and "salvaguarda essencial"
- [Reisaraujo — SaaS DPA](https://reisaraujo.com.br/obrigatoriedade-legal-seu-contrato-de-licenca-de-software-saas-exige-clausulas-de-protecao-de-dados) — two implementation forms: clauses in MSA or standalone DPA
- [Machertech — Aviso vs Política de Privacidade](https://www.machertecnologia.com.br/lgpd-aviso-privacidade-versus-politica-privacidade/) — ANPD terminology and DPO Dec 2024 guide
- See auxiliary: `lgpd_sources_raw_1.md` — full raw notes per source including verbatim quotes, article numbers, and fetch verdicts

---

## Section 1 — Recommended/standard LGPD document set

This section covers the full set that Brazilian privacy professionals and the ANPD associate with a compliant operadora/SaaS company. Documents marked "4Shark has" are not analyzed for gaps here unless a source flags a scope or sufficiency problem.

### Tier A — Legally grounded obligations (art. 6, 9, 18, 37, 39, 41, 46, 48)

| Document | Legal anchor | Who it applies to | 4Shark has it? |
|---|---|---|---|
| Política de Privacidade / Aviso de Privacidade (public-facing) | Art. 9 (transparency), art. 18 | Controladores (and operadoras with a public site) | Yes |
| Registro de Operações de Tratamento (RoPA / ROPA) | Art. 37 — "O controlador e o operador devem manter registro" | Both controller and **operator** | Draft |
| DPA / Acordo de Processamento de Dados Pessoais (operadora → controladora clients) | Arts. 37+39 combined; acknowledged as "salvaguarda essencial" by legal commentary | **Operadora** entering client contracts | NO — see Finding 2 |
| Canal de atendimento ao titular (DSR channel, public-facing policy) | Art. 18 (nine rights), art. 41(I) (DPO role) | Controladores | Partial — internal runbook exists; no public-facing page found in the existing list |
| Plano / Procedimento de Resposta a Incidentes de Segurança | Art. 48 (incident notification), Resolution CD/ANPD 15/2024 (3-business-day deadline) | Both | Yes |
| Medidas de Segurança Técnicas e Organizacionais (TOMs) documented | Art. 46 | Both | Covered by several existing policies |
| Designação formal do Encarregado (DPO) publicada | Art. 41, Resolution 18/2024 | Controladores; operadoras should follow same practice | DPO = Paulo Ribeiro; publication status not verified |

### Tier B — Regulatory guidance and strong industry standard (not explicit legal mandates)

| Document | Primary reference | Applicability to 4Shark | 4Shark has it? |
|---|---|---|---|
| Política de Segurança da Informação (umbrella) | Art. 50 boas práticas; ANPD Guide for small entities | Both | Yes |
| Programa de Conscientização em Segurança da Informação | Art. 50 ("ações educativas") | Both | Yes |
| Política de Gestão de Identidade e Acesso | Art. 46 + art. 50 | Both | Yes |
| Política de Desenvolvimento Seguro de Software | Art. 46 + art. 50 | Operadora providing SaaS | Yes |
| Política de Backup e Restauração | Art. 46 (availability pillar) | Both | Yes |
| Política de Armazenamento, Anonimização e Descarte | Art. 16 (data deletion), art. 12 (anonymization) | Both | Yes |
| Política de Gestão de Fornecedores / Suboperadores | Arts. 37+39 (implied), industry standard | Operadora using cloud/SaaS vendors | NO — see Finding 4 |
| Política de Cookies | ANPD Cookie Guide 2022 | Any company with a public web presence using cookies | Conditional — see Finding 3 |
| Política de Classificação da Informação | ISO 27001 / art. 46 best-practice | Technology companies; not a direct LGPD mandate | NO — see Finding 5 |
| Plano de Continuidade de Negócios / DRP | Art. 46 (availability + integrity); ABNT NBR ISO 22301 | Best-practice for SaaS providers | NO — see Finding 6 |
| Contrato de Confidencialidade (NDA) | General law; art. 50 governance | Internal/HR | Yes |

### Tier C — Situation-specific (not universally applicable)

| Document | Trigger | Applies to 4Shark? |
|---|---|---|
| RIPD / DPIA | Art. 38: high-risk processing, legitimate-interest basis, ANPD demand; **controller only** | Only if 4Shark acts as controladora for high-risk processing (e.g., employee data with biometrics). NOT required for its operator role. Low-risk employee data: probably not triggered now. |
| Termo de Consentimento templates | When consent is the legal basis chosen for a specific treatment; art. 7 I, art. 11 I | 4Shark likely uses contract execution and legitimate interest as bases, not consent, for client-facing SaaS. Needed if consent is relied upon anywhere. |
| Política de Transferência Internacional de Dados | Resolution 19/2024 (SCCs, grace period ended Aug 2025) | Yes — 4Shark uses AWS (international regions). The requirement is incorporating SCCs into contracts/DPAs, not necessarily a standalone policy, but documentation of the mechanism is required. |
| Programa de Governança em Privacidade (formal PGP) | Art. 50; optional certification with ANPD | Overkill for a small team. Useful only if 4Shark pursues formal ANPD certification or enterprise sales require it. |

---

## Section 2 — Findings (gap analysis)

### Finding 1: DPA / Acordo de Processamento de Dados Pessoais — MISSING and high-priority

**Evidence:**
- Art. 37: "O controlador e o operador devem manter registro das operações de tratamento de dados pessoais que realizarem" — creates a documentation obligation on both parties.
- Art. 39: operator must "realize the treatment according to the instructions furnished by the controller." Legal commentary (Farina & Antunes): "O contrato estabelece claramente quem é responsável pelo quê" and is described as "salvaguarda essencial."
- Legrow Law 2026: "Operating without DPA with these vendors is among the most common irregularities found during audits."
- LGPDPro 2025 inspection checklist explicitly includes "Contratos com operadores com obrigações de segurança, confidencialidade e suboperadores."
- Reisaraujo: two valid forms: (a) LGPD clauses in the standard service/MSA, or (b) a standalone DPA. Both satisfy the underlying legal requirement.

**Source:** [LGPD Brasil Art. 37](https://lgpd-brasil.info/capitulo_06/artigo_37); [Farina & Antunes](https://farinaeantunes.com.br/blog/contrato-entre-controlador-e-operador-na-lgpd-uma-salvaguarda-para-a-protecao-de-dados/); [Legrow Law](https://legrowlaw.com/gpd-2026-empresas-tecnologia/); [LGPDPro](https://lgpdpro.com.br/fiscalizacao-lgpd-2025/)

**Significance:** 4Shark signs service contracts with client companies (the controladoras). These contracts currently include a Contrato de Confidencialidade (NDA), but a DPA / Acordo de Processamento de Dados Pessoais is a distinct instrument covering: (a) scope and purpose limitations on the operator, (b) suboperator authorization rules, (c) security obligations, (d) incident notification deadline (typically 48–72h to the controladora), (e) audit rights, (f) data return and deletion at contract end. The legal anchor (arts. 37+39) and the 2025–2026 enforcement pattern both point to this as the highest-priority gap. Whether it is a standalone DPA or a heavy addendum to the existing service contract is a structural decision for the engineer.

---

### Finding 2: Canal de Atendimento ao Titular — public-facing page/policy may be missing

**Evidence:**
- Art. 18 of LGPD establishes nine rights that controllers must enable.
- Art. 41(I): the DPO is responsible for "accepting, receiving and analyzing data subject messages."
- Bcompliance (May 2026): "ANPD explicitly verified the absence of effective communication channels among 20 major companies in December 2024, making this a primary inspection priority."
- LGPDBrasil: "mandatory 15-day response timeframe applies to all requests."

**Source:** [LGPDBrasil — Canal de atendimento](https://lgpdbrasil.com.br/canal-de-atendimento-aos-titulares-e-garantia-dos-direitos-fundamentais/); [Bcompliance](https://blog.bcompliance.com.br/2026/05/09/sancoes-anpd-canal-lgpd-fiscalizacao/)

**Significance:** 4Shark already has an internal runbook (Runbook interno de atendimento a pedido de titular / DSR). What the ANPD inspection pattern shows is that companies are being checked for a **functional, public-facing channel** — a visible contact point (e.g., the DPO's email on the public privacy policy, a dedicated form, or similar) that data subjects can actually use. The gap is not the internal process but the external visibility of the contact mechanism. The distinction is between "we have a process" and "titulares can find the way in." The obligation is on 4Shark as controladora of employee/contractor data. For client end-users, the controladora (client company) is primarily responsible — but 4Shark's Política de Privacidade should already include the DPO contact.

---

### Finding 3: Política de Cookies — conditional on actual cookie usage

**Evidence:**
- ANPD Cookie Guide (2022): "a Cookie Policy is mandatory for websites using cookies under LGPD." Must contain specific purposes, retention periods, third-party sharing details, art. 9 information.
- Strictly necessary cookies: no prior consent needed; but a notice still required explaining what they are.
- Non-necessary cookies: opt-in consent required.

**Source:** [GoAdopt — ANPD Cookie Guide](https://goadopt.io/blog/anpd-cookies-guia-orientativo-cookies-protecao-dados-pessoais/)

**Significance:** This gap is conditional. If 4Shark's web presence (app client, webclient, onboarding portal) uses any cookies — including session cookies, authentication tokens, or analytics scripts — a Política de Cookies or at minimum a cookie notice section within the existing Política de Privacidade is needed. If the product is a pure API with no browser-facing front-end using cookies, the obligation does not arise. The engineer should confirm whether the existing Política de Privacidade already addresses cookie treatment. If not, a dedicated cookie section or standalone notice is needed. This is low-effort to add but is an ANPD inspection point.

---

### Finding 4: Política de Gestão de Fornecedores / Suboperadores — best-practice gap

**Evidence:**
- Conjur (Feb 2024): no specific LGPD articles cited as mandating a written supplier management policy. Framed as preventive risk management. "98% das organizações têm relacionamento com pelo menos um terceiro que sofreu uma violação."
- LGPDPro 2025: "unmapped supplier/suboperator ecosystems" listed as a common inspection gap.
- The legal anchor for the substance (vetting and contracting suboperators) flows from the DPA obligation (Finding 1): standard DPA clauses require the operadora to obtain controladora authorization before engaging suboperators.

**Source:** [Conjur](https://www.conjur.com.br/2024-fev-21/a-importancia-da-gestao-de-fornecedores-para-o-cumprimento-da-lgpd/); [LGPDPro](https://lgpdpro.com.br/fiscalizacao-lgpd-2025/)

**Significance:** A formal "Política de Gestão de Fornecedores" is recommended but not a direct legal requirement. The underlying obligation — that suboperators must meet the same data protection standards — is covered if the DPA (Finding 1) includes suboperator authorization clauses and 4Shark maintains a list of its suboperators (AWS, Google Workspace, 1Password, etc.) in the RoPA. A separate written policy adds maturity and is worth doing if 4Shark wants enterprise-grade compliance or is entering procurement with large clients who run vendor risk assessments. For a small team today, addressing it through the DPA + RoPA is an acceptable minimum.

---

### Finding 5: Política de Classificação da Informação — ISO-grade best practice, not a direct LGPD requirement

**Evidence:**
- Perallis: classification framed as "best practice necessary for compliance" — enabling LGPD compliance but "does not reference specific LGPD articles or ANPD guidance mandating the practice." Aligned with ISO 27001, not a standalone LGPD mandate.
- No ANPD guidance or enforcement case was found that specifically cites absence of a classification policy as a violation.

**Source:** [Perallis](https://www.perallis.com/news/o-que-e-classificacao-da-informacao-e-como-ela-se-torna-critica-com-a-lgpd)

**Significance:** For a small team where most employees access most systems and data is already treated consistently, a formal classification policy adds limited marginal value to LGPD compliance. It becomes more relevant if 4Shark scales its team, hires contractors with scoped access, or is evaluated under ISO 27001 / SOC 2. At the current size, this is a low-priority, deferred item. The existing Política de Gestão de Identidade e Acesso + Política de Segurança da Informação likely cover the functional controls that classification enables.

---

### Finding 6: Plano de Continuidade de Negócios (BCP) / Disaster Recovery Plan — best-practice, not explicit LGPD requirement

**Evidence:**
- Migalhas: "BCP is NOT explicitly mandated by LGPD." Arts. 6(VII), 33(II)(d), 50 create indirect pressure toward availability controls, but the LGPD text does not use the words "plano de continuidade." ABNT NBR ISO 22301:2020 is the referenced standard.

**Source:** [Migalhas — BCP e LGPD](https://www.migalhas.com.br/depeso/338658/nem--so--de-privacidade-vive-a-lgpd--a-importancia-do-plano-de-continuidade-de-negocios)

**Significance:** 4Shark already has a Política de Backup e Restauração, which covers the recovery dimension. A formal BCP goes beyond backup — it addresses continuity of the business process itself during an outage. For a SaaS company whose service IS the product, some BCP thinking is embedded in the infrastructure design (AWS multi-AZ, etc.). A written BCP document is appropriate if 4Shark's enterprise clients contractually require it or if a due diligence/security questionnaire asks for one. Not an immediate LGPD compliance gap.

---

### Finding 7: Política / Mecanismo de Transferência Internacional de Dados — compliance action required, documentation may be missing

**Evidence:**
- Resolution CD/ANPD 19/2024, published August 23, 2024. Grace period ended August 23, 2025. "Os agentes de tratamento que utilizam cláusulas contratuais para realizar transferências internacionais de dados deverão incorporar as cláusulas-padrão contratuais aprovadas pela ANPD aos seus respectivos instrumentos contratuais no prazo de até doze meses."
- LGPDPro 2025 inspection checklist: "International transfers: mapped and justified cross-border data flows."
- AWS stores data in regions that may be outside Brazil; this constitutes international data transfer under LGPD.

**Source:** [ANPD Resolution 19/2024](https://www.gov.br/anpd/pt-br/assuntos/noticias/resolucao-normatiza-transferencia-internacional-de-dados); [LGPDPro](https://lgpdpro.com.br/fiscalizacao-lgpd-2025/)

**Significance:** The gap here is not a policy document per se — it is a contractual and mapping action that is now past the grace period deadline (Aug 2025). 4Shark needs to: (a) identify which AWS regions it uses and whether any are outside Brazil, (b) confirm that its DPA with client controladoras addresses international transfers (because if 4Shark processes client data in a US-based AWS region, that is an international transfer it must justify), (c) check whether AWS's standard DPA/SCCs already cover the ANPD Resolution 19/2024 requirements (AWS has published LGPD-specific compliance documentation). A short internal memo or a section within the RoPA documenting the transfer mechanism is the minimum documentation artifact. A standalone "Política de Transferência Internacional" is optional unless a client or audit requires it.

---

### Finding 8: RIPD / DPIA — NOT currently required for 4Shark's operator role

**Evidence:**
- ANPD: "O controlador é o agente de tratamento responsável pela elaboração do RIPD." The obligation is on **controllers only**.
- Art. 38 triggers: high-risk processing, legitimate-interest basis, public-security operations, government entities, ANPD demand.
- 4Shark treats no sensitive data (art. 5 II).

**Source:** [ANPD — RIPD page](https://www.gov.br/anpd/pt-br/canais_atendimento/agente-de-tratamento/relatorio-de-impacto-a-protecao-de-dados-pessoais-ripd)

**Significance:** 4Shark is predominantly an operadora. The RIPD obligation falls on its clients (the controladoras). For 4Shark's own role as controladora of employee/contractor personal data, a RIPD is warranted only if that processing qualifies as high-risk (e.g., large-scale, involves biometrics, or uses legitimate interest as the basis for processing). For a small remote team with standard employment data, this threshold is unlikely met today. No immediate gap; monitor if processing scope expands.

---

### Finding 9: Termo de Consentimento templates — situational

**Evidence:**
- Art. 7(I) LGPD: consent is one of ten legal bases for processing. When consent is chosen, it must be "free, informed, unequivocal, and specific."
- If 4Shark uses contract execution, legitimate interest, or legal obligation as bases for its main processing activities, a consent template is not needed for those.

**Source:** [LGPD Art. 7](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm)

**Significance:** No immediate gap unless 4Shark relies on consent as a legal basis somewhere. If the RoPA shows consent is never used as the legal basis, there is no requirement for consent templates. If there are touchpoints where consent is relied upon (e.g., marketing emails, optional analytics), a template should exist. The engineer should verify the RoPA legal-basis column.

---

## Section 3 — Trade-offs surfaced

| Document | Pros of adding | Cons / Risk of not adding | Urgency for 4Shark | Source |
|---|---|---|---|---|
| DPA with client companies | Legally anchored, ANPD inspection priority, protects 4Shark from joint liability claims | High risk: most common audit irregularity; gap in every client contract | High — legal requirement | [Legrow Law](https://legrowlaw.com/gpd-2026-empresas-tecnoria/), [LGPDPro](https://lgpdpro.com.br/fiscalizacao-lgpd-2025/) |
| Public DSR channel visibility | ANPD Dec 2024 verified absence in 20 companies | Titulares (employees, users) cannot find how to exercise rights | High — direct art. 18/41 obligation | [Bcompliance](https://blog.bcompliance.com.br/2026/05/09/sancoes-anpd-canal-lgpd-fiscalizacao/) |
| International transfer documentation | Required by Resolution 19/2024 (grace period ended Aug 2025) | Non-compliant since Aug 2025 if transfers exist without SCCs | High — grace period expired | [ANPD Res. 19/2024](https://www.gov.br/anpd/pt-br/assuntos/noticias/resolucao-normatiza-transferencia-internacional-de-dados) |
| Cookie Policy | Mandatory if any cookies used on public-facing web properties | Minor enforcement risk; easy to fix | Medium — confirm if cookies are in use | [ANPD Cookie Guide](https://goadopt.io/blog/anpd-cookies-guia-orientativo-cookies-protecao-dados-pessoais/) |
| Supplier management policy | Enterprise sales; vendor risk assessments | Substance already covered by DPA + RoPA | Low-Medium — maturity, not LGPD mandate | [Conjur](https://www.conjur.com.br/2024-fev-21/a-importancia-da-gestao-de-fornecedores-para-o-cumprimento-da-lgpd/) |
| Information classification policy | ISO 27001 alignment; supports access control | No LGPD enforcement risk for absence | Low — deferred | [Perallis](https://www.perallis.com/news/o-que-e-classificacao-da-informacao-e-como-ela-se-torna-critica-com-a-lgpd) |
| BCP / DRP formal document | Enterprise procurement, ISO 22301 | Not an explicit LGPD requirement | Low — deferred | [Migalhas](https://www.migalhas.com.br/depeso/338658/nem--so--de-privacidade-vive-a-lgpd--a-importancia-do-plano-de-continuidade-de-negocios) |
| RIPD / DPIA | Readiness if processing scope grows | Not currently required for operator role | Not applicable now | [ANPD RIPD](https://www.gov.br/anpd/pt-br/canais_atendimento/agente-de-tratamento/relatorio-de-impacto-a-protecao-de-dados-pessoais-ripd) |
| Consent templates | Required only where consent is the chosen legal basis | Low risk if contract/legitimate interest bases used | Only if consent is used — check RoPA | [LGPD Art. 7](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm) |

---

## What remains uncertain

- Whether 4Shark's current Política de Privacidade already includes a visible DPO contact / DSR channel description (would resolve Finding 2 partially).
- Which AWS regions 4Shark actually uses, and whether those constitute international transfers requiring SCC documentation (required for Finding 7).
- Whether 4Shark's client service contracts already include LGPD data protection clauses (even if not a standalone DPA) — if so, Finding 1's gap may be partially addressed.
- Whether the product's web front-end (app-webclient, onboarding portal) uses any non-essential cookies — determines whether Finding 3 is a real gap.
- Whether consent is used as a legal basis for any processing activity — determines whether Termo de Consentimento templates are needed (Finding 9).
- ANPD Resolution 19/2024 compliance for cloud providers: AWS publishes SCCs and LGPD addenda; whether 4Shark has accepted/signed those or whether the standard AWS Service Agreement is considered sufficient is an open legal question.

---

## Suggested options for main and the engineer

**Priority 1 — Address now (legal exposure)**

- **Option A — DPA standalone document:** Draft a Acordo de Processamento de Dados Pessoais as a standalone annex to the existing client service contract. Standard structure: scope/purpose, security obligations, suboperator authorization, incident notification (72h), audit rights, data return/deletion. This is the cleanest form for enterprise clients and new contracts.
- **Option B — LGPD addendum to existing contracts:** Add a "Adendo de Proteção de Dados Pessoais" as a contract addendum to existing client relationships. Lower friction to deploy to existing accounts, can be rolled out without renegotiating the main contract.

**Priority 2 — Address now (ANPD active enforcement)**

- Verify that the public Política de Privacidade includes a functional DPO contact and a reference to how titulares can exercise their rights (the "canal de atendimento" visibility gap — Finding 2). If already present, this closes. If not, a single paragraph update to the existing policy is the fix.

**Priority 3 — Address now (grace period expired)**

- Document international data transfers: identify AWS regions in use, confirm whether SCCs with AWS are in place or whether a memo documenting the transfer mechanism (and legal basis) should be added to the RoPA and/or DPA. This does not require a standalone policy document.

**Priority 4 — Address short-term (easy effort, ANPD inspection point)**

- Confirm whether the product web-facing properties use cookies. If yes, add a Política de Cookies or a cookie section to the existing Política de Privacidade.

**Priority 5 — Deferred (best-practice, not LGPD mandate)**

- Política de Gestão de Fornecedores: worthwhile when 4Shark begins enterprise procurement cycles or when the DPA (Priority 1) is deployed and a companion vendor due-diligence process is needed.
- Política de Classificação da Informação: relevant if team grows or ISO 27001 / SOC 2 is pursued.
- Plano de Continuidade de Negócios / DRP formal document: relevant if client contracts require it or enterprise due diligence asks for it.
- RIPD: monitor; not currently triggered.
- Termo de Consentimento templates: only if consent is added as a legal basis in any processing activity.
