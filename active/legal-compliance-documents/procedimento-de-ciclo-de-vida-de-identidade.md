# PROCEDIMENTO DE GESTÃO DO CICLO DE VIDA DE IDENTIDADE (JOINER-MOVER-LEAVER)

**Versão:** 1.0 — **Data de emissão:** [DD/MM/AAAA] — **Responsável:** Departamento de Tecnologia da Informação

O presente Procedimento ("Procedimento") estabelece os passos operacionais da 4Shark Soluções Financeiras Ltda. ("4SHARK") para a criação, a alteração e a revogação dos acessos de colaboradores, prestadores de serviço e parceiros ao longo de todo o vínculo com a 4SHARK — entrada (*joiner*), movimentação (*mover*) e desligamento (*leaver*). Operacionaliza a Política de Gestão de Identidade e Acesso e a Política de Senhas, detalhando como aquelas diretrizes são executadas na prática e como cada evento é registrado. Aplica-se a toda pessoa com acesso autorizado aos sistemas da 4SHARK, independentemente do tipo de vínculo (CLT, PJ, prestador ou parceiro) — o critério é o acesso, não a forma de contratação. Pessoas sem acesso aos sistemas não são objeto deste procedimento.

## 1. RESPONSABILIDADE E GARANTIA DO PROCESSO

Dado o porte da 4SHARK, o ciclo de vida de identidade é operado por uma única responsabilidade — a área de Tecnologia da Informação —, que solicita, autoriza e executa cada evento. Não há segregação de funções entre pessoas distintas, e o presente Procedimento não pressupõe tal segregação.

A garantia do processo, no lugar da aprovação por múltiplas pessoas, é técnica e repousa em dois controles compensatórios:

a) **Conta segregada (*break glass*)** — toda alteração de permissão é aplicada exclusivamente pela *break glass account*, conta administrativa de uso excepcional, distinta das contas de uso diário;\
b) **Tudo como código, auditável** — toda concessão, alteração e revogação é aplicada por meio de controle de versão (Pull Request) sobre a fonte única de identidade. O histórico de cada alteração — data, autor e conteúdo — é imutável e revisável a qualquer momento, e é essa trilha de auditoria que provê a validação do processo, em lugar da segregação de funções entre pessoas.

## 2. PERFIS DE ACESSO POR FUNÇÃO

O acesso é concedido por função, segundo o princípio do menor privilégio. Cada função recebe apenas o acesso necessário à sua atuação.

### 2.1 Sócios

Os três sócios exercem, respectivamente, as funções de engenharia, operações e comercial, detendo cada um o perfil da sua função (seções 2.2 a 2.4). O sócio responsável pela área de Tecnologia da Informação detém adicionalmente a *break glass account* e o acesso aos repositórios sensíveis (seção 2.3).

### 2.2 Operações

- Na aplicação, em ambiente **produtivo** (ambiente dedicado e ambiente compartilhado, com clientes reais): perfil **super administrador** com finalidade de **visibilidade** — visão de todas as contas de clientes, para suporte e verificação de que tudo está correto. Operações **não cadastra dados por iniciativa própria**; toda inclusão ou alteração em produção ocorre por conta e ordem do cliente, na operação assistida descrita a seguir.
- **Operação assistida** — para clientes neste modelo, o cliente envia os dados (planilhas) e aponta as alterações por e-mail, e o time de Operações executa o cadastro e a atualização de regras **dentro da conta do cliente**, por meio de contas de administrador nessa conta, **estritamente conforme a instrução escrita do cliente e após a sua aprovação**. A 4SHARK atua como executora da operação; o cliente permanece controlador dos dados e responsável por instruir cada alteração.
- **Setup/implantação de cliente** — criação da conta do cliente (*company*) e dos usuários do próprio cliente. As contas de acesso da 4SHARK criadas durante a homologação são **desativadas quando o ambiente entra em produção**; a reativação é controlada pelo próprio cliente e solicitada pontualmente quando há necessidade de suporte.
- **Ambiente de POC/demonstração** (segregado do ambiente produtivo) — criação das contas necessárias para montar e apresentar provas de conceito.
- Sem acesso a código, infraestrutura ou repositórios.

### 2.3 Engenharia

- **Acesso pleno**: código de front-end e de back-end e parte da infraestrutura (Terraform, Ansible).
- **Acesso restrito a front-end**: apenas as *stacks* de front-end.
- Os **repositórios sensíveis** (documentos de compliance e operações de apagamento de dados — LGPD *data erasure*) e a ***break glass account*** são restritos ao responsável pela área de Tecnologia da Informação. As demais contas de engenharia têm permissão mínima equivalente, e ações destrutivas ou de maior impacto passam exclusivamente pela *break glass account*.

### 2.4 Comercial

A 4SHARK não mantém força de vendas interna: a prospecção é terceirizada a parceiros de geração de leads (modelo *finder fee*), que utilizam suas próprias ferramentas, realizam o agendamento da reunião inicial e **não possuem acesso a nenhum sistema da 4SHARK** — estando, portanto, fora do escopo deste procedimento e regidos por seus contratos e termos de confidencialidade. A condução subsequente (provas de conceito e demonstrações) ocorre internamente, em ambiente de demonstração segregado, com acesso de menor privilégio e **sem perfil de super administrador**.

Acessos fora do perfil padrão de cada função são concedidos pontualmente e revistos na recertificação periódica (seção 8).

## 3. INVENTÁRIO DE SISTEMAS — TRÊS LOCI DE GOVERNANÇA DE ACESSO

**Princípio de seleção.** Ao adotar uma nova ferramenta, a 4SHARK avalia o suporte a *single sign-on* (SSO) e prioriza as soluções que o oferecem — o SSO é um dos critérios que pesam a favor da escolha, junto com a adequação da ferramenta à necessidade. Havendo SSO viável, a autenticação se dá pelo SSO corporativo (Google Workspace); na sua ausência, por usuário e senha geridos no gerenciador corporativo de senhas (1Password).

Independentemente da forma de login, todo acesso é **governado** em um de três loci. O locus define **como o acesso é revogado, onde está a lista viva de quem tem acesso e onde está a trilha de auditoria**:

- **Camada A — Identidade federada (Google Workspace).** Acesso concedido pela federação no IdP corporativo. **Revogação:** suspender a conta no Google Workspace, que derruba simultaneamente todos os sistemas federados. **Lista viva:** catálogo de aplicações do Google Admin (atualizado automaticamente a cada integração, não mantido manualmente neste documento). **Auditoria:** logs do Google Admin.
- **Camada B — Gerido como código (IaC / Pull Request).** A autorização é um objeto versionado — por exemplo, identidade e permissões IAM na AWS, *membership* de organização e equipes no GitHub, *membership* de projeto no MongoDB Atlas. **Revogação:** Pull Request aplicado pela *break glass account*. **Lista viva:** o próprio código. **Auditoria:** histórico de Pull Requests. *Um mesmo sistema pode estar em A e B: na AWS, o login federa no Google (Camada A), mas a autorização IAM é um grant em código que a suspensão do Google não apaga e exige remoção própria (Camada B).*
- **Camada C — Gerido no 1Password (sem SSO).** Soluções sem SSO viável, conforme o princípio de seleção. A credencial vive no cofre e o acesso equivale à participação nele. **Revogação:** remover a pessoa do cofre, **rotacionar a credencial compartilhada** e transferir a titularidade (*ownership*) de billing e administração. **Lista viva:** estrutura de cofres do 1Password. **Auditoria:** histórico de participação nos cofres.

**Fonte da verdade do catálogo de sistemas.** A lista autoritativa e sempre atualizada dos sistemas de que a 4SHARK depende é o **Inventário de Fornecedores** (`records/inventario-de-fornecedores.md`, no repositório de compliance). Em cada evento do ciclo de vida — entrada, movimentação e desligamento —, o executor consulta esse inventário diretamente e percorre todos os sistemas nele listados, sem depender de uma enumeração paralela mantida neste Procedimento — que ficaria desatualizada a cada sistema adicionado ou removido. O quadro abaixo não é essa enumeração: mapeia, a título ilustrativo, como cada tipo de sistema se enquadra nas três camadas de governança e como é revogado.

Mapeamento por camada (ilustrativo; `[CONFIRMAR]` onde o locus de governança depende de confirmação):

| Sistema | Camada | Revogação no desligamento |
|---|---|---|
| Google Workspace | — (IdP — raiz da Camada A) | Suspender a conta — derruba a Camada A |
| AWS (console + IaC) | A + B | Suspender Google (login) + remover IAM por PR/break-glass |
| GitHub | B | Remover de organização/equipes por PR |
| MongoDB Atlas | A + B | Suspender Google (login federado) + remover do projeto por IaC |
| Redis Cloud | C | Remover do 1Password + rotacionar credencial |
| Cloudflare | [CONFIRMAR] | Remover usuário da conta |
| Pritunl (VPN) | [CONFIRMAR] | Remover o perfil de VPN |
| Keycloak (admin — auth-001) | [CONFIRMAR] | Rotacionar a credencial de admin (AWS Secrets Manager) |
| 1Password | — (cofre — raiz da Camada C) | Remover do cofre |
| Netlify | [CONFIRMAR] | [CONFIRMAR] |
| Datadog | [CONFIRMAR: A?] | Suspender Google |
| New Relic | [CONFIRMAR] | Suspender Google |
| Rollbar | [CONFIRMAR] | Suspender Google |
| Slack | [CONFIRMAR: A?] | Suspender Google |
| Zendesk (suporte ao cliente) | [CONFIRMAR: A?] | Suspender Google (se federado) ou remover o usuário |
| Google Analytics (GA4) | A | Suspender Google |
| Stripe (cobrança de clientes) | C | Remover do 1Password + transferir titularidade de billing |
| Pontomais (ponto eletrônico) | C | Remover do 1Password + rotacionar credencial |
| [demais sistemas — lista do engenheiro] | | |

## 4. ENTRADA (JOINER)

**Gatilho:** contratação ou início de contrato confirmado.

1. A área de Tecnologia da Informação registra a entrada, informando função e data de início, e define o perfil de acesso padrão da função (seção 2) e eventuais acessos adicionais.
2. A identidade é criada na fonte única de identidade e o acesso é aplicado por Pull Request sob a *break glass account*.
3. A identidade é habilitada no SSO corporativo (Google Workspace), com MFA obrigatório, cobrindo a Camada A.
4. Para os sistemas das Camadas B e C do perfil, o acesso é concedido individualmente (B) ou provisionado via 1Password com credencial dedicada/compartilhada (C).
5. O evento é registrado conforme a seção 7.

## 5. MOVIMENTAÇÃO (MOVER)

**Gatilho:** mudança de função, área ou escopo de responsabilidade.

1. A área de Tecnologia da Informação registra a movimentação, informando a função de origem e a de destino, e define o novo perfil de acesso.
2. Aplica, **na mesma operação**, a concessão dos novos acessos e a **remoção dos acessos da função anterior** que não pertencem à nova função. A revogação do acesso antigo não pode ser adiada — o acúmulo de acessos entre funções é vedado.
3. O evento é registrado conforme a seção 7.

## 6. DESLIGAMENTO (LEAVER)

**Gatilho:** desligamento ou encerramento de contrato.

**Prazo (SLA):** a revogação é iniciada e concluída [CONFIRMAR — sugestão: no mesmo dia útil do desligamento].

1. **Suspender a conta no Google Workspace** — revoga, de uma só vez, todo o acesso da Camada A e encerra as sessões ativas associadas à identidade federada.
2. **Revogar os sistemas da Camada B** — remoção da fonte única de identidade por Pull Request aplicado pela *break glass account*, o que revoga AWS, GitHub, MongoDB Atlas e demais sistemas críticos geridos como código; remoção direta do usuário nos que não são geridos por código.
3. **Revogar os sistemas da Camada C** — remover a pessoa dos cofres do 1Password, **rotacionar as credenciais compartilhadas** a que ela tinha acesso e transferir a titularidade (billing, administração, automações) que a simples remoção do usuário não retira.
4. **Encerrar sessões remanescentes** e revogar tokens/chaves de acesso pessoais eventualmente emitidos.
5. **Recolher o hardware** corporativo (notebook) e demais ativos.
6. O evento é registrado conforme a seção 7.

## 7. REGISTRO E EVIDÊNCIA

Cada evento do ciclo de vida é registrado de forma a permitir auditoria posterior. O registro aproveita as trilhas que a 4SHARK já mantém:

- Para os acessos geridos como código (infraestrutura e fonte única de identidade), o **histórico de Pull Requests** é a trilha de auditoria — com data, autor, revisor e a alteração aplicada.
- Para a Camada C, a **participação nos cofres do 1Password** é o registro de quem tem acesso a quê, e a sua remoção é a evidência da revogação.
- Para cada evento (entrada, movimentação, desligamento), mantém-se um registro com data, identidade, tipo de evento, sistemas afetados e responsáveis pela aprovação e execução.

## 8. REVISÃO PERIÓDICA DE ACESSO

Os acessos são revistos periodicamente, em cadência [CONFIRMAR — sugestão: semestral], confrontando o acesso concedido a cada identidade com a sua função atual e com o princípio do menor privilégio. Acessos sem justificativa são revogados. A revisão é registrada conforme a seção 7.

## 9. VIGÊNCIA E REVISÃO

Este Procedimento entra em vigor na data de sua publicação e permanece vigente por prazo indeterminado, podendo ser revisado periodicamente ou sempre que houver mudança significativa no ambiente de tecnologia, no quadro de sistemas ou no escopo de atuação da 4SHARK.

## TERMO DE CIÊNCIA E COMPROMISSO

Declaro, para os devidos fins, que recebi, li e compreendi integralmente o presente Procedimento de Gestão do Ciclo de Vida de Identidade da 4SHARK, comprometendo-me a cumpri-lo em todas as suas disposições.

\
Nome completo: _______________________________________________

Cargo: _____________________________  CPF: __________________

Local e data: ____________________, ______ / ______ / __________

Assinatura: ___________________________________________________

\
**Aprovação**

Aprovado por: _________________________________________________

Departamento de Tecnologia da Informação — 4SHARK
