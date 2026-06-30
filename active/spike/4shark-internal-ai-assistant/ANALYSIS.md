# ANALYSIS — LGPD document impact of adding AI sub-processors (4Shark internal assistant)

> Composed by main from the Q5 research sources in `4shark-internal-ai-assistant_doc_10.txt` (verbatim legal citations preserved). Companion to `SPIKE.md` (research) and `PLAN.md` (decisions). Legal-quote text is from a secondary site (`lgpd-brasil.info`) because `planalto.gov.br` was unreachable during research — confirm against planalto before any binding legal decision.

## The question

When the internal assistant sends clients' employee PII to AI vendors (Anthropic for the LLM; Deepgram/ElevenLabs for L1 voice), which 4Shark privacy/compliance documents must be created or updated, and which are 4Shark's responsibility versus the client's?

## The frame that decides everything: 4Shark is the OPERADOR, not the controller

The data chain is: **CLIENT (controlador) → 4Shark (operador) → AI vendor (sub-operador)**.

This is the same chain 4Shark already runs with AWS as a sub-operador — the AI vendors just extend it. Because 4Shark is the *operador* of the clients' employee data (the client company is the *controlador*), the heavy "data subject facing" obligations sit primarily with the **client**, and 4Shark's duties are the operator-side ones.

- **Primarily the client's (controlador) responsibility:** informing the data subjects (the Aviso de Privacidade), the legal basis for processing, the controller-side ROPA, and the RIPD/DPIA. 4Shark's role here is to *give the client the information they need* to update their own documents — not to author them.
- **4Shark's own (operador) responsibility:** maintain its operator-side ROPA, keep the sub-processor chain contractually back-to-back (a DPA in force with each AI vendor), and check whether the client DPA requires authorization/notification before adding a new sub-operador.

`Art. 39 (verbatim)`: *"O operador deverá realizar o tratamento segundo as instruções fornecidas pelo controlador, que verificará a observância das próprias instruções e das normas sobre a matéria."* — the controller verifies the operator; so clients must be **informed** of the new AI sub-operadores so they can verify the arrangement.

## Per-document checklist

| # | Document | Legal basis | Update or Create | Mandatory / Recommended | Whose responsibility | What changes |
|---|---|---|---|---|---|---|
| 1 | **ROPA — Registro das Operações de Tratamento** | LGPD Art. 37 (binds *both* controlador and operador) | **Update** | Mandatory | **4Shark** (operator-side entry) + client (controller-side) | New entry: purpose (internal support assistant), data subjects (clients' employees), data categories (names, CPF, identifiers, HR indicators), recipients (Anthropic; ElevenLabs/Deepgram if voice), transfer basis (Art. 33 II / CPCs), security measures (VPN, Keycloak, PII minimization) |
| 2 | **Sub-processor list + authorization to sub-contract** | LGPD Art. 39 | **Update** (+ notify clients) | Mandatory | **4Shark** notifies; client verifies | Add Anthropic (+ Deepgram/ElevenLabs). Confirm whether the client DPA grants *general* authorization with notice, or requires *prior written* authorization for each new sub-operador |
| 3 | **DPA — 4Shark (operador) ↔ clients (controladores)** | LGPD Art. 39 + contractual practice | **Update / review the clause** | Mandatory if the clause requires it | **4Shark** (review existing contracts) | Check the sub-processor clause: does adding an AI sub-operador require notifying or obtaining authorization from each client? This is the most contract-specific item |
| 4 | **Privacy notice — Aviso de Privacidade** | LGPD Arts. 6 (transparência), 9 (information to data subject) | **Update** | Mandatory | **Client (controlador)** — 4Shark supplies the inputs | The notice that *employees* receive is the client's. 4Shark must give clients: purpose of AI processing, vendor identities, transfer destination (US), transfer mechanism (CPCs) |
| 5 | **RIPD / DPIA — Relatório de Impacto** | LGPD Art. 38 (directed at the *controlador*) | **Create** (likely) | ANPD-determinable / recommended for high-risk | **Client (controlador)** — 4Shark supplies the inputs | Art. 38 fragment: *"A autoridade nacional poderá determinar ao controlador que elabore relatório de impacto…"*. Employee PII + AI is a plausible high-risk trigger. 4Shark prepares: processing description, data categories, sub-processor chain, security measures, transfer basis |
| 6 | **International-transfer instrument (standard clauses)** | CD/ANPD Resolution 19/2024 (cláusulas-padrão) | **Execute / attach** | Mandatory for the transfer to be lawful | **4Shark** (with each vendor) | On top of each vendor DPA, the ANPD standard-clause regime applies. Open legal question: whether the EU SCCs in the Anthropic DPA satisfy the LGPD CPC requirement — unsettled, needs counsel |
| 7 | **DPA with each AI vendor** | LGPD Art. 33 II + Art. 39 chain | **Execute / confirm** | Mandatory | **4Shark** | See vendor status below |

## Vendor DPA status (the actionable gate)

| Vendor | LGPD named in DPA? | Transfer mechanism | Status | Action |
|---|---|---|---|---|
| **Anthropic** (LLM) | Not explicitly — DPA covers "applicable data protection laws"; LGPD implied | EU SCCs Module 2 (whether they satisfy LGPD CPCs is legally unsettled) | **Ready** — DPA auto-incorporated on commercial-terms acceptance | Confirm with counsel that EU SCCs are accepted for the LGPD transfer |
| **ElevenLabs** (TTS) | **Yes — explicitly**: *"Brazil's General Data Protection Law (Lei Geral de Proteção de Dados – LGPD)"* | **"Brazil SCCs"** incorporated; 30-day advance notice for new sub-processors | **Available** — accept the public DPA at elevenlabs.io/dpa | Strongest LGPD posture of the three — accept the DPA |
| **Deepgram** (STT) | **Not mentioned** — page covers SOC 2, GDPR, CCPA, HIPAA, PCI only | Not confirmed for Brazil | **UNVERIFIED — BLOCKING** | Must request a DPA with LGPD coverage from Deepgram's account executive *before* any employee PII flows through it |

## What this means in one paragraph

Adding the AI vendors is **document maintenance, not a new compliance regime** — the same paperwork pattern 4Shark already owns for AWS, extended to three more sub-processors. 4Shark's direct to-do list is short: update its operator-side ROPA, review the client DPA's sub-processor clause (notify/authorize as required), and get a DPA in force with each vendor. The heavier documents (privacy notice, RIPD) are the **client's** to author — 4Shark's job is to hand them the processing details. Nothing here is "wrong" today; it is additions and reviews.

## Blockers and open items

- **Deepgram DPA (BLOCKING for the voice path):** no LGPD coverage confirmed on the public page. Confirm a DPA with a Brazilian transfer mechanism before sending PII through Deepgram. If it cannot be obtained, pick a different STT provider for pt-BR or keep voice text-only.
- **EU-SCC-vs-LGPD question (legal, not engineering):** whether the EU SCCs in the Anthropic DPA satisfy the LGPD CPC requirement — unsettled, needs counsel. Same question already applies to existing US sub-processors.
- **Client DPA clause (per-contract):** the sub-processor clause varies by client contract — review each.

## Evidence caveats

- LGPD article text (Arts. 37, 39, 38) quoted from `lgpd-brasil.info` (secondary) — `planalto.gov.br` was unreachable. Confirm at planalto before binding decisions.
- Arts. 6 and 9 returned only English paraphrases, not verbatim statutory text — no verbatim citation made for those two.
- RIPD trigger list (ANPD Resolution 2/2022: large-scale, sensitive data, vulnerable groups, emerging tech) is from prior research context, **UNVERIFIED** against a fetched URL — confirm at anpd.gov.br.
- ElevenLabs and Deepgram facts fetched this/prior session; Anthropic DPA facts cross-referenced from `doc_8.txt`.
