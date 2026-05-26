# Plano de Melhorias — Atento México (v2)

**Data:** 24 de março de 2026
**De:** 4Shark
**Para:** Atento México

**Alterações em relação à v1 (11 de março de 2026):**
- O item "Controle de Acessos" deixou de ser uma configuração de infraestrutura condicionada ao SSO e passou a ser um desenvolvimento da plataforma, cobrindo todos os tipos de login (direto e SSO). Adicionado como primeiro item da Etapa 2.

---

Após análise das 17 solicitações levantadas e reunião de alinhamento realizada em 26 de fevereiro, apresentamos o plano de ação acordado. As melhorias foram organizadas em três etapas com modelos distintos de entrega e investimento.

---

**Nossa recomendação de como avançar:**

Iniciamos mediante aprovação com as correções da Etapa 1, sem nenhum custo. Em seguida, a Atento México escolhe qual melhoria da Etapa 2 quer priorizar primeiro. Para cada item escolhido, o pagamento das horas correspondentes é realizado antes do início da implementação. Após a entrega, a Atento México decide o próximo item e o ciclo se repete.

Dessa forma, não há um compromisso financeiro grande de uma só vez — cada aprovação é pontual, proporcional ao item escolhido, e a entrega acontece antes de qualquer novo investimento.

---

## Etapa 1 — Correções Imediatas

As seguintes correções serão entregues no próximo sprint de desenvolvimento, sem custo para a Atento México.

- **Data de cadastro no Usos Mensuales** — A tela de detalhamento passará a exibir a data de registro de cada colaborador na plataforma.
- **Resumo do plano no resultado Parcial** — A tela de resultado parcial passará a exibir os dados gerais do plano associado (nome, tipo, calendário, grupo, status).
- **Permissões de relatórios de compensações** — A geração automática de relatórios será habilitada para todos os administradores Atento México.
- **Correção da página de relatórios em lote** — O problema de carregamento da página de relatórios em lote de compensações será corrigido.

**Custo:** Nenhum
**Prazo:** Próximo sprint

---

## Etapa 2 — Melhorias da Plataforma

Estas funcionalidades fazem parte da evolução planejada da plataforma ForShark e beneficiarão todos os clientes. A Atento México solicita a antecipação desses itens no roadmap — o que exige reorganização da fila de desenvolvimento atual.

O modelo de entrega é sequencial e sob demanda: a Atento México prioriza o primeiro item, aprova o investimento correspondente, a 4Shark entrega, e então avança para o próximo. Não é necessário aprovar tudo de uma vez.

### 2.1 — Controle de Acessos e Histórico de Login — 70h

**Problema:** A Atento México precisa auditar os acessos dos colaboradores à plataforma — quem acessou, quando, quantas vezes, e se houve tentativas de acesso sem sucesso. Colaboradores ocasionalmente alegam não ter visto uma declaração; a empresa precisa de evidências para confrontar essas situações.

**Solução:** Registro automático de todos os acessos à plataforma, independentemente do método de autenticação utilizado (login direto ou single sign-on). Cada acesso registra: colaborador, data e hora, endereço IP, método de autenticação, provedor de identidade (quando aplicável), e se o acesso foi bem-sucedido ou não.

Os dados ficam disponíveis para consulta diretamente na plataforma por 90 dias, com filtros por período, colaborador, método de autenticação e resultado. Após 90 dias, os registros são arquivados automaticamente em armazenamento de longo prazo, ficando disponíveis sob solicitação.

| Item | Horas |
|------|-------|
| Controle de Acessos e Histórico de Login | 70h |
| Atualização de colaboradores via upload | 25h |
| Exportação do Histórico do Colaborador | 35h |
| Informações adicionais nas listagens de Parciais e Compensações | 50h |
| Importação de Grupos em massa | 40h |
| Importação de Planos em massa | 160h |
| Regras de Validação para Indicadores | 120h |
| **Total** | **500h** |

A ordem apresentada reflete as dependências técnicas entre os itens (ex: a importação de planos requer que grupos já existam na plataforma). A sequência pode ser ajustada em conjunto caso a Atento México queira priorizar itens de maior valor imediato.

---

## Etapa 3 — Desenvolvimento Customizado

Este item é um desenvolvimento exclusivo para a Atento México — não será disponibilizado para outros clientes da plataforma.

### Relatório Consolidado por Calendário (Sábana)

Novo relatório que substitui a planilha TBL General mantida manualmente hoje. Consolida todos os planos em uma única tabela: uma linha por colaborador, com dados cadastrais, campos extras, indicadores operacionais e resultados de cálculo por tipo de pagamento. Disponível em qualquer momento do processo, com indicação do status de aprovação de cada pagamento.

As ~120 colunas da TBL General foram mapeadas na reunião de alinhamento:
- **Dados que o ForShark entrega automaticamente:** hierarquia organizacional, indicadores operacionais, resultados de cálculo, status de pagamento.
- **Dados que a Atento México alimenta via campos extras:** centro de custo, login/AC, data de admissão, salário mensal.
- **Fora do relatório:** campos de observações e aclarações (texto livre longo). Recomendamos complementar via PROCV no Excel, usando o identificador único do colaborador como chave — o relatório incluirá todos os identificadores para facilitar esse cruzamento.

Caso a Atento México identifique colunas não contempladas no mapeamento atual, o escopo será revisado em conjunto antes de iniciar o desenvolvimento.

**Nota:** Recomendamos que as Regras de Validação (último item da Etapa 2) sejam entregues antes deste relatório, garantindo a qualidade dos dados exportados. A ordem pode ser ajustada conforme prioridade da Atento México.

| | Horas |
|-|-------|
| Relatório Consolidado (Sábana) | 160h |

---

## Treinamento

Duas solicitações de treinamento serão atendidas em uma sessão única, sem custo adicional:

- **Sistema de identificadores** — múltiplos identificadores por colaborador e sua relevância para integração com folha de pagamento
- **Módulos da plataforma** — cobertura dos módulos ainda não utilizados pela equipe Atento México

A sessão incluirá demonstração de reset de senha em massa.

**Próximo passo:** Confirmar data e lista de participantes.

---

## Fora do Escopo

As solicitações abaixo foram analisadas e não serão implementadas:

| Solicitação | Situação |
|-------------|----------|
| Criação de parciais em lote e remoção do bloqueio de 24h | O sistema já gera parciais automaticamente todas as noites. Para fechamento e validação, o fluxo de compensações em lote já atende essa necessidade. |
| Geração automática de relatórios para parciais | Parciais são instrumentos de monitoramento — relatórios completos são gerados no fluxo de compensações. |
| Criação seletiva de compensações e remoção do bloqueio de 24h | O processamento em lote já opera de forma inteligente. O intervalo de 24h garante a estabilidade do processamento. |
| Ordenação de calendários por ID | A ordenação alfabética é o padrão da plataforma. Alterá-la para um cliente impactaria a experiência de todos os demais. |

---

## Resumo do Investimento

| Etapa | Horas | Custo |
|-------|-------|-------|
| Etapa 1 — Correções imediatas | 10h | Sem custo |
| Etapa 2 — Melhorias da plataforma | 500h | Por item, sob aprovação |
| Etapa 3 — Relatório Consolidado (Sábana) | 160h | Sob aprovação |
| Treinamento | — | Sem custo |
| **Total** | **670h** | |

---

## Próximos Passos

1. **Etapa 1** — as correções imediatas serão entregues no próximo sprint, independentemente de qualquer aprovação adicional.
2. **Etapa 2** — definir o primeiro item a ser priorizado. Recomendamos iniciar pelo Controle de Acessos (item 2.1). A entrega é incremental; não é necessário aprovar tudo de uma vez.
3. **Etapa 3** — validar o mapeamento de colunas do relatório Sábana antes de iniciar o desenvolvimento.
4. **Treinamento** — confirmar data e lista de participantes.
