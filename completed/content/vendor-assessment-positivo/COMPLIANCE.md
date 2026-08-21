# Playbook de TI — Respostas (Planilha)

Planilha: `Cópia de Playbook de TI.xlsx`
Seções novas (não cobertas pelo Securiti.ai): **Sistemas**, **Infraestrutura**, **Sustentação**

As seções **Ambiente do Parceiro** e **Produtos** têm as mesmas perguntas do Securiti — reaproveitar respostas do PLAN.md.

Legenda: ✅ Confirmado | ⚠️ Verificar com Paulo

---

## Ambiente do Parceiro — Requisitos de SI e Privacidade

Perguntas idênticas ao Securiti (Q2.1–Q2.36). Reaproveitar respostas do PLAN.md.

---

## Produtos — Requisitos de SI e Privacidade

Perguntas idênticas ao Securiti (Q1.x). Reaproveitar respostas do PLAN.md.

---

## Sistemas

### Gerenciamento de Requisitos e Processos

**Existe gerenciamento de requisitos de negócio do contratante?** ✅
> Sim. Os requisitos de negócio são gerenciados por meio de processo estruturado de planejamento, com documentação das necessidades antes do início do desenvolvimento. Cada feature passa por fases de entendimento do problema, modelagem e definição do escopo antes da implementação.

---

**O processo de desenvolvimento de um novo sistema, partindo da necessidade até a entrega, é documentado?** ✅
> Sim. O ciclo de desenvolvimento é inteiramente documentado: da captura de requisitos ao planejamento, implementação, testes, revisão de código, revisão de segurança e entrega. Cada etapa possui artefatos associados.

---

**Após as análises dos requisitos, é feita uma estimativa de esforço e prazo para o projeto/sprint?** ✅
> Sim. Após análise dos requisitos são realizadas estimativas de esforço por tarefa, com datas previstas definidas por sprint.

---

**Após as análises dos requisitos, é feito um cronograma com as datas e sprints para o projeto?** ✅
> Sim. O desenvolvimento é organizado em sprints com datas definidas, permitindo acompanhamento do progresso e ajustes de escopo quando necessário.

---

**Os projetos possuem requisitos gerenciados de forma a contemplar as necessidades do contratante?** ✅
> Sim. Os requisitos são documentados e priorizados com foco nas necessidades do cliente, sendo revisados ao longo do projeto conforme novas informações emergem.

---

**O processo de desenvolvimento de software é planejado, medido e controlado?** ✅
> Sim. O processo segue metodologia ágil com planejamento de sprints, acompanhamento de entregáveis, revisões de código obrigatórias e métricas de qualidade coletadas via CI/CD.

---

**Durante a fase de estimativas, existem métricas (Pontos por função, Horas-Homem, Story Points)?** ✅
> Sim. As estimativas utilizam Story Points e/ou estimativas de esforço em horas por tarefa, vinculadas ao planejamento de cada sprint.

---

**Existe análise de impacto e risco para mudanças solicitadas em sistemas/software?** ✅
> Sim. Toda mudança passa por análise de impacto antes da implementação. O processo inclui revisão de código por pares e revisão de segurança dedicada antes do merge, garantindo que riscos sejam identificados e mitigados.

---

**O processo de conflito entre componentes/objetos (CMDB) está definido e padronizado?** ✅
> Sim. Conflitos de componentes e objetos são gerenciados via controle de versão (Git/GitFlow), com resolução de conflitos padronizada no processo de merge. O histórico completo de alterações é rastreável.

---

**O processo de rollback e reação a incidentes em deploys está definido?** ✅
> Sim. O processo de rollback está definido para todos os ambientes. A infraestrutura utiliza Amazon ECS com capacidade de rollback imediato para versões anteriores dos containers, e Amazon Aurora PostgreSQL com Point-in-Time Recovery (PITR) para restauração de dados.

---

**Existe controle sobre as evidências geradas, referentes aos testes de sistemas/software?** ✅
> Sim. Todas as execuções de testes são registradas e rastreadas via pipeline de CI/CD, com logs completos de cada execução acessíveis para auditoria. Os testes automatizados (unitários e de integração) são obrigatórios para aprovação do merge.

---

**Existe ferramenta para gestão de projetos?** ✅
> Sim. A gestão de projetos é realizada via Monday.com, plataforma que centraliza toda a operação e engenharia da empresa, permitindo o acompanhamento de tarefas, sprints, prazos e progresso de cada projeto.

---

**Existem métricas para definição de prioridades, como por exemplo Valor do Negócio?** ✅
> Sim. A priorização é realizada com base na análise de valor para o produto e para a base de clientes. Por ser uma plataforma SaaS, a 4Shark prioriza demandas que agregam valor transversal — ou seja, melhorias que beneficiam o maior número de clientes simultaneamente. Cada solicitação é avaliada individualmente frente ao impacto no produto e na experiência dos usuários.

---

**Todos os processos de desenvolvimento de sistemas/software são documentados?** ✅
> Sim. O processo de desenvolvimento, desde o requisito até o deploy, é documentado. Inclui especificações de features, planos de implementação, tarefas e critérios de aceite.

---

**Existe conhecimento diversificado na equipe para sustentação e melhorias?** ✅
> Sim. A equipe possui profissionais com conhecimento em desenvolvimento backend (Ruby on Rails), frontend (Angular), infraestrutura (AWS, Ansible, Terraform), banco de dados (PostgreSQL) e segurança, garantindo capacidade de sustentação e evolução da plataforma.

---

**Existe processo de capacitação profissional para a equipe em novas tecnologias?** ✅
> Sim. A equipe participa de capacitações periódicas em novas tecnologias, acompanha atualizações do ecossistema tecnológico e adota práticas de atualização contínua de dependências (Dependabot com merges diários).

---

**Há passagem de conhecimento entre as equipes de projeto e sustentação?** ✅
> Sim. O processo de desenvolvimento inclui documentação técnica e transferência de conhecimento entre equipes. Code reviews obrigatórios garantem que o conhecimento sobre cada mudança seja compartilhado entre os membros da equipe.

---

**Há controle sob responsabilidade em cada sistema?** ✅
> Sim. Cada sistema possui responsável técnico definido. As responsabilidades de desenvolvimento, revisão, aprovação e operação são atribuídas e rastreadas dentro do processo de desenvolvimento.

---

**Os processos de desenvolvimento de software, desde seu requisito até sua entrega, são medidos e controlados?** ✅
> Sim. O processo é medido por meio de métricas de CI/CD (taxa de sucesso de builds, cobertura de testes, tempo de deploy) e controlado via GitFlow com branches protegidas, revisões obrigatórias e pipelines automatizadas.

---

**Há processo de controle sobre a efetividade do produto solicitado e entregue?** ✅
> Sim. A efetividade dos produtos entregues é monitorada por meio de indicadores de qualidade, feedback de usuários e métricas de uso coletadas via ferramentas de monitoramento (CloudWatch).

---

**Há processo para medição de previsto x realizado com relação às estimativas de esforço?** ✅
> Sim. O acompanhamento de previsto x realizado é feito via Monday.com. Todo desenvolvimento obrigatoriamente passa pelo ambiente de staging, onde é validado contra todos os critérios levantados antes de ser promovido para produção.

---

**Os processos de projeto de software, desde o requisito até sua entrega final, são submetidos à melhoria contínua?** ✅
> Sim. O processo de desenvolvimento é continuamente revisado e aprimorado. Retrospectivas periódicas identificam pontos de melhoria, e o workflow de desenvolvimento é atualizado conforme novas práticas e ferramentas são adotadas.

---

**Existe medições quanto a qualidade pós-produção dos sistemas/software desenvolvidos?** ✅
> Sim. A qualidade pós-produção é monitorada continuamente via AWS CloudWatch, com métricas de performance, disponibilidade, erros de aplicação e alertas automatizados para eventos anômalos.

---

### Tecnologia e Arquitetura

**O sistema/software está desenvolvido em linguagem orientada a objetos?** ✅
> Sim. O backend é desenvolvido em Ruby on Rails (linguagem orientada a objetos) e o frontend em Angular com TypeScript (também orientado a objetos).

---

**O sistema faz uso de web server (ex.: Nginx)?** ✅
> Sim. A aplicação utiliza Puma como servidor de aplicação Ruby, operando atrás do CloudFlare como proxy reverso e camada de proteção perimetral.

---

**O sistema está desenvolvido em uma das seguintes linguagens de mercado? Python, Java, .Net, Ruby, PHP, JS?** ✅
> Sim. O backend é desenvolvido em Ruby (Ruby on Rails) e o frontend em TypeScript/JavaScript (Angular) — ambas linguagens amplamente adotadas pelo mercado.

---

**O sistema é desenvolvido usando boas práticas de UX/UI Design?** ✅
> Sim. O frontend (Angular) é desenvolvido com foco em usabilidade e experiência do usuário, seguindo boas práticas de UX/UI Design.

---

**Há versionamento de código fonte?** ✅
> Sim. Todo o código é versionado com Git, seguindo o fluxo GitFlow com branches para features, releases e hotfixes, e histórico completo de alterações rastreável.

---

**A pipeline faz execução de testes automatizados (unitários e/ou integrados)?** ✅
> Sim. A pipeline de CI/CD executa testes automatizados (unitários e de integração) em cada pull request. O merge só é aprovado com todos os testes passando.

---

**O sistema está preparado para envio de logs ao APM?** ✅
> Sim. Os logs da aplicação são centralizados no AWS CloudWatch, com coleta de logs de aplicação, infraestrutura e segurança, além de alertas configurados para eventos críticos.

---

**O sistema possui um script de healthcheck?** ✅
> Sim. Todos os serviços possuem healthchecks configurados no Amazon ECS, garantindo que instâncias não saudáveis sejam automaticamente substituídas sem intervenção manual.

---

**O sistema possui um processo de failover?** ✅
> Sim. A infraestrutura utiliza Amazon Aurora Multi-AZ com failover automático e Amazon ECS com auto-recovery de containers. Em caso de falha, a recuperação ocorre automaticamente sem necessidade de intervenção manual.

---

**O sistema possui versionamento das migrações para as alterações dos objetos do banco de dados?** ✅
> Sim. Todas as alterações de schema do banco de dados são gerenciadas via migrations versionadas (Rails Migrations), garantindo rastreabilidade completa de todas as mudanças estruturais do banco ao longo do tempo.

---

**O sistema faz o uso de cache (REDIS)?** ✅
> Sim. A aplicação utiliza Redis para gerenciamento de filas de processamento assíncrono (background jobs) e cache de sessões.

---

**O sistema possui processos batch ou background?** ✅
> Sim. A plataforma possui processamento assíncrono em background para operações como importação de dados, cálculos de resultados e envio de notificações, garantindo que operações pesadas não impactem a performance da aplicação principal.

---

**O sistema possui uma API para realização de integração com outros sistemas?** ✅
> Sim. A plataforma 4Shark possui API REST para integração com sistemas externos. A autenticação de API é baseada em tokens, e toda comunicação ocorre sobre TLS.

---

**O sistema está preparado para uso de variáveis de ambiente para armazenar credenciais?** ✅
> Sim. Todas as credenciais, chaves de API e strings de conexão são armazenadas como variáveis de ambiente — nunca no código-fonte. As configurações sensíveis são gerenciadas de forma segura na infraestrutura.

---

**Existe um pipeline definido para o sistema desenvolvido?** ✅
> Sim. A pipeline de CI/CD cobre todos os ambientes (desenvolvimento, homologação e produção), com etapas de build, testes automatizados, revisão de código e deploy automatizado seguindo o fluxo GitFlow.

---

**A pipeline faz execução de scanner de qualidade de código (ex.: SonarQube)?** ✅
> Sim. A pipeline executa análise estática de código em todos os pull requests e merges: RuboCop (backend Ruby) e ESLint (frontend TypeScript/Angular). Toda alteração entra exclusivamente via pull request com aprovação obrigatória. PRs de release exigem conformidade total com a revisão do GitHub Copilot, garantindo um padrão adicional de qualidade antes da promoção para produção.

---

**A pipeline realiza o build completo da aplicação?** ✅
> Sim. A pipeline realiza o build completo da aplicação, incluindo compilação, empacotamento em container Docker e publicação da imagem no repositório de containers, antes do deploy.

---

**A pipeline está preparada para realizar deploy em todos os ambientes (Desenvolvimento, QA, PRD)?** ✅
> Sim. A pipeline suporta deploy automatizado em todos os ambientes (desenvolvimento, homologação e produção), com ambientes totalmente segregados e pipelines independentes por ambiente.

---

**Em caso de falha em uma transação, o sistema realiza um rollback na transação não completada?** ✅
> Sim. A aplicação utiliza transações de banco de dados com controle de commit/rollback (ActiveRecord Transactions), garantindo que em caso de erro qualquer operação parcial seja revertida automaticamente, mantendo a consistência dos dados.

---

**O sistema foi construído para executar dentro de container (Docker, Kubernetes)?** ✅
> Sim. Toda a aplicação é containerizada com Docker e orquestrada via Amazon ECS (Elastic Container Service), garantindo isolamento, reprodutibilidade e escalabilidade dos serviços.

---

**Desenvolvimento da aplicação aplica boas práticas de programação (SOLID, KISS, DRY)?** ✅
> Sim. O desenvolvimento segue boas práticas de programação (SOLID, KISS, DRY), com revisões de código obrigatórias que garantem a aplicação consistente desses princípios.

---

**Aplicação utiliza frameworks consolidados da comunidade?** ✅
> Sim. O backend utiliza Ruby on Rails (framework web mais consolidado do ecossistema Ruby) e o frontend utiliza Angular (framework mantido pelo Google). Ambos possuem comunidades ativas, suporte de longo prazo e atualizações regulares de segurança.

---

**O sistema suporta metodologia de deploy do tipo blue/green ou canary?** ✅
> Sim. A infraestrutura Amazon ECS suporta nativamente deploys blue/green, permitindo substituição gradual de instâncias com possibilidade de rollback imediato caso o novo deploy apresente problemas.

---

**O sistema adota arquitetura orientada a eventos?** ✅
> Parcialmente. A plataforma utiliza processamento assíncrono baseado em eventos para operações que não requerem resposta imediata (cálculos, importações, notificações), por meio de filas de background jobs.

---

**A arquitetura da aplicação considera a separação de workloads do tipo Frontend e Backend?** ✅
> Sim. A arquitetura é completamente separada: frontend Angular (SPA) e backend Ruby on Rails (API REST), com comunicação via API. Os workloads são deployados e escalados de forma independente.

---

**As credenciais utilizadas pelo sistema utilizam recursos de cofre de senhas?** ✅
> Sim. As credenciais internas da equipe são gerenciadas via 1Password (cofre corporativo). As credenciais utilizadas pela aplicação em produção são armazenadas como variáveis de ambiente seguras na infraestrutura AWS, nunca em texto plano no código.

---

## Infraestrutura

**O software desenvolvido/utilizado possui a prática de escalabilidade?** ✅
> Sim. A infraestrutura utiliza Amazon ECS com Auto Scaling, permitindo escalar horizontalmente os serviços conforme a demanda. O banco de dados Amazon Aurora também suporta escalabilidade de leitura via réplicas.

---

**Utiliza a metodologia de filas (RabbitMQ/Apache Kafka)?** ✅
> Sim. A plataforma utiliza sistema de filas com Redis como backend para processamento assíncrono de jobs em background, garantindo desacoplamento e resiliência no processamento de operações assíncronas.

---

**Possui utilização de Domínios e/ou Subdomínios?** ✅
> Sim. A plataforma utiliza domínios e subdomínios para separação dos serviços, todos protegidos pelo CloudFlare com certificados TLS válidos.

---

**O conceito de microserviços é aplicado?** ✅
> Parcialmente. A arquitetura é composta por serviços separados e independentes (aplicação principal, serviço de integração, serviço de configuração), cada um com responsabilidades bem definidas, deployados e escalados de forma independente.

---

**Possui mapa de fluxo da aplicação passando pela infraestrutura?** ✅
> Sim. O diagrama de arquitetura de alto nível está disponível como anexo (`architecture-diagram.png`), representando os principais componentes, conexões e camadas de segurança da infraestrutura.

---

**O produto possui documentação completa, como por exemplo portas e protocolos utilizados?** ✅
> Sim. A comunicação externa ocorre exclusivamente via HTTPS (porta 443/TLS). Internamente, os serviços se comunicam dentro da VPC AWS via portas definidas em Security Groups, sem exposição externa. A documentação de portas e protocolos está disponível para revisão.

---

**Possui modelagem de dados?** ✅
> Sim. O banco de dados possui modelagem completa com schema versionado via migrations, documentando todas as entidades, relacionamentos e estruturas de dados da aplicação.

---

**O conceito monolítico é presente?** ✅
> Sim. A aplicação principal é desenvolvida como monolito Rails, o que facilita a manutenção, consistência de dados e simplicidade operacional. A arquitetura é complementada por serviços auxiliares independentes quando necessário.

---

**Possui o conceito de paralelismo para execução de operações no sistema?** ✅
> Sim. A plataforma utiliza processamento paralelo via background jobs com múltiplos workers simultâneos, além de múltiplas instâncias do serviço no ECS, permitindo atender requisições concorrentes de forma eficiente.

---

**Adota algum Framework ou melhores práticas na questão de gerenciamento de recursos?** ✅
> Sim. A infraestrutura segue as práticas do AWS Well-Architected Framework, com gerenciamento de recursos via infraestrutura como código (Ansible e Terraform), garantindo configuração padronizada, rastreável e reprodutível.

---

**Possui imagens de containers personalizadas para os serviços da aplicação?** ✅
> Sim. Cada serviço possui Dockerfile customizado, gerando imagens específicas para cada componente da plataforma. As imagens são versionadas e publicadas em repositório privado de containers.

---

**Utiliza ferramenta Docker-compose para orquestração de deploy da aplicação?** ✅
> Sim. Docker Compose é utilizado no ambiente de desenvolvimento local para orquestração dos serviços. Em produção, a orquestração é realizada pelo Amazon ECS.

---

**Utiliza ferramenta de orquestração de microserviços Kubernetes?** ✅
> Não. A orquestração de containers é realizada via Amazon ECS (Elastic Container Service), serviço gerenciado pela AWS que oferece as mesmas capacidades de orquestração sem a complexidade operacional do Kubernetes.

---

**Utiliza a prática de infraestrutura como código (Ex: Terraform/Ansible)?** ✅
> Sim. Toda a infraestrutura é definida e gerenciada como código utilizando Ansible (automação de configuração) e Terraform (provisionamento de recursos AWS), garantindo reproducibilidade, rastreabilidade e controle de versão da infraestrutura.

---

**Arquitetura da aplicação é Cloud Native?** ✅
> Sim. A plataforma é 100% Cloud Native, hospedada na Amazon Web Services (AWS), utilizando serviços gerenciados (ECS, Aurora, CloudWatch, S3) e seguindo os princípios de arquitetura cloud nativa: containers, serviços gerenciados, escalabilidade automática e infraestrutura como código.

---

**É possível executar o sistema no Sistema Operacional Linux/Windows/Windows Server?** ✅
> Sim. A aplicação executa em containers Linux (Docker), compatível com qualquer ambiente que suporte containers Docker em Linux.

---

**É compatível e homologado para VMware/RedHat Openshift/Nutanix/Hyper-v?** ✅
> A plataforma é Cloud Native e hospedada na AWS. A execução em ambientes on-premises (VMware, Nutanix, Hyper-V) ou plataformas container (OpenShift) pode ser avaliada sob demanda — a base containerizada (Docker) é compatível com esses ambientes, requerendo análise de adequação para cada caso específico.

---

**Adota solução de performance para aplicação utilizando memória em cache (Ex. Redis)?** ✅
> Sim. A aplicação utiliza Redis para cache e gerenciamento de filas de background jobs, melhorando a performance e reduzindo a carga sobre o banco de dados.

---

**A solução é compatível com banco de dados opensource (PostgreSQL, MariaDB, MySQL)?** ✅
> Sim. O banco de dados utilizado é Amazon Aurora PostgreSQL, 100% compatível com PostgreSQL open source. A aplicação é desenvolvida com suporte nativo a PostgreSQL.

---

**É possível realizar a exportação do banco de dados?** ✅
> Sim. O banco de dados pode ser exportado via ferramentas padrão PostgreSQL (pg_dump) ou por meio dos recursos de backup da AWS (snapshots Aurora), permitindo exportação completa ou parcial dos dados.

---

**É possível exportar o software para cloud?** ✅
> A plataforma já opera nativamente na nuvem (AWS). A aplicação containerizada (Docker) pode ser portada para outros provedores cloud conforme necessidade, dado que utiliza tecnologias abertas e padronizadas.

---

**A arquitetura da aplicação prevê uso de coleta de métricas, logs e traces?** ✅
> Sim. A arquitetura utiliza AWS CloudWatch para coleta centralizada de métricas, logs de aplicação e infraestrutura, e traces de performance. Alertas automatizados são configurados para eventos críticos.

---

**Aplicação utiliza de ferramentas de observabilidade e telemetria (Ex: OpenTelemetry)?** ✅
> Sim. A plataforma utiliza AWS CloudWatch como solução central de observabilidade, coletando métricas, logs e rastreamento distribuído dos serviços. Integração com ferramentas adicionais de APM pode ser avaliada conforme necessidade.

---

## Sustentação

**Política de evolução tecnológica da aplicação. O fabricante prevê em seu roadmap melhorias de infraestrutura/tecnologia?** ✅
> Sim. A 4Shark mantém roadmap ativo de evolução tecnológica, incluindo atualizações contínuas de dependências (Dependabot com merges diários), atualização de versões de linguagem e frameworks, e melhorias de infraestrutura planejadas. O objetivo é manter a plataforma sempre em versões estáveis e suportadas.

---

**O contrato de suporte prevê acordo de nível de serviço para atendimentos funcionais?** ✅
> Sim. O contrato de suporte com a Positivo prevê acordo de nível de serviço (SLA) para atendimentos funcionais, com prazos definidos contratualmente.

---

**A disponibilidade da solução (caso SaaS) é garantida em pelo menos 95%?** ✅
> Sim. A plataforma SaaS 4Shark opera com disponibilidade superior a 99%, sustentada por infraestrutura AWS com Multi-AZ, failover automático (Amazon Aurora + ECS auto-recovery) e proteção perimetral via CloudFlare.

---

**Possui modalidade de atendimento a incidentes de infraestrutura em regime 24x7?** ✅
> Sim. A 4Shark opera com monitoramento contínuo 24x7 via stack de observabilidade composta por New Relic, Datadog e Rollbar, todos integrados a um canal dedicado no Slack. Alertas e avisos de incidentes são recebidos em tempo real pela equipe, permitindo resposta imediata a qualquer ocorrência independentemente do horário.

---

**Possui grade de SLA definido com prazos limites de retorno para primeiro atendimento?** ✅
> Sim. A 4Shark possui grade de SLA definida com os seguintes prazos (em horas úteis):
>
> | Tipo | Atendimento | Solução |
> |------|-------------|---------|
> | Severidade 1 — Serviço completamente indisponível | 4h | 16h |
> | Severidade 2 — Serviço operando parcialmente | 6h | 36h |
> | Severidade 3 — Problemas que não afetam o serviço | 8h | 52h |
> | Dúvidas e demais problemas de utilização | 24h | 72h |
>
> **Classificação:**
> - **Severidade 1 (Urgente)**: Perda ou paralisação total do sistema. Indisponibilidade total do serviço/aplicação em uma operação/cliente ou em toda a plataforma.
> - **Severidade 2 (Média)**: Perda parcial de funcionalidade ou lentidão generalizada. Sistema mantido por contingência.
> - **Severidade 3 (Baixa)**: Falha de componentes isolados sem restrições substanciais. Erro irrelevante, comportamento incorreto ou erro de documentação que não afeta a operação.

---

**Possui portal para registro e acompanhamento de chamados com rastreabilidade do histórico?** ✅
> Sim. O suporte é gerenciado via Zendesk, plataforma que permite o registro, acompanhamento e rastreabilidade completa do histórico de todos os chamados.

---

## Pendências

Nenhuma. Todas as perguntas respondidas.
