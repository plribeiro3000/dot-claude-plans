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

## Por que a plataforma não resolve sozinha

O roll-up hierárquico existe e é o `override` do plano. `AggregatedIndicator#result`
(`app/models/aggregated_indicator.rb:91-100`) resolve os subordinados por `UserScope` e soma os
indicadores deles quando `user_commission.override?` é verdadeiro.

**O override sobe um nível apenas.** Para o Coordenador isso alcança a líder imediata, mas não a
equipe dela — que é onde o faturamento está. Ligar a flag no plano do Coordenador entregaria os
indicadores próprios da líder, não o agregado. Por isso a correção não é configuração.

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

## Os scripts

Nesta pasta, na ordem de execução: `plan_anchor.rb` (descobre plano, período e variáveis a partir
do usuário), `preflight.rb` (projeta e valida, sem mutar), `mutation.rb` (cria os espelhos),
`verification.rb` (lê o que a plataforma calculou).

Todos escrevem CSV no bucket do próprio ambiente, em
`integration-debug/audits/2077/<fase>/<timestamp>.csv`, via
`Aws.connection.put_object(ApplicationConfiguration.aws_bucket, file_path, csv_string)` — o mesmo
formato das rake tasks `integration_audit:*`.

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

`modifiers.value` e `aggregated_modifiers.value` são `string` (`db/schema.rb:1120`, `:84`). Somar
com `SUM()` no Postgres levanta `PG::UndefinedFunction`. A conversão é `variable.format(value)` e a
redução acontece em Ruby, como em `AggregatedIndicator#calculate!`.

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
| `quantidade_lojas_atingimento` | 36927 | não |
| `quantidade_parceiros_acima_mil` | 36940 | não |

Grupos: `TERRA_Coordenador` 40315, `TERRA_Gerente_Regional` 40314, `TERRA_Lider_PAP` 50216,
`Terra_Gerente_Loja` 50212, `TERRA_VendedorII_PAP` 50370.

O id 40315 aparece aqui como `TERRA_Coordenador` e, na tabela de julho abaixo, como grupo do plano
dos Executivos de Vendas — enquanto o plano do Coordenador em julho sai do grupo 50210. Os dois
não podem estar certos ao mesmo tempo. Para o Coordenador isso não trava nada, porque a âncora de
julho foi resolvida pelo plano e conferida no `plan_anchor.rb`; para os outros dois cargos, resolver
essa contradição é parte do passo de descoberta e vem antes de qualquer pré-flight.

Pessoas confirmadas: Alex Lima Lofeu `User.id` 1119697 (identificador 1918117), Roberta Dos Santos
Cardoso Da Silva `User.id` 1119878.

## A âncora é o plano, nunca a compensação

O período sai de `plan.calendar` — `Plan belongs_to :calendar` com `has_many :periods, through:
:calendar` (`plan.rb:8,35`). Uma competência existe assim que o calendário do plano a define; a
compensação é cortada depois e pode não existir ainda. Procurar o período em `Commission` faz uma
competência viva parecer inexistente.

Do usuário chega-se ao plano por dois caminhos, ambos reais: as `PlanStatement` dele e as
`Groupification` → grupos → planos.

## Âncoras de julho/2026

Calendário 19604, período **528210** (01/07 a 31/07).

| Cargo | Plano | Grupo | Override | Variáveis com métrica |
|---|---|---|---|---|
| Coordenador de Call Center | 78941 | 50210 | não | `vendas_instaladas` 36311, `movel` 36600 |
| Líder de Call Center | 78943 | 50213 | sim | `vendas_instaladas` 36311, `movel` 36600 |
| Executivos de Vendas | 78939 | 40315 | sim | `vendas_instaladas` 36311, `movel` 36600 |

Todos são `SalesPlan` com `deal_type` `Sale`, portanto a redução da métrica é
`sold_price * quantity`.

O plano do Coordenador **não** consome `indicacao` (36819) — a lista de variáveis a espelhar sai de
`plan.variables.with_metrics`, nunca de uma lista fixa.

Métricas: `vendas_instaladas` → 4819; `movel` → 4907, que filtra apenas por `status_id` 3846 e
`installment >= 1`, sem cliente nem produto.

## O portão: a coluna existe no código, não no banco do shared-001

A coluna `external` está mergeada em `develop` (PR https://github.com/4shark/app/pull/5334) e o
`schema.rb` já a declara. **Ela não existe no banco do `app-shared-001`**: uma migration só toca o
banco de um ambiente quando aquele ambiente é deployado, numa task efêmera que roda antes do
código novo entrar. Rodar `mutation.rb` antes disso falha na primeira gravação, com coluna
inexistente.

O deploy do `shared-001` espera uma migração de RDS em curso, que impede deployar qualquer coisa
que altere estrutura. Enquanto essa janela não fechar, nada de julho pode ser executado — nem o
pré-flight, cujo valor é ser conferido imediatamente antes da mutação.

Quando a janela fechar, o deploy é ação do engenheiro: ambiente produtivo passa antes pelo
`sidekiq-queue-check.sh`, que libera só com a fila limpa, e o gatilho é
`gh workflow run deploy-shared-001.yaml -R 4shark/app`.

## Execução

1. **Deploy do `shared-001`** — leva a coluna `external` ao banco do ambiente. Bloqueado pela
   migração de RDS; é o portão de tudo que vem depois.
2. **Descoberta de julho** — resolver, para o período de julho/2026, o plano de cada cargo pela
   `Groupification` → grupos → planos, se é `override`, e o período pelo `plan.calendar`. Sem isso
   nada mais tem âncora. Já feito para o Coordenador; falta para os outros dois cargos.
3. **Pré-flight por cargo** — resolver a subárvore, aplicar o filtro do adapter, e projetar o total
   que o cargo terá após o espelho. A projeção é conferida contra o agregado que a plataforma já
   calcula para a liderança imediata; divergência significa filtro errado, não dado errado.
4. **Mutação por cargo** — um deal espelhado por deal original, registro a registro, erro por
   registro logado e laço seguindo.
5. **Verificação** — reprocessar a compensação e ler o `AggregatedIndicator` do cargo.
6. **Relatório consolidado** — planilha em `~/Downloads/` com contagens por cargo e pendências.

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

## Pendências

A queda de 16 para 1 nos deals com `status_id` 3846 precisa de resposta do Patrick — ou móvel
parou de vender em julho, ou a integração parou de classificar deal com esse status. No segundo
caso o coordenador fecha o mês faltando valor sem nada acusar.

O Patrick precisa confirmar se a régua de julho é a mesma para os três cargos, e se as deals com
condição de estado divergente — que ele levantou com a Larissa e a Laura — já foram corrigidas na
competência de julho.

A verificação só roda depois que a compensação de julho for cortada e reprocessada: o valor
agregado materializa numa `UserCommission`, que não existe antes disso.

Executivos de Vendas (plano 78939) e Gerentes Comerciais seguem a mesma mecânica com outro alvo e
outra subárvore.
