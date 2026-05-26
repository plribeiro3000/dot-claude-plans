# SPIKE — Full Financial ERP for 4Shark Operations

**Conducted by:** 4Shark team
**Date:** 2026-03-13
**Status:** Research complete — pending vendor demos and final decision
**Previous spike:** SPIKE.md (billing/collections platform — scope: accounts receivable only)

---

## Goal

Expand the evaluation from the billing/collections spike (SPIKE.md) to a full financial ERP capable of running 4Shark's complete financial operation: accounts receivable, accounts payable, fiscal documents, cash flow management, financial planning, and accounting.

SPIKE.md answered: *"Which platform automates billing for ~500 clients?"*
This spike answers: *"Which ERP runs the full financial operation of a growing B2B SaaS?"*

---

## Context

4Shark is a B2B SaaS selling variable compensation management software (Núcleos) to companies across Latin America. Revenue comes from two sources:
- **Brazilian clients** paying in BRL (boleto, Pix) — managed by the Brazilian entity
- **Latin American clients** (non-Brazilian) paying in USD to a US LLC — revenue stays in the US, covering partner costs (Danilo) and USD-billed infrastructure (AWS, MongoDB, Cloudflare)

The two operations are legally and financially separate. There is no formal contract between the US LLC and the Brazilian entity. However, the founders need a **consolidated view of total company P&L** to understand real profitability — meaning BRL and USD revenues must appear together in reporting.

The financial operation is currently fully manual — contracts, billings, and financial control are managed by the accounting partner (Sérgio) in spreadsheets and Monday. The ERP replaces this. No automatic integration with Núcleos is expected — all data entry will be manual.

**Primary user:** Sérgio (accounting co-founder).
**External accounting firm:** needs read access or file export (SPED Contábil).
**Team:** 3 co-founders today, no employees — simple payment approval flow, no multi-level workflow needed.

---

## Architectural Priority

This ERP is a long-term investment — it will be used for years. Evaluate candidates in this priority order:

1. **Single system covering everything natively (N1–N15)** — ideal
2. **Two systems with a native, automatic integration maintained by the vendors** — acceptable
3. **Single system covering most needs, with known gaps accepted for now** — acceptable if gaps are minor
4. **Two systems requiring custom integration** — last resort, only if simple and well-scoped

---

## Requirements

### Core Requirements (inherited from SPIKE.md — already researched)

| # | Need |
|---|---|
| N1 | Client registration with payment due dates, contract values, and billing cycles |
| N2 | Automated pre-due-date notification: email to client ~1 week before |
| N3 | Automatic charge trigger on due date: boleto or Pix issued automatically |
| N4 | Automated late payment notification |
| N5 | Internal alerts: Slack and/or email to the 4Shark team listing overdue clients |
| N6 | Overdue dashboard: who is late, outstanding amount, cash flow impact |
| N7 | Bank reconciliation: match actual payments against expected billing |

### New Requirements (expanded scope)

| # | Need |
|---|---|
| N8 | **NFS-e issuance**: automatic electronic service invoice generation integrated with billing, SEFAZ submission, XML storage |
| N9 | **Accounts payable**: supplier registration, payment scheduling, tax and withholding control (ISS, PIS, COFINS, IRRF). No multi-level approval needed |
| N10 | **Contract management with indexers**: contract registration, validity control, IPCA/IGPM adjustment, automatic renewal, automatic billing generation |
| N11 | **Consolidated cash flow**: daily/monthly/annual, multi-bank consolidation, real-time balance, projection based on contracts |
| N12 | **DRE gerencial (P&L)**: revenue and expense by cost center, product, or client; margin visibility |
| N13 | **Financial planning and forecast**: annual/monthly budget, previsto vs. realizado, scenario simulation, burn rate, runway |
| N14 | **Accounting export for external firm**: balancete, razão contábil — read access for external accountant or SPED Contábil export |
| N15 | **Consolidated multi-currency reporting**: USD (US LLC) + BRL (Brazil) in a single consolidated P&L — operations remain separate, reporting must be unified |

### Plus Requirements (nice to have — cannot block the decision)

| # | Need | Notes |
|---|---|---|
| P1 | **Investment control** (CDB, funds, fixed income, yield) | No investments today — future need |
| P2 | **Multi-level AP approval workflow** | Future need when headcount grows |
| P3 | **AI for data querying and insights** | Accounting partner self-serves data without depending on engineering |

---

## Evidence

### NetSuite (Oracle)

Brazilian fintech SaaS companies use NetSuite globally. Native Brazilian localization available via SuiteApps (certified partners).

| Requirement | Status | Notes |
|---|---|---|
| N1–N7 (billing, AR, reconciliation) | ✅ | Brazil Banking Integration SuiteApp: boleto, Pix QR codes, automated interest on late payments |
| N8 NFS-e | ✅ | Brazilian Hub SuiteApp with SEFAZ integration |
| N9 AP | ✅ | Full supplier management and AP module |
| N10 Contracts with IPCA/IGPM | ⚠️ | Contract management yes; IPCA/IGPM indexation requires custom scripting or manual tracking — not native |
| N11 Cash flow | ✅ | Multi-bank reconciliation, cash flow forecasting |
| N12 DRE gerencial | ✅ | Configurable GL and financial reporting |
| N13 Forecast/budget | ✅ | Planning & Budgeting module; revenue management |
| N14 Accounting export | ✅ | SPED ECD, ECF, and EFD ICMS export natively |
| N15 Multi-currency P&L | ✅ **native** | NetSuite OneWorld: each subsidiary (BRL and USD) has its own base currency; consolidated P&L with period exchange rates (average rate for P&L, closing rate for balance sheet) |
| P3 AI | ⚠️ | Analytics features available |

**Pricing:** ~R$ 40K–R$ 60K/month (annual contract, 10 users minimum). Implementation: additional R$ 25K–R$ 75K, 12–16 weeks with certified Brazil localization partner.

**Strengths:** Only platform with fully native multi-currency consolidation AND full Brazilian fiscal compliance (SPED, NFS-e, SEFAZ). Best long-term scalability. Single system.

**Weaknesses:** Very expensive for current stage. Requires certified implementation partners. IPCA/IGPM indexation not native (universal gap).

---

### Nibo

Brazilian financial management platform built around accountant collaboration. Primary users are SMBs and their external accounting firms.

| Requirement | Status | Notes |
|---|---|---|
| N1–N7 (billing, AR, reconciliation) | ✅ | Native boleto (100 free/plan), Pix reception (R$ 2,49/transaction), automated NFS-e |
| N8 NFS-e | ✅ | Municipal SEFAZ integration |
| N9 AP | ✅ | Full AP with CNAB file generation and supplier management |
| N10 Contracts with IPCA/IGPM | ❌ | No contract management module |
| N11 Cash flow | ✅ | Multi-bank, core feature |
| N12 DRE gerencial | ✅ | Auto-generated |
| N13 Forecast/budget | ⚠️ | Budget on higher plans; forecasting limited |
| N14 Accounting export | ✅ | Built for external accountants: read access, SPED via Fortes integration |
| N15 Multi-currency P&L | ❌ | BRL only — critical gap |
| P3 AI | ❌ | Not found |

**Pricing:** R$ 500–R$ 2.000/month. Implementation: days to weeks.

**Strengths:** Best-in-class for Brazilian compliance. Lowest cost. Designed for accountant collaboration — fits the Sérgio + external firm setup. Fast to deploy.

**Weaknesses:** No multi-currency (N15). No contract management (N10).

---

### Omie

Full Brazilian ERP for SMBs. Previously evaluated in SPIKE.md for AR only.

| Requirement | Status | Notes |
|---|---|---|
| N1–N7 (billing, AR, reconciliation) | ✅ | Native boleto, Pix, NFS-e, bank reconciliation |
| N8 NFS-e | ✅ | Full fiscal module with AI-assisted tax calculation |
| N9 AP | ✅ | Native AP module with CNAB and supplier management |
| N10 Contracts with IPCA/IGPM | ❌ | No dedicated contract management. Manual tracking required |
| N11 Cash flow | ✅ | Multi-bank, operational and projected |
| N12 DRE gerencial | ✅ | Auto-generated |
| N13 Forecast/budget | ⚠️ | DFC and DRE yes; budget/forecast limited |
| N14 Accounting export | ✅ | Accountant access and SPED export |
| N15 Multi-currency P&L | ⚠️ via Power BI | No native multi-currency. **Native Power BI connector exists** — Omie feeds into Power BI, where currency conversion and consolidated P&L are configured. Pre-built integration maintained by Omie, no custom engineering required |
| P3 AI | ⚠️ | Launching AI features — status unclear |

**Pricing:** R$ 99/month base. With Power BI Pro (~R$ 500–R$ 1.000/month): total ~R$ 1.500–R$ 3.500/month.

**Strengths:** Covers N1–N14. Native Power BI connector means N15 is achievable within priority 2 architecture (two systems, native integration). Lowest cost among full-ERP options. Fast implementation.

**Weaknesses:** N15 requires Power BI setup and maintenance — someone on the team needs to configure the consolidated P&L dashboard. No contract management with IPCA/IGPM (N10). Budget/forecast module limited.

---

### Sankhya

Mid-market Brazilian ERP (typically R$ 10M–R$ 500M revenue companies).

| Requirement | Status | Notes |
|---|---|---|
| N1–N7 | ⚠️ | AP/AR confirmed; boleto/Pix depth unclear |
| N8 NFS-e | ✅ | Confirmed |
| N9 AP | ✅ | Full module |
| N10 Contracts with IPCA/IGPM | ❌ | Not documented |
| N11–N13 Cash flow / DRE / Forecast | ✅ | Built-in BI module for KPIs and dashboards |
| N14 Accounting export | ⚠️ | Expected for a mid-market ERP — not explicitly confirmed |
| N15 Multi-currency | ⚠️ | Multi-currency transactions supported; consolidated reporting methodology unclear |
| P3 AI | ❌ | Not found |

**Pricing:** Unclear — public data shows R$ 29–R$ 599/month but mid-market positioning suggests higher. Requires direct contact.

**Assessment:** Too much ambiguity to rank confidently. May solve N15. Requires one demo call to validate before including or excluding.

---

### TOTVS Protheus

Enterprise Brazilian ERP. Market leader in manufacturing and distribution.

**Assessment: Eliminated.**

Enterprise ERP built for manufacturing/distribution, not SaaS. Implementation: 4–6 months minimum with certified partners. Pricing: R$ 5.000–R$ 20.000+/month. Cost and complexity far exceed 4Shark's current stage and team size.

---

### SAP Business One

Mid-market international ERP with LatAm presence.

| Requirement | Status | Notes |
|---|---|---|
| N1–N14 | ✅ | Full ERP coverage |
| N15 Multi-currency | ✅ | Dual accounting; multi-currency consolidation native |
| Brazil localization | ⚠️ | Requires LatAm localization partner for NFS-e, SPED, SEFAZ — adds cost and complexity |

**Pricing:** ~R$ 40K–R$ 80K/year (cloud). Implementation: additional cost via partner.

**Assessment:** Viable alternative to NetSuite for multi-currency at lower cost. But Brazil localization is not built-in — requires a partner, which adds friction and ongoing dependency. Less clean than NetSuite for the Brazilian fiscal layer.

---

## Cross-Platform Gap: Contract Management with Indexers (N10)

**No evaluated platform has native IPCA/IGPM indexation for contracts.**

This is a universal gap. Options:
- Manual tracking in a spreadsheet (acceptable at current scale)
- Use Superlógica as the contract/AR layer on top of the chosen ERP — it supports indexers natively (see SPIKE.md), but adds a second system and removes AP from Superlógica's scope
- Custom development on the chosen ERP

This gap does not eliminate any platform but must be planned for separately.

---

## Comparative Table

| Platform | N1–N7 | N8 NFS-e | N9 AP | N10 Idx | N11 Cash | N12 DRE | N13 Forecast | N14 Acct. | N15 Multi-FX | P1 Invest. | P3 AI | Price/month |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **NetSuite** | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ native | ⚠️ | ⚠️ | R$ 40K–60K |
| **Omie + Power BI** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ⚠️ | ✅ | ⚠️ via BI¹ | ⚠️ | ⚠️ | R$ 1,5K–3,5K |
| **Nibo** | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ | ⚠️ | ✅ | ❌ | ❌ | ❌ | R$ 500–2K |
| **Sankhya** | ⚠️ | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | ❌ | ❌ | To confirm |
| **SAP B1** | ✅ | ⚠️ partner | ✅ | ⚠️ | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | ❌ | R$ 40K–80K/yr |
| **Conta Azul** | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ | ⚠️ | ✅ | ❌ | ❌ | ❌ | R$ 159–720 |
| **Superlógica** | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ SaaS | ⚠️ | ⚠️ | ❌ | ❌ | ❌ | On request |
| **Protheus** | — | — | — | — | — | — | — | — | — | — | — | Eliminated |

¹ *Omie N15: native Power BI connector — pre-built integration, not custom engineering.*

---

## Fit Ranking

### 1st — Omie + Power BI (best fit for current stage)

Covers N1–N14 natively. N15 handled via the native Power BI connector — pre-built integration maintained by Omie, no custom engineering. Fits **priority 2** architecture (two systems, native integration).

- Cost: R$ 1.500–R$ 3.500/month
- Implementation: weeks
- No custom development needed
- Gap: N10 (IPCA/IGPM) — universal across all low-cost platforms
- Risk: Power BI requires setup and maintenance by someone on the team

### 2nd — NetSuite (best fit for long-term)

Single system covering N1–N15 natively. Full Brazilian fiscal compliance via certified SuiteApps. No second system required. N10 still not native (universal gap).

- Cost: ~R$ 40K–R$ 60K/month
- Implementation: 12–16 weeks + certified Brazil localization partner
- Risk: significant financial investment; potentially oversized for current stage

### 3rd — Nibo (if multi-currency is deferred)

Best Brazilian compliance at lowest cost. Strongest accountant-collaboration design. If the team decides to manage USD consolidation manually while operations are small, Nibo is the fastest path.

- Cost: R$ 500–R$ 2.000/month
- Implementation: days to weeks
- Gaps: N15 (multi-currency) and N10 (IPCA/IGPM)
- Risk: N15 handled manually becomes unsustainable as the USD client base grows

### 4th — Sankhya (pending demo)

May solve N15 at mid-market pricing. Not enough confirmed information to rank higher. One demo call needed.

---

## Open Items

1. **N10 (IPCA/IGPM):** No platform solves this natively. Decision needed: accept manual tracking for now, or use Superlógica as the contract/AR layer alongside the chosen ERP.

2. **Power BI ownership (if Omie):** Someone needs to configure and maintain the consolidated P&L dashboard in Power BI. Who on the team owns this?

3. **NetSuite entry cost:** Worth one call with a NetSuite LatAm reseller before ruling it out — there may be lighter entry packages for early-stage SaaS companies.

4. **Sankhya validation:** One demo call to confirm N15 (multi-currency) and N10 (IPCA/IGPM) before finalizing the ranking.

---

## Next Steps

1. Demo with **Omie** — validate AP depth, Power BI integration setup, and forecast module
2. Demo with **Nibo** — validate accountant access model; confirm whether a BI layer is feasible as complement
3. One call with **NetSuite LatAm reseller** — understand entry-level pricing for a SaaS company at 4Shark's stage
4. One call with **Sankhya** — validate N15 and N10
5. Decide on N10 strategy: accept manual tracking, or add Superlógica as a contract layer
6. Decide who owns Power BI setup if Omie is chosen
