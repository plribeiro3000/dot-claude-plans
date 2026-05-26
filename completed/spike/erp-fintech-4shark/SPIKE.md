# SPIKE — ERP for Client Billing Operations at 4Shark

**Conducted by:** 4Shark team
**Date:** 2026-03-13
**Status:** Research complete — pending vendor evaluation

---

## Goal

Find an ERP or billing management platform to handle 4Shark's accounts receivable operations as the client base grows (including ~500 franchise units from a new partnership). The product and payment infrastructure are already solved — this is purely an operational need.

---

## Context

4Shark is a B2B SaaS that sells variable compensation management software (Núcleos) to companies. It is growing its client base, including a new franchise partnership with a franchisor that has ~500 franchise units.

The company currently manages client billing manually or with minimal tooling. What is missing is a back-office platform to industrialize the billing and collections process.

---

## What Needs to Be Solved

| # | Need |
|---|---|
| N1 | Client registration with payment due dates, contract values, and billing cycles |
| N2 | Automated pre-due-date notification: email to client ~1 week before ("your payment is coming up") |
| N3 | Automatic charge trigger on due date: boleto or Pix issued automatically on the billing date |
| N4 | Automated late payment notification: email to client after overdue date ("you are X days late") |
| N5 | Internal alerts: Slack and/or email to the 4Shark team listing overdue clients |
| N6 | Overdue dashboard: which clients are late, how much is outstanding, cash flow impact, which to prioritize for manual follow-up |
| N7 | Bank reconciliation: match actual payments received against expected billing (nice to have / future) |

---

## Method

- Web research on Brazilian and international billing platforms, recurring revenue tools, dunning/collections tools, and ERPs with accounts receivable modules
- Evaluated each solution against the 7 needs listed above
- Cross-referenced pricing models against a realistic scenario of ~500 franchise clients

---

## Evidence

### Asaas

**What it does:** Brazilian PJ digital bank with full billing infrastructure — boleto, Pix, credit card, installments. Highly configurable dunning rules (notifications 5, 10, 15, or 30 days before due date; overdue alerts every 1, 3, 7, 15, or 30 days after). Serasa negativation. NF-e issuance.

| Need | Status |
|---|---|
| N1 Client registration | ✅ Yes |
| N2 Pre-due-date notification | ✅ Yes — configurable per client |
| N3 Automatic boleto/Pix issuance | ✅ Yes |
| N4 Post-due-date notification | ✅ Yes |
| N5 Internal alerts (Slack) | ⚠️ Partial — REST webhook (up to 10 URLs); no native Slack |
| N6 Overdue dashboard | ✅ Yes |
| N7 Bank reconciliation | ✅ Yes — integrated digital account |

**Pricing:**
- No fixed monthly fee
- Boleto: R$ 1.99/paid transaction (promo R$ 0.99 for 3 months)
- Pix: R$ 1.99/transaction (first 100/month free for PJ)
- Credit card: R$ 0.49 + 3.49%
- WhatsApp notification: R$ 0.55/message
- Serasa negativation: R$ 9.90/title

**API:** REST — well documented, granular webhooks, up to 10 configurable URLs

**Estimated cost with 500 clients (monthly boleto):** ~R$ 995/month with no fixed fee

**Strengths:** No monthly fee, most configurable dunning in the market, pay-per-use ideal for scaling to 500 franchises, robust API for Rails integration.

**Weaknesses:** N5 (internal team alerts) requires 1–2 days of development in the Rails app via webhook; interface considered dated by some users.

---

### Iugu

**What it does:** Financial automation platform for recurrence and subscriptions. Boleto, Pix, credit card, and Bolix. Official Ruby SDK available.

| Need | Status |
|---|---|
| N1 Client registration | ✅ Yes |
| N2 Pre-due-date notification | ✅ Yes |
| N3 Automatic boleto/Pix issuance | ✅ Yes |
| N4 Post-due-date notification | ✅ Yes |
| N5 Internal alerts (Slack) | ⚠️ Partial — webhooks/triggers |
| N6 Overdue dashboard | ✅ Yes |
| N7 Bank reconciliation | ✅ Yes |

**Pricing:**
- Essential plan: ~R$ 149/month
- Boleto: R$ 2.50/paid transaction
- Pix: R$ 1.50/transaction
- Credit card (7–12x): 4.79%
- Ruby SDK: github.com/iugu/iugu-ruby

**API:** 140+ REST endpoints, official Ruby SDK, webhooks

**Strengths:** Official Ruby SDK enables native integration with Núcleos (Rails), mature and well-documented API.

**Weaknesses:** Boleto more expensive (R$ 2.50 vs. R$ 1.99 at Asaas), fixed monthly fee even in low-volume months, N5 not native.

---

### Vindi

**What it does:** Specialist platform for B2B recurrence and subscriptions. Smart retry, multiple acquirers, Bolepix, customizable branded notifications.

| Need | Status |
|---|---|
| N1 Client registration | ✅ Yes |
| N2 Pre-due-date notification | ✅ Yes |
| N3 Automatic boleto/Pix issuance | ✅ Yes |
| N4 Post-due-date notification | ✅ Yes |
| N5 Internal alerts (Slack) | ⚠️ Partial — webhooks |
| N6 Overdue dashboard | ✅ Yes — 9 reports on Essential, full on higher plans |
| N7 Bank reconciliation | ✅ Yes — multi-bank on Corporate plan |

**Pricing:**
- Essential: R$ 299/month (1 user, 9 reports)
- Pro/Premium/Corporate: on request
- Boleto: R$ 2.99/transaction
- Pix: 0.95% + minimum R$ 1.60 (percentage gets expensive for high-value B2B contracts)
- Credit card: 3.87%

**Strengths:** Specialist in B2B recurrence, smart retry reduces passive delinquency, robust dashboard on Pro+.

**Weaknesses:** More expensive than Asaas, Pix with percentage (bad for high-value B2B contracts), relevant plans without transparent pricing.

---

### Superlógica Assinaturas

**What it does:** ERP built specifically for SaaS and recurring businesses. Native metrics: MRR, churn, LTV, average ticket. Smart dunning, integrated NF-e, API and webhooks.

| Need | Status |
|---|---|
| N1 Client registration | ✅ Yes |
| N2 Pre-due-date notification | ✅ Yes |
| N3 Automatic boleto/Pix issuance | ✅ Yes (boleto confirmed; Pix not clearly documented) |
| N4 Post-due-date notification | ✅ Yes |
| N5 Internal alerts (Slack) | ⚠️ Partial — webhooks |
| N6 Overdue dashboard | ✅ Yes — unique with native SaaS metrics |
| N7 Bank reconciliation | ✅ Yes — via integrated PJBank |

**Pricing:** On request only. Perceived as expensive for smaller companies.

**Strengths:** Only platform with MRR/churn/LTV native — relevant as 4Shark grows and needs business-level reporting. Built for exactly 4Shark's business model.

**Weaknesses:** Opaque pricing, Pix support not clearly confirmed, slower commercial support for smaller accounts.

---

### Omie

**What it does:** Full online ERP. Accounts receivable module with unlimited boleto on any plan, Pix via Omie.Cash, dunning workflow via add-on app, automatic bank reconciliation, full financial reports. Manager receives daily email summary of overdue clients.

| Need | Status |
|---|---|
| N1 Client registration | ✅ Yes |
| N2 Pre-due-date notification | ✅ Yes |
| N3 Automatic boleto/Pix issuance | ✅ Yes |
| N4 Post-due-date notification | ✅ Yes |
| N5 Internal alerts (Slack) | ⚠️ Daily email summary for managers; no Slack |
| N6 Overdue dashboard | ✅ Yes — cash flow, accounts receivable |
| N7 Bank reconciliation | ✅ Yes |

**Pricing:** From R$ 99/month (scaled by revenue). Unlimited boleto included. Free Pix. Advanced dunning is a paid add-on in the Omie marketplace.

**Fit for 4Shark:** Good cost-benefit, but is a full ERP with many irrelevant modules. Good option if 4Shark also needs fiscal/inventory management in the future.

---

### Conta Azul

**What it does:** ERP for SMBs with recurring contracts. Automatic issuance of boleto, Pix Cobrança, or credit card link per contract. Dunning via email, SMS, and WhatsApp.

| Need | Status |
|---|---|
| N1 Client registration | ✅ Yes |
| N2 Pre-due-date notification | ✅ Yes |
| N3 Automatic boleto/Pix issuance | ✅ Yes |
| N4 Post-due-date notification | ✅ Yes |
| N5 Internal alerts (Slack) | ❌ Not identified |
| N6 Overdue dashboard | ⚠️ Partial |
| N7 Bank reconciliation | ✅ Yes |

**Pricing:**
- Essential: R$ 159.90/month (1 user)
- Control: R$ 309.90/month (2 users)
- Advanced: R$ 399.90/month (5 users)
- Performance: R$ 719.90/month (15 users)

**Strengths:** Recurring contracts well handled, multi-channel notification, automatic reconciliation.

**Weaknesses:** N5 not identified, limited external API compared to Asaas/Iugu, no SaaS metrics, expensive for what it delivers compared to Omie.

---

### EFI Bank (ex-Gerencianet)

**What it does:** BACEN-regulated financial institution. Payment infrastructure with Pix API (including Pix Automático launched June 2025), registered boletos, recurring subscriptions. This is infrastructure, not a management platform.

| Need | Status |
|---|---|
| N1 Client registration | ⚠️ Basic |
| N2 Pre-due-date notification | ⚠️ Basic |
| N3 Automatic boleto/Pix issuance | ✅ Yes |
| N4 Post-due-date notification | ⚠️ Via API |
| N5 Internal alerts (Slack) | ⚠️ Webhook available |
| N6 Overdue dashboard | ⚠️ Basic — no delinquency focus |
| N7 Bank reconciliation | ✅ Yes |

**Pricing:** No fixed monthly fee. Boleto: free to issue. Pix: free (BACEN regulation).

**Strengths:** Pix Automático (automatic debit via Pix, launched June 2025 — client authorizes once, future charges are automatic), very low cost.

**Weaknesses:** Infrastructure, not management — N1, N5, N6 require custom development. Not suitable as a standalone solution for 4Shark.

---

### Neofin

**What it does:** Specialized intelligent collections software. Collections CRM with full history per client, multi-channel dunning (email, WhatsApp, SMS, voice), automatic renegotiation portal, protest, Serasa negativation, delinquency dashboards. Integrates on top of existing ERPs (Omie, Protheus). Does NOT issue boleto/Pix directly — requires a partner gateway.

| Need | Status |
|---|---|
| N1 Client registration | ✅ Yes — collections CRM |
| N2 Pre-due-date notification | ✅ Yes |
| N3 Automatic boleto/Pix issuance | ❌ No — requires partner gateway |
| N4 Post-due-date notification | ✅ Yes |
| N5 Internal alerts (Slack) | ✅ Yes — CRM with alerts per client for financial team |
| N6 Overdue dashboard | ✅ Yes — delinquency, payment profile |
| N7 Bank reconciliation | ✅ Via integrated ERP |

**Pricing:** On request.

**Fit for 4Shark:** Excellent specifically for N4, N5, N6. Makes more sense as an additional layer in the future, when delinquency volume justifies a dedicated collections tool (combined with Asaas for issuance).

---

### Chargebee

**What it does:** Global subscription billing platform. Automated dunning with smart retries, automatic emails throughout the entire client lifecycle, MRR/churn/ARR/delinquency dashboards, robust API, **native Slack integration**, integrations with 30+ tools. Boleto via Stripe, Pix via EBANX or dLocal.

| Need | Status |
|---|---|
| N1 Client registration | ✅ Yes |
| N2 Pre-due-date notification | ✅ Yes |
| N3 Automatic boleto/Pix issuance | ⚠️ Yes, via partner gateway (additional friction) |
| N4 Post-due-date notification | ✅ Yes |
| N5 Internal alerts (Slack) | ✅ **Native Slack integration** |
| N6 Overdue dashboard | ✅ Yes — full revenue management |
| N7 Bank reconciliation | ✅ Yes |

**Pricing:**
- Starter: Free up to US$ 250K total cumulative billing; then 0.75%
- Performance: US$ 599/month (~R$ 3,000/month) up to US$ 100K/month; then 0.75%
- Enterprise: on request

**Strengths:** Only platform with native Slack (solves N5 without development), world-class revenue management dashboard, Starter plan free up to significant scale.

**Weaknesses:** Boleto/Pix with friction (partner gateway required), high cost on Performance, documentation and support primarily in English, no native Brazilian NF-e support.

---

## Comparative Table

| Platform | N1 | N2 | N3 | N4 | N5 Slack | N6 | N7 | Rails API | Base price |
|---|---|---|---|---|---|---|---|---|---|
| **Asaas** | ✅ | ✅ | ✅ | ✅ | Webhook¹ | ✅ | ✅ | ✅ | No monthly fee |
| **Iugu** | ✅ | ✅ | ✅ | ✅ | Webhook¹ | ✅ | ✅ | ✅ Ruby SDK | ~R$ 149/mo |
| **Vindi** | ✅ | ✅ | ✅ | ✅ | Webhook¹ | ✅ | ✅ Corp | ✅ | R$ 299/mo+ |
| **Superlógica** | ✅ | ✅ | ✅ | ✅ | Webhook¹ | ✅ + MRR/Churn | ✅ | ✅ | On request |
| **Omie** | ✅ | ✅ | ✅ | ✅ | Email summary | ✅ | ✅ | ✅ | R$ 99/mo+ |
| **Conta Azul** | ✅ | ✅ | ✅ | ✅ | ❌ | Partial | ✅ | Limited | R$ 159/mo+ |
| **EFI Bank** | Basic | Basic | ✅ | Via API | Webhook¹ | Basic | ✅ | ✅ | No monthly fee |
| **Neofin** | ✅ | ✅ | ❌² | ✅ | ✅ Native CRM | ✅ | Via ERP | ✅ | On request |
| **Chargebee** | ✅ | ✅ | Via gateway³ | ✅ | ✅ **Native** | ✅ Revenue | ✅ | ✅ | $0–$599/mo |

¹ *Webhook: Slack integration via ~1–2 days of dev in the Rails app. Not an eliminating factor.*
² *Neofin does not issue charges — requires a partner gateway (e.g., Asaas) for N3.*
³ *Chargebee: boleto/Pix via partner gateway (Stripe or EBANX), additional setup required.*

---

## Fit Ranking for 4Shark

### 1st — Asaas (primary recommendation)
Covers 6 of 7 needs natively. N5 (Slack) resolved with ~1–2 days of development via webhook in the Rails app. No fixed monthly fee — ideal for scaling from current clients to 500 franchises without proportional fixed cost. Well-documented API for Rails.

**Estimated cost with 500 clients paying monthly boleto:** ~R$ 995/month with no fixed fee.

### 2nd — Superlógica Assinaturas
Built exactly for recurring B2B SaaS. Only platform with MRR/churn/LTV native — relevant as 4Shark grows and needs business-level reporting. Opaque pricing is the main risk.

### 3rd — Iugu
Official Ruby SDK facilitates native integration with Núcleos. Mature API. Loses to Asaas on cost (boleto R$ 2.50 vs. R$ 1.99 + fixed monthly fee).

### 4th — Vindi
Specialist in recurrence, smart retry reduces passive delinquency. More expensive, Pix with percentage is bad for high-value B2B contracts.

### 5th — Chargebee (if N5 is critical and no development resource is available)
Only platform with native Slack. However, boleto/Pix requires gateway setup, high cost in USD, additional complexity for Brazilian payment methods.

---

## Note: Pix Automático (new in 2025)

The BACEN launched **Pix Automático** in June 2025 — it works like automatic debit via Pix infrastructure. The client authorizes once, and future charges are automatically debited without any client action. Asaas, Vindi, and EFI Bank already support it. Significantly reduces passive delinquency (clients who forget to pay) — highly relevant for 4Shark's recurring contracts.

---

## Conclusions

No single platform is a clear winner for every need, but **Asaas** is the strongest option for the current stage:
- Pay-per-use model scales cleanly with the franchise ramp-up
- All critical needs covered natively except N5, which is a small engineering task
- Ruby/Rails API compatibility is solid

The main open question is whether the 4Shark team wants to invest 1–2 days of development to handle N5 via webhook (favors Asaas/Iugu/Vindi), or prefers to have Slack out of the box without development (favors Chargebee, at the cost of boleto/Pix friction).

---

## Next Steps

- Evaluate Asaas pricing with actual client volume projections (current + franchise ramp-up)
- Evaluate Superlógica pricing — may justify premium if MRR/churn reporting is a priority
- Decide on N5 approach: webhook development (~1–2 days) vs. Chargebee (native Slack, gateway friction)
- Request demos from top 2–3 candidates
- Map integration points between selected platform and Núcleos (Rails)
