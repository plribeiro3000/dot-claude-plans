# SPIKE — Cookie Consent for 4Shark B2B SaaS

## Investigation question

4Shark is a Brazilian B2B SaaS (HR/people-analytics). Its logged-in application sets a strictly-necessary session/authentication cookie without which the user cannot access the platform. Separately, the front-end uses Google Analytics (behavioral tracking). 4Shark has NO cookie-consent banner today.

Engineer's specific fear: "if the session cookie is essential and the user refuses cookies, they can't access the platform — how do other SaaS handle this?"

Five sub-questions: (Q1) Are strictly-necessary cookies exempt from consent? (Q2) Do analytics cookies require consent? (Q3) Does a banner apply inside the authenticated app vs. only the marketing site? (Q4) What is the category-based CMP pattern used by B2B SaaS? (Q5) What is the specific exposure from keeping Google Analytics?

## Executive answer (to the engineer's specific fear)

The engineer's fear is based on a false premise. The session/authentication cookie is NOT subject to consent under either LGPD (ANPD guidance) or GDPR/ePrivacy. The legal basis for it is **legitimate interest** (or contract performance), not consent. Because consent is not the legal basis, there is no "refuse" option to offer — and offering one would be incorrect. The only way a user "blocks" the session cookie is by disabling all cookies in their browser, which breaks virtually every web application; this is universally accepted as the user's own choice and is not a compliance problem for 4Shark.

The separate problem: **Google Analytics is not a strictly necessary cookie**. GA requires a distinct legal basis. Under LGPD, that basis is either consent or legitimate interest (with opt-out). Under GDPR/ePrivacy (relevant if 4Shark processes EU users' data), GA requires consent. The missing cookie-consent banner is a problem only for GA, not for the session cookie.

## Sources consulted

- `cookie-consent_anpd_quotes_1.txt` (auxiliary) — verbatim Portuguese excerpts from ANPD Guia Orientativo via secondary sources (Souto Correa, GoAdopt, Lefosse, LEC)
- `cookie-consent_ga_decisions_1.txt` (auxiliary) — verbatim quotes from Austrian DSB, CNIL, Italian Garante decisions on GA; EU-US DPF current status
- https://www.deceptive.design/laws/eprivacy-directive-article-5-3/ — ePrivacy Directive Art. 5(3) full text
- https://noyb.eu/en/austrian-dsb-eu-us-data-transfers-google-analytics-illegal — Austrian DSB decision (Jan 2022)
- https://www.hunton.com/privacy-and-cybersecurity-law-blog/2022/06/30/italian-garante-bans-google-analytics/ — Italian Garante decision (Jun 2022)
- https://cookie-script.com/blog/google-analytics-4-and-gdpr — CNIL decision (Feb 2022) and GA4 overview
- https://trustyourwebsite.com/eu/en/guides/google-analytics-gdpr — EU-US DPF status and GA4 consent requirement
- https://goadopt.io/blog/anpd-cookies-guia-orientativo-cookies-protecao-dados-pessoais/ — ANPD guide excerpts (analytics and necessary cookies)
- https://www.soutocorrea.com.br/client-alerts/anpd-lanca-guia-orientativo-sobre-cookies-e-protecao-de-dados-pessoais/ — ANPD guide excerpt (strictly necessary, free consent)
- https://lefosse.com/noticias/alerta/anpd-publishes-guidelines-on-the-use-of-cookies/ — ANPD guide summary (consent inappropriate for necessary cookies)
- https://secureprivacy.ai/blog/cookie-consent-for-saas-companies — SaaS consent pattern in authenticated environments

## Findings

### Finding 1 — ePrivacy Art. 5(3) exempts strictly-necessary cookies from consent (GDPR/ePrivacy layer)

**Evidence (verbatim):**
> "Member States shall ensure that the storing of information, or the gaining of access to information already stored, in the terminal equipment of a subscriber or user is only allowed on condition that the subscriber or user concerned has given his or her consent … **This shall not prevent any technical storage or access** for the sole purpose of carrying out the transmission of a communication over an electronic communications network, **or as strictly necessary in order for the provider of an information society service explicitly requested by the subscriber or user to provide the service.**"

**Source:** ePrivacy Directive Art. 5(3), as reproduced at https://www.deceptive.design/laws/eprivacy-directive-article-5-3/

**Significance:** A session/authentication cookie that is required to identify the user and deliver the service the user explicitly requested (logging in to 4Shark) falls directly in the "strictly necessary … to provide the service" exemption. No prior consent is required and no "refuse" toggle is legally needed for this cookie. GDPR's other obligations (transparency, lawful basis, data subject rights) still apply; only the consent requirement is lifted.

**Verification:**
- URL fetched: https://www.deceptive.design/laws/eprivacy-directive-article-5-3/
- Verbatim quote checked: yes
- Quote substring confirmed at: main article body, "Article 5(3) text" section

---

### Finding 2 — ANPD guide: cookies estritamente necessários don't require consent under LGPD (Q1 answered)

**Evidence (verbatim, Portuguese — two independent secondary sources citing the ANPD guide):**

Quote A (Souto Correa citing ANPD guide):
> "Cookies estritamente necessários – já que nesses casos a coleta das informações é essencial para o funcionamento da página eletrônica ou do serviço, e, portanto, **não há condição efetiva para a manifestação livre do titular**"

Quote B (Lefosse summarizing ANPD guide, in English):
> "ANPD recommends that consent (art. 7, I, of the LGPD) will not be the appropriate legal basis for the use of strictly necessary cookies as these are essential for the functioning of the electronic page."

**Source:** Quote A — https://www.soutocorrea.com.br/client-alerts/anpd-lanca-guia-orientativo-sobre-cookies-e-protecao-de-dados-pessoais/ (quoting ANPD Guia Orientativo, updated Jan 2025). Quote B — https://lefosse.com/noticias/alerta/anpd-publishes-guidelines-on-the-use-of-cookies/

**Significance:** "Não há condição efetiva para a manifestação livre do titular" ("there is no effective condition for the free expression of the data subject's will") is the ANPD's direct explanation of why consent cannot be the legal basis: if the user must accept the cookie to use the service, consent is not free. The ANPD instead directs controllers to use legitimate interest (art. 7, IX, LGPD) or contract performance (art. 7, V, LGPD) for strictly necessary cookies. This is the canonical answer to the engineer's fear.

**Verification:**
- URL fetched (Quote A): https://www.soutocorrea.com.br/client-alerts/anpd-lanca-guia-orientativo-sobre-cookies-e-protecao-de-dados-pessoais/
- Verbatim quote checked: yes (re-fetched; "não há condição efetiva para a manifestação livre do titular" confirmed present)
- Quote substring confirmed at: section on cookies estritamente necessários
- URL fetched (Quote B): https://lefosse.com/noticias/alerta/anpd-publishes-guidelines-on-the-use-of-cookies/
- Verbatim quote checked: yes (fetched; phrase confirmed)
- Quote substring confirmed at: section "(i) Consent" under "Legal basis for the use of cookies"

---

### Finding 3 — ANPD guide: analytics cookies need a separate legal basis; consent is "more appropriate" for non-necessary cookies (Q2 answered)

**Evidence (verbatim, Portuguese — GoAdopt citing ANPD guide, three phrases confirmed on re-fetch):**

> "Assim, embora inexista hierarquia ou preferência entre as hipóteses legais previstas na LGPD, **o recurso ao consentimento será mais apropriado quando a coleta de informações for realizada por cookies não necessários.**"

> "A utilização de cookies para fins de medição de audiência pode ser amparada na hipótese legal do legítimo interesse em determinados contextos, observados, em qualquer hipótese, os requisitos previstos na LGPD."

**Source:** https://goadopt.io/blog/anpd-cookies-guia-orientativo-cookies-protecao-dados-pessoais/ (quoting ANPD Guia Orientativo)

**Significance:** Two options emerge under LGPD for GA: (a) consent ("mais apropriado" = more appropriate for non-necessary cookies) or (b) legitimate interest with a balancing test, only where the processing is for audience measurement in a limited context, and with an opt-out mechanism. GA is NOT classifiable as a strictly necessary cookie — it collects behavioral data to serve Google's and the controller's analytics interests, not to authenticate the user. Using GA therefore requires a legal basis independent of the session cookie.

**Verification:**
- URL fetched: https://goadopt.io/blog/anpd-cookies-guia-orientativo-cookies-protecao-dados-pessoais/
- Verbatim quote checked: yes (re-fetched; all three phrases confirmed present)
- Quote substring confirmed at: sections "Hipótese Legal – Consentimento" and "Hipótese Legal – Legítimo Interesse"

---

### Finding 4 — Institutional site vs. authenticated app: where a banner is required (Q3)

**Evidence (verbatim):**
> "Dashboard and application consent involves logged-in environments where session recordings, feature flags, and analytics tools collect detailed user interaction data requiring granular consent management beyond simple marketing website tracking."

**Source:** https://secureprivacy.ai/blog/cookie-consent-for-saas-companies

**Significance:** The secureprivacy.ai article — aimed at SaaS compliance practitioners — treats the authenticated dashboard as a place where consent IS still required for non-essential tools. The fact that a user is logged in does not remove the consent requirement for GA. Consent must be obtained for GA regardless of whether it runs on the marketing site, inside the authenticated app, or both. A common implementation pattern: show the consent banner before or immediately after the first session so the user is given a choice on GA before GA fires.

**Verification:**
- URL fetched: https://secureprivacy.ai/blog/cookie-consent-for-saas-companies
- Verbatim quote checked: yes (fetched; phrase confirmed present)
- Quote substring confirmed at: section on "Dashboard and application consent"

---

### Finding 5 — Category-based CMP pattern used by B2B SaaS (Q4)

**Evidence (paraphrased from multiple verified sources — no single source provides a uniquely quotable definition of "category-based CMP"):**

Across the sources consulted (cookie-script.com, secureprivacy.ai, cookieyes.com), the dominant pattern described for B2B SaaS is:

- **Strictly Necessary** category: always ON, no toggle for the user to disable. The banner discloses these cookies but offers no refusal option.
- **Analytics** category (e.g., GA): OFF by default or presented as opt-in. The user must actively consent before the analytics cookies fire.
- **Marketing/Advertising** category: OFF by default, opt-in.

From CookieYes (https://www.cookieyes.com/blog/cookie-consent-exemption-for-strictly-necessary-cookies/): "It's not possible to simply turn off strictly necessary cookies, as these are required for the website to operate correctly … The only way to block strictly necessary cookies is to disable all cookies in your browser settings."

This pattern directly solves the engineer's stated concern: the session cookie lives in the Necessary category, which has no refuse toggle. GA lives in the Analytics category, which is opt-in. The user choosing to decline analytics still gets full access to the authenticated platform.

**Verification:**
- URL fetched: https://www.cookieyes.com/blog/cookie-consent-exemption-for-strictly-necessary-cookies/
- Verbatim quote checked: yes (fetched; phrase confirmed)
- Quote substring confirmed at: section "Can users turn off strictly necessary cookies?"

---

### Finding 6 — Austrian DSB (Jan 2022), French CNIL (Feb 2022), Italian Garante (Jun 2022): GA violates GDPR on US data transfers (Q5 — European DPA rulings)

**Evidence:**

Austrian DSB (quoted by noyb.eu from DSB decision pages 38-39):
> "With regard to the contractual and organizational measures outlined, it is not apparent, to what extent [the measure] are effective in the sense of the above considerations."
> "Insofar as the technical measures are concerned, it is also not recognizable (...) to what extent [the measure] would actually prevent or limit access by U.S. intelligence agencies considering U.S. law."

French CNIL (quoted by cookie-script.com):
> "France also rejected Google Analytics IP address anonymization function as an adequate measure for protecting data transfers from Europe to the US."

Italian Garante (quoted by hunton.com):
> "In the Garante's ruling, website operator Caffeina Media S.r.l. was ordered to bring its processing into compliance with the GDPR within 90 days, but the ruling has wider implications as the Garante commented that it had received many 'alerts and queries' relating to Google Analytics."
> "It also stated that it called upon 'all controllers to verify that the use of cookies and other tracking tools on their websites is compliant with data protection law; this applies in particular to Google Analytics and similar services.'"

**Sources:** noyb.eu (Austrian DSB), cookie-script.com (CNIL), hunton.com (Garante). Additional coverage: Italy, Netherlands, UK, Norway, Denmark, and Sweden (per cookie-script.com) have also found GA compliance issues.

**Significance:** Between January and June 2022, three major European DPAs found GA's US data transfers unlawful. The shared finding: IP anonymization is pseudonymization, not anonymization; US surveillance law (FISA 702, EO 12.333) makes technical/contractual safeguards insufficient. The Garante explicitly called upon ALL controllers using GA to review compliance. For 4Shark, if it processes EU users' data, these rulings set the risk baseline. Even for Brazilian users only, the ANPD's rules on international transfers (LGPD Chapter V) would separately apply.

**Verification:**
- URL fetched: https://noyb.eu/en/austrian-dsb-eu-us-data-transfers-google-analytics-illegal → both DSB quotes confirmed
- URL fetched: https://cookie-script.com/blog/google-analytics-4-and-gdpr → CNIL phrase confirmed
- URL fetched: https://www.hunton.com/privacy-and-cybersecurity-law-blog/2022/06/30/italian-garante-bans-google-analytics/ → both Garante phrases confirmed

---

### Finding 7 — EU-US Data Privacy Framework (July 2023): US transfer issue modified, consent requirement unchanged (Q5 — current status)

**Evidence (verbatim):**
> "Google LLC certified on 10 July 2023" [under the EU-US Data Privacy Framework].
> "Certified US importers can now receive personal data without additional safeguards."
> "What has **not** changed is the consent requirement."
> "The current enforcement focus across member states has shifted toward the consent failure, which is more straightforward to inspect."

**Source:** https://trustyourwebsite.com/eu/en/guides/google-analytics-gdpr

**Significance:** The EU-US DPF (effective July 2023) changed the legal landscape for EU→US transfers: Google is certified under the DPF, which means the Schrems-II-era transfer violation identified by the 2022 DPA decisions is no longer automatically present for EU-based controllers. However, the DPF does NOT remove the consent requirement for placing GA cookies. Enforcement focus has shifted precisely to consent failures. (An earlier draft cited a specific pending CJEU challenge to the DPF by docket number; that claim could NOT be verified against any fetched source and is treated as UNVERIFIED — the DPF's long-term durability is an open question.) For 4Shark's LGPD obligations (Brazilian users), the EU DPF is not applicable — LGPD Chapter V and ANPD rules on international transfers govern separately.

**Verification:**
- URL fetched: https://trustyourwebsite.com/eu/en/guides/google-analytics-gdpr
- Verbatim quote checked: yes (fetched; all four quoted phrases confirmed)
- Quote substring confirmed at: sections on DPF and consent analysis

---

## Trade-offs surfaced

| Approach | Pros | Cons | Sustained by |
|---|---|---|---|
| **A — Keep GA, add category-based consent banner** | Legal under LGPD (consent basis); known pattern; maintains analytics data for opted-in users | Implementation cost (CMP); some users will decline GA → data gaps; must also address LGPD Chapter V (international transfer disclosure) | Findings 2, 3, 4, 5 |
| **B — Keep GA, use legitimate interest as legal basis** | No consent banner needed for GA (under LGPD only) | Requires formal balancing test (ANPD guide requires this); must provide opt-out mechanism; risk of ANPD challenge; does NOT work under GDPR/ePrivacy if EU users are in scope | Finding 3 |
| **C — Drop GA, use a LGPD-friendly analytics tool** | Eliminates the third-party transfer risk; no consent banner needed for analytics; simplest compliance story | Loses Google's ecosystem (attribution, audiences); migration cost; alternative tools may still set non-essential cookies | Findings 6, 7 |
| **D — Status quo (no banner, GA running)** | Zero implementation cost | False statement in privacy policy ("no third-party cookies"); no legal basis documented for GA; exposure to ANPD scrutiny and GDPR if EU users present | Findings 2, 3, 6 |

---

## What 4Shark's privacy policy must change

These are factual gaps between the current policy ("we don't exchange cookies with third parties") and the evidence:

1. **"We don't exchange cookies with third parties" is false.** GA places the `_ga` cookie (a persistent pseudonymous identifier) and sends per-visit data — IP address, client ID, session ID, device characteristics, page events — to Google LLC servers in the US. This is a third-party data exchange. The policy must accurately disclose this.

2. **The policy must distinguish cookie categories.** The session/authentication cookie and the GA cookie have different legal bases, different data flows, and different retention periods. They must be disclosed separately with their respective legal bases.

3. **A legal basis for GA must be documented.** Currently none is stated. Under LGPD, options are: (a) consent or (b) legitimate interest with a balancing test and opt-out. The choice must be documented before deployment.

4. **International transfer disclosure is missing.** GA sends data to Google LLC in the United States. LGPD Chapter V (arts. 33–36) requires disclosure of international transfers and the legal instrument used. For EU users, GDPR art. 13(1)(f) requires the same.

5. **If consent is chosen as the legal basis for GA, a consent mechanism must be implemented before GA fires.** The ANPD is explicit: consent cannot be "forced" — "não é compatível com a LGPD a obtenção 'forçada' do consentimento, isto é, de forma condicionada." GA must not load until the user has actively consented.

---

## What remains uncertain

1. **Does GA run inside the authenticated app, on the marketing/institutional site, or both?** The engineering scope of "where GA fires" determines the exact banner placement(s) needed.
2. **Does 4Shark process data of EU residents?** If yes, GDPR/ePrivacy apply in addition to LGPD, and consent is mandatory for GA (GDPR has no legitimate-interest exemption for behavioral tracking cookies under ePrivacy).
3. **Does 4Shark have a Data Processing Agreement (DPA) with Google?** Required under both LGPD (art. 39) and GDPR (art. 28) when a processor (Google) handles personal data on the controller's behalf.
4. **Which ANPD instrument covers 4Shark's international transfer of GA data to the US?** The ANPD published Resolution CD/ANPD nº 19/2024 on international data transfers. Whether 4Shark currently relies on standard contractual clauses or another instrument is not documented.
5. **Durability of the EU-US DPF.** [UNVERIFIED] A specific pending CJEU challenge to the DPF could not be confirmed against any fetched source in this research. If the DPF were invalidated, the 2022 DPA decisions on GA transfers would become relevant again for EU users — the risk is noted, the specific case status is unverified.

---

## Suggested options for main and the engineer

No recommendation is made — the choice depends on 4Shark's user geography, analytics needs, and implementation capacity.

**Option A: Implement a category-based consent banner covering GA**
- Session cookie → "Necessary" (always on, disclosed but no toggle)
- GA → "Analytics" (off by default, user must actively accept)
- Implement before GA fires on any page (marketing site and authenticated app if GA runs there)
- Legal basis: consent
- Fixes: privacy policy misstatement, missing legal basis, consent mechanism requirement, international transfer disclosure
- Evidence base: Findings 1, 2, 3, 4, 5

**Option B: Replace GA with a LGPD/GDPR-native analytics tool**
- Session cookie → "Necessary" (same as above)
- Remove GA and its `_ga` cookie entirely
- Choose a tool that does not transfer data to US servers (e.g., server-side analytics, self-hosted tools)
- Eliminates the international transfer risk and the consent requirement for analytics
- Evidence base: Findings 6, 7

**Option C: Keep GA with legitimate interest + opt-out (LGPD-only scope)**
- Only defensible if 4Shark's user base is exclusively Brazilian (no EU users)
- Requires a documented balancing test (ANPD guide requires this for legitimate interest on analytics)
- Must implement a visible, easy opt-out mechanism
- Does NOT satisfy GDPR/ePrivacy if EU users are in scope
- Evidence base: Finding 3
