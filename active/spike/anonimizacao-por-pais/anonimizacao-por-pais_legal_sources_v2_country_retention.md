# Auxiliary file (v2) — anonimizacao-por-pais spike

Legal sources consulted for the country-by-country data/records-retention research (Chile,
Colombia, Argentina, Peru, Panama, Guatemala, plus a generic/US reference). Brazil and Mexico
were already researched in v1 — see `anonimizacao-por-pais_legal_sources_1.md`; not repeated
here. Local-jurisdiction research about country-specific regulation stays in the language of the
primary sources per `~/.claude/docs/LANGUAGE-POLICY.md` — quotes below are kept in the original
Portuguese/Spanish/English. Every quote below was fetched (`WebFetch`) directly from the cited
URL and the substring is confirmed present at that URL, unless explicitly marked UNVERIFIED
(WebSearch-summary-only, not independently fetched — per Citation Discipline rule 4/quote-or-drop
these do NOT sustain a Finding on their own).

## Chile

### Dirección del Trabajo — 5-year post-termination retention of labor documentation — VERIFIED

URL: https://www.tributariolaboral.cl/610/w3-article-150975.html

Quote: "el tiempo durante el cual debe conservarse la documentación laboral debe ser de, a lo
menos, cinco años" — Dictamen N°3677/189 (06/11/2002), Dirección del Trabajo, Legal Division.

Cross-verified at a second URL:

URL: https://transtecnia.cl/noticias/cuanto-tiempo-debe-conservarse-la-documentacion-laboral/

Quote: "the time of conservation of labor documentation is of five years from the extinction of
the labor link" — Ord. N°834 (05/03/2021), Dirección del Trabajo, citing Dictamen Nº 3268/46
(22/08/2014): "at least sufficient to properly support labor and accounting
obligations...a space of time that, therefore, could not be less than the prescription periods
of each of the various rights and actions."

Significance: the 5-year figure is explicitly anchored to the LONGEST prescription period the
Dirección del Trabajo itself must be able to inspect — the previsional/social-security
contribution prescription — the same "longest reach of claims" logic 4Shark's own runbook uses
to justify the Brazilian ~5.5-year composite figure.

## Colombia — no single confident short-window figure

### Código Sustantivo del Trabajo (CST) art. 488 — 3-year labor-claims prescription — VERIFIED

URL: https://vlex.com.co/vid/prescripcion-materia-laboral-574724746

Quote: "Las acciones correspondientes a los derechos regulados en este código prescriben en tres
(3) años, que se cuentan desde que la respectiva obligación se haya hecho exigible..."

### Decreto 1072 de 2015, art. 2.2.4.6.13 — 20-year MANDATORY retention for SG-SST records — VERIFIED

URL: https://safetya.co/conservacion-informacion-laboral/

Quote: "Los siguientes documentos y registros, deben ser conservados por un periodo mínimo de
veinte (20) años" — applies to occupational-health profiles, exam results, environmental
monitoring, and training records (a narrower record category than the general personnel file).

### Archivo General de la Nación (AGN) guidance — 80-year retention for payroll/personnel file — VERIFIED but explicitly NON-mandatory for private companies

URL: https://safetya.co/conservacion-informacion-laboral/

Quote (payroll): "Tiempo de retención documental recomendado: 80 años." (first 2 years in active
file, 78 in central archive)

Quote (personnel file / historia laboral): "Tiempo de retención documental recomendado: 80 años
en el archivo de gestión."

The fetched page's own framing: these AGN-derived recommendations are noted as best practices
and NOT confirmed as legally mandatory for private employers (only the SG-SST 20-year figure
above is stated as a mandatory minimum by decree).

### Corte Constitucional Sentencia T-926 de 2013 — "indefinite" duty framing — NOT independently verified

The engineer-facing search summaries (not a direct fetch) attribute to this ruling the
proposition that a private employer's duty to preserve a worker's "historia laboral" is
indefinite/does not prescribe as a worker's right. The directly fetched `safetya.co` page did
NOT reference this sentencia at all when fetched. This claim is therefore UNVERIFIED per
Citation Discipline and does not sustain a Finding on its own — recorded here only as a signal
that a genuinely open-ended Colombian retention duty may exist in case law, separate from the
3-year CST art. 488 claims-prescription figure and the 20-year/80-year figures above.

**Significance for the spike:** Colombia does not reduce to one number the way Brazil/Mexico/
Chile do. The figures found span 3 years (claims prescription) → 20 years (mandatory SG-SST
subset) → 80 years (non-mandatory archival best practice for the general personnel/payroll
file) → possibly indefinite (unverified case-law framing). This is flagged as a country where a
single confident retention-window number was NOT found in this research.

## Argentina

### Ley de Contrato de Trabajo (LCT) art. 256 — 2-year labor-claims prescription — VERIFIED

URL: https://leyes-ar.com/ley_de_contrato_de_trabajo/256.htm

Quote: "Prescriben a los dos (2) años las acciones relativas a créditos provenientes de las
relaciones ind[ividuales de trabajo]"

### Código Civil y Comercial (CCyC) art. 2560 — 5-year generic civil prescription — VERIFIED

URL: https://leyes-ar.com/codigo_civil_y_comercial/2560.htm

Quote: "El plazo de la prescripción es de cinco años, excepto que esté previsto uno diferente en
la legislación local."

Significance: Argentina's 2015 civil-code reform (Ley 26.994) replaced the OLD Código Civil's
10-year general prescription with a 5-year generic default. This matters for any composite
"civil debt reach" comparison analogous to what 4Shark's runbook uses for Brazil/Mexico — in
Argentina that generic civil figure is 5 years, not 10.

### Extended tax/labor retention (~12 years combined) — NOT independently verified

A WebSearch summary of `sbsauditores.com.ar` states retention for tax/labor documentation "may
extend beyond the basic prescription period, potentially totaling almost 12 years in total when
considering interruptions or suspensions." Not independently fetch-confirmed — UNVERIFIED,
recorded as a signal only.

## Peru

### Ley 27321 — 4-year labor-claims prescription from termination — VERIFIED

URL: https://vlex.com.pe/vid/prescripcion-acciones-derivadas-laboral-373209386

Quote: "Las acciones por derechos derivados de la relación laboral prescriben a los 4 (cuatro)
años, contados desde el día siguiente en que se extingue el vínculo laboral."

### Código Civil art. 2001(1) — 10-year prescription for personal actions — VERIFIED

URL: https://www.infobae.com/peru/2026/05/31/la-prescripcion-de-deudas-en-peru-no-funciona-como-muchos-creen-lo-que-dice-el-codigo-civil/

Quote: "Prescriben, salvo disposición diversa de la ley: 1.- A los diez años, la acción
personal, la acción real, la que nace de una ejecutoria y la de nulidad del acto jurídico."

### Data-protection regulation — 2-year post-purpose retention cap — NOT independently verified

A WebSearch summary of Peru's updated Reglamento de la Ley de Protección de Datos Personales
(D.S. 016-2024-JUS) states: "The period for the conservation of personal data is a maximum of
two (2) years counted from the finalization of the last assignment carried out," and that
"indeterminate conservation of personal data is, as a general rule, prohibited." Direct fetch
attempts failed for all three candidate URLs (uria.com PDF unparseable, lpderecho.pe HTTP 403,
sek.io page did not contain the figure). UNVERIFIED — does not sustain a Finding on its own, but
is recorded because if accurate it would put Peru's data-protection-specific ceiling well BELOW
the 4-year labor and 10-year civil figures above — the opposite direction from Mexico's LFPDPPP
framing (which ties blocking to the underlying relationship's own prescription, i.e. potentially
the LONGER figure).

## Panama

### Código de Trabajo art. 12 — prescription rules (partially confirmed) — VERIFIED (narrow scope)

URL: https://vlex.com.pa/vid/codigo-trabajo-40572019

Quote: "Las acciones derivadas de un riesgo profesional, prescriben en dos años." (professional
risk claims: 2 years)

Quote: "sin que en ningún caso el plazo de prescripción pueda exceder en total de dos años" — this
clause, per the fetched excerpt, applies specifically to dismissal-authorization actions
involving criminal facts, NOT as a universal 2-year cap on every labor action in the Código de
Trabajo. Other prescription figures attributed to art. 12 by WebSearch summaries only (5 years
for overtime-pay actions, 3 months for reinstatement, 1 year for "special" actions) were NOT
independently fetch-confirmed — UNVERIFIED, recorded as signals only.

### Ley 81 de 2019 (Protección de Datos Personales) — 7-year post-obligation transfer restriction — VERIFIED

URL: https://icazalaw.com/es/2021/06/reglamentacion-de-la-ley-de-proteccion-de-datos-en-panama/

Quote: "El responsable del tratamiento de los datos personales o el custodio de la base de
datos no puede transferir o comunicar en ningún caso los datos que relacionen a una persona
después de transcurridos siete años, desde que se extinguió la obligación legal de conservarla"

Significance: unlike Mexico's LFPDPPP or Peru's reglamento, Panama's data-protection statute
does supply a fixed number — but it is framed as a POST-obligation buffer (an extra 7 years
after whatever underlying legal retention duty already ended), not the retention duty itself.
Structurally similar in spirit to 4Shark's own "5-year claims reach + 6-month buffer" framing,
but the buffer here is far larger (7 years) and stacks on top of an unspecified base obligation
rather than a specific labor-prescription number.

## Guatemala — confirmed absence of a general data protection law

### Código de Trabajo arts. 263 and 264 — 4-month / 2-year labor prescription — VERIFIED

URL: http://trabajadorguatemalteco.blogspot.com/2013/12/la-prescripcion.html

Quote (art. 263 — contract/pact-derived rights): "Todos los derechos que provengan directamente
de contratos de trabajo, de pactos colectivos, de convenios de aplicación general o del
reglamento interior de trabajo" prescribe in 4 months from contract termination.

Quote (art. 264 — Code-derived rights): "Todos los derechos que provengan directamente del
Código de Trabajo, de sus reglamentos o de las demás leyes de trabajo y previsión social"
prescribe in 2 years from the triggering fact/omission.

### No general personal-data-protection law — VERIFIED

URL: https://consortiumlegal.com/2022/06/02/guatemala-la-proteccion-de-datos-en-el-ambito-laboral/

Quote: "en Guatemala no existe una ley que regule específicamente la protección de datos
personales"

Quote (retention framing, in the absence of a statute): "los datos personales de los
trabajadores deben ser guardados únicamente por un periodo justificable" — i.e. "a justifiable
period," with NO fixed number attached.

Significance: Guatemala is the clearest case in this research of a country where a firm,
citable retention-window figure genuinely does not exist in public sources — the labor-code
prescription figures (4 months / 2 years) are the only hard numbers found, and they are far
shorter than any of the other countries' figures, with no data-protection statute to
cross-reference against (unlike every other country in this table).

## United States (generic reference, not a 4Shark locale suffix today)

### Fair Labor Standards Act (FLSA) — 3-year payroll-record retention — VERIFIED (secondary source)

URL: https://www.paradigmie.com/post/employment-records-retention-requirements

Quote: "The FLSA mandates that employers keep basic payroll records for at least three years."

Direct fetch of the primary source (dol.gov) returned HTTP 403 in this session; the above is a
secondary compliance-advisory source quoting the same figure independently corroborated across
multiple WebSearch result summaries.

### EEOC — 1-year (2-year for large filers/federal contractors) personnel-record retention — VERIFIED

URL: https://www.eeoc.gov/employers/recordkeeping-requirements

Quote: "EEOC Regulations require that employers keep all personnel or employment records for
one year." And: "if an employee is terminated involuntarily, his/her personnel records must be
retained for one year from the date of termination."

Significance: the US has no single federal retention number — FLSA (3 years, payroll-specific)
and EEOC (1 year general, 2 years for large filers/federal contractors) diverge, and state law
adds further variation on top. This is presented only as a reference point since 4Shark's
current `locale` enum has no US-specific value (only generic `en`) and the engineer's brief
listed the US as optional ("se achar base").

## Records-management naming grounding (for the domain/naming section of SPIKE-v2.md)

### ARMA International — "jurisdiction" is the standard records-management term for what drives a retention schedule — VERIFIED

URL: https://magazine.arma.org/2022/04/the-impact-of-data-protection-laws-on-your-records-retention-schedule/

Quote: "your records retention schedule is compliant with the data protection requirements in
the jurisdictions where your organization operates" and "it should contain the records created
and retained by your organization and the jurisdictions where you operate."

Significance: grounds "jurisdiction" (rather than, say, "domicile" or "locale") as the
established records-management industry term for the concept the engineer is describing — the
country whose law governs how long a given class of records must be kept.
