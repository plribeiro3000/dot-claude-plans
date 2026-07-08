# Auxiliary source — LGPD international transfer (arts. 33-36), ANPD Resolução 19/2024, and the cloud/SaaS transfer concept

All fetched/searched 2026-07-07.

---

## A. LGPD (Lei 13.709/2018), Capítulo V — Da Transferência Internacional de Dados

Text assembled from WebSearch results citing lgpd-brasil.info, jusbrasil.com.br, and modeloinicial.com.br (the Planalto.gov.br primary-source fetch failed with a connection reset; the text below is corroborated by multiple independent secondary transcriptions of the official law text, but is **not independently verified against the Planalto primary source in this spike** — flagged accordingly).

**Art. 33** — A transferência internacional de dados pessoais somente é permitida nos seguintes casos:
- I - para países ou organismos internacionais que proporcionem grau de proteção de dados pessoais adequado ao previsto nesta Lei;
- II - quando o controlador oferecer e comprovar garantias de cumprimento dos princípios, dos direitos do titular e do regime de proteção de dados previstos nesta Lei, na forma de: (a) cláusulas contratuais específicas para uma determinada transferência; (b) cláusulas-padrão contratuais; (c) normas corporativas globais; (d) selos, certificados e códigos de conduta regularmente emitidos;
- III through VI — international legal cooperation (public authorities), protection of life/physical integrity, ANPD authorization, international cooperation agreements between public entities;
- VII - quando a transferência for necessária para a execução de política pública ou atribuição legal de serviço público;
- VIII - quando o titular tiver fornecido o seu consentimento específico e destacado para a transferência, com informação prévia sobre o caráter internacional da operação;
- IX - quando necessário para atender as hipóteses previstas nos incisos II, V e VI do art. 7º desta Lei.

**Art. 34** — O nível de proteção de dados do país estrangeiro ou do organismo internacional será avaliado pela ANPD, que levará em consideração: as normas gerais e setoriais da legislação em vigor no país de destino; a natureza dos dados; a observância dos princípios gerais e direitos dos titulares; a adoção de medidas de segurança; a existência de garantias judiciais/institucionais; outras circunstâncias específicas da transferência.

**Art. 35** — A definição do conteúdo de cláusulas-padrão contratuais, bem como a verificação de cláusulas contratuais específicas, normas corporativas globais ou selos/certificados/códigos de conduta, é atribuição da ANPD.

**Art. 36** — Alterações nas garantias apresentadas como suficientes (art. 33, II) devem ser comunicadas à ANPD antes de sua implementação, podendo a ANPD vedar a transferência caso a alteração implique risco à proteção de dados.

---

## B. Resolução CD/ANPD nº 19/2024

WebSearch-derived summary (multiple corroborating law-firm sources: Mayer Brown, Tauil & Chequer, GTLawyers, Opice Blum — not independently fetched as primary PDF text in this spike):

> "The Resolution CD/ANPD nº 19/2024 was published in the Official Journal on August 23, 2024, approving the Regulation on International Data Transfers... regulates articles 33 to 36 of the LGPD, establishing procedures and rules for recognizing the adequacy of other countries or international organizations, as well as disciplining contractual mechanisms for conducting international personal data transfers."

> "Controllers using contractual clauses to conduct international data transfers must incorporate the standard contractual clauses approved by ANPD into their respective contractual instruments within twelve months" (grace period ended August 23, 2025, per Mayer Brown's later publication "Fim do Período de Graça da Resolução CD/ANPD nº. 19/2024").

**United States adequacy status** (WebSearch-derived, dponet.com summary, not independently fetched):

> "Regarding the United States specifically, the vast majority of international data transfers have as their destination countries that still do not have recognition of adequacy by ANPD, and the main one is the United States... the perspective that the US will be included in the list of countries with adequate protection is, in the current scenario, quite remote."

**Significance**: since the US (where Anthropic is headquartered and processes data) has **no ANPD adequacy decision**, art. 33-I is not available as a legal basis for a 4Shark→Anthropic transfer. The applicable path is art. 33-II — contractual guarantees, most practically the ANPD Standard Contractual Clauses from Resolução 19/2024 (or Anthropic's own DPA, if its clauses satisfy the ANPD's "cláusulas contratuais específicas" or "cláusulas-padrão" standard).

---

## C. Does the transfer concept apply even to ephemeral/inference-only processing?

**URL**: https://www.conjur.com.br/2024-dez-07/armazenamento-em-nuvem-configura-transferencia-internacional-de-dados/ (fetched directly, verbatim quotes below)

> "transferência" (transfer) is defined as "toda operação de tratamento por meio do qual um agente de tratamento transmite, compartilha ou disponibiliza acesso a dados pessoais a outro agente" [any data processing operation where one agent transmits, shares, or provides access to personal data to another agent]

> "os casos de cloud computing configuram uma transmissão de dados para o servidor localizado no exterior ou, no mínimo, uma disponibilização de acesso aos dados guardados na nuvem do provedor" [cloud computing instances constitute either transmission of data to foreign servers or, at minimum, provision of access to data stored in the provider's cloud]

> the characterization applies broadly because of "a extrema abrangência da definição de tratamento de dados pessoais na LGPD" [the extremely broad scope of the LGPD's personal data processing definition] — the article's conclusion (per the fetch summary) is that this applies "whether permanent storage or temporary processing."

Corroborating WebSearch summary (same theme, independent secondary source not separately fetched):

> "considering the broad scope of the definition of personal data treatment in the LGPD, cloud computing cases can be understood as constituting transmission of data to a server located abroad or, at minimum, making data stored on the provider's cloud accessible—which characterizes international data transfer and subjects the operation to regulation requirements."

**Significance — this is the crux finding for the engineer's question**: LGPD's transfer concept turns on *transmission or access*, not on *retention duration*. This means an art. 33 legal basis (SCC/DPA) is required for **both** "inference-only, ephemeral, ZDR" traffic **and** "files persisted on vendor cloud storage" — sending a single prompt to Anthropic's API already triggers the international-transfer requirement, because it transmits data to a foreign processor, however briefly. What changes between the two modes is NOT whether art. 33 applies, but:
1. The volume/duration of PII sitting on infrastructure 4Shark does not control (retention/storage-limitation exposure — LGPD art. 6º, X, "não conservação" beyond necessity);
2. The practical blast radius if Anthropic's storage layer is breached, subpoenaed, or subject to a foreign legal process;
3. The residual audit surface (persisted files are a discoverable artifact on a system 4Shark cannot inspect; ephemeral inference is not).
