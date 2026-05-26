# SPIKE — Labor Charges on Commissions vs Awards (Prêmios) for Savings Calculator

**Conducted by:** Pedro Ribeiro
**Date:** 2026-02-27
**Status:** Research complete — pending decisions

---

## Goal

Build the technical foundation for a savings calculator on 4Shark's institutional website. The calculator shows how much companies overpay when structuring variable compensation as **commissions** (fully taxed) vs. **awards/prêmios** (zero charges under Art. 457 §2° CLT, Lei 13.467/2017).

Two prior research sources (one from ChatGPT, one from internet search) provided conflicting information. This spike validates all data against official government sources and extends coverage to all tax regimes.

---

## Method

- Researched official legislation: Art. 457 CLT, Lei 13.467/2017, LC 123/2006, Lei 14.973/2024
- Cross-referenced Receita Federal tables and Simples Nacional annex rates
- Validated against Solução de Consulta COSIT 151/2019
- Analyzed both prior sources for errors and gaps
- Extended research to cover: Simples Nacional (all 5 Annexes), Lucro Presumido (with presumption brackets), Lucro Real, Desoneração da Folha

---

## Evidence

All evidence is documented in supporting files:

| Spike | Description |
|-------|-------------|
| `../encargos-trabalhistas-consolidacao/SPIKE.md` | Main compiled document with all data tagged by source reliability (`[OFICIAL]`, `[SEMI-OFICIAL]`, `[NÃO OFICIAL]`). Includes draft legal texts (PARTE 10) for lawyer review. |
| `../encargos-trabalhistas-estudo-inicial/SPIKE.md` | Initial consolidated study before source tagging |
| `../encargos-trabalhistas-simples-nacional/SPIKE.md` | Detailed Simples Nacional research (CPP by annex, rate tables, DAS allocation) |
| `../encargos-trabalhistas-lucro-presumido-real/SPIKE.md` | Detailed Lucro Presumido/Real research (Sistema S, DSR, step-by-step calculations, Desoneração) |

### Key Findings — Multiplier Factors

| Tax Regime | Cost per R$1,000 commission | Savings if paid as award |
|------------|---------------------------|--------------------------|
| Simples (Annexes I, II, III, V) | ~R$ 1,540 | ~R$ 540 |
| Simples (Annex IV) | ~R$ 1,850 | ~R$ 850 |
| Lucro Presumido | ~R$ 1,940 | ~R$ 940 |
| Lucro Real | ~R$ 1,940 (gross) | ~R$ 940 |
| Desoneração 2026 | ~R$ 1,840 | ~R$ 840 |

### Errors Found in Prior Sources

- **Source 1 (ChatGPT)**: 1/3 constitucional double-counted, total 66% underestimated (real: 54-94%), missing FGTS/multa cascade
- **Source 2 (Internet)**: Factor 1.40-1.60 conservative (real: up to 1.94), 13°+férias listed as 11-15% (correct: 19.44%), missing DSR cascade

---

## Conclusions

1. The legal basis is solid — Art. 457 §2° CLT confirmed by COSIT 151/2019, no pending ADI, MP 808/2017 expired
2. Both prior sources significantly underestimated total charges due to missing DSR cascade effect
3. LC 224/2025 (Lucro Presumido change for 2026) could NOT be verified on official sources — flagged for accountant validation
4. The page should be called **"Simulador"** (simulator) not "calculadora" — reduces expectation of precision
5. Legal disclaimer and award requirements text must be reviewed by a labor lawyer before publication

---

## Next Steps

- [ ] Accountant validation — multiplier factors and LC 224/2025 change
- [ ] Labor lawyer review — disclaimer text and award requirements (drafts in `DISCLAIMER-RASCUNHO.md`)
- [ ] Product decision — include Desoneração in V1 or defer (transition regime, ends 2028)
- [ ] After validations: generate PLAN.md for calculator/simulator implementation

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
