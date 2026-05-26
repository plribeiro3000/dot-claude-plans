# Research: Brazilian Payroll Tax Charges (Encargos Trabalhistas)
# Lucro Presumido vs Lucro Real - Focus on Employee Commissions
# Date: 2026-02-27

---

## 1. LUCRO PRESUMIDO - Complete Breakdown

### A) Payroll Charges (Encargos sobre Folha/Comissões)

These charges apply equally to salaries and commissions paid to CLT employees.

#### Direct Social Charges (Encargos Sociais Diretos)

| Charge | Rate | Notes |
|--------|------|-------|
| INSS Patronal (CPP) | 20.00% | Over total payroll (Art. 22, Lei 8.212/91) |
| RAT/SAT (Gilrat) | 1% to 3% | Depends on risk level of activity (CNAE). Adjusted by FAP (0.5 to 2.0), so effective range is 0.5% to 6% |
| **Terceiros/Sistema S** | **5.80%** | See breakdown below |
| FGTS | 8.00% | Monthly deposit (Lei 8.036/90) |

**Total direct social charges: 34.80% to 36.80%** (using RAT midpoint of 2%)

#### Terceiros/Sistema S - Detailed Breakdown

For **Industry** (FPAS 515):

| Entity | Rate | Purpose |
|--------|------|---------|
| Salário-Educação (FNDE) | 2.50% | Education funding |
| INCRA | 0.20% | Agrarian reform |
| SENAI | 1.00% | Industrial training |
| SESI | 1.50% | Industrial social services |
| SEBRAE | 0.60% | Small business support |
| **Total** | **5.80%** | |

For **Commerce** (FPAS 507):

| Entity | Rate | Purpose |
|--------|------|---------|
| Salário-Educação (FNDE) | 2.50% | Education funding |
| INCRA | 0.20% | Agrarian reform |
| SENAC | 1.00% | Commercial training |
| SESC | 1.50% | Commercial social services |
| SEBRAE | 0.60% | Small business support |
| **Total** | **5.80%** | |

For **Services** (FPAS 515 or varies):

| Entity | Rate | Purpose |
|--------|------|---------|
| Salário-Educação (FNDE) | 2.50% | Education funding |
| INCRA | 0.20% | Agrarian reform |
| SESC or SESI | 1.50% | Depends on classification |
| SENAC or SENAI | 1.00% | Depends on classification |
| SEBRAE | 0.60% | Small business support |
| **Total** | **5.80%** | |

Note: The total for Terceiros is 5.80% regardless of sector (commerce, industry, or services), only the distribution among entities changes based on FPAS code.

#### Labor Provisions (Encargos Trabalhistas / Provisões)

| Provision | Rate | Formula/Notes |
|-----------|------|---------------|
| 13th Salary | 8.33% | 1/12 of monthly salary = 8.33% |
| Vacation + 1/3 constitutional bonus | 11.11% | (1/12) + (1/3 of 1/12) = 8.33% + 2.78% = 11.11% |
| DSR on Commissions | ~16% to 20% | See formula below |
| FGTS on 13th + Vacation | 1.55% | 8% x (8.33% + 11.11%) = 8% x 19.44% |
| INSS/RAT/Terceiros on 13th + Vacation | ~5.58% | (20% + 2% + 5.8%) x 19.44% (approx) |
| FGTS Termination Penalty | ~4.00% | 40% of total FGTS balance (provisioned at ~4% of payroll) |

#### DSR on Commissions - Formula and Calculation

**Formula:**
```
DSR = (Total commissions in the month / Number of business days worked) x Number of Sundays and holidays
```

- Business days include Saturdays (unless it's a holiday)
- Typical month: ~25-26 business days, 4-5 Sundays + 0-1 holidays
- **Typical DSR percentage: ~16% to 20% of commissions**

Example: In a month with 26 business days and 5 Sundays:
- DSR = Commissions x (5/26) = ~19.23%

**IMPORTANT**: DSR integrates the calculation base for 13th salary, vacation, and FGTS.

#### FGTS Termination Penalty

- Upon termination without cause: employer pays 40% of the total FGTS balance
- FGTS balance = 8% x total remuneration over employment period
- For provisioning purposes: typically estimated at 4% of payroll (based on turnover statistics)
- Since 2020, there is also a monthly contribution of 3.2% to a digital FGTS account (multa rescisória antecipada) for contracts under the "green and yellow" provisions, but this is not universally applied

---

### B) Tax Brackets/Rates for Lucro Presumido

#### Presumption Percentages by Activity (IRPJ)

| Activity | Presumption % (IRPJ) | Presumption % (CSLL) |
|----------|----------------------|----------------------|
| Fuel resale | 1.6% | 12% |
| General commerce (merchandise resale) | 8% | 12% |
| General industry | 8% | 12% |
| Cargo transport | 8% | 12% |
| Hospital/diagnostic services (with requirements) | 8% | 12% |
| Construction with material supply | 8% | 12% |
| Real estate (property sales) | 8% | 12% |
| Passenger transport | 16% | 12% |
| General services (revenue up to R$120k/year) | 16% | 12% |
| General services (revenue above R$120k/year) | 32% | 32% |
| Professional services (law, accounting, engineering) | 32% | 32% |
| Business intermediation | 32% | 32% |
| Asset administration, leasing | 32% | 32% |
| Construction (labor-only) | 32% | 32% |
| Factoring operations | 32% | 32% |
| Consulting and advisory | 32% | 32% |

#### Tax Rates Applied on Presumed Base

| Tax | Rate | Notes |
|-----|------|-------|
| IRPJ | 15% | On presumed profit |
| IRPJ Additional | 10% | On presumed profit exceeding R$20,000/month (R$60,000/quarter) |
| CSLL | 9% | On presumed profit |
| PIS | 0.65% | Cumulative regime, on gross revenue |
| COFINS | 3.00% | Cumulative regime, on gross revenue |

#### Total Effective Tax Rates by Activity (on gross revenue)

**Commerce (8% IRPJ / 12% CSLL presumption):**
- IRPJ: 8% x 15% = 1.20%
- CSLL: 12% x 9% = 1.08%
- PIS: 0.65%
- COFINS: 3.00%
- **Total: 5.93%** (without IRPJ additional)

**Services (32% IRPJ / 32% CSLL presumption):**
- IRPJ: 32% x 15% = 4.80%
- CSLL: 32% x 9% = 2.88%
- PIS: 0.65%
- COFINS: 3.00%
- **Total: 11.33%** (without IRPJ additional)

**Passenger Transport (16% IRPJ / 12% CSLL presumption):**
- IRPJ: 16% x 15% = 2.40%
- CSLL: 12% x 9% = 1.08%
- PIS: 0.65%
- COFINS: 3.00%
- **Total: 7.13%** (without IRPJ additional)

#### IMPORTANT CHANGE FOR 2026 (Lei Complementar nº 224/2025)

- Companies with annual revenue up to R$5 million: original presumption percentages maintained
- Companies with annual revenue above R$5 million: 10% surcharge on the presumption percentage applied to revenue exceeding R$5 million
  - Example: Services with 32% presumption → excess over R$5M taxed at 35.2% (32% x 1.10)
- IRPJ: effective from January 2026
- CSLL: effective from April 2026

---

### C) Total Cost of R$100,000 in Commissions under Lucro Presumido

**Assumptions:**
- Commission-based employee (comissionista)
- RAT/SAT: 2% (mid-range)
- DSR: ~19.23% (typical month with 26 business days and 5 Sundays)
- The company is NOT in a desoneração-eligible sector

#### Step 1: Commissions + DSR

| Item | Value |
|------|-------|
| Commissions paid | R$ 100,000.00 |
| DSR on commissions (19.23%) | R$ 19,230.00 |
| **Total remuneration base** | **R$ 119,230.00** |

#### Step 2: Direct Social Charges on Total Remuneration

| Charge | Rate | Value |
|--------|------|-------|
| INSS Patronal | 20.00% | R$ 23,846.00 |
| RAT/SAT | 2.00% | R$ 2,384.60 |
| Terceiros/Sistema S | 5.80% | R$ 6,915.34 |
| FGTS | 8.00% | R$ 9,538.40 |
| **Subtotal direct charges** | **35.80%** | **R$ 42,684.34** |

#### Step 3: Labor Provisions

| Provision | Rate | Base | Value |
|-----------|------|------|-------|
| 13th Salary | 8.33% | R$ 119,230.00 | R$ 9,929.86 |
| Vacation + 1/3 | 11.11% | R$ 119,230.00 | R$ 13,246.45 |
| **Subtotal provisions** | **19.44%** | | **R$ 23,176.31** |

#### Step 4: Charges on Provisions (13th + Vacation)

| Charge | Rate | Base (R$23,176.31) | Value |
|--------|------|---------------------|-------|
| INSS Patronal on provisions | 20.00% | R$ 23,176.31 | R$ 4,635.26 |
| RAT/SAT on provisions | 2.00% | R$ 23,176.31 | R$ 463.53 |
| Terceiros on provisions | 5.80% | R$ 23,176.31 | R$ 1,344.23 |
| FGTS on provisions | 8.00% | R$ 23,176.31 | R$ 1,854.10 |
| **Subtotal charges on provisions** | **35.80%** | | **R$ 8,297.12** |

#### Step 5: FGTS Termination Provision

| Item | Rate | Base | Value |
|------|------|------|-------|
| FGTS Termination (40% of FGTS) | 40% of 8% = 3.2% | R$ 142,406.31 | R$ 4,557.00 |

(Base = total remuneration + provisions = R$119,230 + R$23,176.31)

#### TOTAL COST SUMMARY

| Component | Value |
|-----------|-------|
| Commissions paid | R$ 100,000.00 |
| DSR | R$ 19,230.00 |
| Direct social charges | R$ 42,684.34 |
| Labor provisions (13th + Vacation) | R$ 23,176.31 |
| Charges on provisions | R$ 8,297.12 |
| FGTS termination provision | R$ 4,557.00 |
| **TOTAL EMPLOYER COST** | **R$ 197,944.77** |
| **Total charge percentage over commissions** | **~97.94%** |

**For every R$100,000 in commissions, the company pays approximately R$197,945 in total cost.**

---

## 2. LUCRO REAL - Complete Breakdown

### A) Payroll Charges - IDENTICAL to Lucro Presumido

**CONFIRMED: Payroll charges (encargos trabalhistas) are IDENTICAL between Lucro Presumido and Lucro Real.**

The tax regime (Lucro Presumido vs Lucro Real) affects how IRPJ, CSLL, PIS, and COFINS are calculated on the company's revenue/profit. It does NOT affect:
- INSS Patronal (20%)
- RAT/SAT (1-3%)
- Terceiros/Sistema S (5.8%)
- FGTS (8%)
- 13th salary provision (8.33%)
- Vacation + 1/3 provision (11.11%)
- DSR on commissions
- FGTS termination penalty (40%)

The payroll charges are determined by labor legislation (CLT, Lei 8.212/91, Lei 8.036/90), not by the corporate tax regime.

### B) Tax Brackets/Rates for Lucro Real

| Tax | Rate | Regime | Notes |
|-----|------|--------|-------|
| IRPJ | 15% | On actual profit | Real accounting profit with fiscal adjustments |
| IRPJ Additional | 10% | On actual profit exceeding R$20k/month | Same threshold as Lucro Presumido |
| CSLL | 9% | On actual profit | Same rate, different base |
| PIS | 1.65% | Non-cumulative | With credits on inputs |
| COFINS | 7.6% | Non-cumulative | With credits on inputs |

#### Key Differences from Lucro Presumido

1. **Tax base**: Actual profit (revenue minus all deductible expenses), not presumed profit
2. **PIS/COFINS**: Higher nominal rates (1.65% + 7.6% = 9.25%) but with credit system (non-cumulative)
3. **Payroll deductibility**: All payroll costs are fully deductible from the tax base
4. **Loss carryforward**: Fiscal losses can be carried forward (limited to 30% of current year profit)

### C) Tax Benefit of Payroll Deductibility in Lucro Real

**CRITICAL DIFFERENCE**: In Lucro Real, the entire payroll cost (salaries, commissions, DSR, provisions, INSS, FGTS, etc.) reduces the profit base for IRPJ and CSLL calculation.

#### Example: Tax saving from R$100,000 in commissions

Total payroll cost of R$100,000 in commissions = ~R$197,945 (as calculated above)

This entire R$197,945 is deductible from the IRPJ/CSLL base in Lucro Real:

| Tax | Rate | Saving |
|-----|------|--------|
| IRPJ | 15% | R$ 29,691.75 |
| IRPJ Additional (if applicable) | 10% | R$ 19,794.50 |
| CSLL | 9% | R$ 17,815.03 |
| **Total potential tax saving** | **up to 34%** | **R$ 67,301.28** |

Note: The IRPJ additional only applies if the company's monthly profit exceeds R$20,000. For profitable companies, the effective tax saving on payroll costs is between 24% (IRPJ 15% + CSLL 9%) and 34% (IRPJ 15% + additional 10% + CSLL 9%).

**In Lucro Presumido, the payroll costs do NOT reduce the tax base** because the base is presumed from revenue, not calculated from actual profit.

#### PIS/COFINS: No Credit on Payroll

**IMPORTANT**: Even in Lucro Real's non-cumulative PIS/COFINS regime, **payroll expenses do NOT generate PIS/COFINS credits**. Only inputs, energy, rent, depreciation, and similar costs generate credits. This is a critical consideration for service companies whose main cost is payroll.

---

## 3. DESONERAÇÃO DA FOLHA (Payroll Tax Relief)

### What Is It?

The desoneração da folha (payroll tax relief) substitutes the 20% INSS Patronal contribution on payroll with a percentage on gross revenue called CPRB (Contribuição Previdenciária sobre a Receita Bruta).

It was created by Lei 12.546/2011, extended by Lei 14.784/2023, and is being phased out by Lei 14.973/2024 through gradual reoneração (re-imposition).

### Which Sectors Qualify?

17 sectors are eligible (as per Lei 14.784/2023 and IN RFB 2.053/2021):

| Sector | Original CPRB Rate |
|--------|-------------------|
| Technology (TI) - Development & Programming | 4.5% |
| Technology (TIC) - Support & Services | 4.5% |
| Integrated Circuit Design | 4.5% |
| Call Centers (Teleatendimento) | 3.0% |
| Civil Construction | 4.5% |
| Infrastructure Construction | 4.5% |
| Confection and Apparel | 1.0% - 2.5% |
| Footwear | 1.0% - 2.5% |
| Leather goods | 1.0% - 2.5% |
| Textiles | 1.0% - 2.5% |
| Animal Protein Production | 1.0% - 2.5% |
| Vehicle and Body Manufacturing | 1.0% - 2.5% |
| Machinery and Equipment | 1.0% - 2.5% |
| Collective Road Transport (Passengers) | 2.0% |
| Road Freight Transport | 1.0% - 1.5% |
| Metro-Rail Passenger Transport | 2.0% |
| Communications/Journalism | 1.5% |

Note: Specific rates within ranges depend on exact CNAE code. Consult Annex I of IN RFB 2.053/2021 for exact rates per CNAE.

### Transition Schedule (Reoneração Gradual) - Lei 14.973/2024

| Year | CPRB Rate (% of original) | INSS Patronal on Payroll | Total Structure |
|------|--------------------------|--------------------------|-----------------|
| Until 2024 | 100% of original CPRB | 0% (fully substituted) | Revenue-only |
| 2025 | 80% of original CPRB | 5% on payroll | Hybrid |
| 2026 | 60% of original CPRB | 10% on payroll | Hybrid |
| 2027 | 40% of original CPRB | 15% on payroll | Hybrid |
| 2028+ | 0% (CPRB extinct) | 20% on payroll (full) | Payroll-only |

#### Example: TI company (original CPRB = 4.5%) in 2026

- CPRB on revenue: 4.5% x 60% = **2.7%** on gross revenue
- INSS Patronal on payroll: **10%** on payroll
- (Instead of the standard 20% on payroll for non-desonerated companies)

#### Conditions for Opting In (2025-2027)

- Companies must maintain at least **75% of the average number of employees** from the previous calendar year
- Option is made in January and is irrevocable for the entire calendar year
- Company must be in one of the 17 eligible sectors

### How Desoneração Affects the Calculation

For a company in an eligible sector with R$100,000 in commissions and R$2,000,000 annual revenue:

**Without desoneração (standard):**
- INSS Patronal: 20% x R$119,230 (commissions + DSR) = R$23,846

**With desoneração in 2026 (example: TI at 4.5% original CPRB):**
- CPRB portion: 2.7% x (R$2,000,000/12) = R$4,500/month
- INSS Patronal portion: 10% x R$119,230 = R$11,923
- Total: R$16,423 (vs R$23,846 without desoneração)
- **Saving: R$7,423** (but depends heavily on revenue vs payroll ratio)

**Key insight**: Desoneração benefits companies with HIGH payroll relative to revenue. Companies with LOW payroll relative to revenue may actually pay MORE under CPRB.

---

## 4. Comparison Table: Total Effective Payroll Charge Percentage

### Payroll Charges Only (identical across regimes)

| Component | Monthly Employee | Commission Employee (with DSR ~19%) |
|-----------|-----------------|--------------------------------------|
| INSS Patronal | 20.00% | 20.00% |
| RAT/SAT (avg) | 2.00% | 2.00% |
| Terceiros/Sistema S | 5.80% | 5.80% |
| FGTS | 8.00% | 8.00% |
| **Direct charges** | **35.80%** | **35.80%** |
| DSR | 0% (included in salary) | ~16-20% (additional) |
| 13th Salary | 8.33% | 8.33% |
| Vacation + 1/3 | 11.11% | 11.11% |
| Charges on provisions | ~6.96% | ~6.96% |
| FGTS Termination provision | ~3.2-4.0% | ~3.2-4.0% |
| **Total charge over base salary** | **~65-68%** | **~80-98%** (higher due to DSR) |

### Corporate Tax Impact on Cost

| Aspect | Lucro Presumido | Lucro Real |
|--------|----------------|------------|
| Payroll charges | Identical | Identical |
| Payroll deductible from IRPJ/CSLL? | NO (presumed base) | YES (actual profit base) |
| Tax saving on payroll | None | 24% to 34% of payroll cost |
| PIS rate | 0.65% (cumulative) | 1.65% (non-cumulative) |
| COFINS rate | 3.00% (cumulative) | 7.6% (non-cumulative) |
| PIS/COFINS credit on payroll? | N/A | NO (payroll not eligible) |

### Net Effective Cost per R$100,000 in Commissions

| Scenario | Gross Cost | Tax Saving | Net Effective Cost |
|----------|-----------|------------|-------------------|
| Lucro Presumido (standard) | ~R$197,945 | R$0 | ~R$197,945 |
| Lucro Real (24% bracket) | ~R$197,945 | ~R$47,507 | ~R$150,438 |
| Lucro Real (34% bracket) | ~R$197,945 | ~R$67,301 | ~R$130,644 |
| Desoneração (varies) | ~R$185,000-R$195,000 | Depends on regime | Varies |

---

## Sources

### Official Government Sources
- [INSS - Alíquotas de contribuição](https://www.gov.br/inss/pt-br/noticias/confira-como-ficaram-as-aliquotas-de-contribuicao-ao-inss)
- [Receita Federal - Redução de benefícios tributários](https://www.gov.br/receitafederal/pt-br/assuntos/noticias/2025/dezembro/receita-federal-edita-norma-que-dispoe-sobre-a-reducao-de-beneficios-tributarios)
- [Câmara dos Deputados - Desoneração da folha](https://www.camara.leg.br/noticias/1091935-CAMARA-VAI-ANALISAR-O-FIM-GRADUAL-DA-DESONERACAO-DA-FOLHA-DE-PAGAMENTO)
- [PGFN - Contribuições a terceiros](https://www.gov.br/pgfn/pt-br/cidadania-tributaria/por-assunto/indice-assuntos-portal/tributacao-sobre-a-folhas-de-salarios-e-outras/contribuicoes-devidas-a-terceiros)
- [Governo Federal - Orientações reoneração gradual](https://www.gov.br/compras/pt-br/agente-publico/orientacoes-e-procedimentos/Orientaesreoneraogradual.pdf)

### Reputable Accounting/Tax Firms and Portals
- [Guia Trabalhista - Encargos sociais e trabalhistas](https://www.guiatrabalhista.com.br/tematicas/custostrabalhistas.htm)
- [Guia Trabalhista - Planilha de custos](https://www.guiatrabalhista.com.br/guia/planilha_custos_trab.htm)
- [Contabilizei - Lucro Presumido](https://www.contabilizei.com.br/contabilidade-online/lucro-presumido/)
- [Contabilizei - Tabela INSS 2026](https://www.contabilizei.com.br/contabilidade-online/tabela-inss/)
- [Portal da Contabilidade - Custo funcionário Lucro Presumido](https://portaldacontabilidade.clmcontroller.com.br/quanto-custa-um-funcionario-para-empresa-lucro-presumido/)
- [Portal da Contabilidade - Calcular Lucro Presumido](https://portaldacontabilidade.clmcontroller.com.br/como-calcular-o-lucro-presumido/)
- [Escola Superior ESN - Lucro Presumido percentuais](https://escolasuperioresn.com.br/lucro-presumido-percentuais-distribuicao-lucros/)
- [Paulicon Contábil - Tributação Lucro Presumido 2026](https://paulicon.com.br/2026/01/23/tributacao-pelo-lucro-presumido-em-2026/)
- [VS Contabilidade - Terceiros alíquotas por FPAS](http://www.vscontabilidadefacil.com.br/servico/tabelas-praticas/terceiros-aliquotas-por-codigo-fpas/)
- [Delphin - Encargos sociais sobre folha](https://www.delphin.com.br/orientacao/66-encargos-sociais-sobre-a-folha-de-pagamento)
- [Portal Tributário - IRPJ Lucro Presumido](https://www.portaltributario.com.br/guia/lucro_presumido_irpj.html)

### Legal and News Sources
- [Contábeis - Desoneração 2026](https://www.contabeis.com.br/noticias/74532/desoneracao-da-folha-em-2026-o-que-muda-com-a-reoneracao-gradual/)
- [Migalhas - Reoneração 2026](https://www.migalhas.com.br/depeso/447519/reoneracao-da-folha-de-salarios--2026)
- [FIRJAN - Reoneração gradual](https://www.firjan.com.br/noticias/reoneracao-gradual-da-folha-de-pagamentos.htm)
- [FENACON - Lucro Presumido como benefício fiscal](https://fenacon.org.br/noticias/o-jabuti-de-2026-governo-transformou-lucro-presumido-em-beneficio-fiscal/)
- [Conjur - Confisco silencioso](https://www.conjur.com.br/2026-jan-20/reducao-de-beneficios-fiscais-para-2026-o-confisco-silencioso-pela-rfb-com-a-publicacao-da-in-rfb-no-2305-2025-sobre-o-planejamento-tributario/)
- [Legisweb - Mudança Lucro Presumido](https://www.legisweb.com.br/noticia/?id=32137)
- [DP Especialista - Desoneração e reoneração](https://dpespecialista.com.br/2025/02/03/desoneracao-e-reoneracao-da-folha-de-pagamento-complementar-as-materias-desoneracao-publicadas-em-15-e-24-09-2024-atualizacao-para-2025/)
- [Zeber Advogados - Guia desoneração](https://zeberadvogados.com.br/desoneracao-da-folha-guia/)

### Relevant Legislation
- Lei 8.212/1991 - INSS contributions
- Lei 8.036/1990 - FGTS
- Lei 12.546/2011 - Original desoneração
- Lei 14.784/2023 - Desoneração extension
- Lei 14.973/2024 - Gradual reoneração (2025-2028)
- Lei Complementar 224/2025 - Lucro Presumido changes for 2026
- IN RFB 2.053/2021 - CPRB eligible sectors and CNAE codes
- IN RFB 2.305/2025 - Tax benefit reduction measures
