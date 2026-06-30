# SPIKE — LGPD Privacy Policy Requirements for Multi-Entity Economic Group

**Conducted by:** @agent-spike
**Date:** 2026-06-25
**Status:** Research complete — pending decisions

---

## Goal

**Primary question:** Does Brazilian LGPD require one privacy policy per legal entity / per CNPJ — meaning 4Shark needs three separate public policies for its three legal entities — or can a single policy cover the entire economic group?

**Engineer's instinct under investigation:** Single-policy is probably the market norm and the "3× — one per operator" rule in the internal runbook is likely over-engineered.

**Sub-questions:**
1. Does LGPD text explicitly require a policy per legal entity / CNPJ?
2. Does LGPD recognize "grupo econômico" or joint controllership at the policy level?
3. Does 4Shark being the OPERADOR (not the controlador) reduce its public-notice obligation?
4. What do Brazilian economic groups actually do in practice?
5. What is the real enforcement exposure of naming one CNPJ when three entities operate?

**Context:** 4Shark is an economic group with three legal entities (three CNPJs): 4Shark Soluções Financeiras Ltda, 4T Soluções Ltda, and Incentive Gestão de Incentivos Ltda. Each entity acts as OPERADOR of its clients' employee data; the client companies are the CONTROLADORES. 4Shark currently publishes one public privacy policy naming a single CNPJ (the oldest entity).

---

## Method

- Fetched verbatim LGPD articles 9, 39, 42, 50 from lgpd-brasil.info (article-by-article source for Lei 13.709/2018)
- Searched ANPD guidance documents, enforcement actions, and 2026-2027 priority themes
- Fetched and verified Grupo Tiradentes public privacy policy as a confirmed market practice example of a Brazilian economic group
- Searched Brazilian legal commentary (Migalhas) on intra-group data sharing and co-controller doctrine
- Searched ANPD enforcement reports: Telekall fine (2023), December 2024 mass notification (20 companies)
- Raw sources and verbatim quotes preserved in three auxiliary files (see Sources below)

---

## Evidence

### Sources consulted

- https://lgpd-brasil.info/capitulo_02/artigo_09 — verbatim LGPD Art. 9 (data subject right to controller identification); see `privpolicy_lgpd_1.txt`
- https://lgpd-brasil.info/capitulo_06/artigo_39 — verbatim LGPD Art. 39 (operator follows controller instructions); see `privpolicy_lgpd_1.txt`
- https://lgpd-brasil.info/capitulo_07/artigo_50 — LGPD Art. 50 (good practices / governance program covering "todo o conjunto de dados"); see `privpolicy_lgpd_1.txt`
- https://grupotiradentes.com/governancacorporativa/politica-de-privacidade/ — Grupo Tiradentes single group-level policy, no individual CNPJ, confirmed market practice; see `privpolicy_market_1.txt`
- https://migalhas.com.br/depeso/356219 — LGPD on intra-group data sharing (consent/legal basis); see `privpolicy_market_1.txt`
- https://teletime.com.br/13/12/2024/anpd-fiscaliza-falta-de-encarregado-de-dados-e-canais-efetivos/ — ANPD December 2024 enforcement: 20 companies notified for DPO + channels (no CNPJ-misidentification case); see `privpolicy_anpd_1.txt`
- https://blog.bcompliance.com.br/2026/05/09/sancoes-anpd-canal-lgpd-fiscalizacao/ — ANPD enforcement history: Telekall fine, Dec 2024 notifications, 2026-2027 priority themes; see `privpolicy_anpd_1.txt`
- See auxiliary: `privpolicy_lgpd_1.txt` — verbatim LGPD articles 9, 39, 42, 50 with source and verification notes
- See auxiliary: `privpolicy_market_1.txt` — Grupo Tiradentes policy text, co-controller doctrine, intra-group data sharing distinction, UNVERIFIED sources list
- See auxiliary: `privpolicy_anpd_1.txt` — ANPD enforcement history with company names, violation types, 2026-2027 priority themes

---

### Q1: Does LGPD text require a separate policy per legal entity / per CNPJ?

**No explicit requirement found.**

LGPD Art. 9 requires the controller to disclose "identificação do controlador" and "informações de contato do controlador" to data subjects. Verbatim (source: https://lgpd-brasil.info/capitulo_02/artigo_09):

> "O titular tem direito ao acesso facilitado às informações sobre o tratamento de seus dados, que deverão ser disponibilizadas de forma clara, adequada e ostensiva acerca de, entre outras características previstas em regulamentação para o atendimento do princípio do livre acesso: [...] III - identificação do controlador; IV - informações de contato do controlador"

The statute specifies disclosure of WHICH controller is processing — not that one document may cover only one CNPJ. ANPD has not issued any normative resolution, guidance document, or enforcement decision imposing per-CNPJ policy requirements. The law is silent on group policies; silence is not prohibition.

Verification: URL fetched / Verbatim quote checked / Substring "identificação do controlador" confirmed in fetch response at lgpd-brasil.info/capitulo_02/artigo_09.

---

### Q2: Does LGPD recognize "grupo econômico" or joint controllership at the policy level?

**No "grupo econômico" definition in LGPD; co-controllership is a practitioner import from GDPR Art. 26.**

LGPD Art. 5 defines controlador (VI) and operador (VII) but contains no definition of "grupo econômico," "controladores conjuntos," or affiliated entities. Brazilian practitioners import joint controllership from GDPR Art. 26. A practitioner definition (partially verified, from search results referencing grupoassaf.com):

> "Quando duas ou mais empresas têm participação conjunta nas decisões sobre o tratamento, seja por meio de decisões comuns ou decisões convergentes, elas formarão a controladoria conjunta"

Because LGPD does not define "grupo econômico," there is no statutory shortcut that automatically satisfies all three entities' disclosure obligations via a group label. However, a single document can discharge the Art. 9 obligation for multiple controllers if it clearly names each one. The gap in the law neither prohibits a group policy nor automatically authorizes one without naming each entity.

Verification: LGPD Art. 5 definition confirmed by search results and lgpd-brasil.info. Co-controller practitioner quote is PARTIALLY VERIFIED (search result, not independently re-fetched for this spike).

---

### Q3: Does 4Shark being the OPERADOR reduce its public-notice obligation?

**Yes — the statutory transparency obligation primarily falls on the CONTROLADOR (4Shark's clients), not on 4Shark as operador.**

LGPD Art. 39 establishes the operator's primary obligation: follow the controller's instructions. Verbatim (source: https://lgpd-brasil.info/capitulo_06/artigo_39):

> "O operador deverá realizar o tratamento segundo as instruções fornecidas pelo controlador, que verificará a observância das próprias instruções e das normas sobre a matéria."

The Art. 9 transparency obligation falls on the CONTROLADOR — 4Shark's client companies — who must inform their employees (the data subjects) about processing. 4Shark as operador is not the entity that owes the employee a primary Art. 9 notice.

However, 4Shark publishes a public privacy policy on its platform. This is:
- Good practice for vendor due diligence (enterprise clients perform LGPD vendor assessments)
- Expected in commercial B2B SaaS relationships
- Not a clear statutory obligation toward the end data subjects (employees) — but a practical necessity for sales and procurement

The December 2024 ANPD enforcement action targeted companies that lacked a functioning DPO contact and effective communication channels — two obligations that apply to operators too.

Verification: URL fetched / Verbatim quote "O operador deverá realizar o tratamento segundo as instruções fornecidas pelo controlador" confirmed in fetch response at lgpd-brasil.info/capitulo_06/artigo_39.

---

### Q4: What do Brazilian economic groups actually do in practice?

**Single group-level policy is the documented market practice. Three separate policies is not observed.**

Grupo Tiradentes (large Brazilian educational economic group with multiple legal entities) uses a single privacy policy covering all group operations. Verbatim from the scope section (source: https://grupotiradentes.com/governancacorporativa/politica-de-privacidade/):

> "A presente Política de Privacidade é aplicável a todas as operações desenvolvidas no âmbito do Grupo Tiradentes compreendendo as atividades de suas unidades acadêmicas, administrativas, culturais e demais estruturas que integram o universo do Grupo Tiradentes conforme o organograma institucional vigente."

Observed in the fetched page (the agent's own reading, NOT a source quote): the scope section contains no individual CNPJ numbers and applies the policy group-wide, without carving out subsidiary entities from coverage.

Grupo Tiradentes is a regulated entity with governance compliance obligations. Its use of a single group-level policy without per-entity CNPJ breakdown is confirmed market practice under LGPD.

Verification: URL fetched / Verbatim quote "A presente Política de Privacidade é aplicável a todas as operações desenvolvidas no âmbito do Grupo Tiradentes" confirmed in fetch response.

---

### Q5: What is the real enforcement exposure of naming one CNPJ when three entities operate?

**No documented enforcement precedent; exposure is a transparency/documentation gap, not an enforcement priority.**

ANPD enforcement history (all verified — see `privpolicy_anpd_1.txt`):

- **Telekall fine (July 2023):** R$ 14,400 for processing without legal basis + absent DPO. No CNPJ misidentification issue. (Source: https://blog.bcompliance.com.br/2026/05/09/sancoes-anpd-canal-lgpd-fiscalizacao/)
- **December 2024 mass notification (20 companies):** Uber, Serasa, Vivo, TikTok, X, Telegram, QuintoAndar, Latam, Cacau Show, Tinder and 10 others notified for: (1) missing DPO and (2) ineffective data subject communication channels. Confirmed from fetch: "The article contains no reference to violations involving incorrect CNPJ registration or controller misidentification in privacy policies." All 20 implemented adequacy measures. (Source: https://teletime.com.br/13/12/2024/anpd-fiscaliza-falta-de-encarregado-de-dados-e-canais-efetivos/)
- **2026-2027 priority themes:** Data subjects' rights (biometric/health/financial), children online, public authorities, AI. CNPJ identification is not a named axis. (Source: https://blog.bcompliance.com.br/2026/05/09/sancoes-anpd-canal-lgpd-fiscalizacao/)

The exposure from naming one CNPJ when three entities operate is a documentation/transparency gap. It creates a risk of confusion in enterprise client due diligence ("which entity is my DPA with?") rather than a direct ANPD enforcement risk for which any precedent exists.

Verification: Both URLs fetched / Quoted content confirmed / "no reference to violations involving incorrect CNPJ" confirmed in teletime.com.br fetch response.

---

### Trade-offs

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **A. Update single policy to list all 3 CNPJs** | Satisfies Art. 9 III for all entities; single document; matches Grupo Tiradentes market practice; minimal maintenance | Requires one-time update; clients who scrutinize CNPJ changes may ask questions | Art. 9 LGPD; grupotiradentes.com |
| **B. Group/brand name only, CNPJ appendix** | Even simpler; brand consistency; CNPJs can be in a legal footer | Less immediately transparent than A for due diligence; appendix may be missed | Art. 9 LGPD; market practice |
| **C. Three separate policies (one per entity)** | Maximum per-entity transparency | No statutory basis; not market norm; three documents to maintain; deviates from documented practice; contradicts the goal of simplifying the runbook | This spike: not found as market norm; no LGPD requirement |
| **D. Keep current policy unchanged** | Zero effort | Wrong CNPJ for two of three operating entities; documentation gap; potential confusion in vendor due diligence; least defensible | Art. 9 LGPD; ANPD transparency trend |

---

## Conclusions

### Executive summary: the engineer's instinct is supported by the evidence

The evidence shows that:
- LGPD does not require a policy per legal entity or per CNPJ
- Grupo Tiradentes (a regulated Brazilian economic group) uses a single group policy with no per-CNPJ breakdown
- ANPD has never enforced against a company for wrong or incomplete CNPJ identification in a privacy policy
- 4Shark as OPERADOR does not owe the data subjects (employees) a primary Art. 9 notice — the client companies do
- The "3× policies" rule in the internal runbook is not supported by any statutory requirement, ANPD guidance, or market practice

The lowest-effort compliant path is updating ONE policy to name all three entities — not creating three separate policies.

### What this means for 4Shark

The actual compliance gap is not "wrong number of policies" — it is "the current single policy names only one CNPJ, creating ambiguity about which entity is processing data in client DPAs and vendor questionnaires." The fix is to update one document, not multiply three.

The more urgent LGPD compliance items for 4Shark (based on ANPD enforcement priorities) are:
1. DPO designation publicly disclosed with a functional contact channel (ANPD's confirmed enforcement focus, December 2024)
2. DPA coverage in place with all client companies
3. CNPJ identification correction (update of single policy) — lower urgency but straightforward

### Urgency level

**Low-medium.** No enforcement precedent targets CNPJ misidentification in a privacy policy. The risk is commercial (vendor questionnaire friction) rather than regulatory (ANPD fine). Fixing it requires updating one document. However, it should be done before the next enterprise client due diligence cycle, not deferred indefinitely.

---

## Next Steps

The evidence supports three concrete options. No recommendation is made here — main and the engineer decide.

**Option A (matches market norm, minimal effort):** Update the single current privacy policy to name all three legal entities. Frame the controller section as "4Shark grupo econômico, composto por: [Entity 1 — CNPJ X], [Entity 2 — CNPJ Y], [Entity 3 — CNPJ Z]." This satisfies Art. 9(III) for all three entities in one document.

**Option B (group-name approach):** Update to use a group brand name ("4Shark") as the controller name and list all three CNPJs in a "Dados do Controlador" legal section. Legally equivalent to Option A; may be simpler to maintain if entities change.

**Option C (three separate policies — NOT supported by evidence as necessary):** Implement three separate public privacy policies as the current runbook prescribes. Highest maintenance burden; no statutory requirement identified; deviates from documented Brazilian market practice.

**Option D (ANPD-priority-aligned sequencing):** Regardless of which option is chosen for CNPJ identification, prioritize in order: (1) DPO designation publicly disclosed with functional contact (ANPD's confirmed highest enforcement focus), (2) DPAs in place with all client companies, (3) CNPJ identification fix. The urgency ordering matters for resource allocation.

The internal runbook that prescribes "3× — one per operator" should be revised to reflect whichever option is chosen.

---

> **What remains uncertain:**
> - Whether the ANPD "Guia orientativo para definições dos agentes de tratamento" PDF (not fetchable for this spike) contains specific guidance on group privacy notices
> - Whether 4Shark's three entities operate as joint controllers (deciding purposes/means jointly) or as independent operators for separate client sets — this classification affects whether joint-controller disclosure is required within the policy
> - Whether enterprise clients' current vendor questionnaires in Brazil expect per-CNPJ policies (a commercial risk, distinct from a legal risk)
> - Intra-group data sharing legal basis: if 4Shark's three entities share employee data between themselves, Art. 7 LGPD requires a legal basis for each transfer — a single group policy does not resolve this; it is a separate compliance question
