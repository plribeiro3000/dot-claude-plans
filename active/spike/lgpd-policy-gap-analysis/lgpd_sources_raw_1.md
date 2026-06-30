# LGPD Policy Gap Analysis — Raw Source Notes

Collected during research phase, 2026-06-24.

---

## Source 1: ANPD — Relatório de Impacto à Proteção de Dados Pessoais (RIPD)
URL: https://www.gov.br/anpd/pt-br/canais_atendimento/agente-de-tratamento/relatorio-de-impacto-a-protecao-de-dados-pessoais-ripd

Governing articles: 5(XVII), 38, 55-J(XIII), plus 4(§3), 10(§3), 32.

Key finding: "O controlador é o agente de tratamento responsável pela elaboração do RIPD" — obligation is on **controllers only**, not operators.

Triggers: high-risk treatments, legitimate-interest basis (art. 10 §3), public-security operations (art. 4 §3), government entities (art. 32), ANPD demand.

Verdict: RIPD is NOT an obligation for operators acting purely as operators. When 4Shark acts simultaneously as controller of its own employee data, it could be triggered.

---

## Source 2: LGPD Brasil — Artigo 37 (RoPA)
URL: https://lgpd-brasil.info/capitulo_06/artigo_37

Verbatim: "O controlador e o operador devem manter registro das operações de tratamento de dados pessoais que realizarem, especialmente quando baseado no legítimo interesse."

Verdict: RoPA is **mandatory for both controllers and operators** under art. 37.

---

## Source 3: LGPD Brasil — Artigo 39 (Operator obligations)
URL: https://lgpd-brasil.info/capitulo_06/artigo_39

Verbatim: "realize the treatment according to the instructions furnished by the controller, which will verify the observance of its own instructions and norms on the matter."

The article does not explicitly mandate a written contract in its text, but the instruction relationship implies documentation. Legal commentary (Kuster Machado 404, Farina & Antunes) consistently treats the DPA as "legally required" flowing from arts. 37 + 39 combined.

---

## Source 4: Legrow Law — LGPD 2026 tech companies
URL: https://legrowlaw.com/gpd-2026-empresas-tecnologia/

Common gaps: "Operating without DPA with these vendors is among the most common irregularities found during audits."

Mandatory according to this source: DPO designated with functional contact, functional DSR channel, updated privacy policy reflecting actual product, treatment operations registry, DPAs with all third-party vendors.

---

## Source 5: Bcompliance — Canal LGPD fiscalização ANPD (May 2026)
URL: https://blog.bcompliance.com.br/2026/05/09/sancoes-anpd-canal-lgpd-fiscalizacao/

ANPD explicitly verified the absence of effective communication channels among 20 major companies in December 2024, making this a primary inspection priority.

Documents ANPD checks: data mapping records, legal basis documentation, DPO appointment + functional contact, privacy policy, incident response plan, DSR channel records.

---

## Source 6: LGPDPro — Fiscalização 2025
URL: https://lgpdpro.com.br/fiscalizacao-lgpd-2025/

"conformidade não é PDF. É processo, evidência e rastreabilidade."

What inspectors request: updated operations registry with audit trails, operator contracts with clear data protection obligations, international transfers mapped and justified, proof of legal basis per purpose, incident response procedures.

Common gaps: unmapped supplier/suboperator ecosystems, undocumented legal bases, generic RIPD without real risk analysis.

---

## Source 7: ANPD — Resolução 19/2024 — International Data Transfers
URL: https://www.gov.br/anpd/pt-br/assuntos/noticias/resolucao-normatiza-transferencia-internacional-de-dados

Published: August 23, 2024. Grace period ended: August 23, 2025.

Mechanism required: Standard Contractual Clauses (SCCs) approved by ANPD must be incorporated into contracts within 12 months of publication (deadline passed).

Does NOT require a standalone "Política de Transferência Internacional" document explicitly. However, compliance requires: (a) mapping all international transfers, (b) incorporating SCCs into existing DPAs/contracts with cloud providers, (c) documentation of legal basis for each transfer.

---

## Source 8: ANPD Cookie Guide summary
URL: https://goadopt.io/blog/anpd-cookies-guia-orientativo-cookies-protecao-dados-pessoais/

"A Cookie Policy is mandatory for websites using cookies under LGPD." Must contain: specific purposes, retention periods, third-party sharing details, information per LGPD art. 9.

Key nuance: Strictly necessary cookies do NOT require prior consent; non-necessary cookies require opt-in consent. But ANY site using cookies must have a cookie notice/policy regardless of cookie type.

---

## Source 9: Migalhas — BCP and LGPD
URL: https://www.migalhas.com.br/depeso/338658/nem--so--de-privacidade-vive-a-lgpd--a-importancia-do-plano-de-continuidade-de-negocios

BCP is NOT explicitly mandated by LGPD. Art. 6(VII) security obligations + arts. 33(II)(d) + 50 imply good security practices including availability. ABNT NBR ISO 22301:2020 is the referenced framework. Verdict: best-practice, not a direct legal requirement.

---

## Source 10: Conjur — Gestão de Fornecedores (Feb 2024)
URL: https://www.conjur.com.br/2024-fev-21/a-importancia-da-gestao-de-fornecedores-para-o-cumprimento-da-lgpd/

No specific LGPD articles cited for a formal supplier management policy document. Framed as preventive risk management. "98% das organizações têm relacionamento com pelo menos um terceiro que sofreu uma violação." Three-phase framework: pre-contract due diligence, during-contract monitoring, post-contract data deletion.

Verdict: A formal written Política de Gestão de Fornecedores is best-practice, not an explicit legal requirement. The DPA requirement (arts. 37+39) is the legal anchor, not a policy document.

---

## Source 11: Perallis Security — Classificação da Informação e LGPD
URL: https://www.perallis.com/news/o-que-e-classificacao-da-informacao-e-como-ela-se-torna-critica-com-a-lgpd

Classification framed as "best practice necessary for compliance" rather than an explicitly mandated requirement. Aligned with ISO 27001. No LGPD articles cited as specifically mandating a classification policy.

Verdict: Recommended/best-practice under the umbrella of art. 46 security obligations, not a standalone legal requirement.

---

## Source 12: LGPD Brasil — Canal de atendimento titulares
URL: https://lgpdbrasil.com.br/canal-de-atendimento-aos-titulares-e-garantia-dos-direitos-fundamentais/

Art. 18 LGPD: nine rights that controllers must enable through channels. Art. 41(I): DPO responsible for "accepting, receiving and analyzing data subject messages." Mandatory 15-day response timeframe. Applies to controllers, not operators directly. No specific format mandated.

---

## Source 13: Reisaraujo — SaaS DPA
URL: https://reisaraujo.com.br/obrigatoriedade-legal-seu-contrato-de-licenca-de-software-saas-exige-clausulas-de-protecao-de-dados

Two implementation options for operators: (a) data protection clauses within the standard service/license agreement, or (b) a standalone DPA document. Both satisfy the underlying legal obligation. DPA format is the standard for higher-risk or international contracts.

---

## Source 14: Machertech — LGPD Aviso vs Política de Privacidade
URL: https://www.machertecnologia.com.br/lgpd-aviso-privacidade-versus-politica-privacidade/

ANPD prefers the term "aviso de privacidade" for the external/public-facing document. "Política de Privacidade" is used by market convention and often is the same thing in practice. Resolution CD/ANPD nº 20/2024 published ANPD's own internal privacy policy. DPO guide (Dec 2024) recommends DPO participate in creating both the internal privacy policy and the external privacy notice.

---

## Source 15: Farina & Antunes — Contrato Controlador-Operador
URL: https://farinaeantunes.com.br/blog/contrato-entre-controlador-e-operador-na-lgpd-uma-salvaguarda-para-a-protecao-de-dados/

"O contrato estabelece claramente quem é responsável pelo quê." Contract must include: LGPD compliance clauses, data security measures operator must implement, processing limitations (operator follows controller instructions only). Described as "legally mandatory" and "salvaguarda essencial."

---

## Source 16: LGPDPro / ANPD enforcement 2025 — priority sectors
URL: https://lgpdpro.com.br/fiscalizacao-lgpd-2025/

Priority enforcement sectors: health (10+ actions planned through Dec 2026), education, e-commerce. Technology/SaaS companies not named as a primary enforcement target in 2025, but operator-controller contract gaps are consistently flagged.
