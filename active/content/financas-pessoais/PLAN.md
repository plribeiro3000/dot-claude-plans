# PLAN — Finanças Pessoais (Paulo)

> Documento **pessoal** — controle das minhas finanças, sem relação com trabalho. Versionado por git: cada revisão de número fica no histórico, nada é sobrescrito de forma irrecuperável, ao contrário da planilha.

Fonte de dados: `~/Downloads/painel_financeiro_pessoal.xlsx` (aba `Configurações` = fonte única de verdade) e as faturas mensais do cartão final 4607.

---

## Objetivo

Sair do LIS (cheque especial do Itaú, 8% ao mês / 173,77% ao ano) e não deixá-lo voltar a crescer. Toda sobra mensal vai para amortizar o LIS até zerar; só depois começa a reserva de emergência.

**Meta operacional:** manter a fatura do cartão dentro do teto de **R$ 7.300/mês**. Esse teto foi calibrado para caber ao lado das despesas fixas e ainda sobrar caixa para amortizar o LIS.

---

## Premissas travadas (aba Configurações do painel)

| Item | Valor | Observação |
|---|---|---|
| Salário líquido mensal | R$ 20.000,00 | |
| Aluguel | R$ 5.000,00 | fixo |
| Condomínio | R$ 1.027,40 | fixo |
| Água + Energia | R$ 500,00 | **premissa a corrigir — ver Pendências** |
| Empréstimo (parcela) | R$ 1.934,34 | parcela 14/24 em ago; restam 11; termina ~jul/27 |
| Teto planejado do cartão | R$ 7.300,00 | meta mensal |
| Plano de saúde (Alice) | R$ 1.305,97 | **Cancelado** — 0 meses de cobrança restantes |
| LIS — limite total | R$ 65.400,00 | |
| LIS — saldo devedor (ref. jul) | R$ 10.356,37 | |
| LIS — juros efetivos a.m. | 8,00% | CET 8,63% a.m. |
| Refinanciamento da fatura | 6× de R$ 2.251,85 | parcela 1/6 em ago; termina jan/27 |
| Meta: sair do LIS até | mês 6 da projeção | |

**Sobra planejada por mês (com teto respeitado):**

```
20.000 − 7.300 (teto) − 5.000 − 1.027,40 − 1.934,34 = +4.738,26
```

Esses R$ 4.738,26/mês são o motor do plano — é com eles que o LIS seria amortizado. Quando não há sobra, o LIS sobe.

---

## Decisões tomadas (26/08/2026)

1. **Teto real é R$ 7.300, não R$ 8.000.** Confirmado na aba Configurações. Toda conta de estouro usa 7.300.
2. **Alice está fora.** Status "Cancelado", 0 meses de cobrança. Setembro em diante não tem esse gasto.
3. **Anthropic não repete.** As 5 cobranças de 12/08 (R$ 1.363,16 + IOF) foram excepcionais e não entram nas projeções futuras.
4. **Corte de assinaturas é a única alavanca do tamanho do problema no prazo.** As parcelas já contratadas são contratos fechados (caem sozinhas até jan/27); as assinaturas recorrentes (~R$ 1.679,63/mês) são o que dá para cortar agora.

---

## Log mensal — o que realmente aconteceu

> Uma linha por mês. Não sobrescrever: cada mês é um registro novo. O painel projeta o futuro; este log guarda o passado.

### Agosto/2026 — fatura fechada, vence 01/09

| Métrica | Valor |
|---|---|
| Total da fatura 4607 (declarado pelo banco) | R$ 14.529,60 |
| Movimento líquido do ciclo (124 lançamentos) | R$ 2.308,51 |
| Diferença não detalhada no arquivo | **R$ 12.221,09** (ver Pendências) |
| Gasto do ciclo comparável ao teto¹ | R$ 11.766,26 |
| **Estouro do cartão vs. teto** | **R$ 4.466,26 (+61,2%)** |
| Estouro descontando a Anthropic | R$ 3.103,10 (+42,5%) |
| **Estouro do MÊS (fatura acima do teto)** | **R$ 7.229,60** |
| Resultado do mês (real, sem energia) | −R$ 2.491,34 |
| Resultado do mês (com os R$ 500 de água/energia) | −R$ 2.991,34 |

¹ Débitos brutos 17.243,20 − parcela refin. 1/6 + IOF (2.390,31) − Airbnb antecipado/estornado no dia (3.086,63) = 11.766,26. O teto de 7.300 é gasto do cartão; a parcela do refinanciamento tem linha própria no painel, então sai da comparação.

**Leitura de agosto:** aluguel, condomínio e empréstimo entraram no valor exato que o plano previa — nenhum deles contribui com o estouro. O buraco inteiro é a fatura. Em vez de sobrar R$ 4.738,26 para amortizar, faltaram R$ 2.491,34, que saíram do LIS. Diferença de R$ 7.229,60 no saldo devedor, a 8% ao mês.

**Gasto bruto do ciclo por categoria (sem o refinanciamento):**

| Categoria | Valor | Nº |
|---|---|---|
| IA e software | R$ 2.176,50 | 14 |
| Mercado | R$ 1.897,12 | 18 |
| Compras parceladas | R$ 1.735,76 | 7 |
| Casa e serviços | R$ 1.712,63 | 16 |
| Restaurantes | R$ 1.347,44 | 12 |
| Transporte | R$ 1.172,33 | 10 |
| Streaming e lazer | R$ 866,29 | 15 |
| Saúde e farmácia | R$ 685,07 | 6 |
| Outros | R$ 199,00 | 1 |
| IOF internacional | R$ 62,61 | 9 |
| Viagem (Airbnb) | −R$ 88,49 | 12 |
| Refinanciamento | −R$ 9.457,75 | 4 |

Dentro de "IA e software", a Anthropic sozinha foi R$ 1.363,16 (5 cobranças + IOF em 12/08) — excepcional, não repete.

### Setembro/2026 — projeção (a preencher no fechamento)

| Métrica | Projetado | Real (preencher) |
|---|---|---|
| Piso da fatura (parcelas + recorrente) | R$ 7.310,78 | |
| Fatura projetada (repetindo o variável de ago) | ~R$ 12.400 | |
| Resultado do mês projetado | ~−R$ 2.500 a −R$ 3.000 | |

**Por que setembro já nasce sem espaço:** as parcelas já contratadas cobram R$ 3.918,52 sozinhas, e as assinaturas + contas de casa cobram outros R$ 3.392,26. Somados dão R$ 7.310,78 — já passa o teto de 7.300 antes de qualquer compra nova. Alice sair e Anthropic não repetir não resolvem isso, porque nenhuma das duas está nesse piso.

---

## Parcelas já contratadas (contratos fechados — caem sozinhas)

Cobrança da PRÓXIMA fatura (a que fecha em setembro):

| Compra | Parcela | Valor | Restam | Total a vencer | Termina |
|---|---|---|---|---|---|
| Refinanciamento da fatura | 2/6 | R$ 2.251,85 | 5 | R$ 11.259,25 | jan/27 |
| Airbnb (reserva nova) | 2/6 | R$ 423,00 | 5 | R$ 2.115,00 | jan/27 |
| Magalu-foto | 2/10 | R$ 174,39 | 9 | R$ 1.569,51 | jul/27 |
| TT Técnica | 3/4 | R$ 391,00 | 2 | R$ 782,00 | out/26 |
| Magalu-KaBuM | 3/5 | R$ 211,77 | 3 | R$ 635,31 | nov/26 |
| Rawev | 5/10 | R$ 94,70 | 6 | R$ 568,20 | fev/27 |
| Globo Combo | 6/12 | R$ 64,90 | 7 | R$ 454,30 | mai/27 |
| Atacadão | 3/3 | R$ 287,01 | 1 | R$ 287,01 | set/26 |
| Hotmart | 11/12 | R$ 19,90 | 2 | R$ 39,80 | out/26 |
| **Total** | | **R$ 3.918,52/mês** | | **R$ 17.710,38** | |

Ordem em que aliviam: Atacadão (set) → TT Técnica, Magalu-KaBuM, Hotmart (out–nov) → refinanciamento e Airbnb (jan/27) → resto até jul/27.

---

## Assinaturas recorrentes (a alavanca cortável — ~R$ 1.679,63/mês sem Anthropic)

| Assinatura | Valor mensal |
|---|---|
| Deepstash | R$ 277,78 |
| Locaweb | R$ 216,85 |
| PlayStation | R$ 200,00 |
| Confraria | R$ 99,00 |
| ChatGPT | R$ 95,99 |
| LinkedIn | R$ 88,61 |
| Granola | R$ 82,73 |
| Google One | R$ 72,98 |
| Disney+ | R$ 69,90 |
| Netflix | R$ 59,90 |
| Fantastical | R$ 38,85 |
| Paramount+ | R$ 34,90 |
| Spotify | R$ 31,90 |
| Crunchyroll | R$ 24,90 |
| Amazon Prime | R$ 19,90 |
| Serasa | R$ 19,90 |
| Amazon Ad Free | R$ 10,00 |
| Rush Royale | R$ 13,99 |

Casa e serviços (recorrente, não é assinatura mas repete): Sabesp R$ 477,73 · Vivo R$ 289,90 · Parafuzo limpeza R$ 154,00 × 4 = R$ 616,00 · diaristas/avulsos ~R$ 329,00 → **R$ 1.712,63**.

---

## Pendências (verificar / corrigir)

1. **[VERIFICAR NO BANCO] Fatura não fecha: faltam R$ 12.221,09.** Os 124 lançamentos exportados somam R$ 2.308,51, mas o banco declara R$ 14.529,60. A diferença (R$ 12.221,09) é o valor que a planilha registrava como fatura de agosto. Duas hipóteses: (a) saldo anterior que o refinanciamento NÃO zerou — crédito 10.735,65 + entrada 1.112,41 = 11.848,06, ainda R$ 373,03 aquém; ou (b) cobrança em duplicidade. Confirmar a composição no app do Itaú antes de pagar.

2. **[CORRIGIR PLANILHA] Água contada em dobro.** A conta da Sabesp (R$ 477,73) já vem dentro da fatura do cartão (linha 49, cartão virtual recorrente), mas a aba Configurações tem "Água + Energia | 500" como despesa fixa à parte. Trocar por "Energia" com o valor real da conta da Enel; a água sai dali porque já está no cartão. Com os R$ 500 como estão, setembro fecha em −R$ 2.991,34 em vez de −R$ 2.491,34.

3. **[ACOMPANHAR] Divisão titular/adicional.** Dos R$ 17.243,20 de débitos brutos, R$ 13.788,91 são do titular (82 lançamentos) e R$ 3.454,29 do adicional (33). Opcional desdobrar a linha "cartão principal" do painel em titular e adicional.

---

## Próximas ações

- [ ] Verificar no app do Itaú a composição dos R$ 14.529,60 (pendência 1) antes do vencimento 01/09.
- [ ] Corrigir a linha "Água + Energia" da planilha (pendência 2).
- [ ] Decidir quais assinaturas cortar (lista acima) — único corte que cabe no prazo de setembro.
- [ ] No fechamento de setembro, preencher a linha do log com os valores reais.
