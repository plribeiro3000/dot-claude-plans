# Sincronização diária de transações espelhadas

Replicar, todo dia, as transações da subárvore de um gestor para o próprio gestor, mantendo o
espelho alinhado com a origem ao longo do mês.

## Por que a demanda existe

O roll-up hierárquico da plataforma é o `override` do plano, e ele sobe **um nível apenas**
(`app/models/aggregated_indicator.rb:91-100`). Um cargo que precisa do faturamento de toda a
estrutura abaixo — não só da liderança imediata — não é alcançado por ele.

O contorno é espelhar transação: para cada deal de cada pessoa da subárvore, criar um deal
equivalente no gestor, que então entra na métrica como se fosse dele. Isso resolve a competência,
mas só enquanto alguém roda o script; a origem continua se movendo depois.

O cliente que motivou a demanda é a CommCenter (company 2077), nos cargos Coordenador de Call
Center, Executivos de Vendas e Gerentes Comerciais. A execução pontual e os scripts que a fazem
estão em `../commcenter-premiacao-cargos/`.

## A decisão que precede o trabalho

Duas saídas, e elas não são complementares.

**Override multinível no produto.** Resolve os três cargos sem duplicar nenhum dado, e vale para
qualquer cliente com a mesma estrutura. É mudança de produto, com o custo e o prazo que isso
carrega.

**Espelho diário como rotina.** Entrega agora, com o código que já existe, e não depende de
roadmap. Em troca cria uma sombra permanente na base de deals.

A segunda tem um efeito colateral que precisa ser aceito conscientemente: **um deal espelhado é
indistinguível de um deal real para todo o resto da plataforma.** Ele entra em qualquer contagem,
soma ou relatório que consulte a tabela de deals sem filtrar por plano. Numa competência isso são
centenas de registros; como rotina diária, replicada por cargo e acumulada mês a mês, cresce sem
que ninguém acompanhe.

A coluna `external` torna os espelhos filtráveis, e é o que tem de defesa. Mas filtrar depende de
cada consumidor saber que precisa, e hoje nenhum sabe.

## O que a rotina precisa fazer

Quatro operações, todas derivadas da comparação entre a origem e o espelho:

1. **Original novo sem espelho** → criar o espelho.
2. **Original desativado com espelho ativo** → desativar o espelho.
3. **Original com valor diferente** → atualizar o espelho.
4. **Original com estado diferente** → atualizar o espelho.

## A chave de reconciliação

Um espelho se identifica pela coluna `external` de `Deal`, gravada como `false` — o mesmo molde da
homônima em `Indicator`, adicionada em https://github.com/4shark/app/pull/5334. Listar o lado
esquerdo da comparação é `where(external: false)`, um filtro sobre coluna real em vez de casamento
de string.

Qual original cada espelho copia sai do `external_id`, que é `<external_id original>_<User.id do
destinatário>`: remove-se o sufixo e chega-se ao original. Essa metade é textual, e é a limitação
conhecida da chave — uma coluna de referência ao deal original seria mais forte, e é migração.
Decisão a tomar se a rotina virar permanente.

## Onde a rotina deve viver

Um script de console não serve para execução diária. Pelo `DATA-PROCESSING.md`, a forma é um
worker: `Processor` se a reconciliação de um cargo for uma unidade indivisível, `Producer`/`Consumer`
se valer paralelizar por cargo ou por usuário da subárvore.

Vale checar antes se a plataforma já tem alguma rotina de reconciliação de deals que possa
hospedar isso, em vez de nascer isolada.

## Pendências

A decisão entre override multinível e espelho permanente é do produto, e é o que destrava ou
encerra esta demanda.

Se for espelho permanente, decidir também se o vínculo espelho→original continua textual ou vira
coluna, e o que fazer com os consumidores da tabela de deals que hoje contam os espelhos sem
saber.
