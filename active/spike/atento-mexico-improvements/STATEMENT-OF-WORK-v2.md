# Proposta de Melhorias — Atento México

**Data:** 27 de fevereiro de 2026

---

## Resumo

Após análise detalhada das 17 solicitações de melhoria e reunião de alinhamento realizada em 26 de fevereiro de 2026, apresentamos o plano de ação proposto.

As solicitações foram organizadas em quatro frentes:

- **Ajustes e entregas sem custo** — correções imediatas e funcionalidades disponíveis via configuração
- **7 melhorias da plataforma** — priorizadas no roadmap a pedido da Atento México
- **2 desenvolvimentos customizados** — exclusivos para Atento México
- **1 sessão de treinamento** — capacitação sobre funcionalidades existentes

Adicionalmente, 4 solicitações foram avaliadas e já estão cobertas por funcionalidades existentes na plataforma.

---

## 1. Ajustes e Entregas Sem Custo

### 1.1 — Correções Imediatas

Ajustes pontuais já incorporados ao próximo sprint de desenvolvimento.

**Data de cadastro no Usos Mensais** — A tela de detalhamento passará a exibir a data de registro de cada colaborador na plataforma.

**Resumo do plano no resultado Parcial** — A tela de resultado parcial passará a exibir os dados gerais do plano associado (nome, tipo, calendário, grupo, status).

**Permissões de relatórios de compensações** — As permissões para geração automática de relatórios serão habilitadas para todos os administradores Atento México.

**Correção da página de relatórios em lote** — O problema de carregamento da página de relatórios em lote de compensações será corrigido.

| Item | Horas |
|------|-------|
| Data de cadastro no Usos Mensais | 3h |
| Resumo do plano no resultado Parcial | 4h |
| Permissões de relatórios de compensações | 1h |
| Correção da página de relatórios em lote | 3h |
| **Total — Correções Imediatas** | **10h** |

**Prazo:** Próximo sprint
**Custo adicional:** Nenhum

---

## 2. Melhorias da Plataforma

Funcionalidades da plataforma que serão desenvolvidas a pedido da Atento México.

A ordem de entrega considera o valor entregue ao cliente e as dependências técnicas entre os itens.

### 2.1 — Controle de Acessos e Histórico de Login — 70h

**Problema:** A Atento México precisa auditar os acessos dos colaboradores à plataforma — quem acessou, quando, quantas vezes, e se houve tentativas de acesso sem sucesso. Colaboradores ocasionalmente alegam não ter visto uma declaração; a empresa precisa de evidências para confrontar essas situações.

**Solução:** Registro automático de todos os acessos à plataforma, independentemente do método de autenticação utilizado (login direto ou single sign-on). Cada acesso registra: colaborador, data e hora, endereço IP, método de autenticação, provedor de identidade (quando aplicável), e se o acesso foi bem-sucedido ou não.

Os dados ficam disponíveis para consulta diretamente na plataforma por 90 dias, com filtros por período, colaborador, método de autenticação e resultado. Após 90 dias, os registros são arquivados automaticamente em armazenamento de longo prazo, ficando disponíveis sob solicitação.

### 2.2 — Atualização de colaboradores via upload — 25h

**Problema:** A importação de colaboradores hoje só permite criação de novos registros. Quando um colaborador já existe, o upload rejeita a linha. Para corrigir dados de ~20 colaboradores por quinzena (erros de digitação, mudanças de status), é necessário editar um por um.

**Solução:** O upload de colaboradores passará a identificar registros existentes e atualizar seus dados automaticamente, mantendo o comportamento de criação para colaboradores novos.

### 2.3 — Exportação do Histórico do Colaborador — 35h

**Problema:** O Histórico do Colaborador exibe dados paginados, tornando impraticável consultar centenas de registros para auditorias, transferências ou promoções.

**Solução:** Nova exportação para Excel com todas as informações consolidadas: pagamentos, indicadores, transações, grupos, hierarquia, metas e extratos.

### 2.4 — Informações adicionais nas listagens de Parciais e Compensações — 50h

**Problema:** As listagens de parciais e compensações mostram apenas informações básicas (ID, Plano, Período, Status). Para validar os valores de cada plano, é necessário abrir cada item individualmente — com 130 planos, isso consome tempo significativo.

**Solução:** Adição de três informações em ambas as listagens: nome do grupo, quantidade de colaboradores e valor total gerado. Os valores respeitam a hierarquia de acesso (administrador vê o total, gestor vê apenas sua equipe).

### 2.5 — Importação de Grupos em massa — 40h

**Problema:** A criação de grupos é feita um a um pela interface. Com ~130 novos grupos por mês, o processo manual é inviável.

**Solução:** Nova importação de grupos via arquivo, permitindo criação e atualização em massa. Grupos existentes serão identificados e atualizados; novos grupos serão criados automaticamente.

### 2.6 — Importação de Planos em massa — 160h

**Problema:** A criação de 130 planos por mês é feita manualmente, selecionando calendário, grupo, incentivos e tipos de pagamento um a um para cada plano.

**Solução:** Nova importação de planos via arquivo. O arquivo permite definir todos os parâmetros do plano (calendário, grupo, incentivos, tipos de pagamento, aprovadores). Validação completa antes da criação — se qualquer linha tiver erro, o arquivo inteiro é rejeitado com mensagem detalhada indicando o erro e a linha.

Esta funcionalidade exige uma etapa de preparação da plataforma: os incentivos existentes precisam receber um identificador externo para serem referenciados no arquivo de importação. Essa preparação inclui migração dos registros existentes e testes extensivos para garantir que nenhum cálculo em andamento seja afetado.

**Dependência:** A importação de grupos (item 2.5) deve ser entregue primeiro, pois os planos referenciam grupos que precisam existir na plataforma.

### 2.7 — Regras de Validação para Indicadores — 120h

**Problema:** Dados incorretos em indicadores (ex: qualidade acima de 100%, valores negativos) só são detectados tardiamente — quando a compensação já foi calculada ou, pior, quando a carta de compensação já foi enviada ao colaborador. Corrigir nesse ponto é custoso e arriscado.

**Solução:** Regras de validação configuráveis por variável de incentivo. Os dados são validados no momento da entrada no sistema, impedindo que valores inválidos se propaguem para cálculos e pagamentos. A validação acontece na entrada, não na saída — o sistema previne o problema ao invés de permitir que ele chegue até o pagamento.

As regras possuem ciclo de vida próprio (ativação e desativação) com histórico completo para auditoria.

Inclui um período inicial de prova de conceito para validar a abordagem técnica e definir o nível de complexidade das regras que o sistema poderá suportar.

| Item | Horas |
|------|-------|
| Controle de Acessos e Histórico de Login | 70h |
| Atualização de colaboradores via upload | 25h |
| Exportação do Histórico do Colaborador | 35h |
| Informações adicionais nas listagens | 50h |
| Importação de Grupos em massa | 40h |
| Importação de Planos em massa | 160h |
| Regras de Validação para Indicadores | 120h |
| **Total — Melhorias da Plataforma** | **500h** |

---

## 3. Customização

### 3.1 — Criptografia dos campos extras do colaborador — 80h

Os campos extras do colaborador armazenam dados associados a cada usuário (chave-valor), alimentados via upload. Hoje esses campos não possuem criptografia — o que impede o armazenamento de dados sensíveis como o salário mensal (protegido pela LFPDPPP).

Esta entrega implementa criptografia em repouso nos campos extras, permitindo que a Atento México envie dados sensíveis com segurança. O trabalho inclui: criptografia das colunas de valor em 2 tabelas, migração de todos os dados existentes em todos os ambientes da plataforma, e ajustes nos processos internos que manipulam esses dados.

### 3.2 — Relatório consolidado por calendário (Sábana) — 160h

**Problema:** A Atento México mantém manualmente uma planilha Excel ("TBL General") consolidando todos os indicadores operacionais e resultados de cálculo de bônus dos 130 planos (~120 colunas). Esta planilha é utilizada para controle financeiro e auditoria junto ao Banco de México.

**Solução:** Duas entregas:

Novo relatório que consolida todos os planos em uma única tabela — uma linha por colaborador, com colunas para dados do colaborador, campos extras (incluindo salário), indicadores e resultados de cálculo por tipo de pagamento. Disponível em qualquer momento do processo (não apenas após o pagamento final), com indicação de status de aprovação do pagamento.

**Condições:**

- Recomendamos que as Regras de Validação (item 2.7) sejam entregues antes deste relatório, garantindo a qualidade dos dados exportados

#### Mapeamento de colunas — o que o relatório vai conter

Após análise da planilha atual da Atento México e da reunião de alinhamento de 26 de fevereiro, realizamos o mapeamento preliminar das colunas. As ~120 colunas da TBL General se dividem em três categorias:

**Categoria A — Dados que o 4Shark já possui e o relatório entregará automaticamente:**

| Coluna | Origem no 4Shark |
|--------|--------------------|
| Mes | Calendário / Período |
| Id Coordinador | Hierarquia organizacional |
| Nombre Coordinador | Hierarquia organizacional |
| Id Supervisor | Hierarquia organizacional |
| Nombre Supervisor | Hierarquia organizacional |
| Id Agente | Identificador único do colaborador |
| Nombre Agente | Cadastro do colaborador |
| Servicio Especifico | Nome do grupo |
| Puntos Bono | Resultado do cálculo (pontos) |
| Porcentaje Bono | Resultado do cálculo (indicador agregado) |
| Bono Politica (tope) | Resultado do limitador |
| Monto Final | Valor monetário final da compensação |
| Comisión | Valores monetários por tipo de pagamento |
| Indicadores operacionais (Calidad, Adherencia, Hold, Casos, Resolución, Captura, Cumplimiento, etc.) | Indicadores agregados — desde que alimentados como variáveis na plataforma |
| Status de pagamento | "Pago aprobado" / "No pago aprobado" |

O relatório incluirá os identificadores únicos de cada colaborador (ID, external_id, documento único), permitindo cruzamento com dados de outros sistemas via PROCV.

**Categoria B — Dados que a Atento México pode incluir via campos extras do colaborador:**

A plataforma permite associar campos extras (chave-valor) a cada colaborador. Estes campos podem ser alimentados via upload e serão incluídos no relatório.

| Coluna | Como alimentar |
|--------|----------------|
| Centro | Campo extra do colaborador — alimentar via upload com o código do centro de custo |
| Login/AC | Campo extra do colaborador — alimentar via upload com o ID do sistema telefônico |
| Fecha de Ingreso | Campo extra do colaborador — alimentar via upload com a data de admissão na empresa |
| Sueldo Mensual | Campo extra do colaborador (criptografado) — alimentar via upload com o salário mensal |

Estas colunas dependem da Atento México manter os dados atualizados na plataforma. A funcionalidade de campos extras já existe — não há desenvolvimento adicional para Centro, Login/AC e Fecha de Ingreso. O armazenamento seguro do salário mensal é viabilizado pela entrega 3.1 (criptografia dos campos extras).

**Categoria C — Dados que ficam fora do relatório:**

| Coluna | Motivo |
|--------|--------|
| Observaciones | Campo de texto livre de grande extensão, incompatível com campos extras do colaborador (limitados a valores curtos). **Recomendação:** complementar via PROCV no Excel após a exportação, utilizando o identificador único do colaborador como chave de cruzamento. |
| Aclaraciones | Idem Observaciones. |

#### Resumo

A grande maioria das ~120 colunas da TBL General corresponde a indicadores operacionais que já são alimentados na plataforma. O relatório consolidará automaticamente todos esses dados — incluindo o salário mensal, que poderá ser armazenado de forma segura como campo extra criptografado. As duas colunas que ficam de fora (observações e aclarações) podem ser complementadas via PROCV no Excel — o relatório incluirá todos os identificadores únicos do colaborador para facilitar esse cruzamento.

Caso a Atento México identifique colunas adicionais que não se enquadrem nas categorias acima, o escopo e a estimativa serão revisados em conjunto.

| Item | Horas |
|------|-------|
| 3.1 — Criptografia dos campos extras do colaborador | 80h |
| 3.2 — Relatório Consolidado (Sábana) | 160h |
| **Total — Customização** | **240h** |

---

## 4. Funcionalidades Existentes

As solicitações abaixo foram avaliadas e já estão cobertas por funcionalidades existentes na plataforma:

| Solicitação | Situação |
|-------------|----------|
| Criação de parciais em lote e remoção do bloqueio de 24h | O sistema gera parciais automaticamente todas as noites com dados atualizados. Para fechamento e validação final, o fluxo de compensações em lote já atende essa necessidade. |
| Geração automática de relatórios para parciais | Parciais são instrumentos de monitoramento via dashboard. Relatórios completos estão disponíveis no fluxo de compensações. |
| Criação seletiva de compensações e remoção do bloqueio de 24h | O processamento em lote já opera de forma inteligente: cria novas compensações, reprocessa pendentes e preserva aprovadas. O intervalo de 24h existe para garantir a estabilidade do processamento. |
| Ordenação de calendários por ID | A ordenação alfabética é o padrão da plataforma para todos os clientes. Alterá-la impactaria a experiência de uso dos demais clientes. |

---

## 5. Treinamento

Duas solicitações de treinamento serão atendidas em uma sessão única:

- **Identificações** — Sistema de múltiplos identificadores por colaborador e sua relevância para integração com folha de pagamento
- **Módulos da plataforma** — Relatórios de rendimento, Produtos, Clientes, Incentivos transacionais, Classificações, Campanhas, Transações, Transações colaborativas, Métricas, Configurações de classificações, Estados e Razões de reconhecimento

A sessão incluirá demonstração da funcionalidade de reset de senha em massa.

**Custo adicional:** Nenhum
**Próximo passo:** Confirmar data e participantes

---

## Cronograma

| Fase | Escopo | Início |
|------|--------|--------|
| **Fase 1** | Correções imediatas (seção 1.1) | Próximo sprint |
| **Fase 2** | 7 melhorias da plataforma (500h) | Após aprovação |
| **Fase 3** | Relatório consolidado + criptografia (240h) | Após aprovação |
| **Treinamento** | 1 sessão | Agendar independentemente |

A Fase 2 será entregue na ordem apresentada na seção 2, respeitando as dependências técnicas entre os itens.

---


## Próximos Passos

1. **Aprovar o escopo das melhorias da plataforma** (Fase 2) para iniciarmos a reorganização do roadmap
2. **Validar o mapeamento de colunas do relatório consolidado** (Fase 3) — o mapeamento preliminar está descrito na seção 3 deste documento. Caso a Atento México identifique colunas adicionais não contempladas, o escopo será revisado em conjunto
3. **Confirmar data e participantes** para a sessão de treinamento
4. As correções imediatas (Fase 1) serão entregues independentemente no próximo sprint
