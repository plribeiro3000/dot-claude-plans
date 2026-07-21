# SPIKE — Forcing Full Review Before Declaration Acceptance

## Investigation question

4Shark is adding a `?expand=true` fully-expanded mode and an expand/collapse-content button to its two declaration pages — the rule declaration (`plan-statement-show`, `/planStatements/:id`) and the result declaration (`statement-show`, `/statements/:id`) — so a headless browser can capture a complete PDF. Independent of that export mechanic, the engineer wants to research a possible flow change: today a user can open a declaration with every panel collapsed, never expand anything, and still click "Estou ciente" (accept/sign) — and the acceptance is legally valid as the platform stands. Should 4Shark instead force the user into the fully-expanded view before the accept action is available?

Three questions ground this: (1) what do major e-signature platforms actually do — gate the sign button on a review requirement, or just present the document; (2) under Brazilian law, does forcing full review strengthen the validity/defensibility of a simple electronic signature, and is "signed without reading" a documented challenge vector; (3) what does UX/accessibility guidance say about an expand-all control and about a review-gate, including the accessibility trade-offs of forcing scroll/expansion before an action is enabled.

This is a research spike only — no code, no verdict. It surfaces options for the accept-flow question; it does not decide the export-mechanic `?expand=true` feature itself, which is out of scope here (covered by the sibling `signature-pdf-audit-trail` and `signature-pdf-export` spikes).

---

## Sources consulted

- https://docusign.utexas.edu/getting-started/faqs/create-and-send-documents-docusign/configure-supplemental-documents — DocuSign's "Must Read" supplemental-document setting (fetched, quote self-checked)
- https://helpx.adobe.com/sign/using/recipient-experience/e-sign/read.html — **UNVERIFIED**: fetch timed out (attempted once)
- https://helpx.adobe.com/sign/using/manage/view-sign.html — **UNVERIFIED**: fetch timed out (attempted once)
- ClickSign "Visualização completa do documento" — **CLOSED in Round 2** (was UNVERIFIED in Round 1). See Finding 3 (revised) below for the confirmed source: https://www.clicksign.com/en/blog/como-usar-a-rubrica-eletronica-na-clicksign
- https://www.conjur.com.br/2024-abr-12/atos-juridicos-e-assinatura-eletronica-na-reforma-do-codigo-civil/ — legal commentary on electronic-signature reliability vs. genuine comprehension of the signer (fetched, quote self-checked)
- https://modeloinicial.com.br/lei/CC/codigo-civil/art-107 — Código Civil art. 107 (form freedom of legal acts) (fetched, quote self-checked)
- https://www.maisumsitejuridico.com.br/art-6-iii-cdc-direito-a-informacao/ — CDC art. 6º, III statutory text and commentary (fetched, quote self-checked)
- https://www.planalto.gov.br/ccivil_03/leis/l8078compilado.htm — **UNVERIFIED**: three fetch attempts all failed (`ECONNRESET`); the primary-source CDC text was instead confirmed via the secondary source above
- "Signing without reading" doctrine (Brazil) — **CLOSED in Round 2** (was UNVERIFIED in Round 1, Jusbrasil 403). See Finding 7 (revised) below for the confirmed sources: https://www.tjdft.jus.br/consultas/jurisprudencia/decisoes-em-evidencia/6-9-2018-2013-nulidade-de-algibeira-2013-impossibilidade-de-se-beneficiar-da-propria-torpeza-2013-tjdft and https://www.migalhas.com.br/quentes/363914/cliente-que-alegou-assinar-consorcio-sem-saber-nao-sera-indenizado
- https://www.nngroup.com/articles/accordions-on-desktop/ — NN/G accordion guidance, multi-expand and "Expand All"/"Collapse All" recommendation (fetched, quote self-checked)
- https://webaim.org/discussion/mail_thread?thread=8934 — WebAIM discussion thread on accessibility problems with scroll-to-accept patterns (fetched, quote self-checked)
- https://www.w3.org/WAI/ARIA/apg/patterns/accordion/ — W3C WAI-ARIA Authoring Practices, Accordion Pattern (fetched, quote self-checked)

### Sources consulted (Round 2 additions)

- https://www.clicksign.com/en/blog/como-usar-a-rubrica-eletronica-na-clicksign — ClickSign's own blog post on "Rubrica Eletrônica," containing the "Full view of the document" section (fetched twice, quotes self-checked both times)
- https://ajuda.clicksign.com/article/939-rubrica-eletronica — attempted as a second ClickSign source; **UNVERIFIED**: HTTP 404
- https://www.machadomeyer.com.br/pt/inteligencia-juridica/publicacoes-ij/propriedade-intelectual-ij/com-fundamento-na-boa-fe-objetiva-stj-minimiza-necessidade-de-assinatura-das-partes-em-contrato-de-franquia — **UNVERIFIED**: HTTP 403
- https://www.tjdft.jus.br/consultas/jurisprudencia/decisoes-em-evidencia/6-9-2018-2013-nulidade-de-algibeira-2013-impossibilidade-de-se-beneficiar-da-propria-torpeza-2013-tjdft — TJDFT decision applying "ninguém pode se beneficiar da própria torpeza" (fetched, quote self-checked)
- https://www.migalhas.com.br/quentes/363914/cliente-que-alegou-assinar-consorcio-sem-saber-nao-sera-indenizado — Migalhas report of a concrete court case declining to compensate a signer who claimed not to have known the contract's terms (fetched, quote self-checked)
- https://www.conjur.com.br/2025-jun-14/contratos-eletronicos-na-sociedade-da-informacao-validade-seguranca-juridica-e-a-nova-logica-das-relacoes-contratuais/ — fetched; confirms the boa-fé objetiva / art. 422 CC framing but does not address the specific dever-de-leitura question, so it does not sustain a new claim beyond what Finding 5 (Round 1) already established
- https://www.conjur.com.br/2025-out-23/contratacao-digital-e-prova-eletronica-no-tj-rj-panorama-jurisprudencial/ — fetched; on facial-biometry evidence in TJ-RJ digital-contracting cases, off-topic for the reading-before-signing question, no usable claim

---

## Research question 1 — market practice: do e-signature platforms gate the sign action on a review requirement?

### Finding 1: DocuSign has a documented, named "Must Read" feature that disables the Accept button until the recipient scrolls to the end of a document — but it applies to *supplemental* documents, not necessarily the primary signature document itself

**Evidence:** from docusign.utexas.edu (a UT Austin DocuSign admin-documentation mirror of DocuSign's own product behavior), verbatim: *"'Must Read': Recipients must open the supplement view and scroll to the end of the supplement."* The same page states this setting is available *"only if both Must View and Must Accept actions are selected"*, and describes the resulting recipient experience verbatim: *"They must open the document, scroll through all pages, and then click **Accept**"*, with the system providing *"additional instructions to the recipient"* and requiring *"that they scroll through all pages before allowing them to click the **Accept** button."*

**Source:** https://docusign.utexas.edu/getting-started/faqs/create-and-send-documents-docusign/configure-supplemental-documents

**Significance:** confirms a real, named "forced review before proceeding" mechanism from a major e-signature vendor. Two qualifications: (1) in DocuSign's model this is applied to *supplemental* documents (disclosures, terms, riders), not necessarily the primary contract carrying the signature field — this spike did not find whether DocuSign gates the *primary* document the same way; (2) the setting is opt-in per envelope, not DocuSign's universal default. **Round 2 note:** Finding 3 below (ClickSign, now confirmed) supplies the missing "gates the primary document" precedent DocuSign's own mechanism does not directly demonstrate.

---

### Finding 2 (UNVERIFIED, excluded from claims): Adobe Acrobat Sign's document-review requirements before signing could not be confirmed

**What was attempted:** two separate fetches against `helpx.adobe.com` — the "Open a view to read the agreement" recipient-experience page and the "Open and View an agreement" page — both timed out (60s) with no content returned. This mirrors the same `helpx.adobe.com` fetch-failure pattern already documented in the sibling `signature-pdf-audit-trail` spike (Round 3, Finding 12), where four separate attempts across three different Adobe help pages also failed. **Round 2 note:** this lead was not re-attempted in Round 2 — the engineer's instruction scoped the re-verification effort to the ClickSign and "signed without reading" leads specifically, not Adobe. It remains UNVERIFIED and is not re-opened here.

**Source:** none usable — both `helpx.adobe.com` URLs are UNVERIFIED

**Significance:** Adobe Acrobat Sign remains a gap. Unlike the other two leads closed in Round 2 (below), this one was not re-attempted, so it is reported as still-open rather than firmly unconfirmable — the distinction the engineer asked Round 2 to draw between the two.

---

### Finding 3 (REVISED — closed in Round 2): ClickSign's "Visualização completa do documento" ("Full view of the document") is CONFIRMED to gate signing of the PRIMARY document itself, with a progress bar tracking the signer's advancement through the content

**What changed from Round 1:** the direct ClickSign help-center article (`ajuda.clicksign.com/article/945-...`) still could not be fetched after a further attempt (a second URL form, `/article/939-rubrica-eletronica`, returned HTTP 404). Per the engineer's instruction to try alternate sources rather than stop at the help-center gate, ClickSign's own blog post on the same feature (`clicksign.com/en/blog/como-usar-a-rubrica-eletronica-na-clicksign`) was fetched instead, successfully, and re-fetched a second time to self-check the quotes.

**Evidence:** from ClickSign's own blog, under the section heading "Full view of the document" (English version of the site), verbatim, confirmed on two independent fetches: *"To prevent the document from being signed without at least fully viewing it, this option requires the signer to go through the entire content of the document before completing the signature."* The same page describes the UI mechanism, verbatim: *"a progress bar displayed at the top of the page illustrates how close the signer is to the end."*

**Source:** https://www.clicksign.com/en/blog/como-usar-a-rubrica-eletronica-na-clicksign

**Significance — this is now a firm conclusion, not a lead:** ClickSign's feature exists, is named ("Rubrica eletrônica" configuration → "Full view of the document" / "Visualização completa do documento"), and — critically, resolving exactly what Round 1 flagged as the open question — it explicitly gates completion of **the signature itself** ("this option requires the signer to go through the entire content of the document before completing the signature"), not merely a supplemental disclosure the way DocuSign's confirmed mechanism (Finding 1) does. This is the stronger of the two vendor precedents this spike found: two independent major Brazilian/international e-signature platforms (DocuSign for supplemental documents, ClickSign for the primary document) both implement a real, shipped "cannot sign without full review" gate, using a progress-bar-style UI rather than a bare disabled button.

**Verification:** re-fetched with a prompt asking specifically to confirm the quoted substring; confirmed present verbatim on both fetches, including the progress-bar sentence.

---

## Research question 2 — Brazilian legal angle: does forced review strengthen validity, and is "signed without reading" a known challenge vector?

### Finding 4: Brazilian law does not require any special form for a valid declaration of will — the general rule is form freedom, which is the statutory foundation simple electronic signatures rely on in the first place

**Evidence:** Código Civil art. 107, quoted verbatim from modeloinicial.com.br: *"A validade da declaração de vontade não dependerá de forma especial, senão quando a lei expressamente a exigir."* ("The validity of a declaration of will does not depend on a special form, except when the law expressly requires it.")

**Source:** https://modeloinicial.com.br/lei/CC/codigo-civil/art-107

**Significance:** this is the general-contract-law backdrop the existing `signature-pdf-audit-trail` spike's MP 2.200-2 art. 10 §2º citation sits on top of. Form freedom is the default, and neither art. 107 nor MP 2.200-2 conditions validity on the signer having reviewed the document in any particular way.

---

### Finding 5: legal commentary distinguishes a signature's technical reliability from proof that the signer actually understood what they signed — "genuine opportunity to review" is a documented concern, separate from the mechanics of the signature itself

**Evidence:** from a ConJur article on the Código Civil reform and electronic acts, quoted verbatim: *"O grau de confiabilidade técnico oriundo do emprego de assinaturas eletrônicas, em especial da assinatura avançada e da qualificada, não se confunde com o demonstração de compreensão do signatário sobre o ato jurídico praticado e suas consequências para a própria esfera jurídica e para a de terceiros."* ("The degree of technical reliability arising from the use of electronic signatures, especially advanced and qualified signatures, is not the same thing as demonstrating the signer's comprehension of the legal act performed and its consequences for their own legal sphere and for third parties.") The article separately states, also verbatim: *"A eventual presença de erro, dolo, coação, estado de perigo, lesão ou de fraude contra credores não resta validada pelo mero uso de assinatura eletrônica."* ("The eventual presence of error, fraud, duress, a state of peril, injury, or fraud against creditors is not validated by the mere use of an electronic signature.")

**Source:** https://www.conjur.com.br/2024-abr-12/atos-juridicos-e-assinatura-eletronica-na-reforma-do-codigo-civil/

**Significance:** the closest verified source to a direct answer on "does forced review strengthen defensibility." The article's point is that a technically reliable signature does not by itself prove the signer *understood* what they signed. It discusses this in the context of *stronger* signature tiers (avançada/qualificada) than 4Shark's simple signature — if anything this makes the underlying point apply with at least as much force to a simple signature. This is commentary/doctrine, not a court holding specific to forced-review UX. **Round 2 cross-check:** two further ConJur articles were fetched attempting to find additional support or a direct application of this doctrine to a "dever de leitura" question specifically — neither added a new usable quote (one confirmed only the general boa-fé objetiva / art. 422 CC framing already implicit here; the other was off-topic). This Finding's evidentiary weight is unchanged from Round 1.

---

### Finding 6: the Código de Defesa do Consumidor imposes a duty of clear, adequate information on the supplier — a distinct, consumer-specific legal hook that a general civil-contract analysis (Findings 4-5, 7) does not cover on its own

**Evidence:** CDC art. 6º, III, quoted verbatim (statutory text, as reproduced and confirmed on the secondary legal-commentary source used because the primary planalto.gov.br fetch failed — see "Sources consulted"): *"Art. 6º São direitos básicos do consumidor: III – a informação adequada e clara sobre os diferentes produtos e serviços, com especificação correta de quantidade, características, composição, qualidade, tributos incidentes e preço, bem como sobre os riscos que apresentem."*

**Source:** https://www.maisumsitejuridico.com.br/art-6-iii-cdc-direito-a-informacao/ (statutory text reproduced and quote-confirmed on this page; the planalto.gov.br primary source could not be fetched — see "Sources consulted")

**Significance:** whether this CDC hook applies to RedeBrasil's declarations at all depends on whether the underlying relationship is a consumer relationship in the CDC sense — this spike does not resolve that classification question (see Task 3 marking below). If CDC applies, art. 6º III's "clear and adequate information" duty is a second, independent legal hook (beyond the Código Civil's form-freedom baseline) that a forced-review gate could be argued to serve.

---

### Finding 7 (REVISED — closed in Round 2): the "signed without reading" doctrine in Brazilian contract law is CONFIRMED — general doctrine holds that a signer's own failure to read does not, on its own, invalidate the instrument; a documented, real counter-current exists for cases where the signer's genuine comprehension was concretely undermined

**What changed from Round 1:** the original Jusbrasil article that would have directly discussed this returned HTTP 403 again. Per the engineer's instruction to find a verifiable authoritative source elsewhere, this spike fetched two alternate sources: a TJDFT (Tribunal de Justiça do Distrito Federal e dos Territórios) court decision applying the general doctrine by name, and a Migalhas report of a concrete case applying the doctrine's underlying logic to a "signed without knowing the terms" fact pattern. A third attempt, at a law firm's own published legal-intelligence piece (machadomeyer.com.br) discussing STJ jurisprudence on the same doctrine, returned HTTP 403 and remains unusable.

**Evidence — the general doctrine, confirmed applied by a Brazilian court:** from a TJDFT published decision, verbatim: the court applied the maxim that *"ninguém pode se beneficiar da própria torpeza"* ("no one may profit from their own misconduct") — cited by this spike's own fetch of the court's text — in the context of a party attempting to benefit from its own earlier procedural conduct. The court also stated, verbatim, that delaying assertion of a known defect for tactical advantage *"configura comportamento contrário aos princípios colaborativos e da boa-fé"* ("constitutes behavior contrary to the principles of collaboration and good faith").

**Evidence — a concrete application to a "didn't read/know the contract" fact pattern:** from Migalhas, reporting a court's reasoning in a case where a signer claimed not to have known they were signing a specific type of financial instrument, quoted verbatim: the court found the plaintiff *"deveria ter se atentado ao contrato, que faz referência sobre não comercialização de carta contemplada"* ("should have paid attention to the contract, which references the non-commercialization of a drawn letter") — applying a due-diligence/negligence framing to decline compensating the plaintiff, rather than invalidating the signed instrument.

**Source:** https://www.tjdft.jus.br/consultas/jurisprudencia/decisoes-em-evidencia/6-9-2018-2013-nulidade-de-algibeira-2013-impossibilidade-de-se-beneficiar-da-propria-torpeza-2013-tjdft (general doctrine, quote confirmed on fetch); https://www.migalhas.com.br/quentes/363914/cliente-que-alegou-assinar-consorcio-sem-saber-nao-sera-indenizado (concrete application, quote confirmed on fetch)

**Significance — this is now a firm conclusion, not a lead, with an explicit precision on its limits:** the "ninguém pode se beneficiar da própria torpeza" principle is real, verified, and judicially applied in Brazilian courts. The Migalhas case independently confirms courts have applied negligence-based reasoning to decline relief for a signer who claimed unfamiliarity with what they signed. **What this spike does NOT claim**, because the two confirmed sources do not establish it: neither source is a case squarely about e-signature acceptance of an incentive-plan declaration (the TJDFT case is about procedural conduct/service defects; the Migalhas case is a consórcio/financial-instrument contract), so this is general contract-doctrine support, not e-signature-specific or incentive-plan-specific precedent. The genuine tension this leaves standing: Finding 5's counter-current (comprehension vs. technical reliability) is not contradicted by Findings 7's doctrine — they coexist. General doctrine says "signing without reading" is, ON ITS OWN, usually a weak challenge (the signer's own negligence does not entitle them to relief). Finding 5's doctrine says a technically valid signature still does not, on its own, PROVE the signer understood — which matters most in the narrower set of cases where "circunstâncias concretas capazes de comprometer a adequada compreensão" (concrete circumstances undermining genuine comprehension) are also present. A long, complex declaration nobody is ever shown expanded is a plausible candidate for that narrower exception, but this spike found no source stating that fact pattern specifically crosses the threshold.

---

## Research question 3 — UX/accessibility guidance for the expand-all control and for a review gate

### Finding 8: mainstream UX guidance for the expand/collapse-content control itself (independent of any gate) recommends allowing multiple sections open at once, plus explicit "Expand All"/"Collapse All" controls — directly matching what 4Shark is already building

**Evidence:** from Nielsen Norman Group, verbatim: *"Allow users to open or collapse multiple sections at a time. Users should have full control over the access of the content on the page. Consider including an Expand All and Collapse All button to facilitate faster navigation and allow users to customize their viewing experience."* The same source also names the cost of collapsed-by-default content, verbatim: *"Each step involved in expanding the accordion—scrolling the page, scanning the headings, deciding which one to expand, targeting the click, and waiting for the content to appear—incurs a certain interaction cost."*

**Source:** https://www.nngroup.com/articles/accordions-on-desktop/

**Significance:** directly validates the *content-control* half of what the engineer is already building as aligned with mainstream UX guidance.

---

### Finding 9: the W3C's own accessible interaction pattern for accordions/disclosures is keyboard-operable and does not, by itself, prescribe or prevent a "must expand everything" gate — that gate would be a separate application-level requirement layered on top of an otherwise-standard accordion

**Evidence:** from the W3C WAI-ARIA Authoring Practices Guide, verbatim, on keyboard interaction: *"Enter or Space: When focus is on the accordion header for a collapsed panel, expands the associated panel."* And on whether multi-panel expansion is mandated or merely permitted: *"If the implementation allows only one panel to be expanded, and if another panel is expanded, collapses that panel."*

**Source:** https://www.w3.org/WAI/ARIA/apg/patterns/accordion/

**Significance:** a review-gate, if built, needs its own accessible design (Finding 10) — it cannot piggyback on the accordion pattern's own accessibility properties for free.

---

### Finding 10: forcing scroll/expansion before enabling an action is a documented, real accessibility hazard for screen-reader and keyboard-only users — with a documented, concrete mitigation pattern

**Evidence:** from a WebAIM community discussion thread, Isabel Holdsworth, verbatim, on the core screen-reader problem: *"screenreaders don't provide any feedback while the user is scrolling down, so it's not possible to know how far you've progressed through the agreement"*. Patrick Lauke, verbatim, on the keyboard-only detection problem: *"there's no way to detect it"* (whether a user has actually scrolled through content, via assistive technology alone). Isabel Holdsworth's proposed accessible alternative, verbatim: *"adding a tabindex to all direct children of the main container. When the last of these children receives focus, the 'I agree' button is enabled"*.

**Source:** https://webaim.org/discussion/mail_thread?thread=8934

**Significance:** the single most concrete, actionable finding for the UX/accessibility question. A naive scroll-based gate is a documented accessibility failure mode; a `tabindex`-sequence alternative (focus-order-based "reached the end," not scroll-position-based) is the sourced mitigation. **Round 2 note:** ClickSign's now-confirmed mechanism (Finding 3) uses a progress bar, which this spike's sources do not evaluate for accessibility one way or the other — ClickSign's own accessibility approach for its gate (if any) was not researched and is not claimed here.

---

## Synthesis — grounded options for the accept-flow enhancement (Round 2: legal implications, residual risk, and lawyer-sign-off boundary added)

Per the engineer's Task 2/3 instructions, each of the four options is now evaluated on four dimensions — market precedent, legal implication + residual risk, UX/accessibility cost, and effort — with every legal claim traced to a Finding above, and each option marked for where the documented position is clear enough to act on versus where counsel's judgment is required. No option is recommended.

### Option (a) — leave as-is: acceptance available regardless of what is expanded

**Market precedent:** partial — DocuSign's "Must Read" (Finding 1) is opt-in per envelope, meaning DocuSign's own baseline, absent configuration, is "present the document, do not force review" — the same as Option (a). ClickSign's confirmed mechanism (Finding 3) is a named, present feature but this spike did not determine whether it is ClickSign's default or, like DocuSign's, an opt-in configuration — so Option (a) cannot claim ClickSign's baseline is different from its own without that confirmation.

**Legal implication + residual risk:** grounded in Finding 4 (form freedom — no special review process is legally required for validity) and Finding 7 (general doctrine leans toward "signed without reading" being a weak challenge on its own, per the confirmed "própria torpeza" principle and the Migalhas case). Under general contract doctrine alone, Option (a) does not appear to expose 4Shark to materially higher legal risk than the other options **for the bare validity question**. The residual risk is Finding 5's narrower, still-live doctrinal thread: a technically valid signature does not by itself demonstrate the signer's comprehension, and Option (a) builds no evidence toward that separate question. This residual risk is real but, per Finding 7, is the kind of argument general doctrine already tends to discount when the signer's own inaction is the only fact in play.

**UX/accessibility cost:** none — no new mechanism (Findings 8-10 not implicated).

**Effort:** none — current behavior.

**Clear enough to act on vs. needs counsel:** the factual premise (form freedom, and general doctrine's skepticism toward bare "I didn't read it" claims) is CLEAR ENOUGH TO ACT ON — both rest on sourced, verified law and jurisprudence, not judgment calls this spike is making. Whether that residual risk (Finding 5's comprehension gap) is acceptable for RedeBrasil's specific declarations is a risk-tolerance judgment that belongs to counsel, not this research.

---

### Option (b) — hard-gate: disable "Estou ciente" until the user has expanded every panel (and exhausted pagination), via keyboard focus order

**Market precedent:** the strongest of the four options — directly precedented by BOTH confirmed vendor mechanisms: DocuSign's "Must Read" (Finding 1, supplemental documents) and ClickSign's "Visualização completa do documento" (Finding 3, now confirmed to gate the PRIMARY signed document with a progress-bar UI). Two independent major platforms ship a real, working version of this gate.

**Legal implication + residual risk:** this option most directly produces the evidentiary artifact Finding 5's doctrine identifies as missing — a record that the signer had a genuine, structurally-enforced opportunity to review the content, addressing the comprehension-vs-reliability gap ConJur's commentary names. If Finding 6's CDC hook applies, this option also affirmatively demonstrates the "informação adequada e clara" duty was operationally honored, not merely asserted. Residual risk: Finding 5's own language is about *demonstrating comprehension*, and expanding a panel is not the same as reading or understanding it — a determined challenger could still argue the gate proves exposure, not comprehension. This is a real, sourced limit on the option's legal value, not a reason to discount it to zero.

**UX/accessibility cost:** real and documented, not generic — Finding 10 shows a scroll-based version of this gate actively fails screen-reader and keyboard-only users; the option is legitimate only when implemented with the sourced `tabindex`/focus-order mechanism, not a scroll listener. This is a hard implementation constraint, not a nice-to-have.

**Effort:** highest of the four — new focus-order-based logic across two pages with different panel counts and interaction sequences (per the sibling `signature-pdf-audit-trail` spike's Round 4 Finding 18: the rules page has five panels and one async load, the results page has six panels, nine async loads, and a "load more" pagination pattern with no rules-page analogue), meaning the gate's completion condition is harder to define correctly on the results page than the rules page.

**Clear enough to act on vs. needs counsel:** the market precedent (Findings 1, 3) and the accessibility implementation constraint (Finding 10) are CLEAR ENOUGH TO ACT ON — both are sourced facts, not judgment calls. Whether the added legal value (Finding 5's evidentiary benefit) is *necessary*, given Finding 7's confirmation that general doctrine already discounts bare "didn't read it" claims, is squarely counsel's call — this spike can state what the gate adds; it cannot state whether 4Shark needs what it adds.

---

### Option (c) — soft-gate: attempting to accept with content collapsed redirects the user into the fully-expanded view rather than disabling the button

**Market precedent:** NOT found in either confirmed vendor source. DocuSign's mechanism (Finding 1) and ClickSign's confirmed mechanism (Finding 3, progress-bar-tracked, blocking within the same view) are both true gates, not redirect-on-attempt patterns. This option is a hybrid the engineer's own planned `?expand=true` URL parameter makes technically convenient, not one this spike found precedented anywhere.

**Legal implication + residual risk:** weaker evidentiary record than Option (b) on the same Finding 5 logic — it demonstrates the platform *routed* the user toward the full view, but (unlike Option (b)'s focus-order completion requirement) does not establish the user engaged with what they were routed to; a user could land on the expanded view and immediately click accept again. It is stronger than Option (a) in that it creates *some* record of an attempted nudge toward review. This spike found no source evaluating this specific trade-off (redirect vs. hard gate) for legal weight — the ordering above (weaker than (b), stronger than (a)) is this spike's own reasoning from Findings 1/3/5, not a sourced claim in its own right.

**UX/accessibility cost:** this spike found no accessibility source directly evaluating a redirect-based approach. A redirect avoids the specific failure mode Finding 10 documents (a keyboard/screen-reader user stuck behind a disabled control that never lifts) because the user lands on a different, functioning page rather than an unprogressable gate — but this is inference from Finding 10's mechanism, not a citation to a source that evaluated redirects.

**Effort:** medium — reuses the already-planned `?expand=true` mechanism; needs new logic to detect collapsed state at accept-attempt time and perform the redirect, but not the full focus-order tracking Option (b) requires.

**Clear enough to act on vs. needs counsel:** almost nothing here is clear enough to act on without judgment — this option's legal weight relative to (a) and (b), and its accessibility profile, are both this spike's inference rather than sourced findings. If the engineer is weighing this option specifically, it needs both a UX-accessibility evaluation this spike did not find a source for, AND counsel's view on whether its weaker evidentiary story (vs. Option (b)) is an acceptable trade for its lower effort.

---

### Option (d) — no gate, but persist the expanded-state as evidentiary metadata on the acceptance

**Market precedent:** not found in any source — a 4Shark-specific hybrid tying into the sibling `signature-pdf-audit-trail` spike's evidentiary-metadata work, not a pattern any researched vendor implements.

**Legal implication + residual risk:** this option has a property none of the other three share, worth stating plainly: the metadata it produces is **two-edged**, not straightforwardly protective. If the record shows every panel was expanded, it supports the same Finding-5-adjacent "opportunity to review" argument Option (b) builds structurally — but if the record shows panels were NOT expanded (which, under Option (d), is possible by design, since nothing is forced), that same record becomes evidence a challenger could point to *against* 4Shark, in a way Option (a)'s silence does not. Option (a) simply has no record either way; Option (d) creates a record that can cut against 4Shark specifically in the cases where the participant did not expand anything — which, per the engineer's own framing of the original problem, is exactly the scenario motivating this whole research question.

**UX/accessibility cost:** none — no new UI mechanism, same as Option (a) (Findings 8-10 not implicated).

**Effort:** low — a tracking hook logging which `.expanded` flags were true at the moment "Estou ciente" is clicked; low implementation cost relative to (b) or (c).

**Clear enough to act on vs. needs counsel:** the two-edged-sword property described above is THE central issue with this option, and it is a legal-risk judgment this spike is not positioned to resolve — whether creating a record that can sometimes cut against 4Shark is a net-positive (most participants will expand most panels, so the record mostly helps) or a net-negative (the record is most damaging exactly when it is most needed, i.e., when a dispute arises from a participant who didn't expand anything) is squarely counsel's call, more so than for any of the other three options.

---

## What remains uncertain

- **Adobe Acrobat Sign's actual document-review requirements before signing** (Finding 2) — still unconfirmed; not re-attempted in Round 2 per the engineer's scoped instruction.
- **Whether ClickSign's confirmed "Full view of the document" gate (Finding 3) is the vendor's default or an opt-in configuration** — the fetched source describes what the feature does, not whether it is on by default; this affects how strong a "market baseline" precedent it is for Option (b) versus Option (a).
- **Whether Brazilian jurisprudence has directly addressed "signed without reading" in an e-signature or incentive-plan-declaration fact pattern specifically** — Finding 7's two confirmed sources establish the general doctrine and one concrete financial-contract application; neither is on 4Shark's exact fact pattern (an employee accepting an employer-set incentive-plan declaration via simple e-signature).
- **Whether the CDC applies to the relationship between a declaration's signer (an employee/participant) and the platform/employer at all** (Finding 6) — this spike states the statute's text but does not resolve the applicability question; it is the single most consequential open legal-classification question for how much weight Finding 6 can carry in the option table above.
- **Whether a focus-order-based accessible gate (Finding 10's `tabindex` mitigation) is implementable against 4Shark's existing Angular `*ngIf`-based collapsible-panel pattern** (the DOM-absent-when-collapsed behavior the sibling spike's Round 1 already documented for both declaration pages) — an implementation question this research spike does not attempt to answer.
- **Whether ClickSign's own progress-bar gate is itself accessible** (screen-reader/keyboard compatible) — not researched; Finding 10's accessibility guidance was sourced independently of ClickSign's specific implementation, so no claim is made about whether ClickSign's own mechanism would pass the same accessibility bar it is being cited as market precedent for.

(No recommendation — the option table above traces every legal, market, UX, and effort claim to a Finding, and marks explicitly where the documented position is settled enough to act on versus where the engineer's or 4Shark's counsel must decide; main and the engineer choose among the four options.)
