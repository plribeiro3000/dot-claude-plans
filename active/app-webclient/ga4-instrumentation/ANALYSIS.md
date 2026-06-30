# ANALYSIS — Per-front privacy policy vs shared / multi-tenant fronts

> Concern raised by the engineer after wiring `PRIVACY_POLICY_URL` per Netlify front: the per-front model has an implicit "one front = one client" premise, but some fronts are shared by multiple clients. Today the shared fronts are Brazil-only, so nothing is broken now — but is a control missing before this bites us later?

## Current state

- The GA4 cookie consent banner links to `PRIVACY_POLICY_URL`, set **per Netlify front** (build-time env var → `environment.privacy_policy_url`).
- Banner is gated on `enabled: !!(analytics_id && privacy_policy_url)` (`app.module.ts`).
- Analytics is **4Shark-level**: a single GA4 property (`G-8ZJ9TGHX11`) across all BR fronts; users are disambiguated by `user_id = ${backend_slug}_${internalUserId}` (`analytics.service.ts`), where `backend_slug = env.GRAPHQL_API_SERVER.split('.')[0]`.

## The implicit premise — and why it is NOT "one front = one client"

The per-front policy URL assumes the front is the unit that decides which policy applies. The engineer's worry is that a shared front breaks "one front = one client".

**Reframe:** for the *cookie banner specifically*, the policy it links to is about **4Shark's own analytics data collection** (4Shark is the controller of the GA4 data — single property, 4Shark's privacy policy), not the client's policy. So the unit that actually matters is **jurisdiction**, not client. A shared Brazil front → every user, regardless of which client, is under BR jurisdiction → 4Shark's BR policy applies to all → correct.

So "one front = one client" is **stronger than the design actually needs**. The real premise is **"one front = one jurisdiction"**. A multi-client shared front is fine as long as all its clients are in the same jurisdiction.

## Where it actually breaks

A single front serving clients across **different jurisdictions** (e.g. Brazilian and Chilean users on the same site). Then one static per-front `PRIVACY_POLICY_URL` is wrong for part of the audience (a Chilean user sees the BR/PT policy).

- **Today:** shared fronts are BR-only → no live problem. This is a **latent risk**, not a current bug.

## Two different "consents" — do not conflate them

| | Cookie / analytics consent (this banner) | Legal-document acceptance (already exists) |
|---|---|---|
| Scope | Browser-level, **per front** | **Per user / per company**, backend-tracked |
| About | GA4 analytics cookies (`analytics_storage`) | The LGPD privacy-policy acceptance (statutory) |
| Source | `PRIVACY_POLICY_URL` env var | `pending_legal_documents_acceptance` → `/legalDocumentAcceptance` (`LegalDocumentAcceptanceModule`, versioned policy in `4shark-legal`) |
| Controller | 4Shark (analytics) | Per the user's company/jurisdiction |

**Key insight:** the robust per-user, jurisdiction-aware policy control the engineer is reaching for **already exists** — it is the legal-document-acceptance flow (#2). The cookie banner (#1) is the only piece still on the coarser per-front model. The gap is real but narrow: it is only the **cookie banner's policy link**, not the platform's legal acceptance.

## Options for control

**A. Process guardrail (cheapest, no code).** Document the rule: *"a shared front must be single-jurisdiction"*, and keep the per-front env var. Makes the real premise explicit. Risk: breaks silently if the rule is violated when onboarding a mixed-jurisdiction client onto a shared front.

**B. Runtime jurisdiction resolution (medium).** Derive the banner's policy URL from the **user's jurisdiction** (from company/backend data) at login, instead of a static per-front env var. Makes a multi-jurisdiction shared front correct. Naturally reuses the same source of truth as the legal-document-acceptance flow (#2) — unifying the two consents on one jurisdiction signal. Bigger change; depends on the jurisdiction being available client-side after login.

**C. Client → jurisdiction → backend → front registry (largest).** A source of truth that maps where each client lives. Directly answers the engineer's second worry ("onde cada cliente está em cada backend") and enables auditing + correct policy selection beyond just the banner. Foundational, but much broader than this feature.

## Recommendation

1. **Now (BR-only shared fronts):** the Phase-1 design is sound — ship it. Adopt **Option A** as a written guardrail so the premise ("shared front = single jurisdiction") is explicit and not accidental.
2. **Before onboarding the first multi-jurisdiction shared front:** do **Option B** (runtime resolution), sourcing jurisdiction from the legal-document-acceptance data path (#2). That removes the latent risk at its root and unifies the cookie banner with the existing per-user policy control.
3. **Option C** is the bigger "data control" the engineer intuited. It is worth a **separate spike** if/when knowing each client's location/backend becomes a need in its own right (auditing, multi-jurisdiction reporting) — not required just for the banner.

## Bottom line

The concern is valid but the blast radius is smaller than "one front per client": the cookie banner only needs **one jurisdiction per front**, and the analytics policy is 4Shark's, not the client's. Today's shared fronts satisfy that. The clean long-term fix (Option B) is to source the banner's policy from the same per-user jurisdiction signal the legal-acceptance flow already uses — deferred until a multi-jurisdiction shared front actually appears, guarded until then by an explicit single-jurisdiction rule.
