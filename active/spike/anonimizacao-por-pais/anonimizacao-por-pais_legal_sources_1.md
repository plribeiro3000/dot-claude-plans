# Auxiliary file — anonimizacao-por-pais spike

Legal sources consulted for the Brazil-vs-Mexico retention-window research. Local-jurisdiction
research about country-specific regulation stays in the language of the primary sources per
`~/.claude/docs/LANGUAGE-POLICY.md` — quotes below are kept in the original Portuguese/Spanish.
Every quote here was independently fetched (`WebFetch`) and the substring below is confirmed
present at that specific URL, unless marked UNVERIFIED.

## Brazil

### LGPD art. 16 (Lei 13.709/2018) — VERIFIED

URL: https://lgpd-brasil.info/capitulo_02/artigo_16

Quote (main rule): "Os dados pessoais serão eliminados após o término de seu tratamento"

Quote (retention exceptions): "cumprimento de obrigação legal ou regulatória pelo controlador"
/ "estudo por órgão de pesquisa, garantida, sempre que possível, a anonimização dos dados
pessoais" / "transferência a terceiro, desde que respeitados os requisitos de tratamento de
dados" / "uso exclusivo do controlador, vedado seu acesso por terceiro, e desde que
anonimizados os dados"

### CLT art. 11 (Decreto-Lei 5.452/1943, redação da Lei 13.467/2017) — UNVERIFIED

Attempted URLs (all failed to fetch in this session — network errors, not content errors):
- http://www.planalto.gov.br/ccivil_03/decreto-lei/del5452.htm (ECONNRESET, twice)
- https://www.jusbrasil.com.br/topicos/10765655/artigo-11-do-decreto-lei-n-5452-de-01-de-maio-de-1943 (HTTP 403)
- https://tdn.totvs.com/pages/releaseview.action?pageId=315901712 (HTTP 403)
- https://brasil.mylex.net/legislacao/consolidacao-leis-trabalho-clt-art11_80862.html (DNS failure)
- https://www.normaslegais.com.br/legislacao/clt/clt-art11.htm (page had no article text)
- https://www.guiatrabalhista.com.br/clt/clt5a20.htm (HTTP 404)

Per Citation Discipline rule 4 (UNVERIFIED tag), the commonly-cited text of CLT art. 11 — "A
pretensão quanto a créditos resultantes das relações de trabalho prescreve em cinco anos para
os trabalhadores urbanos e rurais, até o limite de dois anos após a extinção do contrato de
trabalho" — could NOT be independently confirmed by a direct fetch in this session, despite
appearing consistently across multiple `WebSearch` result summaries (jusbrasil.com.br,
solides.com.br, iep.adv.br). This UNVERIFIED external claim does not sustain a Finding on its
own. It is corroborated internally, however: 4Shark's own runbook already documents and relies
on this "labor quinquenal" figure as one component of the ~5.5-year Brazilian window — see
`~/.claude/docs/runbooks/compliance/LGPD-DATA-ERASURE.md:72-73`, quoted directly in SPIKE.md
(an internal, not external, citation — already verified by reading that file in full).

## Mexico

### Código Civil Federal art. 1159 — general 10-year civil-action prescription — VERIFIED

URL: https://www.conceptosjuridicos.com/mx/codigo-civil-articulo-1159/

Quote: "Se necesita el lapso de diez años, contado desde que una obligación pudo exigirse,
para que se extinga el derecho de pedir su cumplimiento."

This is the general ("fuera de los casos de excepción") prescription period for personal
actions ("acciones personales") under Mexican federal civil law — the closest documented
external analog of the "civil debt" component 4Shark's own runbook cites for the Brazilian
5.5-year figure (`LGPD-DATA-ERASURE.md:72`: "the ~5-year reach of claims (labor quinquenal,
CDC art. 27, civil debt, fiscal)").

### Código Fiscal de la Federación (CFF) arts. 30 and 67 — accounting retention — VERIFIED

URL: https://contadormx.com/plazos-para-conservacion-de-la-contabilidad-y-documentacion-del-cff/

Quote (general rule): "cinco años" — taxpayers must preserve accounting documentation for
five years, counted from the date the related tax declarations were filed or should have been
filed (CFF art. 30).

Quote (extended-effects exception): "For transactions with prolonged effects (such as fiscal
loss carryforwards), the five-year clock begins only after the final declaration showing the
completion of those effects is filed" — a fiscal loss amortized over up to 10 years extends
the retention obligation for the originating documentation across that same 10-year
amortization period.

Quote (non-compliance exception, CFF art. 67): the tax authority's inspection window extends
to "ten years" when the taxpayer failed to register with the Federal Taxpayers Registry,
failed to maintain accounting records for the legally required period, did not file an
obligatory annual return, or omitted required VAT/IEPS information.

### LFPDPPP (Ley Federal de Protección de Datos Personales en Posesión de los Particulares) — VERIFIED

URL: http://www.ordenjuridico.gob.mx/Documentos/Federal/html/wo83178.html

Quote (definition of "bloqueo"): "La identificación y conservación de datos personales una vez
cumplida la finalidad para la cual fueron recabados, con el único propósito de determinar
posibles responsabilidades..."

Quote (art. 25 — blocking period tied to the underlying relationship's own prescription): "El
periodo de bloqueo será equivalente al plazo de prescripción de las acciones derivadas de la
relación jurídica que funda el tratamiento..."

Significance: Mexico's own data-protection statute does not set a single fixed number of years
— it explicitly ties the post-purpose retention/blocking period to whatever legal prescription
period governs the underlying relationship (labor, civil, fiscal, etc.), the same
composite-reach logic 4Shark's own runbook already uses to justify the Brazilian ~5.5-year
figure. This is external, structural support for a country-configurable (rather than a single
hardcoded) retention window — the Mexican statute itself does not point to one universal
number, it points to "whatever the underlying relationship's own prescription is in that
jurisdiction."

### Ley Federal del Trabajo (LFT) arts. 804 and 516-522 — labor document/claim windows — summary-level, not independently fetch-verified

`WebSearch` result summaries (not a direct `WebFetch` quote-confirmation) indicate LFT
labor-specific windows are considerably SHORTER than 10 years: payroll/attendance records kept
"durante el último año de trabajo y un año más tras su terminación" (LFT art. 804), and
dismissal-related worker actions prescribing in as little as two months (LFT arts. 516-522).
Because these are search-summary attributions rather than confirmed literal quotes from a
directly fetched URL, they do NOT sustain a Finding under Citation Discipline rule 1
(quote-or-drop) — they are recorded here only as a signal that the "10 years for Mexico"
figure the engineer was given does NOT appear to trace directly to Mexican LABOR law the way
Brazil's ~5.5-year figure traces to CLT art. 11's labor quinquenal. The Código Civil Federal
art. 1159 general civil prescription (10 years, verified above) is the strongest documented
candidate for where "10 years" comes from.
