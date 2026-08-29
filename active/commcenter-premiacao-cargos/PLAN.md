# CommCenter — premiação de Coordenador, Executivos e Gerentes Comerciais

Company 2077, stack `app-shared-001`. Competência corrente: **julho/2026**.

## Objetivo

Três cargos não recebem, na plataforma, os valores que a régua de premiação deles exige, porque
esses valores são agregados da equipe abaixo e o cálculo não os alcança:

- **Coordenador de Call Center** — precisa do faturamento da liderança imediata e de toda a equipe
  abaixo dela (vendas instaladas + móvel).
- **Executivos de Vendas** — precisam da soma dos liderados (vendas instaladas, móvel, indicação),
  além de contagens de líderes e lojas no atingimento.
- **Gerentes Comerciais** — precisam da soma dos executivos abaixo (Loja, PAP, Call Center, online).

## Estado da entrega

**Espelhos e contagens dos três cargos estão reconciliados contra a mesma base — os deals e a
hierarquia de 26/08.** O que uma competência seguinte reencontra é isto: uma apuração só é coerente
enquanto a base por baixo dela não se mexe, e ela se mexe por dois caminhos independentes — correção
de venda e remanejamento de hierarquia. O segundo é o que engana, porque não deixa rastro no volume:
quatro linhas de `seats` reescritas movem 54 pessoas e milhares de reais entre alvos sem que nenhuma
venda mude.

**Onde a apuração está em 2026-08-28:** a reconciliação (`10`) rodou contra a base de 28/08 nos
Gerentes e nos Executivos e está verificada — 3 `CREATE` e 16 `DISABLE` no plano 78940, 670 `CREATE`,
9 `UPDATE` e 160 `DISABLE` no 79175, zero `FAILED` nos dois, e o `12` releu os 858 registros tocados
contra a origem devolvendo `PASS@858@FAIL@0`. As contagens (`11`) corrigiram duas linhas de
`lojas_atingimento` — Flavia de 1 para 2 e Cristiano de 1 para 3 — e a releitura seguinte veio
`MATCHING@10@DIVERGING@0`. Os CSVs que revertem ou re-verificam essa rodada, em
`s3://4shark-shared-001/integration-debug/audits/2077/premiacao-reconciliation/`, são
`20260828-221853-78940.csv` (Gerentes) e `20260828-221913-79175.csv` (Executivos). O Coordenador não
entrou nesta rodada, e o conjunto dele é o da reconciliação de 27/08
(`20260827-132227-78941.csv`).

**O que falta desta rodada são duas coisas, nesta ordem:** reprocessar as compensações 63309 e 63128,
que é ação do engenheiro e sem a qual o número não se move, e rodar o `05-validacao.rb` em seguida.
Como os dois planos são `override: false`, o `05` tem de imprimir `subtree@0.0` em todo alvo e um
`expected` igual ao `total_after` que a reconciliação registrou.

**O cargo de Executivo é apurado pelo plano 79175** (§ A errata dos Executivos), que substituiu o
78939 com a régua de receita corrigida e os valores de `hc` zerados pelo Patrick. O `11-contagens.rb`
é o script a manusear com cuidado aqui, porque a definição de `hc` que ele carrega é uma soma e o
valor certo é uma contagem — por isso essa variável fica fora do conjunto que ele grava.

**A rodada corrente cobre DOIS cargos — Executivos (79175) e Gerentes (78940) — e o Coordenador fica
de fora dela.** O Patrick pediu exatamente esses dois em 28/08, para a Andresa fechar a RV no mesmo
dia, e o pedido é o que decide o escopo: `plan_ids` no `10`, no `01` e no `05` carrega os dois, e o
`11` já era só dos Executivos. O Coordenador entra numa rodada própria, com a mesma sequência.

**Rodar antes de a Larissa terminar as deals de Loja é decisão do cliente, e ele a tomou.** A
correção dela muda deals que os espelhos copiam, então o conjunto reconciliado agora envelhece quando
ela fechar — o que a rodada seguinte absorve, porque a reconciliação é barata justamente por isso
(§ A divisão de trabalho). O que continua valendo é a ordem: reconciliação, reprocessamento e
verificação próximos no tempo (§ A subárvore que a agregação lê é a de HOJE).

| Frente | Estado |
|---|---|
| Espelhos do Coordenador | 304 ativos, R$ 33.038,00 — reconciliados contra os deals de 26/08 |
| Espelhos dos Gerentes | 870 ativos, R$ 88.485,83 — reconciliados contra os deals de 28/08 e verificados |
| Espelhos dos Executivos | 703 ativos, R$ 72.658,14 — com o filtro de PAP aplicado, reconciliados contra os deals de 28/08 e verificados |
| Filtro de PAP no `10` | aplicado e verificado; dois dos quatro totais conferem ao centavo contra o recorte do `14` |
| Descrição dos espelhos | 1.686 reescritos em português com o `external_id`, verificados por segunda passada |
| Atingimento de lojas e líderes | 10 indicators — recalculados contra a base de 26/08, 1 corrigido |
| Headcount (`hc`) | zerado pelo Patrick, que é o valor certo de julho; o `11` não grava essa variável |
| `atingimento_consultor_lider` | sem valor — depende da Andresa |
| `quantidade_parceiro_acima_mil` | gravado para o Cristiano (1); os outros quatro sem linha, que é o valor certo |
| Régua de receita | operador invertido na regra 265434 (`>` onde cabe `<`), então a faixa de 80% a 100% não paga; em julho o efeito é zero porque ninguém passa de 100% e o Patrick fechou o assunto para esta competência |
| `faturamento_parceiro` | base nova da régua de receita; status 3968 "Venda Parceiro", R$ 989,93 na empresa em julho, tudo dentro da subárvore do Luiz Felipe |
| Âncoras dos Executivos nos scripts | 79175 / 63309, com a exclusão de carriers gateada pelo `override` em `07`, `08` e `10` |
| Valor de controle de PAP | não existe verificado; o Patrick vai conferir com a Andresa e mandar (§ A receita que entra no atingimento dos Executivos) |
| Divergência Líder de Call Center × Coordenador | levantada pelo Patrick, não investigada — as duas deveriam ter a mesma receita |
| Valor dos Gerentes | a Andresa aponta divergência; o Patrick espera que a correção das deals de Loja melhore |

**O Coordenador (63126) e os Gerentes (63128) não dependem da errata dos Executivos.** O filtro de PAP
não os alcança e o plano deles não mudou; o que os alcança é a correção da Larissa, porque ela muda
deals que os espelhos dos dois copiam. Uma execução do `10` cobre quantos cargos estiverem em
`plan_ids`, então incluir o Coordenador é acrescentar 78941 à lista.

**Os Executivos fecham incompletos por dado que o cliente não mandou, e isso não segura o
processamento.** `atingimento_consultor_lider` segue vazia porque só a Andresa tem esse número, e a
régua de receita carrega um operador invertido que apaga a faixa de 80% a 100%. O resultado sai com o
que existe, o que falta é apontado, e a régua é corrigida na competência que o cliente decidir
(§ A divisão de trabalho).

## A errata dos Executivos — o plano é o 79175

**O cargo de Executivo de Vendas é apurado em julho pelo plano 79175, "Remuneração Variável
Executivos de Vendas Julho 2026 Errata", compensação 63309.** O plano 78939 e a compensação 63127
estão desabilitados desde 28/08; o agregado que aquela compensação exibe foi compilado noutro
instante e não serve para conferir nada.

**O `override: false` do 79175 é DELIBERADO.** O Patrick desmarcou "metas por participação" porque a
plataforma somava duas vezes: os liderados de primeiro nível por um caminho e a subárvore recursiva
inteira por outro, e o valor fechava muito acima. É o mesmo par de mecanismos descrito em
§ A abordagem está decidida — `Commission::DealOptionsProcessor` passeia um nível,
`IndicatorAggregation::UserProducer` resolve a subárvore inteira. Desligar o flag para os dois.

**Sem varredura, o agregado de cada Executivo é exatamente a soma dos deals dele** — e é o que a
compensação mostra, ao centavo: Luiz Felipe R$ 3.280,72 contra 35 espelhos de R$ 3.280,72, Loandra
R$ 3.719,64 contra 38, Flavia R$ 2.759,73 contra 27, Cristiano R$ 8.667,42 mais R$ 196,00 de móvel
contra 93 espelhos de R$ 8.863,42. Toda receita da equipe passa a depender exclusivamente do espelho.

**O conjunto de origem é a parte PAP da subárvore, carriers incluídos — nem a subárvore inteira, nem
a subárvore menos carriers** (§ A receita que entra no atingimento dos Executivos). A exclusão de
carriers existia porque a varredura já os alcançava; sem varredura ela não tem mais razão de ser, e o
`10-reconciliacao.rb` a desliga sozinho ao ler `plan.override?`. O filtro que ele ainda NÃO tem é o de
PAP, e sem ele a rodada espelha receita de loja que não pertence ao cargo.

**A régua de receita mudou de BASE, não só de faixa.** O incentivo 94277 paga sobre
`faturamento_parceiro` (variável 37035, com métrica) em vez de `(vendas_instaladas + movel)`, embora
o atingimento continue sendo medido por `(vendas_instaladas + movel) / vendas_instaladas_goal`. Hoje
`faturamento_parceiro` agrega zero nos cinco, então esse incentivo não paga nada — e como a variável
tem métrica, ela entra sozinha no conjunto de origem do `10`, que passa a espelhar também os deals
que a métrica dela selecionar. A métrica é a 5006 e seleciona o status **3968, "Venda Parceiro"**:
9 deals somando R$ 989,93 na empresa inteira em julho, então o que ela pode pagar é da ordem de
dezenas de reais.

**O defeito da régua é UM OPERADOR INVERTIDO na regra 265434, e as duas fórmulas do incentivo 94277
lado a lado mostram isso sem interpretação:**

```
265434  "Atingimento entre 80% e 99,99% da meta | Ganha 3% ..."
IF((vendas_instaladas + movel) / vendas_instaladas_goal >= PERCENT(80)
   AND (vendas_instaladas + movel) / vendas_instaladas_goal > PERCENT(100),
   (faturamento_parceiro) * PERCENT(3) - desconto_retroativo, 0)

265435  "Atingimento superior ou igual a 100% da meta | Ganha 5% ..."
IF((vendas_instaladas + movel) / vendas_instaladas_goal >= PERCENT(100),
   (faturamento_parceiro) * PERCENT(5) - desconto_retroativo, 0)
```

O segundo operador da 265434 é `>` onde a descrição dela exige `<`. Com `>= 80% AND > 100%` a
conjunção se reduz a `> 100%`, que é a condição da 265435 — **a faixa de baixo passa a cobrir a faixa
de cima**. O efeito é dos dois lados e o segundo é o que dói: acima de 100% as duas pagam juntas, e
entre 80% e 100% NENHUMA paga, então a faixa dos 3% não existe na prática.

**O PORTÃO e a BASE DE PAGAMENTO são variáveis diferentes, e isso é deliberado.** O atingimento que
abre a regra é medido em `(vendas_instaladas + movel) / vendas_instaladas_goal`, mas quem multiplica
pelos 3% ou 5% é `faturamento_parceiro` — coerente com o nome do incentivo, "Receita instalada por
indicação de Parceiro ou venda de Terceiro-Afiliado". Ler a base como sendo a receita do portão
superestima o pagamento em duas ordens de grandeza.

**O `hc` não é a soma dos `hc_<cidade>` da subárvore — é uma conjunção com DUAS condições por líder,
e o Patrick a escreveu por extenso.** A regra 263617 se chama "Meta PAP batida em todas as cidades
com menos HC do que o orçado | Ganha R$ 1.000,00", e ele detalhou no Slack em 27/07: *"executivos só
ganham bônus de 1000 se todos os líderes abaixo dele(PAP) atingirem meta vedas mais HC abaixo dos
orçados"*. Cada líder precisa das duas ao mesmo tempo — bater a meta de VENDA e ficar com headcount
ABAIXO do orçado —, e o Executivo só pontua quando isso vale para TODOS. `IF(hc >= 1, 1000, 0)`
transforma o resultado em R$ 1.000. Somar o realizado dos liderados responde outra pergunta, e é o
valor errado que o Patrick zerou.

**Os cinco `hc` estão zerados e é esse o valor certo de julho.** O que falta definir é o detalhe —
o que fazer com um Executivo sem nenhuma cidade abaixo do orçado, e com uma cidade sem `hc_<cidade>`
gravado (§ Atingimento de lojas e líderes). Até isso fechar, `hc` fica fora do conjunto que o
`11-contagens.rb` grava: um `dry_run = false` com a definição de soma reescreve os cinco zeros e
volta a pagar R$ 1.000 a quatro Executivos, porque o script só enxerga divergência entre o que
calcula e o que está lá — não que aquilo foi uma correção humana.

**`quantidade_parceiro_acima_mil` já tem o valor de julho e não tem cálculo.** O indicator do
Cristiano está gravado com 1; os outros quatro não têm linha, o que é o valor certo deles. O cálculo
depende de como as deals de parceiro e de indicação passam a ser representadas, decisão que a Larissa
e a Andresa estão tomando entre duas opções para a competência seguinte — até fechar, nenhum script
calcula essa variável, e gravá-la por conta apagaria o número do Patrick.

**A receita ter saído quase no dobro na compensação antiga é o instante do processamento, não o
plano.** Ela foi compilada quando o conjunto de espelhos ainda estava dobrado — 750 espelhos, dos
quais 534 de origem duplicada, limpos em 24/08 (§ Executivos de Vendas).

**As contagens gravadas pagam** Luiz Felipe R$ 1.000 (3 lojas × 200 + 1 líder × 400), Loandra R$ 800
(2 líderes), Flavia R$ 800 (2 lojas + 1 líder), Cristiano R$ 700 (3 lojas × 200 + 1 parceiro × 100) e
Beatriz zero. Os indicators de contagem estão com `destroyable@false` nos cinco, então correção ali é
`update` do `value`, nunca `destroy`.

**A régua de receita não paga nada em julho, e a razão é o ATINGIMENTO, não a régua.** Com o conjunto
de origem correto o atingimento fica em Loandra 94,92%, Flavia 81,59%, Luiz Felipe 57,11% e Cristiano
44,79% — **ninguém passa de 100%**, então a faixa dos 5% não dispara para ninguém e a dos 3% não
dispara por causa do operador invertido descrito acima. O Patrick
fechou o assunto para esta competência: *"de qualquer forma eles não vão receber nela nesse mês e não
entrou a regras, então já solicitei que Andresa valide"*.

**A meta é o que segura os quatro abaixo de 100%** — 27.295,00 no Luiz Felipe, 28.001,67 na Flavia,
26.174,67 no Cristiano e 22.658,67 na Loandra, todas em `vendas_instaladas`. Uma sessão que projetar
pagamento de receita a partir do salto da receita espelhada, sem ler a meta, chega à conclusão oposta
e errada.

## A divisão de trabalho: o cliente manda o dado, a gente calcula

**A 4Shark não valida o dado do cliente e não segura processamento esperando ele confirmar o próprio
dado.** Hierarquia, meta, grupificação e venda são ENTRADA. O cálculo reflete a entrada como ela está
e o resultado é comunicado; se a entrada estava errada, o erro é do lado que a subiu, e a correção é
subir de novo e reprocessar.

**Isso não é aspereza, é o contrato.** A 4Shark não tem como saber qual hierarquia é a certa — nada
na base distingue um remanejamento intencional de um engano de digitação. Uma sessão que trava o
reprocessamento até o cliente "confirmar" está fazendo o trabalho de conferência que é dele, atrasando
o fechamento e assumindo uma responsabilidade que a 4Shark não pode cumprir.

**O que a 4Shark deve é EXPLICAR o número, nunca julgá-lo.** Quando um valor muda muito entre duas
apurações, o recado diz o que mudou, de quanto para quanto e qual foi a causa mecânica — "quatro
pessoas mudaram de equipe nos dias 24 e 25 e levaram 54 junto" —, e segue. Não diz "segura", não diz
"confirma antes", não abre pergunta cuja resposta a 4Shark precisaria para agir.

**Um defeito de régua é o mesmo caso.** A 4Shark aponta o defeito com o efeito em dinheiro e segue
processando com a régua como ela está; alterar régua é decisão do cliente e acontece na competência
que ele decidir.

**O recado no Slack interno é RELATÓRIO, não pauta e não instrução.** O Patrick é da 4Shark e a
Andresa é da Concentra; ele conduz a relação com ela e a sessão não sabe o que ele já combinou. Então
o recado diz três coisas e para: **o que foi feito, o que não foi feito, e por que não foi feito.**
Nada de "pode reprocessar", "avisa a Andresa", "vocês decidem quando" — dizer a ele o que fazer com o
que ele controla é o mesmo erro de assumir o trabalho do outro lado, uma casa antes.

## A abordagem está decidida: espelhar DEALS. Não reabrir.

**A correção acontece na tabela de deals, e em lugar nenhum além dela.** Isso é decisão do
engenheiro, tomada, e não é insumo para reanálise: uma sessão que chega aqui executa o espelhamento
descrito abaixo. Reabrir custa dias e já custou duas vezes.

**`override` no plano está FORA — não propor, não investigar, não pedir query para conferir.** O
roll-up hierárquico existe e é a flag `override` do plano, e o comportamento dela é discutível
lendo o código: `Commission::DealOptionsProcessor` (`deal_options_processor.rb:14-20`) passeia um
nível só, por `SeatHistory.where(parent_id: user.seat.id)`, enquanto
`IndicatorAggregation::UserProducer` (`user_producer.rb:17-22`) resolve o `HierarchyScope` recursivo
sobre a subárvore inteira. Os dois convivem porque alimentam artefatos diferentes. **Nada disso muda
a decisão** — está registrado aqui só para que a próxima sessão reconheça o beco e não entre nele.

**Um `Indicator` INTERNO está FORA — não criar, não atualizar, não espelhar.** Os indicadores
internos da competência já estão gravados (`compiled_at` 2026-07-01, `external: false`, escritos por
`Metric::Consumer`), e são base já calculada de várias comissões que não têm relação com esta
demanda. Escrever ali reescreve resultado alheio. Numa variável COM métrica, deal é dado de entrada e
indicator é resultado — é por isso que a correção entra pela entrada.

**Um `Indicator` EXTERNO numa variável SEM métrica é o caso oposto, e é o único caminho que o modelo
aceita.** `indicator.rb:116-122` recusa um indicator interno quando a variável não tem métrica, e
recusa um externo quando ela tem. Numa variável sem métrica o externo não é uma opção entre outras, é
a forma; e ali o indicator É o dado de entrada, não resultado de cálculo nenhum, então a regra acima
não o alcança. É por essa porta que a premiação de atingimento entra (§ Atingimento de lojas e
líderes).

**`Metric::Grower` / `Metric::Sower` não valem como fonte sobre o que roda.** O módulo Sower/Grower
está implementado e **nenhum cliente o usa hoje**, então ler `metric/grower.rb` e concluir qualquer
coisa sobre o cálculo em produção é conclusão sobre código que não executa. O caminho vivo é
`Metric::Producer` → `Metric::Consumer` → `AccumulatedDeal::Producer` → `AccumulatedDeal::Consumer`.

**Grupo não é plano.** Estar numa `Groupification` é candidatura. `PlanParticipation` tem máquina de
estado própria (`plan_participation.rb:34-47`) e só a participação em `final` chega ao
`PlanStatement` (`plan_participation/consumer.rb:10,35`) — é o statement que faz alguém entrar na
compensação. Um usuário no grupo sem `user_commission` é participação não aprovada, não anomalia.

## A correção

Espelhar transações. Para cada usuário da subárvore do cargo, cada deal que casa com o filtro da
métrica gera um deal equivalente no próprio cargo, copiando todos os valores e trocando apenas o
usuário e o identificador externo.

Um espelho se identifica pela coluna `external` de `Deal`, gravada como `false`. Filtrar é
`where(external: false)` — coluna real, descobrível no schema, diferente de uma convenção de string
que só protege quem souber que ela existe.

A coluna é cópia exata da homônima em `Indicator`, conferida campo a campo:

| | `Indicator` (tabela `modifiers`) | `Deal` (tabela `deals`) |
|---|---|---|
| coluna | `t.boolean "external", default: true, null: false` (`db/schema.rb:1116`) | `t.boolean "external", default: true, null: false` |
| método | `def internal?; !external?; end` (`indicator.rb:95-97`) | `def internal?; !external?; end` (`deal.rb:84-86`) |
| índice | nenhum | nenhum |

O `default: true` é o que preserva o significado do que já existe: todo registro vindo da
integração continua sendo externo sem precisar de backfill.

O que `Indicator` tem e `Deal` deliberadamente não recebeu é a validação `internal_variable`
(`indicator.rb:118-124`), que usa `external?`/`internal?` para exigir que uma variável com métrica
seja interna. É regra do indicador; não existe equivalente em `Deal`.

O `external_id` do espelho é `<external_id original>_<User.id do cargo>`. O sufixo existe apenas
para unicidade, porque dois destinatários podem espelhar o mesmo original; como os identificadores
originais já são únicos por `(external_id, installment, company_id)`, o conjunto também é, e o
índice único recusa uma segunda execução em vez de duplicar. O limite de 36 caracteres do modelo é
o que restringe o formato.

A `description` é **texto que o cliente lê na transação**, então é em PORTUGUÊS e nomeia a venda pelo
`external_id` — nunca pelo `id` interno, que não identifica nada fora deste banco. O formato é
`espelho da venda <external_id da origem> de <nome do vendedor>`. Ela é contexto para quem lê o
registro, **nunca** chave de busca: é campo livre que qualquer um pode escrever.

A subárvore sai de `UserScope` → `HierarchyScope` (`app/scopes/hierarchy_scope.rb:5-12`), um
`WITH RECURSIVE` sobre `seats.parent_id` que alcança todos os níveis a partir do seat do usuário.
Não reimplementar essa recursão.

## O espelho é reversível e atualizável — as quatro operações da rotina

A execução manual cria; a rotina diária que vem depois precisa também desativar e atualizar. Todas
as quatro existem sem código novo, e o que cada uma exige está aqui para a rotina não redescobrir.

**Criar** — `Deal.new(..., external: false, external_id: "<original>_<target>")` e `save`. O índice
único `(external_id, installment, company_id)` (`deal.rb:71`) recusa a segunda tentativa como erro
de validação em `external_id`, não como exceção, então re-execução é segura.

**Desativar** — `deal.disable(by:)` (`application_record.rb:109-127`) grava `disabled_at` e
`disabler_id` mantendo a linha. O cálculo para de enxergar porque `enabled` é
`where(disabled_at: nil)` (`application_record.rb:20-26`) e `Metric::TotalAdapter` aplica `.enabled`
nos dois braços (`total_adapter.rb:39,50`). Já desativado retorna `false` com `:already_inactive` —
idempotente. `enable` reverte.

**Atualizar estado** — `update(status_id:)`. Nada bloqueia: a validação `collaborative_deal`
(`deal.rb:152-157`) só morde quando há `deal_collaboration`, que espelho não tem.

**Atualizar valor** — `update(sold_price:, quantity:)`, **com um limite que muda a regra**:
ambos são `numericality: { greater_than: 0 }` (`deal.rb:41-42`), então um original que passa a valer
zero **não** pode ser refletido zerando o espelho. Valor que vai a zero é DESATIVAÇÃO, não update.

**Achar o espelho de um original não exige parsing** — `Deal.find_by(company_id:,
external_id: "#{original.external_id}_#{target_user_id}", installment: original.installment)` bate no
índice único. Só a direção inversa remove o sufixo, e é determinística porque a rotina conhece o
`target_user_id`.

**Nenhuma das quatro move número sozinha.** O conjunto que a métrica lê vem de um índice chaveado
por `commission_uuid` (`deal_search_index.rb:7-8`), então criar, desativar ou atualizar só aparece
no resultado depois que a compensação da competência é reprocessada.

## A rodada de reconciliação — por que a segunda passada não é a primeira de novo

**Um espelho é uma cópia congelada no instante em que foi criado, e nada o mantém sincronizado com o
original.** Quando a origem muda — a Larissa corrige o valor, troca o status, desativa a venda ou
sobe uma venda nova — o espelho continua exatamente como estava. O cálculo soma o que está lá, então
a divergência não aparece como erro: aparece como um número plausível que ninguém consegue explicar
depois.

**Rodar `04-mutacao.rb` de novo não resolve, e o motivo é o próprio portão que protege a primeira
rodada.** Ele conta os espelhos que já existem e recusa gravar qualquer coisa quando esse número é
maior que zero (`04-mutacao.rb:100-101`, `[mutation] gate failed — nothing was written`). Com 1.436
espelhos na base, a segunda passada não cria os que faltam — ela para inteira. O portão está certo
para o que foi escrito: uma gravação parcial sobre vários alvos deixa um lote que ninguém consegue
auditar. Ele só não é a ferramenta desta rodada.

**O que a segunda passada precisa é de um DELTA, e as quatro operações que ele usa já estão
descritas acima** (§ O espelho é reversível e atualizável). Para cada alvo, comparando o conjunto de
origem de agora contra os espelhos que existem:

| Situação | Operação |
|---|---|
| A origem passou a existir (venda nova, ou status que agora casa com a métrica) | **criar** |
| A origem mudou de valor, quantidade, status ou data | **atualizar** |
| A origem saiu do conjunto (desativada, status que não casa mais, dono fora da subárvore, virou carrier) | **desativar** o espelho |
| A origem voltou a casar e o espelho está desativado | **reativar** |
| Nada mudou | deixar como está |

**A desativação é o caminho para o espelho órfão, nunca `destroy`.** A linha fica, `enable` reverte,
e o CSV de auditoria da rodada registra o antes e o depois de cada alteração — que é o que permite
desfazer uma reconciliação inteira se ela partir de uma premissa errada.

**Um valor que vai a zero é desativação, não atualização** — `sold_price` e `quantity` são
`numericality: { greater_than: 0 }` (`deal.rb:41-42`). Na prática esse caso chega pelo caminho do
órfão: se a venda foi zerada ou desativada na origem, ela sai do conjunto de origem e o espelho é
desativado por isso.

**A reconciliação e a verificação andam juntas no tempo, pelo mesmo motivo que a classificação e o
reprocessamento** (§ A subárvore que a agregação lê é a de HOJE). Reconciliar hoje e reprocessar
depois de amanhã, com a Larissa mexendo no meio, entrega de novo o problema que a reconciliação
existe para resolver.

## Os ajustes de julho que dependem do cliente

**Nenhum destes é query nossa** — cada um espera um dado ou uma ação do outro lado. **A lista existe
para ser REPORTADA, não para ser esperada**: a apuração roda contra a base como ela está a qualquer
momento, e o que o cliente mudar depois entra na reconciliação seguinte, que é barata justamente por
isso (§ A divisão de trabalho). **O item 1 é o único que muda os DEALS**, então uma rodada anterior a
ele fica desatualizada quando ele chegar — o que se resolve reconciliando de novo, nunca segurando o
que o cliente pediu para hoje.

| # | O que está aberto | O que destrava | Responsável |
|---|---|---|---|
| 1 | Deals de Loja em ajuste, para o atingimento ficar correto | A Larissa terminar; o Patrick avisa, e uma nova reconciliação roda em seguida. Pedido feito, sem prazo dado | Larissa → Patrick |
| 2 | Não existe valor de controle de PAP verificado para conferir o recorte | O Patrick vai conferir com a Andresa se a receita de PAP está correta e mandar o número; o recorte da 63125 e o total de R$ 15.588,39 do Luiz Felipe já foram apresentados a ele | Patrick → Andresa |
| 3 | Receita do Líder de Call Center e do Coordenador divergem, devendo ser a mesma | O Patrick conferir se alguma transação foi enviada direta ao Coordenador; se foi, desativa | Patrick |
| 4 | Quatro vendedores do bônus de R$ 300 subiram, mas não constam na compensação | Andresa indica os grupos; Patrick recria o plano, amarra as metas e gera compensação nova, desativando a atual | Andresa → Patrick |
| 5 | Dois gerentes de loja com hierarquia errada | A base de origem precisa ser corrigida — a integração não traz essa correção, então a Larissa faz na mão | Andresa/Larissa |
| 6 | Meta de HC errada numa líder PAP, que por isso não recebe o bônus de R$ 1.000 | Andresa manda a meta e o realizado corretos; Patrick ajusta a meta e refaz o plano de Líder PAP | Andresa → Patrick |
| 7 | `atingimento_consultor_lider` sem valor e sem meta na base | Só a Andresa tem esse número | Andresa |
| 8 | Operador invertido na regra 265434 deixa a faixa de 80% a 100% sem pagar | Alteração de plano; o Patrick decidiu não mexer em julho e pediu à Andresa que valide | Patrick/Andresa |

**O item 5 é o de efeito mais amplo e o menos visível.** Hierarquia muda quem está na subárvore de
quem, e a subárvore é a entrada de tudo: dos espelhos, das contagens de loja e líder, e do `hc`. Uma
correção de hierarquia que chegue depois de uma apuração desloca todos esses números de uma vez — o
que a rodada seguinte absorve, e o relatório nomeia.

## Os scripts

Ficam em `scripts/`, numerados na ordem de execução. **Todos são colados no console via
`bin/ecs run <stack>`** — nunca executados como arquivo, porque o console roda numa task remota que
não enxerga o disco do engenheiro.

**Toda mutação executa TRÊS queries, nesta ordem, sem exceção — pular qualquer uma esconde uma
mutação parcial:**

1. **Dry-run / checagem** — relata o delta e não escreve NADA. É lido ANTES de aplicar, e as contas
   têm de fechar (§ Como as contas do delta fecham). Se não fecharem, uma identidade não pareou e o
   motivo vem antes da escrita.
2. **Execução** — aplica.
3. **Verificação** — relê da base viva CADA registro que a execução tocou e confere contra a origem,
   logo depois de aplicar e antes do reprocessamento. **A execução reportar o que fez NÃO é
   verificação** — é o auto-relato dela, não uma releitura independente: `CREATE@9` prova que o
   script tentou nove, nunca que nove existem e ficaram certos.

A validação do agregado (`05`) é uma QUARTA checagem, à parte: só vale DEPOIS do reprocessamento e
confere o número da compensação, não os registros que a mutação tocou.

### Como as contas do delta fecham

**`UNCHANGED` é somado em DOIS lugares diferentes do `10-reconciliacao.rb`, e é isso que torna uma
identidade ingênua inútil.** Uma origem que já tem espelho idêntico soma `UNCHANGED` no laço dos
esperados; um espelho órfão que JÁ ESTAVA desativado soma o mesmo contador no laço dos órfãos, porque
não há nada a fazer com ele. O contador impresso é a soma dos dois, então `UNCHANGED + UPDATE +
CREATE + ENABLE` estoura o total de esperados por exatamente a quantidade de órfãos já desativados.

Chamando de `parados` os órfãos que já estavam desativados, as duas contas são:

```
esperados  = CREATE + ENABLE + UPDATE + (UNCHANGED - parados)
existentes = ENABLE + UPDATE + (UNCHANGED - parados) + parados + DISABLE
```

**A segunda se reduz a `existentes = UNCHANGED + UPDATE + ENABLE + DISABLE` e é a que se confere
direto**, porque `parados` se cancela. A primeira determina `parados` por subtração, e o delta está
íntegro quando o mesmo valor satisfaz as duas e não é negativo. Uma terceira conferência independente
existe e vale a pena: `parados` tem de ser igual à soma, por alvo, de `existing` menos os espelhos
ativos daquele alvo — número que o `01-checagem.rb` imprime como `mirrors_already_on_target`.

`existing` conta espelho desativado junto, porque a query que monta `existing_mirrors` não filtra
`.enabled` — é deliberado, já que um órfão que voltou a casar precisa ser reativado, e um espelho
invisível para a comparação seria recriado por cima do índice único.

| Script | Fase | O que faz |
|---|---|---|
| `00-descoberta.rb` | leitura | Lista todo plano do período com grupo, override, variáveis e estado da compensação; localiza pessoas por fragmento de nome imprimindo os identificadores para conferência |
| `01-checagem.rb` | leitura | Confirma os portões do ambiente e toda âncora do plano, alvo a alvo, incluindo sobreposição com cargos já espelhados |
| `02-conjuntos.rb` | leitura | Compara as três noções de "abaixo de mim" com o total de deal de cada uma — use quando um número não fecha e o motivo não é óbvio |
| `03-preflight.rb` | leitura | Projeta o que cada alvo passará a carregar e **conta os portões** (`too_long`, `already_exists`) |
| `04-mutacao.rb` | escrita | Cria os espelhos; varre o portão antes e **não grava nada** se encontrar violação |
| `05-validacao.rb` | leitura | Imprime o esperado ao lado do que a plataforma calculou — só produz resposta depois do reprocessamento |
| `06-desativacao.rb` | escrita | Rollback por `disable`, que preserva a linha e é reversível por `enable` |
| `07-classificacao.rb` | leitura | Separa os espelhos existentes em essenciais e dobrados, pela origem de cada um |
| `08-limpeza-duplicados.rb` | escrita | Apaga só os dobrados; reclassifica do zero antes, e não grava nada se algum espelho não tiver origem rastreável |
| `09-restauracao.rb` | escrita | Recria espelhos a partir de qualquer CSV de auditoria desta rotina — é o desfazer de `06` e `08` |
| `10-reconciliacao.rb` | leitura **ou** escrita | Compara o conjunto de origem de agora contra os espelhos que existem e aplica o delta — cria os que faltam, atualiza os que mudaram, desativa os órfãos, reativa os que voltaram. Percorre os três planos numa execução; abre em `dry_run`, que só relata |
| `11-contagens.rb` | leitura **ou** escrita | Recalcula `lojas_atingimento` e `atingimento_lideres` contra a base de agora, imprime cada uma ao lado do `Indicator` gravado e corrige as divergentes por `update` do `value`. Abre em `dry_run`, que só relata. **`hc` fica fora do conjunto que ele grava** (§ A errata dos Executivos) |
| `12-verificacao.rb` | leitura | A terceira query de toda mutação de deal: relê, a partir do CSV de auditoria que `04` ou `10` gravou, cada registro que a mutação tocou e confere que o espelho ficou idêntico à venda de origem nos oito campos que o cálculo lê. Devolve `PASS@N@FAIL@0`; qualquer `FAIL` é mutação parcial, e o bucket não está pronto |
| `13-errata.rb` | leitura | Imprime as âncoras do plano que apura os Executivos ao lado do que ele substitui — variáveis, `override`, compensação, régua regra a regra, e o valor gravado de cada variável sem métrica por Executivo |
| `14-recorte-pap.rb` | leitura | Divide a subárvore de cada Executivo entre a população PAP e o resto e totaliza `vendas_instaladas` dos dois lados; imprime também a distribuição por status da empresa no mês, que é onde os rótulos de cidade aparecem |
| `15-diferenca-pap.rb` | leitura | Enumera tudo que o recorte de PAP deixa de fora de um Executivo — líderes PAP da subárvore, vendedores excluídos com o gestor de cada um, cada venda excluída, vendas próprias do alvo e vendas desativadas no conjunto |
| `16-descricao.rb` | leitura **ou** escrita | Reescreve a `description` de todo espelho já gravado, rastreando cada um até a venda de origem pelo `external_id`; não grava nada se algum espelho não for rastreável. Abre em `dry_run`, que só relata |
| `17-regua.rb` | leitura | Imprime cada regra de cada incentivo do plano dos Executivos com a fórmula literal, e ao lado o valor de cada variável com métrica recalculado dos deals, o valor agregado atual, a meta e o atingimento resultante. É o que se leva ao cliente quando ele questiona a régua — a fórmula, não a descrição dela |

**`10-reconciliacao.rb` é o único script que muda de fase por uma variável, e isso é deliberado.**
Todo o resto da rotina separa pré-flight e mutação em arquivos distintos, mas aqui as duas metades
precisam medir o **mesmo instante**: o delta depende da hierarquia e dos deals de agora, e entre duas
colagens de console a Larissa pode ter subido mais um ajuste. Com `dry_run = true` (o padrão) ele
percorre tudo, imprime os contadores e grava o CSV sem tocar em nada; trocar para `false` aplica
exatamente o delta que acabou de ser relatado.

**Um único script serve qualquer cargo.** A configuração no topo é `plan_ids` e `competence_period_id`
— nada mais. O conjunto de origem se ajusta sozinho: numa subárvore de plano não-override ninguém
carrega linha de `Indicator` alcançável pela varredura, então a exclusão não retira nada e sobra a
subárvore inteira. Os alvos saem dos participantes da própria compensação em vez de uma lista de nomes.

| Cargo | `plan_id` | Compensação | Override | Conjunto de origem resultante |
|---|---|---|---|---|
| Coordenador de Call Center | 78941 | 63126 | não | subárvore inteira |
| Executivos de Vendas | 79175 | 63309 | não | subárvore inteira |
| Gerentes Comerciais | 78940 | 63128 | não | subárvore inteira |

### A garantia: nada apagado aqui é irrecuperável

**Todo script de escrita grava, ANTES de qualquer remoção, um CSV com as dezesseis colunas que
recriam cada registro** — `type`, `user_id`, `owner_id`, `external_id`, `date`, `originated_at`,
`installment`, `quantity`, `sold_price`, `client_id`, `product_id`, `status_id` e o resto. Quatro
delas não são detalhe: `date`, `client_id`, `product_id` e `status_id` são o que a métrica filtra, e
um espelho recriado sem elas existe sem ser visto pelo cálculo — pior que não recriar.

O caminho é `integration-debug/audits/2077/<fase>/<timestamp>.csv` no bucket do próprio ambiente, via
`Aws.connection.put_object(ApplicationConfiguration.aws_bucket, file_path, csv_string)`. O timestamp
no nome garante que execução nenhuma sobrescreve outra, então a cadeia inteira de estados fica
preservada e `09-restauracao.rb` recompõe qualquer um deles apontando `audit_key` para o CSV
correspondente.

**A reconciliação cumpre essa garantia por outro caminho, e é o `dry_run` que a cumpre.** O CSV dela
(`premiacao-reconciliation`) sai no fim da execução, não antes; o que roda antes de qualquer
alteração é a passada em modo relatório, que grava o delta inteiro — inclusive as colunas de recriação
de cada espelho que seria desativado — sem tocar em nada. E a desativação preserva a linha de todo
jeito: o desfazer de uma reconciliação é `enable`, não recriação a partir do CSV.

**Todo script abre imprimindo `ApplicationConfiguration.aws_bucket` e para se não for o esperado**
(§ O portão do ambiente). Um console apontado para outro stack responde zero a toda consulta, e zero
se lê como "o dado sumiu" em vez de "estou no ambiente errado".

## O filtro da métrica sai do adapter, não do modelo

Reconstruir o filtro a partir dos campos de `Metric` produz número errado. A fonte é
`Metric::TotalAdapter.calculate` (`app/adapters/metric/total_adapter.rb`):

- a redução depende do tipo de plano — `sold_price * quantity` para `SalesPlan`, `quantity` para
  `CallsPlan`, `sold_price` para `CreditRecoveryPlan` e `ServiceSalesPlan`;
- o escopo aplica `for_type(plan.deal_type)` e `.enabled`;
- com `ApplicationConfiguration.search_index?` ativo o conjunto vem do `DealSearchIndex`, não de um
  `where` direto.

Somar `sold_price` puro sobre um `SalesPlan` superestima sempre que `quantity` for diferente de 1.

## Armadilhas confirmadas

**Um número atribuído ao cliente só entra aqui com a ORIGEM junto — mensagem, e-mail ou planilha
nomeada.** Um valor de referência sem fonte vira critério de aceite na leitura seguinte, e aí uma
sessão inteira gasta rodadas perseguindo a diferença entre a base e um número que ninguém disse. O
teste é barato e é obrigatório antes de tratar qualquer valor como referência: buscar o número no
Slack. Se ele não aparece, ele não é referência — é a estrutura que sustenta a conferência, e o
número nosso é o que se leva ao cliente para ele reagir.

**Uma régua se LÊ, nunca se descreve de memória — e a descrição da regra não é a regra.** Duas
afirmações erradas chegaram ao cliente por esse caminho numa única mensagem: que os Executivos
passariam de 100% da meta (o atingimento real é 44% a 95%, e a meta estava a uma query de distância) e
que a régua pagaria sobre `vendas_instaladas + movel` (a fórmula multiplica `faturamento_parceiro`).
Some-se a isso que a descrição da 265434 diz "entre 80% e 99,99%" enquanto a condição dela diz o
oposto: o texto que acompanha a regra é do mesmo autor que errou o operador. O `17-regua.rb` existe
para que a fórmula literal e o atingimento cheguem juntos ao cliente, e leva trinta segundos.

O identificador que o cliente usa **não** é `User.id`. O documento de origem escreve "Alex Lima
Lofeu ID 1918117", e 1918117 é `UserIdentifier.value`; o `User.id` dele é 1119697. Resolver sempre
por `UserIdentifier.where(company_id:, value:).pluck(:user_id)`.

`modifiers.value`, `aggregated_modifiers.value` e `goals.value` são `string` (`db/schema.rb:1120`,
`:84`, `:859`). Somar com `SUM()` no Postgres levanta `PG::UndefinedFunction`. A conversão é
`variable.data_type.format(value)` — a mesma chamada que `Indicator#format` faz
(`indicator.rb:85-87`) — e a redução acontece em Ruby, como em `AggregatedIndicator#calculate!`. Ao
gravar de volta, o formato é inteiro simples (`"13"`), que é como a empresa 2077 tem os valores.

**`Aws.connection` NÃO EXISTE.** A classe expõe `connection_pool` e `with_connection` e nada mais
(`app/models/aws.rb:3-11`); o acesso é
`Aws.with_connection { |connection| connection.put_object(bucket, path, body) }`, a forma que as 18
rake tasks de `lib/tasks/integration_audit/` usam. O erro estoura no fim do script, depois de a
mutação já ter acontecido — por isso os contadores são impressos ANTES do upload.

**`DATE(coluna_timestamp)` em SQL opera no valor ARMAZENADO, que é UTC.** `application.rb:64-65` põe
`config.time_zone = 'Brasilia'` com `active_record.default_timezone = :utc`, então agrupar por
`DATE(updated_at)` joga toda escrita após as 21h no dia seguinte. A forma certa é
`DATE(updated_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')`. Um `Time.zone.now`,
`Time.current` ou `10.days.ago` no lado Ruby já vem em -03 e não tem esse problema.

**Um `Indicator` deixa de ser destruível assim que a competência é processada** — `destroyable?`
devolve `false` na presença de `indicator_aggregations` (`indicator.rb:97-105`), e eles nascem do
processamento. Depois disso a correção é `update(value:)`; `destroy` é recusado.

`Deal.for_user(nil)` não filtra — o escopo é condicional a `user_id.present?`. Um usuário de origem
em branco varre a empresa inteira em silêncio.

`abort` num paste de `bin/ecs run` derruba a sessão; guardas usam `if`/`else` com `puts`.

## Variáveis e cargos

| Variável | Id | Métrica |
|---|---|---|
| `vendas_instaladas` | 36311 | sim |
| `movel` | 36600 | sim |
| `indicacao` | 36819 | sim |
| `hc` | 36480 | não |
| `lojas_atingimento` | 36927 | não |
| `atingimento_lideres` | 36928 | não |
| `atingimento_consultor_lider` | 36929 | não |
| `quantidade_parceiro_acima_mil` | 36940 | não |
| `desconto_retroativo` | 36336 | não |
| `qualidade` | 25823 | não |

**A lista a espelhar sai sempre de `plan.variables.with_metrics`, nunca desta tabela.** Ela varia
por plano: o Coordenador consome duas variáveis com métrica, os Gerentes Comerciais três (com
`indicacao`). Herdar a lista do cargo anterior é como se deixa uma variável para trás.

Grupos: 40314 (Gerentes Comerciais), 40315 (Executivos de Vendas), 48179 (Call Center), 50210
(Coordenador de Call Center), 50213 (Líder de Call Center), 50216 (Líderes PAP), 50212
(Atingimento por loja).

Pessoas confirmadas por identificador — o identificador que o cliente escreve **não** é o `User.id`,
e essa é a armadilha que a tabela existe para evitar:

| Pessoa | `User.id` | Identificadores |
|---|---|---|
| Alex Lima Lofeu (Coordenador) | 1119697 | `1918117` |
| Roberta Dos Santos Cardoso Da Silva (Líder) | 1119878 | — |
| Loandra Teixeira Costa (Executiva) | 1026105 | `4sk_236`, `1926540` |
| Cristiano Rodolfo Dionísio De Oliveira (Executivo) | 1119699 | `4sk_482`, `1924504` |
| Flavia Dutra Castanheira De Oliveira (Executiva) | 1119700 | `4sk_483`, `1918280` |
| Luiz Felipe Sonego Bonini (Executivo) | 1243772 | `4sk_717`, `1927287` |
| Beatriz Carvalho Costa (na compensação, fora da lista) | 1119698 | `4sk_481`, `1918853` |
| Joel Geraldo Junior (Gerente) | 1026079 | `4sk_12`, `1922319` |
| Joao Luis Carnelos (Gerente) | 1119696 | `4sk_537`, `1922316` |

## A âncora é o plano, nunca a compensação

O período sai de `plan.calendar` — `Plan belongs_to :calendar` com `has_many :periods, through:
:calendar` (`plan.rb:8,35`). Uma competência existe assim que o calendário do plano a define; a
compensação é cortada depois e pode não existir ainda. Procurar o período em `Commission` faz uma
competência viva parecer inexistente.

Do usuário chega-se ao plano por dois caminhos, ambos reais: as `PlanStatement` dele e as
`Groupification` → grupos → planos.

## Âncoras de julho/2026

Calendário 19604, período **528210** (01/07 a 31/07). Todos os planos são `SalesPlan` com
`deal_type` `Sale`, portanto a redução da métrica é `sold_price * quantity`.

| Cargo | Plano | Grupo | Compensação | Override | Variáveis com métrica |
|---|---|---|---|---|---|
| Coordenador de Call Center | 78941 | 50210 | 63126 | não | `vendas_instaladas`, `movel` |
| Executivos de Vendas | 79175 | 40315 | 63309 | não | `vendas_instaladas`, `movel`, `faturamento_parceiro` |
| Gerentes Comerciais | 78940 | 40314 | 63128 | não | `vendas_instaladas`, `movel`, `indicacao` |
| Líder de Call Center | 78943 | 50213 | 63134 | sim | `vendas_instaladas`, `movel` |
| Call Center | 78942 | 48179 | 63120 | não | `vendas_instaladas`, `movel` |
| Líderes PAP | 78938 | 50216 | 63125 | sim | `vendas_instaladas`, `movel`, `indicacao` |

Métricas: `vendas_instaladas` → 4819; `movel` → 4907, que filtra apenas por `status_id` 3846 e
`installment >= 1`, sem cliente nem produto; `indicacao` → 4940.

## O portão do ambiente

**Todo script desta apuração abre imprimindo `ApplicationConfiguration.aws_bucket` e para se não for
`4shark-shared-001`.** O console é aberto por `bin/ecs run <stack>` e nada dentro dele anuncia em que
ambiente está — um console apontado para outro stack responde a toda consulta com zero, que se lê
como "o dado sumiu" em vez de "estou no lugar errado". O nome do bucket é a identificação mais barata
que existe: já aparece em toda gravação de auditoria e distingue os ambientes sem consulta extra.

A coluna `external` de `Deal` **existe no banco do `app-shared-001`**, levada pelo deploy que aplicou
a migration do PR https://github.com/4shark/app/pull/5334. Uma sessão futura confirma isso pela
primeira linha da checagem (`gate@external_column`) em vez de presumir: uma migration só toca o banco
de um ambiente quando aquele ambiente é deployado, então um ambiente que não recebeu o deploy falha
na primeira gravação com coluna inexistente.

`ApplicationConfiguration.search_index?` está **ligado** neste ambiente, e é isso que faz nenhuma
mutação mover número sozinha: o `TotalAdapter` lê os ids do `DealSearchIndex` filtrando por
`commission_uuid` (`total_adapter.rb:24-39`), e o índice é chaveado por comissão
(`deal_search_index.rb:7-8`). Deal criado depois do processamento não existe para aquela comissão.

Deploy de ambiente produtivo é ação do engenheiro: passa antes pelo `sidekiq-queue-check.sh`, que
libera só com a fila limpa, e o gatilho é `gh workflow run deploy-shared-001.yaml -R 4shark/app`.

## Execução

### Retomada — o primeiro passo é ler o canal, não rodar script

**O escopo de cada rodada sai do `#commcenter`, não deste documento.** O Patrick é quem diz quais
cargos entram e quando, porque é ele quem conduz o fechamento com a Andresa. Antes de qualquer
colagem, leia o canal e classifique o que chegou:

| O que o Patrick pediu | O que fazer |
|---|---|
| Cargos nomeados, com prazo | Rodar a re-apuração abaixo com esses `plan_ids` e avisar que as compensações estão prontas para reprocessar |
| A Larissa terminou as deals de Loja | Rodar a re-apuração nos cargos que ainda não passaram por ela depois da correção |
| O valor de controle de PAP, com a planilha | Comparar `external_id` a `external_id` contra o conjunto PAP do alvo; divergência é registro, não arredondamento (§ Armadilhas confirmadas) |

**Nenhum desses itens bloqueia outro.** O valor de controle confere o RECORTE e não trava rodada
nenhuma; a correção da Larissa muda os DEALS, então um conjunto reconciliado antes dela envelhece
quando ela fechar — o que é motivo para reconciliar de novo, nunca para não entregar hoje o que o
cliente pediu hoje (§ A divisão de trabalho).

**O que já está feito e não se repete:** as descrições dos espelhos estão corrigidas e verificadas, o
filtro de PAP está escrito no `10`, e os scripts dos Executivos estão ancorados no plano 79175 com a
exclusão de carriers gateada pelo `override`. Nada disso precisa ser refeito na retomada.

### Qual das duas sequências

Há duas sequências, e a diferença entre elas é uma pergunta só: **este cargo já tem espelhos gravados
nesta competência?** O `01-checagem.rb` responde isso alvo a alvo, e o `03-preflight.rb` confirma
pelo contador `already_exists`.

### Primeira apuração de uma competência

Por cargo, na ordem, com os scripts de `scripts/`:

1. **Descoberta** (`00`) — só quando o plano do cargo não é conhecido. Lista os planos do período e
   localiza as pessoas, imprimindo identificadores para conferência.
2. **Checagem** (`01`) — portões do ambiente e âncoras do plano, alvo a alvo. `reaches_other_target`
   e `mirrors_already_in_subtree` dizem se este cargo está acima de outro já espelhado.
3. **Pré-flight** (`03`) — a query de checagem: projeta e conta os portões. **A mutação não roda
   enquanto `too_long` e `already_exists` não forem ambos zero.**
4. **Mutação** (`04`) — a query de execução: cria os espelhos, recusando gravar qualquer coisa se o
   portão falhar.
5. **Verificação** (`12`) — a query de validação: relê cada espelho criado e confere contra a venda
   de origem. `PASS@N@FAIL@0` antes de seguir.
6. **Reprocessar a compensação** — ação do engenheiro. Sem isso o número não se move.
7. **Validação do agregado** (`05`) — depois do reprocessamento, compara o esperado com o que a
   plataforma calculou.

### Re-apuração de uma competência que já tem espelhos

São oito colagens que rodam de ponta a ponta numa sessão: o `10` cobre os cargos de `plan_ids` num laço e o
`11` cobre as duas contagens dos Executivos. Cada uma das duas mutações — a reconciliação de deals
(`10`) e a correção de contagens (`11`) — carrega as suas três queries: dry-run, execução,
verificação.

1. **Checagem** (`01`) — portões do ambiente e âncoras do plano. Confirma que o plano, o período e a
   compensação continuam os mesmos, e imprime o `money` atual de cada alvo.
2. **Reconciliação em modo relatório** (`10`, `dry_run = true`) — a query de checagem da reconciliação:
   imprime `CREATE`, `UPDATE`, `DISABLE`, `ENABLE`, `UNCHANGED` e `FAILED` por plano, e grava um CSV
   por plano. **Ler o delta antes de aplicar é o passo que não se pula**, e as contas têm de fechar
   dos dois lados (§ Como as contas do delta fecham). Se não fecharem, alguma identidade não pareou e
   o motivo vem antes da escrita.
3. **Reconciliação aplicando** (`10`, `dry_run = false`) — a query de execução, logo em seguida, sem
   intervalo.
4. **Verificação da reconciliação** (`12`) — a query de validação: relê cada registro que o `10`
   criou, atualizou ou desativou, a partir dos CSVs do apply, e confere contra a origem.
   `PASS@N@FAIL@0` antes de seguir.
5. **Contagens em modo relatório** (`11`, `dry_run = true`) — a query de checagem das contagens:
   recalcula loja e líder e imprime cada uma ao lado do gravado, com o `raw` e o `destroyable?`. O
   `hc` aparece só como leitura por cidade, porque o script não grava essa variável (§ A errata dos
   Executivos).
6. **Contagens aplicando** (`11`, `dry_run = false`) — a query de execução: corrige por `update` só
   as divergentes.
7. **Verificação das contagens** (`11`, `dry_run = true` de novo) — a query de validação das
   contagens: depois do apply, um novo relatório tem de vir `DIVERGING@0`. É a releitura independente,
   porque `11` não gera CSV de espelho para o `12` reler.
8. **Validação do agregado** (`05`) — depois de o reprocessamento acontecer, compara o esperado com o
   que a plataforma calculou, relendo a base.

**Um delta grande não é motivo para parar, é motivo para EXPLICAR.** Quando `DISABLE` e `CREATE` vêm
altos e simétricos entre dois alvos, a causa costuma ser hierarquia: comparar o tamanho das subárvores
com o registrado aqui e datar as escritas por `seats.updated_at` identifica o movimento em duas
consultas (§ A subárvore que a agregação lê é a de HOJE). O resultado vira frase no relatório, não
pergunta ao cliente.

O `02-conjuntos.rb` não está na sequência: é diagnóstico, para quando um número não fecha e o motivo
não é óbvio. O `06-desativacao.rb` é o rollback dos espelhos, e o CSV de cada rodada carrega o valor
anterior de tudo que foi alterado.

Todo output de script vai para CSV no bucket do próprio ambiente, em
`integration-debug/audits/2077/<fase>/<timestamp>.csv`, via
`Aws.connection.put_object(ApplicationConfiguration.aws_bucket, file_path, csv_string)`.

## Coordenador — julho/2026

Alvo: Alex Lima Lofeu, `User.id` 1119697, plano 78941. Subárvore de 73 usuários.

O pré-flight fecha limpo em `vendas_instaladas`: 324 deals de 29 pessoas da subárvore, cobrindo
01/07 a 31/07, todas com `quantity` 1,0 e projeção de **R$ 35.378,78**. Todo `external_id`
espelhado tem no máximo 13 caracteres, contra o limite de 36 do modelo, e nenhum já existe.

`movel` seleciona zero deals na subárvore, e o filtro está funcionando: com `status_id` 3846, a
empresa inteira tem 1 deal em julho contra 16 em junho. A queda é de dado, não de query.

Esses números são a referência de conferência, não um resultado arquivado: o pré-flight roda de
novo imediatamente antes da mutação, e divergir deles significa que os deals de julho se moveram
entre uma execução e outra — o que precisa ser entendido antes de espelhar, nunca ignorado.

**O Coordenador tem 304 espelhos ativos somando R$ 33.038,00**, reconciliados contra os deals de
26/08. Uma sessão que chegar aqui NÃO roda `04-mutacao.rb`: o índice único recusaria, o pré-flight
acusa antes com `already_exists`, e a ferramenta desta fase é `10-reconciliacao.rb`. Para tirar um
espelho do cálculo, o caminho é a desativação (§ as quatro operações), nunca `destroy`.

**O valor do Coordenador continua zero até a compensação 63126 ser reprocessada**, porque ela está
`locked` e o conjunto que a métrica lê vem de um índice chaveado por `commission_uuid`. Reprocessar
uma compensação produtiva é ação do engenheiro — o espelhamento entrega o dado, não o número.

## O conjunto de origem depende do `override` do plano

**Quem decide isso é `IndicatorAggregation::UserProducer`, e a leitura é o oposto do que o nome
sugere** (`user_producer.rb:18-22`):

```ruby
user_ids =
  if commission.plan.override?
    HierarchyScope.new(user, User).resolve.pluck(:id)
  else
    user.id
  end
```

**Com `override: false` o espelho cobre a subárvore inteira**, e é o caso dos TRÊS cargos de julho —
Coordenador 78941, Gerentes 78940 e Executivos 79175: a agregação usa `user.id` sozinho, nada sobe, e
sem espelho o alvo fica zerado. É por isso que a subárvore inteira é o conjunto de origem nos três, e
por isso que o `10-reconciliacao.rb` não exclui carrier nenhum nesta competência.

**Com `override: true` o espelho CONTINUA NECESSÁRIO**, e o
motivo é que a varredura recursiva não calcula nada — ela só **lê linhas de `Indicator` que já
existam**. `AggregatedIndicator#result` (`aggregated_indicator.rb:92-97`) resolve o `HierarchyScope`
sobre a subárvore e chama `indicator(user_id:, interval:)`, que em `aggregated_indicator.rb:109-120`
faz um `find_by` na tabela `modifiers`. Quem não tem linha não contribui com nada.

Quem cria essas linhas é o `Metric::Consumer`, e ele roda **só para os participantes do plano** —
`Metric::Producer` usa `commission.user_ids` (`metric/producer.rb:19`), que em
`commission.rb:237-253` é a lista de `Groupification`, sem nenhum subordinado. E o valor de cada
linha é `for_user(user_id)` (`total_adapter.rb:44`): as deals daquela pessoa e de mais ninguém.

Medido em julho/2026: a subárvore da Loandra tem 119 pessoas e 47 carregam linha; a do Luiz Felipe
tem 211 e 65 carregam; a da Flavia tem 168 e 63 carregam. Os 72, 146 e 105 restantes são invisíveis
para a soma, e o espelho é o único caminho que a receita deles tem para subir.

A relação que fecha o agregado é `aggregated = own_indicator + carriers_sum`, e ela bate ao centavo:
Loandra 19.968,22 + 21.618,08 = 41.586,30; Flavia 22.642,84 + 24.812,60 = 47.455,44; Luiz Felipe
31.351,15 + 22.977,68 = 54.328,83.

**O que ainda não foi medido é a interseção entre a origem dos espelhos e os `carriers`.** Um espelho
que copia deal de alguém que já carrega linha própria conta duas vezes; um que copia de alguém mudo é
a única forma daquela receita chegar. A mutação excluiu `Plan#subordinate_ids_by` (um nível), que não
é o mesmo conjunto que os `carriers` — então o filtro pode estar deixando passar uma fatia dobrada.
Isso se resolve lendo o CSV de auditoria e classificando cada espelho pela origem, não por dedução.

**O `override` é uma propriedade do PLANO daquela competência, não do cargo.** Cada competência tem
seu próprio plano, com sua própria régua, e o flag é lido daquele plano antes de qualquer decisão
sobre espelhar — nunca herdado do que o cargo fazia antes.

**"Abaixo de mim" tem três significados diferentes nesta codebase e eles NÃO são intercambiáveis:**

| Origem | O que devolve |
|---|---|
| `Plan#subordinate_ids_by` (`plan.rb:214-225`) | `SeatHistory` cujo `parent_id` é o assento da pessoa, **dentro da janela do período** — é o que o cálculo do override lê |
| `Commission#subordinate_ids` (`commission.rb:260-275`) | a mesma query, copiada |
| `Commission::DealOptionsProcessor` (`deal_options_processor.rb:15-20`) | a mesma query, inline |
| `User#subordinate_ids` (`user.rb:407-409`) | `seat.subordinates`, um `has_many` de `Seat` sobre si mesmo (`seat.rb:14`) |
| `UserScope` → `HierarchyScope` (`hierarchy_scope.rb:5-12`) | `WITH RECURSIVE` sobre `seats.parent_id`, todos os níveis |

**A subtração é por `user_id`, NUNCA por valor, porque os conjuntos não são aninhados.** O que o
cálculo enxerga vem do **histórico** de assento na janela, não da hierarquia de hoje: quem trocou de
gestor no meio da competência conta para os dois lados. Um Executivo com 29 pessoas na subárvore
atual teve 31 no conjunto do cálculo — oito que já saíram, e a diferença de totais (R$ 304,98)
não tem relação com o total real do resto (R$ 2.949,72).

**O valor agregado que a compensação exibe NÃO serve como referência de conferência quando ela foi
processada antes das últimas correções.** Ele foi compilado naquele instante e não acompanha
correção de deal nem mudança de grupificação — um Executivo apareceu com zero tendo vendedor ativo
abaixo. A conferência é sempre entre conjuntos tirados do mesmo instante, e o fechamento só depois
do reprocessamento.

## Executivos de Vendas — julho/2026

Plano 79175, grupo 40315, `override: false`, compensação 63309 (§ A errata dos Executivos). Cinco participantes, e os quatro
nomes da lista da Andresa batem: Loandra Teixeira Costa, Cristiano Rodolfo Dionísio de Oliveira,
Flavia Dutra Castanheira de Oliveira e Luiz Felipe Sonego Bonini. A quinta é **Beatriz Carvalho
Costa** (`4sk_481` / `1918853`), que a lista não menciona — sem venda abaixo dela fora do que o
plano já entrega, então o espelhamento não a tocou e a dúvida sobre ela não bloqueia nada.

**Este cargo RECEBE espelho como os outros dois, e pelo mesmo motivo deles: `override: false`.** Nada
sobe sozinho da equipe, então sem espelho o Executivo fica com as próprias vendas e mais nada
(§ O conjunto de origem depende do `override` do plano).

**O espelho só é legítimo quando a origem NÃO carrega linha de `Indicator` própria.** Um vendedor com
linha própria já é alcançado pela varredura recursiva, então espelhar a venda dele soma a mesma
receita duas vezes; um vendedor sem linha é invisível para a varredura, e o espelho é o único caminho.
A mutação filtrou por `Plan#subordinate_ids_by` — um nível de hierarquia — que é conjunto diferente
desse, e é o que produz fatia dobrada.

**Os Executivos têm 703 espelhos ativos somando R$ 72.658,14.** A exclusão de carriers NÃO roda aqui:
o plano é `override: false`, então nada da equipe sobe sozinho e a receita de quem carrega indicator
próprio precisa do espelho tanto quanto a de quem não carrega.

| Executivo | Espelhos | Valor | Subárvore | População PAP |
|---|---|---|---|---|
| Flavia Dutra Castanheira De Oliveira | 222 | 22.847,80 | 168 | 100 |
| Loandra Teixeira Costa | 193 | 21.508,09 | 119 | 63 |
| Luiz Felipe Sonego Bonini | 170 | 16.578,32 | 157 | 97 |
| Cristiano Rodolfo Dionísio De Oliveira | 118 | 11.723,93 | 83 | 44 |
| Beatriz Carvalho Costa | 0 | 0,00 | 6 | 0 |

**Dois desses valores conferem ao centavo contra o recorte que o `14-recorte-pap.rb` mediu** — Loandra
R$ 21.508,09 e Flavia R$ 22.847,80 —, o que prova que o filtro de PAP do `10` seleciona a mesma
população. Os outros dois fecham somando a parcela que a regra não restringe a PAP: Luiz Felipe é
15.588,39 de PAP mais 989,93 de `faturamento_parceiro`, e Cristiano 11.328,93 mais 395,00 de `movel`,
ambas as parcelas vindas da subárvore inteira porque a regra do Patrick nomeia `vendas_instaladas`
sozinha.

Os CSVs de auditoria que reconstroem qualquer estado anterior deste conjunto, todos com as dezesseis
colunas necessárias para recriar cada registro:

| Conteúdo | Caminho em `s3://4shark-shared-001/` |
|---|---|
| 750 espelhos originais, apagados | `integration-debug/audits/2077/premiacao-deletion/20260824-205741.csv` |
| 750 recriados a partir do anterior | `integration-debug/audits/2077/premiacao-restore/20260824-213118.csv` |
| 534 de origem duplicada, apagados | `integration-debug/audits/2077/premiacao-duplicate-cleanup/20260824-214726.csv` |

### A receita que entra no atingimento dos Executivos

**Em `vendas_instaladas` o Executivo carrega SÓ a soma de PAP.** É a regra do cargo, dita pelo
Patrick, e ela é filtro no conjunto de origem do espelhamento: receita de loja não entra.

**NÃO EXISTE referência numérica verificada para conferir esse filtro, e inventar uma é pior do que
não ter.** Uma busca no Slack inteiro — canal, DMs, mensagens privadas — não devolve nenhum valor de
receita PAP dito pelo Patrick ou pela Andresa. O que está registrado dele é a REGRA
("no valor de vendas instaladas o executivo só deve ter a soma de PAP", 28/08), nunca um total.
Enquanto um número não vier com origem — um e-mail, uma planilha que ele aponte, uma mensagem — a
conferência do recorte é estrutural: o conjunto PAP tem de ser a subárvore dos líderes da 63125, e
qualquer diferença contra um total "de controle" é conversa a ter com quem produziu esse total.

**A consequência não é um ajuste fino, é a faixa inteira.** A régua de receita só paga a partir de 80%
da meta, e o recorte PAP tira do numerador toda a receita de loja — o atingimento cai junto, e um
Executivo que passaria do piso com a subárvore inteira pode não passar com o recorte. Comparar o
atingimento antes e depois do filtro é o que mostra quem muda de faixa.

**A regra é coerente com o desenho da premiação, e é isso que a sustenta.** O cargo já é pago por
loja através de uma CONTAGEM (`lojas_atingimento * 200`)
e por líder PAP através de outra (`atingimento_lideres * 400`). Se a receita de loja também entrasse
em `vendas_instaladas`, a loja seria paga duas vezes pelo mesmo desempenho — uma vez como contagem e
outra como receita.

**O `10-reconciliacao.rb` ainda não distingue PAP de loja, e a métrica sozinha não distingue.** As
três variáveis de receita se separam só por status (`vendas_instaladas` 3084, `movel` 3846,
`indicacao` 3811), sem nada que diga de onde a venda veio; o recorte tem de entrar como um filtro a
mais sobre o conjunto de usuários de origem, e todos os espelhos dos Executivos precisam ser
reconciliados contra o conjunto novo depois disso.

**O discriminador é a HIERARQUIA.** A população PAP é a união das subárvores dos líderes da
compensação 63125 (plano 78938, Líderes PAP) que caem dentro da subárvore do Executivo; o que sobra
é loja e outros canais. No Luiz Felipe esse recorte devolve **R$ 15.588,39**.

**O que sustenta o recorte é a estrutura, e ela foi verificada.** Os três vendedores que ficam de fora
no Luiz Felipe respondem por R$ 259,97, R$ 850,95 e R$ 1.179,87, e cada um pendura em gestor que não
participa da compensação de Líderes PAP; nenhum líder de PAP ficou de fora da 63125 arrastando equipe
junto. Ele não tem venda própria na métrica e não há venda desativada no conjunto PAP.

| Executivo | Subárvore | PAP | Resto |
|---|---|---|---|
| Luiz Felipe Sonego Bonini | 157 pessoas · R$ 17.879,18 | 97 · R$ 15.588,39 | 60 · R$ 2.290,79 |
| Flavia Dutra Castanheira De Oliveira | 168 · R$ 27.177,37 | 100 · R$ 22.847,80 | 68 · R$ 4.329,57 |
| Loandra Teixeira Costa | 119 · R$ 25.227,73 | 63 · R$ 21.508,09 | 56 · R$ 3.719,64 |
| Cristiano Rodolfo Dionísio De Oliveira | 83 · R$ 18.216,51 | 44 · R$ 11.328,93 | 39 · R$ 6.887,58 |
| Beatriz Carvalho Costa | 6 · R$ 0,00 | 0 · R$ 0,00 | 6 · R$ 0,00 |

**Os rótulos de cidade NÃO entram por `vendas_instaladas`, e é por isso que o recorte é por pessoa e
não por status.** Os status de cidade (3880 a 3897) somam R$ 41,9 mil em julho e nenhum deles é o
3084 que a métrica seleciona — a receita de loja que chega ao Executivo vem das PESSOAS de loja na
subárvore dele vendendo com status Executada, que é exatamente a coluna "Resto" da tabela acima.

**O discriminador que o cliente usa é a "condição de estado" com o nome da loja no deal, e é
exatamente o campo que a Larissa está corrigindo.** Isso tem duas consequências práticas: qualquer
classificação PAP-versus-loja feita antes da correção dela separa por um campo sabidamente errado, e
o mapeamento desse termo do cliente para uma coluna do `Deal` ainda não foi feito — precisa ser
levantado antes de virar filtro em qualquer script.

**A regra é do cliente e já foi dada; onde ela vive na base é a subárvore dos líderes da 63125.** A
conferência é separar a subárvore de cada Executivo entre a população PAP e o resto, somar
`vendas_instaladas` dos dois lados, e mostrar os dois números ao Patrick — é ele quem diz se o lado
PAP corresponde ao que o cargo deve carregar.

**A régua dos Executivos tem CINCO variáveis que pagam, distribuídas em três incentivos**, e é essa
lista que define o que falta para o cargo fechar:

| Incentivo | Regra | Fórmula | Estado |
|---|---|---|---|
| 93846 | 263610 | `atingimento_lideres * 400` | alimentada |
| 93846 | 263612 | `lojas_atingimento * 200` | alimentada |
| 93848 | 263617 | `IF(hc >= 1, 1000, 0)` | alimentada |
| 93846 | 263611 | `atingimento_consultor_lider * 200` | SEM VALOR |
| 93846 | 263613 | `quantidade_parceiro_acima_mil * 100` | SEM VALOR |
| 94277 | 265434 / 265435 | receita sobre `faturamento_parceiro`, portão em `vendas_instaladas + movel` | operador invertido na 265434; zero em julho porque ninguém passa de 100% |

## A subárvore que a agregação lê é a de HOJE, não a da competência

**`HierarchyScope` não tem janela de período** (`hierarchy_scope.rb:5-12`): o `WITH RECURSIVE` navega
`seats.parent_id` no estado atual da tabela. É o oposto de `Plan#subordinate_ids_by`
(`plan.rb:214-225`), que filtra `SeatHistory` pela janela da competência. Como
`AggregatedIndicator#result` resolve o `UserScope` (`aggregated_indicator.rb:93`), o agregado de um
plano override é função da hierarquia no instante do processamento.

Isso não é teórico, e o caso concreto desta competência é grande o bastante para mudar pagamento.
**Quatro seats foram repontados para debaixo do Cristiano — dois em 24/08 (18h36 e 18h37) e dois em
25/08 (17h14 e 17h15) — e cada um arrastou o galho inteiro abaixo de si: 20, 14, 9 e 7 descendentes,
que com os próprios quatro somam 54 pessoas.** A subárvore do Luiz Felipe caiu de 211 para 157 e a do
Cristiano subiu para 83; como o Cristiano fica abaixo do Joel e o Luiz Felipe abaixo do Joao Luis, o
mesmo evento aparece nos Gerentes como receita trocando de lado.

**Nenhuma dessas quatro escritas passou por `SeatAction`** — a tabela está vazia para a empresa 2077
na janela, assim como `SeatActionDocument`, então alguém escreveu `seats.parent_id` direto. É o
caminho que a Larissa usa para corrigir à mão o que a integração não traz, e é também por isso que
não há autor registrado.

**A consequência é retroativa e é EXPLICADA ao cliente, nunca questionada**: a hierarquia foi
remontada em agosto, `HierarchyScope` não tem janela de período, e o resultado é que a receita de
JULHO dessas 54 pessoas conta para o Cristiano e deixa de contar para o Luiz Felipe. Nos Gerentes isso
não paga nada (ambos seguem abaixo do piso de 80%); nos Executivos o Luiz Felipe estava acima de 100%
da meta, então ele muda de faixa. Hierarquia é entrada do cliente e nada na base distingue
remanejamento de engano, então o cálculo reflete o que está lá e o recado diz o que mudou e por quê
(§ A divisão de trabalho).

**Uma escrita direta em `seats.parent_id` não deixa rastro de autoria, então a única forma de datá-la
é `seats.updated_at`.** Ao agrupar por dia, converter o fuso explicitamente —
`DATE(updated_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')`. O banco guarda UTC
(`application.rb:65`) enquanto a aplicação apresenta em Brasília (`application.rb:64`), então um
`DATE(updated_at)` cru joga toda escrita após as 21h no dia seguinte.

**A consequência operacional é que qualquer classificação de espelho e qualquer projeção de agregado
valem para o instante em que foram tiradas.** Reprocessar uma competência override entrega o número
da árvore daquele momento, então a conferência só fecha quando classificação, reprocessamento e
verificação acontecem próximos — e a verificação tem que reler a base, nunca comparar contra uma
projeção guardada.

## Gerentes Comerciais — julho/2026

Plano 78940, grupo 40314, `override: false`, compensação 63128. Dois participantes, ambos da lista
da Andresa: Joel Geraldo Junior (`4sk_12` / `1922319`, subárvore de 206) e Joao Luis Carnelos
(`4sk_537` / `1922316`, subárvore de 328). Como o plano não sobe nada sozinho, o conjunto de origem
é a subárvore inteira — a mesma forma do Coordenador, não a dos Executivos.

Este plano consome **três** variáveis com métrica, uma a mais que os outros dois cargos:
`vendas_instaladas` 36311, `movel` 36600 e `indicacao` 36819. A lista sai sempre de
`plan.variables.with_metrics`, nunca de uma lista fixa herdada do cargo anterior.

**Os Gerentes têm 870 espelhos ativos somando R$ 88.485,83** — Joel R$ 43.899,24 em 422 espelhos e
Joao Luis R$ 44.586,59 em 448. As três variáveis com métrica selecionam alguma coisa no Joel e só
`vendas_instaladas` no Joao Luis, o que é dado do mês e não configuração.

**Os espelhos dos Executivos caem inteiros dentro destas duas subárvores e não incharam os Gerentes**,
que é o filtro `external: true` fazendo o trabalho dele. O conjunto dos Executivos passou de 193 para
703 espelhos na mesma rodada e os Gerentes se moveram só pela deriva de deals — Joel +109,99 e Joao
Luis −1.569,88. Sem o filtro, esses R$ 72,6 mil apareceriam uma segunda vez aqui.

**Este é o cargo onde o filtro `external: true` deixa de ser precaução.** Os Gerentes estão acima dos
Executivos, cujos espelhos caem dentro destas subárvores; sem o filtro, essa receita seria espelhada
uma segunda vez e paga em dobro. O pré-flight imprime o valor excluído por gerente justamente para
que isso seja verificado, e não presumido — e o valor muda toda vez que o conjunto de espelhos dos
Executivos muda, então ele é lido na hora, nunca comparado contra um número guardado.

**Os dois fecham julho em zero** (§ Pendências): Joel a 45,34% da meta e Joao Luis a 54,85%, ambos
abaixo do piso de 80% da primeira faixa da régua.

## O que cada pessoa deve fechar após o reprocessamento

Estes são os valores a conferir na validação (`05-validacao.rb`), todos em `vendas_instaladas`.
Divergir deles significa que algo mudou entre o espelhamento e o reprocessamento — deals corrigidos,
grupificação alterada, ou espelho desativado — e a causa precisa ser entendida antes de aceitar o
resultado.

**A referência é sempre o `total_after` da última reconciliação, nunca um número guardado neste
documento.** O `10-reconciliacao.rb` imprime o total por alvo depois de aplicar o delta, e é esse
total que a validação tem de reproduzir; a tabela abaixo é o valor da última rodada e serve para
dimensionar uma diferença, não para conferi-la. Variação de centavos é arredondamento; variação de
milhares é venda que entrou ou saiu, ou pessoa que trocou de equipe.

| Cargo | Pessoa | Espelhos | Valor esperado |
|---|---|---|---|
| Coordenador | Alex Lima Lofeu | 304 · R$ 33.038,00 | **R$ 33.038,00** |
| Gerentes | Joel Geraldo Junior | 422 · R$ 43.899,24 | **R$ 43.899,24** |
| Gerentes | Joao Luis Carnelos | 448 · R$ 44.586,59 | **R$ 44.586,59** |
| Executivos | Flavia Dutra Castanheira De Oliveira | 222 · R$ 22.847,80 | **R$ 22.847,80** |
| Executivos | Loandra Teixeira Costa | 193 · R$ 21.508,09 | **R$ 21.508,09** |
| Executivos | Luiz Felipe Sonego Bonini | 170 · R$ 16.578,32 | **R$ 16.578,32** |
| Executivos | Cristiano Rodolfo Dionísio De Oliveira | 118 · R$ 11.723,93 | **R$ 11.723,93** |
| Executivos | Beatriz Carvalho Costa | 0 · R$ 0,00 | **R$ 0,00** |

**Nos três cargos o esperado é o total dos espelhos**, porque os três planos são `override: false`:
nada sobe sozinho da equipe e nenhum alvo tem venda própria na métrica. É o que torna a conferência
direta — o `05-validacao.rb` recalcula o indicator próprio a partir dos deals, encontra `subtree@0,00`
porque a varredura não roda, e o esperado tem de reproduzir o `total_after` da reconciliação.

**O valor de um Executivo é a soma de DUAS parcelas com recortes diferentes**, e conferir só uma delas
produz divergência falsa: `vendas_instaladas` vem da população PAP, enquanto `movel` e
`faturamento_parceiro` vêm da subárvore inteira. É por isso que o total do Luiz Felipe passa do recorte
PAP em R$ 989,93 e o do Cristiano em R$ 395,00.

Os valores das duas variáveis de contagem dos Executivos são independentes disso e estão em
§ Atingimento de lojas e líderes.

## Atingimento de lojas e líderes — julho/2026

Os Executivos de Vendas são pagos também por **contagem**: quantas lojas e quantos líderes de PAP
bateram 100% da própria meta abaixo deles. O espelhamento não alcança essas duas variáveis, porque um
espelho é um deal e só uma métrica soma deal — `lojas_atingimento` 36927 e `atingimento_lideres` 36928
não têm métrica nenhuma. O valor delas entra como `Indicator` externo, um por Executivo.

**Uma "loja" é uma VARIÁVEL nomeada pela cidade, não um grupo.** `taquaritinga`, `monte_alto`,
`cerquilho` e as outras dezesseis são `IndicatorVariable` com métrica `quantity`, e a meta de cada uma
é uma `UserGoal` pendurada no responsável. Não existe uma única `GroupGoal` nesta empresa — procurar
loja em `Group` não devolve nada. O realizado sai da compensação 63124 (plano 78944).

**A população de líderes é a compensação 63125** (plano 78938, Líderes PAP), e a comparação é meta
contra realizado em `vendas_instaladas`. Dos 28 participantes, 16 têm meta em julho; os 12 sem meta
contam como não-bateram, porque sem meta não há atingimento.

**A atribuição inclui o próprio Executivo, e ignorar isso zera casos reais.** Várias lojas carregam a
meta no Executivo em vez de num líder dedicado — `aguai` na Flavia, `cerquilho` e `rio_das_pedras` no
Cristiano, `santa_adelia` e `pindorama` no Luiz Felipe. Uma subárvore que exclui o próprio nó perde
todas elas.

**Toda meta existe duas vezes, e a janela que termina em 30/07 é errônea.** A boa cobre o mês inteiro
e está presa ao plano que a apura; a de 30/07 não tem plano. São 102 registros para 53 metas reais, e
contar sem esse corte dobra toda loja e todo líder com aparência de estar certo.

**O indicator é datado do dia 1.** `compiled_at_day` (`indicator.rb:124-133`) exige `day == 1` numa
variável mensal, e as duas são mensais.

| Executivo | `lojas_atingimento` | `atingimento_lideres` |
|---|---|---|
| Luiz Felipe Sonego Bonini | 3 | 1 |
| Flavia Dutra Castanheira De Oliveira | 2 | 1 |
| Loandra Teixeira Costa | 0 | 2 |
| Cristiano Rodolfo Dionísio De Oliveira | 3 | 0 |
| Beatriz Carvalho Costa | 0 | 0 |

**A contagem de loja se move sem que nenhuma venda do Executivo mude**, porque ela depende de duas
entradas que são de outra gente: a hierarquia, que decide qual loja cai sob qual Executivo, e o
realizado de cada loja na compensação 63124, que decide se ela bateu a própria meta. É por isso que
ela precisa da passada do `11` a cada rodada, e é onde a correção das deals de Loja aparece — em
nenhum outro ponto da rotina.

**Os 10 indicators EXISTEM na base do `shared-001`**, criados com `CREATED@10` e `FAILED@0`. Uma
sessão que chegar aqui NÃO roda a mutação de novo: o índice único
`index_modifiers_uniqueness` (`company_id`, `compiled_at`, `user_id`, `variable_id`) recusaria, e o
portão `already_exists` acusa antes.

**O rollback é `destroy`, não `disable`, e a janela dele fecha no reprocessamento.** `modifiers` não
tem coluna `disabled_at`, então não há desativação a fazer — e `destroyable?` (`indicator.rb:97-105`)
passa a devolver `false` assim que existirem `indicator_aggregations`, que nascem do processamento.
Antes de reprocessar, destruir é limpo; depois, o caminho é atualizar o `value`.

**A régua existe para as seis variáveis sem métrica — nenhuma delas é decorativa.** As regras vivem em
três incentives do plano, todas `IndicatorRule`:

| Incentive | Regra | Fórmula |
|---|---|---|
| 93846 | 263610 | `atingimento_lideres * 400` |
| 93846 | 263611 | `atingimento_consultor_lider * 200` |
| 93846 | 263612 | `lojas_atingimento * 200` |
| 93846 | 263613 | `quantidade_parceiro_acima_mil * 100` |
| 93848 | 263617 | `IF(hc >= 1, 1000, 0)` |
| 94277 | 265434 | `IF((vendas_instaladas + movel) / vendas_instaladas_goal >= PERCENT(80) AND (vendas_instaladas + movel) / vendas_instaladas_goal > PERCENT(100), (faturamento_parceiro) * PERCENT(3) - desconto_retroativo, 0)` |
| 94277 | 265435 | `IF((vendas_instaladas + movel) / vendas_instaladas_goal >= PERCENT(100), (faturamento_parceiro) * PERCENT(5) - desconto_retroativo, 0)` |

**Uma fórmula alcança a META pelo sufixo `_goal`.** `vendas_instaladas_goal` não é variável do plano —
é o valor da `Goal` daquela variável, resolvido pelo identificador. A régua de receita já compara
realizado contra meta sozinha, sem nada precisar ser gravado para isso.

**O que a contagem gravada paga**, aplicando 263612 e 263610:

| Executivo | lojas × 200 | líderes × 400 | Total |
|---|---|---|---|
| Luiz Felipe Sonego Bonini | 600,00 | 400,00 | **1.000,00** |
| Flavia Dutra Castanheira De Oliveira | 400,00 | 400,00 | **800,00** |
| Loandra Teixeira Costa | 0,00 | 800,00 | **800,00** |
| Cristiano Rodolfo Dionísio De Oliveira | 600,00 | 0,00 | **600,00** |
| Beatriz Carvalho Costa | 0,00 | 0,00 | **0,00** |

**O `hc` de um Executivo é uma CONTAGEM sobre os líderes abaixo dele, não a soma dos `hc_<cidade>` da
subárvore** (§ A errata dos Executivos). As variáveis `hc_<cidade>` carregam o headcount realizado de
cada loja e são alimentadas por indicator externo, uma por líder — 16 delas gravadas em julho —, e é
contra a meta de cada uma que os líderes são avaliados; o que sobe para o Executivo é o resultado
dessa avaliação, e a régua `IF(hc >= 1, 1000, 0)` paga R$ 1.000 quando a contagem chega a 1.

**Em julho os cinco `hc` estão zerados, e esse é o valor certo da competência.** O `11-contagens.rb`
não grava essa variável, porque a definição que ele carrega é a soma e uma execução em
`dry_run = false` devolveria os valores errados por cima da correção.

**Cinco lojas com meta de venda não têm `hc_<cidade>` gravado** — `monte_alto`, `cerquilho`,
`laranjal_paulista`, `santa_adelia` e `santa_rita_do_passa_quatro`. Três delas carregam a meta num
Executivo em vez de num líder dedicado, o que é consistente com não haver headcount de líder para
registrar; qualquer definição de `hc` precisa dizer o que fazer com um líder sem headcount gravado.

**`desconto_retroativo` zerado é o estado CORRETO** — ele entra subtraindo nas fórmulas de receita, e
zero significa nenhum desconto a aplicar. Não é lacuna.

**`atingimento_consultor_lider` e `quantidade_parceiro_acima_mil` seguem sem população definida.** Têm
régua (200 e 100 por unidade) e não têm nenhuma meta sobre elas na base, então nem o denominador dá
para inferir — dependem da Andresa.

## Pendências

**A queda de móvel é reclassificação de rótulo, não venda perdida, e é NEUTRA em dinheiro para o
Coordenador.** O volume da empresa subiu de 1957 para 1993 deals entre junho e julho; o que encolheu
foram os rótulos específicos — cidades de 376 para 313, Móvel de 16 para 1, Venda Individual de 7
para 2, Indicação de 2 para 0 — enquanto "Executada" subiu de 1139 para 1265. As variações fecham
com o crescimento total.

Isso não custa nada ao Coordenador porque as seis regras dele somam as duas variáveis antes de usá-las,
nos dois lugares: `IF((vendas_instaladas + movel) / vendas_instaladas_goal >= PERCENT(100) AND ... ,
(vendas_instaladas + movel) * 0.02 - desconto_retroativo, 0)`. Como `vendas_instaladas` seleciona o
status 3084 (Executada) e `movel` o 3846 (Móvel), uma venda que troca de rótulo sai de uma parcela e
entra na outra, e a soma não se move — nem o atingimento, nem a base de pagamento.

**As deals com condição de estado divergente estão sendo corrigidas pela Larissa, e é essa correção
que move mais de duas mil transações de julho.** O Patrick ainda precisa confirmar se a régua de
julho é a mesma para os três cargos.

A verificação só roda depois que a compensação de julho for cortada e reprocessada: o valor
agregado materializa numa `UserCommission`, que não existe antes disso.

**As três compensações — 63126, 63127, 63128 — dependem só do reprocessamento pelo Patrick**, que é
ação do engenheiro. O valor exibido enquanto isso é o do processamento anterior e não serve para
conferir nada: o espelhamento entrega o dado, nunca o número.

**O que conta como receita do cargo é decisão da Andresa e não trava nada**
(§ A receita que entra no atingimento dos Executivos está em aberto). Ela muda o conjunto de
espelhos, não só o valor calculado sobre ele — se ela decidir, a reconciliação seguinte absorve.

**`atingimento_consultor_lider` (36929) segue sem valor em julho.** Paga R$ 200 por unidade, foi
alimentada à mão em junho para quatro Executivos, e não tem nenhuma meta na base sobre ela, então nem
o denominador é derivável. `quantidade_parceiro_acima_mil` (36940) está no mesmo estado de origem — o
valor vem do Patrick, não de cálculo (§ A errata dos Executivos).

**Beatriz Carvalho Costa** (`4sk_481` / `1918853`) participa da compensação dos Executivos sem
constar da lista da Andresa. Não recebeu espelho — não há venda abaixo dela fora do que o plano já
entrega — então nada trava por causa disso. O Patrick foi avisado e vai confirmar com a Andresa se
ela é Executiva ou está no grupo por engano.

**A régua do Cristiano fechar acima da equipe atual também já foi antecipada ao Patrick**, com a
explicação de que o cálculo conta quem esteve na equipe durante julho. A resposta ao cliente está
pronta caso a Andresa questione.

**As três variáveis de receita se distinguem SÓ pelo status, sem cliente nem produto** —
`vendas_instaladas` (métrica 4819) pelo 3084 Executada, `movel` (4907) pelo 3846 Móvel, `indicacao`
(4940) pelo 3811 Indicação, todas com `installment >= 1`. É essa separação por rótulo único que faz a
reclassificação mover valor de uma variável para outra, e é por isso que a neutralidade depende de a
régua somar as duas — o que vale para o Coordenador e para os Executivos, mas precisa ser conferido
em qualquer cargo cuja fórmula trate as variáveis separadamente.

**12 dos 28 líderes de PAP não têm meta em julho** — Adysson, Maria Vitoria, Liliana, Matheus, Paula,
Thayna, Diego Soares, Tanillys, Amanda, Pamela, Francisco e Desiree participam da compensação 63125
sem nenhuma `UserGoal` em `vendas_instaladas`. Sem meta não há atingimento, então a contagem os trata
como não-bateram: correto se eles realmente não têm meta, subestimado se a meta deveria ter sido
carregada. É o único fator que muda os valores de `atingimento_lideres` desta competência.

**A régua de receita dos Executivos vive no incentivo 94277 do plano 79175 e carrega o mesmo operador
invertido que a do 78939 carregava** (§ A errata dos Executivos). Ela não paga nada em julho porque
nenhum Executivo passa de 100% da meta, e o Patrick decidiu não alterar o plano nesta competência.

**As três regras dos Gerentes comparam PISO e TETO com expressões diferentes, e as faixas se
sobrepõem.** O piso mede a soma das três variáveis de receita; o teto mede `vendas_instaladas`
sozinha:

```
IF((vendas_instaladas + movel + indicacao) / vendas_instaladas_goal >= PERCENT(80)
   AND vendas_instaladas / vendas_instaladas_goal < PERCENT(91), 1000, 0)
IF((vendas_instaladas + movel + indicacao) / vendas_instaladas_goal >= PERCENT(91)
   AND vendas_instaladas / vendas_instaladas_goal <= PERCENT(100), 2000, 0)
IF((vendas_instaladas + movel + indicacao) / vendas_instaladas_goal > PERCENT(100), 3000, 0)
```

Como a soma é sempre maior ou igual à parcela, um Gerente acima de 100% na soma e abaixo de 91% em
venda instalada dispara a primeira faixa e a terceira ao mesmo tempo: R$ 4.000 no lugar de R$ 3.000.
Entre 91% e 100% de venda instalada, a segunda e a terceira somam R$ 5.000.

**Em julho a sobreposição não é alcançada, e os dois Gerentes fecham em zero.** Joel Geraldo Junior
atinge 45,34% da meta (R$ 43.259,29 contra R$ 95.420,33) e Joao Luis Carnelos 54,85% (R$ 46.461,44
contra R$ 84.711,67) — ambos abaixo do piso de 80% da primeira faixa, então nenhuma regra dispara. Os
valores conferem com os 880 espelhos: 43.259,29 + 46.461,44 = 89.720,73. A correção da sobreposição é
alteração de plano que só muda dinheiro em competências futuras.

**A migração das 54 pessoas aproximou os dois sem chegar perto do piso**, e é por isso que ela não
custou nada aqui: o Joel subiu de 32,87% e o Joao Luis caiu de 71,13%, e nenhum dos dois cruzou os
80%. Num fechamento em que um deles estivesse na faixa, o mesmo movimento teria mudado pagamento.

**A reclassificação de rótulo NÃO é neutra para os Gerentes**, justamente porque o teto lê
`vendas_instaladas` isolada. Uma venda que migra de Móvel para Executada aumenta essa parcela e pode
empurrá-la acima do teto de uma faixa, desligando um pagamento de R$ 1.000 ou R$ 2.000 sem que a
receita total tenha mudado.

**Que as duas faixas disparam juntas acima de 100% não é leitura da condição, é aritmética verificada
na quarta casa decimal — sob o plano ANTIGO, onde o efeito era mensurável.** Num processamento do
78939 em que três Executivos passaram de 100% da meta, o `money` gravado para cada um foi exatamente
`(vendas_instaladas + movel) × 8%` — 4.352,3064 sobre 54.403,83; 3.796,4352 sobre 47.455,44;
3.326,9040 sobre 41.586,30. Com só uma faixa disparando o fator seria 5%.

**A aritmética não transfere para o plano 79175, porque lá a base de pagamento é
`faturamento_parceiro`** (§ A errata dos Executivos). O que o cálculo acima prova é a SOBREPOSIÇÃO das
faixas, que sobreviveu à errata; o valor em dinheiro dela agora depende de outra variável, e é por
isso que o defeito custa zero em julho.

Corrigir a condição é alteração de plano, não de dado, e o valor muda para todo mundo que passar de
100% em qualquer competência.

**A mutação que gera espelho precisa excluir quem tem linha de `Indicator` na variável, não um nível
de hierarquia** (§ Executivos de Vendas). O filtro por `Plan#subordinate_ids_by` deixa passar todo
descendente com indicator próprio que esteja abaixo do primeiro nível, e cada um deles vira receita
contada duas vezes.

**A migração de vinte pessoas entre subárvores durante a apuração não tem causa identificada, e a
trilha de auditoria da plataforma está descartada.** `SeatAction` registra `change_manager` com o
executor e o documento de origem (`seat_action.rb:10-24`), e a empresa 2077 não tem **nenhum**
registro nessa tabela nos últimos sete dias, em nenhum estado. Então o que mexeu na hierarquia
escreveu `seats.parent_id` direto, sem passar pelo documento de ação — o que aponta para a API do
integrador. `seats.updated_at` data essa escrita e é por onde a investigação continua, se alguém
julgar que vale.

Existe uma segunda leitura que não foi descartada: `carriers` é a interseção entre a subárvore e quem
tem indicator, então o número também se move se o conjunto de indicators mudar. Três dos cinco
Executivos ficaram idênticos entre as duas leituras e só dois trocaram exatamente vinte, o que aponta
para movimento de árvore — apontar não é provar.

Nada disso bloqueia a entrega: o `10-reconciliacao.rb` reconstrói o conjunto contra a árvore de agora
a cada execução, então nenhum espelho é dobrado por construção. O que a instabilidade impõe é a ordem
de operação — reconciliação, reprocessamento e verificação próximos no tempo (§ A subárvore que a
agregação lê é a de HOJE).

**O defeito é exclusivo dos Executivos.** `AggregatedIndicator#result` só percorre a subárvore quando
`user_commission.override?`, que delega para `commission.plan.override?`
(`user_commission.rb:102-109`); com `override: false` ele lê apenas o indicator da própria pessoa
(`aggregated_indicator.rb:99`). Coordenador (plano 78941) e Gerentes (plano 78940) são `override:
false`, então os espelhos deles não têm caminho para dobrar — e é exatamente por isso que a exclusão
de carriers é gateada pelo `override` no `10-reconciliacao.rb`: aplicá-la aqui apagaria receita que
não tem outro caminho para subir.

**A régua que converte contagem em dinheiro vive no `Incentive`, não no `Plan`.** A cadeia é
`Plan` → `incentivations` → `Incentive` → `rules`, e uma `FormulaRule` referencia variáveis pela
`key` (`Formula#referenced_identifiers`). Um indicator gravado numa variável que nenhuma regra
referencia não paga nada, então a existência da régua é o que fecha a entrega da contagem.
