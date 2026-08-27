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

| Frente | Estado |
|---|---|
| Espelhos do Coordenador | 304 ativos, R$ 33.038,00 — reconciliados contra os deals de 26/08 |
| Espelhos dos Gerentes | 880 ativos, R$ 89.720,73 — reconciliados contra os deals de 26/08 |
| Espelhos dos Executivos | 192 ativos, R$ 18.573,51 — reconciliados contra os deals de 26/08 |
| Atingimento de lojas e líderes | 10 indicators — recalculados contra a base de 26/08, 1 corrigido |
| Headcount (`hc`) | 5 indicators — recalculados contra a base de 26/08, 2 corrigidos |
| `atingimento_consultor_lider` | sem valor — depende da Andresa |
| `quantidade_parceiro_acima_mil` | sem valor — depende da Andresa |
| Régua 264347 | defeito confirmado — correção é decisão da Andresa |
| Receita dos Executivos somando loja | levantado pela Andresa, não verificado na base (§ Executivos de Vendas) |
| Migração de 54 pessoas para o Cristiano | aplicada na reconciliação — é entrada do cliente, comunicada e não questionada (§ A divisão de trabalho) |
| Reprocessamento 63126 / 63127 / 63128 | os três liberados — depende só do Patrick |

**O Coordenador (63126) e os Gerentes (63128) estão prontos para reprocessar.** Uma reconciliação
envelhece: um espelho é cópia congelada e nada o mantém sincronizado, então se a Larissa mexer nas
vendas de novo entre agora e o reprocessamento, ele volta a divergir. Rodar `10-reconciliacao.rb` em
`dry_run` imediatamente antes do reprocessamento custa uma colagem e responde isso.

**Os Executivos (63127) também estão liberados, e fecham incompletos por dado que o cliente não
mandou.** `atingimento_consultor_lider` e `quantidade_parceiro_acima_mil` seguem vazias porque só a
Andresa tem esses números, e a régua 264347 paga 3% + 5% acima de 100% por um defeito de condição
(§ Executivos de Vendas). Nada disso é motivo para segurar o processamento: o resultado sai com o que
existe, o que falta é apontado, e a régua é corrigida na competência que o cliente decidir
(§ A divisão de trabalho).

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

A `description` recebe texto legível (`mirror of deal <id> from user <id>`) como contexto para
quem lê o registro, **nunca** como chave de busca — é campo livre que qualquer um pode escrever.

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

Estes são os pontos que a Andresa levantou no fechamento, e **nenhum deles é query nossa** — cada um
espera um dado dela ou uma ação do Patrick. Ela mandou os detalhes por e-mail. **A lista existe para
ser REPORTADA, não para ser esperada**: a apuração roda contra a base como ela está a qualquer
momento, e o que o cliente mudar depois entra na reconciliação seguinte, que é barata justamente por
isso (§ A divisão de trabalho).

| # | O que está errado | O que destrava | Responsável |
|---|---|---|---|
| 1 | Quatro vendedores do bônus de R$ 300 subiram, mas não constam na compensação | Andresa indica os grupos; Patrick recria o plano, amarra as metas e gera compensação nova, desativando a atual | Andresa → Patrick |
| 2 | Dois gerentes de loja com hierarquia errada | A base de origem precisa ser corrigida — a integração não traz essa correção, então a Larissa faz na mão | Andresa/Larissa |
| 3 | Meta de HC errada numa líder PAP, que por isso não recebe o bônus de R$ 1.000 | Andresa manda a meta e o realizado corretos; Patrick ajusta a meta e refaz o plano de Líder PAP | Andresa → Patrick |
| 4 | Receita do Líder de Call Center e do Coordenador não batem entre si (≈28k contra ≈35k) sendo que as mesmas receitas entram nos dois | Patrick confere se alguma transação foi enviada direta ao Coordenador; se foi, desativa | Patrick |
| 5 | Compensação dos Executivos muito acima do controle da Andresa | Decisão dela sobre o que é receita do cargo (§ Executivos de Vendas) e sobre a régua 264347 | Andresa |

**O item 2 é o de efeito mais amplo e o menos visível.** Hierarquia muda quem está na subárvore de
quem, e a subárvore é a entrada de tudo: dos espelhos, das contagens de loja e líder, e do `hc`. Uma
correção de hierarquia que chegue depois de uma apuração desloca todos esses números de uma vez — o
que a rodada seguinte absorve, e o relatório nomeia.

## Os scripts

Ficam em `scripts/`, numerados na ordem de execução. **Todos são colados no console via
`bin/ecs run <stack>`** — nunca executados como arquivo, porque o console roda numa task remota que
não enxerga o disco do engenheiro.

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
| `11-contagens.rb` | leitura **ou** escrita | Recalcula `lojas_atingimento`, `atingimento_lideres` e `hc` contra a base de agora, imprime cada uma ao lado do `Indicator` gravado e corrige as divergentes por `update` do `value`. Abre em `dry_run`, que só relata |

**`10-reconciliacao.rb` é o único script que muda de fase por uma variável, e isso é deliberado.**
Todo o resto da rotina separa pré-flight e mutação em arquivos distintos, mas aqui as duas metades
precisam medir o **mesmo instante**: o delta depende da hierarquia e dos deals de agora, e entre duas
colagens de console a Larissa pode ter subido mais um ajuste. Com `dry_run = true` (o padrão) ele
percorre tudo, imprime os contadores e grava o CSV sem tocar em nada; trocar para `false` aplica
exatamente o delta que acabou de ser relatado.

**Um único script serve os três cargos.** A configuração no topo é `plan_id` e `competence_period_id`
— nada mais. O conjunto de origem se ajusta sozinho: numa subárvore de plano não-override ninguém
carrega linha de `Indicator` alcançável pela varredura, então a exclusão não retira nada e sobra a
subárvore inteira. Os alvos saem dos participantes da própria compensação em vez de uma lista de nomes.

| Cargo | `plan_id` | Compensação | Override | Conjunto de origem resultante |
|---|---|---|---|---|
| Coordenador de Call Center | 78941 | 63126 | não | subárvore inteira |
| Executivos de Vendas | 78939 | 63127 | sim | subárvore menos quem carrega `Indicator` na variável |
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
| Executivos de Vendas | 78939 | 40315 | 63127 | sim | `vendas_instaladas`, `movel` |
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

Há duas sequências, e a diferença entre elas é uma pergunta só: **este cargo já tem espelhos gravados
nesta competência?** O `01-checagem.rb` responde isso alvo a alvo, e o `03-preflight.rb` confirma
pelo contador `already_exists`.

### Primeira apuração de uma competência

Por cargo, na ordem, com os scripts de `scripts/`:

1. **Descoberta** (`00`) — só quando o plano do cargo não é conhecido. Lista os planos do período e
   localiza as pessoas, imprimindo identificadores para conferência.
2. **Checagem** (`01`) — portões do ambiente e âncoras do plano, alvo a alvo. `reaches_other_target`
   e `mirrors_already_in_subtree` dizem se este cargo está acima de outro já espelhado.
3. **Pré-flight** (`03`) — projeta e conta os portões. **A mutação não roda enquanto `too_long` e
   `already_exists` não forem ambos zero.**
4. **Mutação** (`04`) — cria os espelhos, recusando gravar qualquer coisa se o portão falhar.
5. **Reprocessar a compensação** — ação do engenheiro. Sem isso o número não se move.
6. **Validação** (`05`) — compara o esperado com o que a plataforma calculou.

### Re-apuração de uma competência que já tem espelhos

São seis colagens e nenhuma espera pelo cliente (§ A divisão de trabalho). O `10` cobre os três
cargos num laço e o `11` cobre as três contagens dos Executivos, então a sequência inteira roda de
ponta a ponta numa sessão:

1. **Checagem** (`01`) — portões do ambiente e âncoras do plano. Confirma que o plano, o período e a
   compensação continuam os mesmos, e imprime o `money` atual de cada alvo.
2. **Reconciliação em modo relatório** (`10`, `dry_run = true`) — imprime `CREATE`, `UPDATE`,
   `DISABLE`, `ENABLE`, `UNCHANGED` e `FAILED` por plano, e grava um CSV por plano. **Ler o delta
   antes de aplicar é o passo que não se pula**, e as contas têm de fechar dos dois lados:
   `esperados = UNCHANGED + UPDATE + CREATE` e `existentes = UNCHANGED + UPDATE + DISABLE`. Se não
   fecharem, alguma identidade não pareou e o motivo vem antes da escrita.
3. **Reconciliação aplicando** (`10`, `dry_run = false`) — logo em seguida, sem intervalo.
4. **Contagens em modo relatório** (`11`, `dry_run = true`) — recalcula loja, líder e headcount e
   imprime cada uma ao lado do gravado, com o `raw` e o `destroyable?`.
5. **Contagens aplicando** (`11`, `dry_run = false`) — corrige por `update` só as divergentes.
6. **Validação** (`05`) — depois de o reprocessamento acontecer, compara o esperado com o que a
   plataforma calculou, relendo a base.

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

**Com `override: false` o espelho cobre a subárvore inteira** (o caso do Coordenador, plano 78941, e
dos Gerentes, plano 78940): a agregação usa `user.id` sozinho, nada sobe, e sem espelho o alvo fica
zerado. É por isso que a subárvore inteira é o conjunto de origem nesses dois cargos.

**Com `override: true` o espelho CONTINUA NECESSÁRIO** (o caso dos Executivos, plano 78939), e o
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

Plano 78939, grupo 40315, `override: true`, compensação 63127. Cinco participantes, e os quatro
nomes da lista da Andresa batem: Loandra Teixeira Costa, Cristiano Rodolfo Dionísio de Oliveira,
Flavia Dutra Castanheira de Oliveira e Luiz Felipe Sonego Bonini. A quinta é **Beatriz Carvalho
Costa** (`4sk_481` / `1918853`), que a lista não menciona — sem venda abaixo dela fora do que o
plano já entrega, então o espelhamento não a tocou e a dúvida sobre ela não bloqueia nada.

**Este cargo RECEBE espelho como os outros dois, apesar do `override: true`.** A varredura recursiva
alcança a subárvore inteira mas só enxerga quem já tem linha de `Indicator`, e a maior parte da base
não tem (§ O conjunto de origem depende do `override` do plano).

**O espelho só é legítimo quando a origem NÃO carrega linha de `Indicator` própria.** Um vendedor com
linha própria já é alcançado pela varredura recursiva, então espelhar a venda dele soma a mesma
receita duas vezes; um vendedor sem linha é invisível para a varredura, e o espelho é o único caminho.
A mutação filtrou por `Plan#subordinate_ids_by` — um nível de hierarquia — que é conjunto diferente
desse, e é o que produz fatia dobrada.

**Os Executivos têm 192 espelhos ativos somando R$ 18.573,51**, reconciliados contra os deals e a
hierarquia de 26/08. Nenhum tem origem que carregue indicator próprio: a exclusão de carriers roda
aqui por construção, porque este é o único dos três planos com `override: true`.

| Executivo | Espelhos | Valor | Subárvore | Carriers |
|---|---|---|---|---|
| Cristiano Rodolfo Dionísio De Oliveira | 92 | 8.813,42 | 83 | 35 |
| Loandra Teixeira Costa | 38 | 3.719,64 | 119 | 49 |
| Luiz Felipe Sonego Bonini | 35 | 3.280,72 | 157 | 45 |
| Flavia Dutra Castanheira De Oliveira | 27 | 2.759,73 | 168 | 64 |
| Beatriz Carvalho Costa | 0 | 0,00 | 6 | 1 |

Os CSVs de auditoria que reconstroem qualquer estado anterior deste conjunto, todos com as dezesseis
colunas necessárias para recriar cada registro:

| Conteúdo | Caminho em `s3://4shark-shared-001/` |
|---|---|
| 750 espelhos originais, apagados | `integration-debug/audits/2077/premiacao-deletion/20260824-205741.csv` |
| 750 recriados a partir do anterior | `integration-debug/audits/2077/premiacao-restore/20260824-213118.csv` |
| 534 de origem duplicada, apagados | `integration-debug/audits/2077/premiacao-duplicate-cleanup/20260824-214726.csv` |

### A receita que entra no atingimento dos Executivos está em aberto

**A Andresa sustenta que só receita de PAP compõe o atingimento do Executivo, e que hoje receita de
loja está entrando junto.** É a maior divergência do fechamento: a compensação do cargo soma
R$ 11.060 na plataforma contra R$ 3.715 no controle dela. No caso do Luiz Felipe, a meta é
R$ 27.295,00 e a receita exibida está acima disso, enquanto o controle dela registra R$ 15.768,00 de
receita PAP — e o Patrick, filtrando a planilha só por PAP, chegou a R$ 15.608,39.

**A consequência não é um ajuste fino, é a faixa inteira.** A régua de receita (264347 / 264348) só
paga a partir de 80% da meta. Com R$ 15,6 mil contra uma meta de R$ 27.295,00 o atingimento fica
perto de 57%, abaixo do piso, e nenhuma das duas regras dispara — o que sobra para o Executivo são
as contagens de loja e de líder, que são pagas por outra via.

**A leitura dela é coerente com o desenho da régua, e essa é a razão para levá-la a sério mesmo sem
verificação na base.** O cargo já é pago por loja através de uma CONTAGEM (`lojas_atingimento * 200`)
e por líder PAP através de outra (`atingimento_lideres * 400`). Se a receita de loja também entrasse
em `vendas_instaladas`, a loja seria paga duas vezes pelo mesmo desempenho — uma vez como contagem e
outra como receita. **Isso é inferência a partir da régua, não medição**: nada foi conferido contra
a base ainda.

**O espelhamento não distingue PAP de loja hoje, e não teria como distinguir sem uma regra.** O
conjunto de origem é a subárvore inteira menos os carriers (§ O conjunto de origem depende do
`override` do plano), filtrada apenas pela métrica — e as três métricas de receita se separam só por
status (`vendas_instaladas` 3084, `movel` 3846, `indicacao` 3811), sem nada que diga se a venda veio
de loja ou de PAP. Se a regra for confirmada, ela entra como um filtro a mais no conjunto de origem,
e todos os espelhos dos Executivos precisam ser reconciliados contra o conjunto novo.

**O discriminador que o cliente usa é a "condição de estado" com o nome da loja no deal, e é
exatamente o campo que a Larissa está corrigindo.** Isso tem duas consequências práticas: qualquer
classificação PAP-versus-loja feita antes da correção dela separa por um campo sabidamente errado, e
o mapeamento desse termo do cliente para uma coluna do `Deal` ainda não foi feito — precisa ser
levantado antes de virar filtro em qualquer script.

**A decisão é da Andresa e não é nossa**, porque é regra de negócio sobre o que remunera o cargo, e
não um defeito de cálculo. A verificação que a torna decidível é estreita: pegar a subárvore do Luiz
Felipe, separar a receita por origem PAP e loja depois da correção da Larissa, e comparar com os
R$ 15.608,39 que o Patrick já apurou pelo lado da planilha.

**A régua dos Executivos tem CINCO variáveis que pagam, distribuídas em três incentivos**, e é essa
lista que define o que falta para o cargo fechar:

| Incentivo | Regra | Fórmula | Estado |
|---|---|---|---|
| 93846 | 263610 | `atingimento_lideres * 400` | alimentada |
| 93846 | 263612 | `lojas_atingimento * 200` | alimentada |
| 93848 | 263617 | `IF(hc >= 1, 1000, 0)` | alimentada |
| 93846 | 263611 | `atingimento_consultor_lider * 200` | SEM VALOR |
| 93846 | 263613 | `quantidade_parceiro_acima_mil * 100` | SEM VALOR |
| 94014 | 264347 / 264348 | receita sobre `vendas_instaladas + movel` | régua com defeito |

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
da Andresa: Joel Geraldo Junior (`4sk_12` / `1922319`, subárvore de 152) e Joao Luis Carnelos
(`4sk_537` / `1922316`, subárvore de 382). Como o plano não sobe nada sozinho, o conjunto de origem
é a subárvore inteira — a mesma forma do Coordenador, não a dos Executivos.

Este plano consome **três** variáveis com métrica, uma a mais que os outros dois cargos:
`vendas_instaladas` 36311, `movel` 36600 e `indicacao` 36819. A lista sai sempre de
`plan.variables.with_metrics`, nunca de uma lista fixa herdada do cargo anterior.

**Os Gerentes têm 880 espelhos ativos somando R$ 89.720,73** — Joel R$ 43.259,29 em 416 espelhos e
Joao Luis R$ 46.461,44 em 464 —, reconciliados contra os deals e a hierarquia de 26/08. `indicacao`
seleciona zero.

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
| Gerentes | Joao Luis Carnelos | 464 · R$ 46.461,44 | **R$ 46.461,44** |
| Gerentes | Joel Geraldo Junior | 416 · R$ 43.259,29 | **R$ 43.259,29** |

Nesses dois cargos o esperado é o total dos espelhos, porque o plano é `override: false`, nada sobe
sozinho e o alvo não tem venda própria.

**Os Executivos não têm valor esperado fixo, e inventar um seria o erro.** O plano é `override: true`,
então o agregado de cada um é `soma dos indicators da subárvore + indicator próprio`, e o primeiro
termo depende da hierarquia no instante do processamento (§ A subárvore que a agregação lê é a de
HOJE). O segundo termo é o que os espelhos entregam e está na tabela da § Executivos de Vendas.

A conferência deles é o que `05-validacao.rb` faz: recalcula o indicator próprio a partir dos deals
(porque o reprocessamento reescreve essa linha), soma as linhas de `Indicator` dos demais membros da
subárvore como elas estão (porque é literalmente o que a varredura vai encontrar), e imprime o total
ao lado do que a compensação gravou. Comparar contra número guardado só produz divergência falsa
quando alguém troca de gestor no intervalo.

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
| Luiz Felipe Sonego Bonini | 4 | 1 |
| Flavia Dutra Castanheira De Oliveira | 1 | 1 |
| Loandra Teixeira Costa | 0 | 2 |
| Cristiano Rodolfo Dionísio De Oliveira | 0 | 0 |
| Beatriz Carvalho Costa | 0 | 0 |

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
| 94014 | 264347 | `IF((vendas_instaladas + movel) / vendas_instaladas_goal >= PERCENT(80) AND ... > PERCENT(100), (vendas_instaladas + movel) * PERCENT(3) - desconto_retroativo, 0)` |
| 94014 | 264348 | `IF((vendas_instaladas + movel) / vendas_instaladas_goal >= PERCENT(100), (vendas_instaladas + movel) * PERCENT(5) - desconto_retroativo, 0)` |

**Uma fórmula alcança a META pelo sufixo `_goal`.** `vendas_instaladas_goal` não é variável do plano —
é o valor da `Goal` daquela variável, resolvido pelo identificador. A régua de receita já compara
realizado contra meta sozinha, sem nada precisar ser gravado para isso.

**O que a contagem gravada paga**, aplicando 263612 e 263610:

| Executivo | lojas × 200 | líderes × 400 | Total |
|---|---|---|---|
| Luiz Felipe Sonego Bonini | 800,00 | 400,00 | **1.200,00** |
| Loandra Teixeira Costa | 0,00 | 800,00 | **800,00** |
| Flavia Dutra Castanheira De Oliveira | 200,00 | 400,00 | **600,00** |
| Cristiano Rodolfo Dionísio De Oliveira | 0,00 | 0,00 | **0,00** |
| Beatriz Carvalho Costa | 0,00 | 0,00 | **0,00** |

**O `hc` de um Executivo é a soma dos `hc_<cidade>` na subárvore dele.** As variáveis `hc_<cidade>`
existem justamente para carregar headcount e são alimentadas por indicator externo, uma por líder —
16 delas gravadas em julho. Contar nós da hierarquia seria inventar uma métrica onde já há uma
explícita, e é por isso que a soma dessas variáveis é a definição adotada.

| Executivo | Lojas com hc abaixo | `hc` | `IF(hc >= 1, 1000, 0)` |
|---|---|---|---|
| Luiz Felipe Sonego Bonini | 6 | 28 | 1.000,00 |
| Flavia Dutra Castanheira De Oliveira | 5 | 18 | 1.000,00 |
| Loandra Teixeira Costa | 4 | 16 | 1.000,00 |
| Cristiano Rodolfo Dionísio De Oliveira | 1 | 4 | 1.000,00 |
| Beatriz Carvalho Costa | 0 | 0 | 0,00 |

**Os 5 indicators de `hc` EXISTEM na base do `shared-001` e conferem** — a verificação recalculou a
soma da subárvore de cada Executivo contra o valor gravado e devolveu `matching@5@diverging@0`, com
`destroyable@true` nos cinco (nenhum `indicator_aggregation` ainda, porque a comissão não foi
reprocessada). Uma sessão que chegar aqui NÃO roda a mutação de novo: o índice único
`index_modifiers_uniqueness` recusaria, e o portão `already_exists` acusa antes.

**A escolha da definição só muda o resultado da Beatriz.** Como o limiar é 1, qualquer leitura
razoável paga os outros quatro; ela tem subárvore de 7 pessoas e nenhuma loja com headcount abaixo,
então uma definição por contagem de pessoas a pagaria e a soma de `hc_<cidade>` não. Ela é também a
participante cuja presença no plano está em aberto, o que torna esse o mesmo assunto e não dois.

**Cinco lojas com meta de venda não têm `hc_<cidade>` gravado** — `monte_alto`, `cerquilho`,
`laranjal_paulista`, `santa_adelia` e `santa_rita_do_passa_quatro`. Três delas carregam a meta num
Executivo em vez de num líder dedicado, o que é consistente com não haver headcount de líder para
registrar; o efeito é que o `hc` desses Executivos é um piso, não um total.

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

**A régua 264347 e o que conta como receita do cargo são decisões da Andresa e não travam nada**
(§ A receita que entra no atingimento dos Executivos está em aberto). A segunda muda o conjunto de
espelhos, não só o valor calculado sobre ele — se ela decidir, a reconciliação seguinte absorve.

**Duas variáveis da régua dos Executivos seguem sem valor em julho** — `atingimento_consultor_lider`
(36929) e `quantidade_parceiro_acima_mil` (36940). Ambas pagam por unidade (R$ 200 e R$ 100), foram
alimentadas manualmente em junho para quatro Executivos, e não têm nenhuma meta na base sobre elas,
então nem o denominador é derivável. Sem esses valores a premiação dos Executivos fecha incompleta
mesmo com tudo o mais correto.

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

**As duas regras de receita dos Executivos disparam juntas acima de 100% da meta, pagando 8% onde a
régua pretende 5%.** A condição da regra 264347 é `>= PERCENT(80) AND > PERCENT(100)`, que se reduz a
`> 100%` — a mesma faixa da 264348. A descrição da própria regra diz "Atingimento entre 80% e
99,99%", então o `<` virou `>`; do jeito que está, ninguém entre 80% e 100% recebe os 3%, e quem
passa de 100% recebe 3% + 5%. O incentivo que as abriga se chama "… Errata", o que sugere correção
já tentada uma vez.

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

**As duas regras disparando juntas não é leitura da condição, é aritmética verificada na quarta casa
decimal.** Num processamento em que três Executivos passaram de 100% da meta, o `money` gravado para
cada um foi exatamente `(vendas_instaladas + movel) × 8%` — 4.352,3064 sobre 54.403,83; 3.796,4352
sobre 47.455,44; 3.326,9040 sobre 41.586,30. Se só a regra 264348 tivesse disparado, o fator seria 5%.

Esses agregados vêm de um processamento com um conjunto de espelhos diferente do atual e não servem
como valor esperado (§ O que cada pessoa deve fechar após o reprocessamento) — o que eles provam é o
fator, e o fator não depende do agregado.

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
