# SPIKE — UnoERP API availability for users and sales integration

**Conducted by:** plribeiro3000
**Date:** 2026-03-13
**Status:** Closed — see conclusions

---

## Goal

Determine whether unoerp.com.br exposes public APIs that would allow integrating users and sales data (orders, invoices, products) with an external system, and identify what authentication/access model is used.

---

## Method

- Web search for public API documentation, developer portal, and SDK
- Direct URL probing of common API/developer paths on unoerp.com.br
- GitHub search for community-built integrations
- Analysis of the official manual at unoerp.com.br/manual
- Review of the integrations/plugins page at unoerp.com.br/integracoes-e-plugins

---

## Evidence

### URLs probed — all returned 404 or ECONNREFUSED

| URL | Result |
|-----|--------|
| unoerp.com.br/api | 404 |
| unoerp.com.br/api/docs | 404 |
| unoerp.com.br/developer | 404 |
| unoerp.com.br/developers | 404 |
| unoerp.com.br/manual/api.html | 404 |
| api.unoerp.com.br | 404 |
| docs.unoerp.com.br | ECONNREFUSED |
| developer.unoerp.com.br | ECONNREFUSED |

### GitHub

Zero repositories found related to the Brazilian UnoERP.

### Manual (unoerp.com.br/manual)

The only API-related page found was `santander-api.html`, which documents UnoERP *consuming* the Santander bank API for automatic boleto registration — not an API exposed by UnoERP.

### Third-party review site

`portalerp.com/unoerp` lists *"Integrações com outros softwares via API"* as a product feature — no technical details provided.

### Integrations page

UnoERP offers paid plugins that consume third-party APIs (Nuvemshop, SkyHub/B2W, AnyMarket, Bling, WooCommerce, Magento, Tray, Mercos, etc.). The system is the *consumer*, not the *provider*.

### Important disambiguation

There is an Italian company `unoerp.it` (Uniwix srl) with a publicly documented developer API at `unoerp.it/api-per-developers/`. This is a completely different product — search results mixing both can cause confusion.

---

## Conclusions

| Question | Finding |
|----------|---------|
| Is there a public documented API? | Not found — all endpoints return 404/ECONNREFUSED |
| Did UnoERP explicitly state they have no API? | No — never stated |
| Is there likely an internal API? | Probably yes — the system integrates with multiple platforms, implying internal integration logic |
| Can an external developer access it? | Likely requires a formal partnership, not self-service |
| Are there community integrations on GitHub? | None found |

The absence of a public portal does not confirm the absence of an API. It indicates the access model is likely **private, partner-gated**.

---

## Next Steps

- Contact UnoERP directly to confirm API availability for integrators:
  - **Technical support**: (15) 4063-9301
  - **Commercial**: (11) 3454-3258
  - Ask specifically for: *"documentação de API para integradores"* or *"programa de parceria técnica"*
- If a private API exists and access is granted → create PLAN.md for integration
- If no API is available → evaluate alternative paths:
  - Use an intermediary already integrated (e.g., Bling, which has a public API)
  - Request custom development from UNO Soluções
  - Evaluate other ERP options with public APIs

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
