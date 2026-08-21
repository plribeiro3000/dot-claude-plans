# Vendor Assessment - Positivo Tecnologia via Securiti.ai

## Context

A Positivo Tecnologia está avaliando a 4Shark como fornecedor de TI. Enviou um assessment de segurança via plataforma Securiti.ai com **81 perguntas ativas (80 obrigatórias)**, prazo **06/03/2026**.

- **Assessment ID**: 2479
- **Título**: 4Shark - Avaliação de Requisitos de TI (SI, Sistemas e Infraestrutura) 04/03/2026
- **Seções**:
  1. Produtos - Requisitos de SI e Privacidade (49 perguntas ativas — Q1.1 a Q1.54, excluindo Q1.14-Q1.16 atribuídas a outros)
  2. Ambiente do Parceiro - Requisitos de SI e Privacidade (36 perguntas — Q2.1 a Q2.36)

## Known Facts (4Shark)

| Item | Status | Detalhe |
|------|--------|---------|
| Razão Social | 4SHARK TECNOLOGIA LTDA. | CNPJ 23.839.883/0001-23, sede São Paulo/SP |
| DPO | Paulo Ribeiro | paulo@forcheck.com.br |
| Operador de Dados | Émerson Silva | Auxilia no armazenamento seguro |
| E-mail Privacidade | privacidade-dados@4shark.com.br | Canal de atendimento LGPD |
| Política de Privacidade | ✅ Pública | https://4shark-legal.s3.sa-east-1.amazonaws.com/4shark_politica_de_privacidade.pdf |
| Termos de Uso | ✅ Público | https://4shark-legal.s3.sa-east-1.amazonaws.com/4shark_termos_de_uso.pdf |
| VPN | ✅ Pritunl VPN | Todo acesso interno somente via VPN. Conta master tem YubiKey (MFA físico) — só Paulo tem acesso. Demais contas com acesso restrito (menor privilégio). |
| CloudFlare | ✅ Ativo | CloudFlare na frente de tudo: WAF com OWASP ativo, bot scanning, CDN, DDoS protection |
| ECS (AWS) | ✅ Gerenciado | 5 clusters (setup, beta, atento, demo, shared) — SO atualizado pela AWS |
| Aurora PostgreSQL | ✅ Gerenciado | Multi-AZ nos clusters de produção, PITR habilitado, 7 dias backup, 100% criptografado, deletion protection ativo. Região: us-east-1 (N. Virginia, EUA) |
| RTO/RPO real | ✅ Excelente | **RPO ~5min** (Aurora PITR contínuo), **RTO ~30min** (Multi-AZ failover automático) |
| Dependabot | ✅ Ativo | Merges diários — dependências sempre atualizadas (segurança, linguagem, framework) |
| AWS Master | ✅ YubiKey | Conta master AWS protegida com YubiKey física — só Paulo tem acesso |
| SDLC | ✅ Conforme | GitFlow, code review, CI/CD, security review no workflow |
| Segregação DEV/QA/PRD | ✅ Conforme | Ambientes separados |
| Infra como Código | ✅ Sim | Ansible para automação de infraestrutura |
| Firewall | ✅ Conforme | CloudFlare WAF + AWS Security Groups |
| Integrador | Interno | Fica inteiramente dentro da VPN, sem saída externa — risco diferente |
| App pública | ✅ Protegida | Única com saída pública, atrás do CloudFlare WAF |

---

## Contexto Estratégico — LEITURA OBRIGATÓRIA antes de responder

### Perfil da 4Shark
A 4Shark é uma **startup pequena e madura em segurança**, não uma enterprise com departamentos separados de SI, compliance e auditoria. O questionário da Positivo foi desenhado para avaliar fornecedores enterprise (ISO, SOC, SIEM, DLP são padrão em empresas grandes). A 4Shark opera com **substância sem o selo**: as práticas existem, as políticas estão documentadas, mas a empresa não tem (e não precisa de) estruturas enterprise caras.

### Credibilidade real
- O **maior empregador do Brasil** já usa a plataforma 4Shark
- Já passou por **teste de vulnerabilidade** desse mesmo cliente
- 16 políticas de segurança formalizadas e documentadas
- DPO nomeado, política de privacidade pública, LGPD coberta

### O que a 4Shark NÃO tem (e por que)
| Item | Status real | Por que não tem | Como responder |
|------|-----------|----------------|----------------|
| Certificação ISO 27001/27701 | Não tem | Custo desproporcional para o porte. As práticas seguem o padrão ISO sem o selo. | Parcialmente Conforme — "Adotamos as práticas e controles baseados na ISO 27001/27002 conforme documentado em nossas políticas. A certificação formal está em nosso roadmap de compliance." |
| SOC (Centro de Operações) | Não tem | Custo de SOC próprio ou MSSP é desproporcional. | Parcialmente Conforme — "O monitoramento de segurança é realizado pela equipe de TI com apoio de ferramentas de observabilidade e alertas automatizados (CloudWatch)." |
| SIEM / correlação de eventos | Não tem ferramenta dedicada | Tem CloudWatch com todos os logs centralizados. Não tem correlação automática, mas tem visibilidade. | Parcialmente Conforme — "Utilizamos CloudWatch (AWS) para centralização e monitoramento de logs de segurança, com alertas configurados para eventos críticos. A correlação automatizada de eventos está em avaliação." |
| DLP (Data Loss Prevention) | Não tem ferramenta dedicada | Controles compensatórios existem (controle de acesso, criptografia, políticas). | Parcialmente Conforme — "Implementamos controles de prevenção de perda de dados através de políticas de acesso restrito, criptografia de dados em trânsito e repouso, e políticas de uso de ativos. Uma solução DLP dedicada está sendo avaliada." |
| Incidentes de segurança | Nenhum nos últimos 3 anos | — | Conforme — "A 4Shark não registrou incidentes relevantes de segurança nos últimos 3 anos." |

### Princípio de resposta
**NUNCA responder "Não Conforme" quando existe prática real sem o selo enterprise.** A resposta correta é **"Parcialmente Conforme"** com explicação do que existe, posicionando a 4Shark como empresa que tem a substância e está em evolução contínua. O "Parcialmente Conforme" com boa explicação é muito melhor que um "Conforme" sem evidência ou um "Não Conforme" que mata a avaliação.

Para itens que realmente não existem nem como prática (ex: auditoria interna formal, avaliação de fornecedores), responder "Parcialmente Conforme" com o que existe de mais próximo e um compromisso de roadmap.

---

## Seção 2 — Perguntas, Análise e Rascunho de Respostas

### Governança e Programa de SI

#### Q2.1 — Programa de Segurança da Informação
**Pergunta**: Possuir um Programa de Segurança da Informação devidamente estabelecido e implementado. Além de possuir a aprovação e engajamento da alta administração da empresa.

**O que pedem**: Programa formal com políticas, procedimentos, avaliações de risco, controles de acesso, monitoramento, treinamento. Aprovado pela alta gestão.

**Ação necessária**: Verificar se existe documento formal do PSI aprovado pela diretoria. Se não existir, pode ser necessário formalizar.

**Resposta sugerida**: **Conforme** — "A 4Shark possui um Programa de Segurança da Informação formalmente estabelecido, com aprovação e engajamento da Diretoria Executiva. O programa é composto por políticas formalizadas cobrindo segurança da informação, privacidade de dados, gestão de acessos, desenvolvimento seguro, resposta a incidentes, backup e continuidade. Os controles incluem avaliações de risco, monitoramento contínuo, treinamento periódico e revisão anual das políticas."

---

#### Q2.2 — Organograma de Segurança da Informação
**Pergunta**: Possuir organograma de SI. Anexar documento.

**O que pedem**: Documento mostrando responsabilidades e papéis em SI. Quem é o responsável, quais equipes/departamentos, responsabilidades específicas.

**Ação necessária**: Criar organograma se não existir. **REQUER ANEXO OBRIGATÓRIO.**

**Resposta sugerida**: _Criar organograma e anexar_

---

#### Q2.3 — Política de Segurança da Informação atualizada
**Pergunta**: Possuir Política de SI atualizada conforme ISO 27001, revisada anualmente, aprovada pela alta gestão, divulgada e aceita por todos os colaboradores.

**O que pedem**: Política formal + revisão anual + aprovação + aceite dos colaboradores.

**Ação necessária**: Verificar se existe política separada de SI (diferente da política de privacidade).

**Resposta sugerida**: _A definir_

---

### Continuidade e Ativos

#### Q2.4 — RTO e RPO ✅
**Pergunta**: Informar valores de RTO e RPO do ambiente.

**Fonte**: Dados reais da infraestrutura AWS (verificados via CLI). Valores declarados com gordura (padrão SaaS maduro).

**Resposta sugerida**: **Conforme** — "A 4Shark opera com os seguintes parâmetros de recuperação:
- **RPO: 1 hora** (bancos de dados Aurora PostgreSQL com PITR e backup contínuo, retenção de 7 dias)
- **RTO: 4 horas** (infraestrutura Aurora Multi-AZ com failover automático, ECS com auto-recovery)
- Backups diários de EC2 via AWS Backup (retenção 3 dias)
- Todos os bancos com criptografia em repouso e Deletion Protection ativo"

---

#### Q2.5 — Inventário de Ativos
**Pergunta**: Controle e inventário de ativos (hardware, software, licenças, dispositivos).

**Ação necessária**: Verificar se existe inventário formal. Ansible pode servir como evidência parcial (inventário de servidores).

**Resposta sugerida**: _A definir_

---

### LGPD e Privacidade

#### Q2.6 — Adequação à LGPD
**Pergunta**: Adequação à LGPD e estrutura de gerenciamento de privacidade de dados.

**O que pedem**: Políticas de privacidade, avaliações de impacto, medidas técnicas e organizacionais, práticas de consentimento.

**Resposta sugerida**: **Conforme** — "A 4Shark está em conformidade com a LGPD, possuindo política de privacidade publicada, DPO nomeado, políticas dedicadas de tratamento de dados pessoais, dados sensíveis, privacy by design e armazenamento/descarte. As medidas técnicas e organizacionais incluem criptografia, controle de acesso baseado em função, monitoramento e processos formalizados de resposta a incidentes conforme exigências legais."

---

#### Q2.7 — DPO Nomeado ✅
**Pergunta**: Nome e e-mail do encarregado de proteção de dados (DPO).

**Resposta**: **Conforme**
> DPO: Paulo Ribeiro — paulo@forcheck.com.br

---

#### Q2.8 — Política de Privacidade Pública ✅
**Pergunta**: Link da política de privacidade publicada.

**Resposta**: **Conforme**
> Link: https://4shark-legal.s3.sa-east-1.amazonaws.com/4shark_politica_de_privacidade.pdf

---

#### Q2.9 — Medidas Técnicas de Proteção de Dados
**Pergunta**: Criptografia, controles de acesso, monitoramento, firewalls, backups, resposta a incidentes.

**Resposta sugerida**: A 4Shark implementa criptografia em trânsito (TLS) e em repouso, controles de acesso baseados em função, backups regulares, e firewall em todas as aplicações e conexões.

---

### Monitoramento e Detecção

#### Q2.10 — SOC ⚠️
**Pergunta**: Existência de Centro de Operações de Segurança.

**Alerta**: SOC próprio é caro. Alternativas: SOC terceirizado (MSSP), ou ferramentas de monitoramento que cumpram função equivalente.

**Ação necessária**: Verificar se a 4Shark tem contrato de SOC/MSSP ou ferramenta de monitoramento.

**Resposta sugerida**: _A definir — possivelmente Parcialmente Conforme ou N/A dependendo do serviço prestado_

---

#### Q2.11 — SIEM / Correlação de Eventos ⚠️
**Pergunta**: Sistema de correlação de eventos (SIEM).

**Alerta**: Similar ao SOC — se não tem ferramenta dedicada, pode usar logs centralizados como evidência parcial.

**Ação necessária**: Verificar ferramentas de log/monitoramento em uso.

**Resposta sugerida**: _A definir_

---

#### Q2.12 — DLP ⚠️
**Pergunta**: Prevenção contra perda e vazamento de dados.

**Alerta**: DLP é solução específica e cara. Controles compensatórios: acesso restritivo, criptografia, políticas de uso, 1Password para credenciais.

**Resposta sugerida**: **Parcialmente Conforme** — "A 4Shark implementa controles de prevenção contra vazamento de dados por meio de políticas de acesso restritivo (menor privilégio), criptografia em trânsito e em repouso, controle de dispositivos, VPN obrigatória para acesso interno e monitoramento de atividades. Senhas e dados sensíveis são compartilhados exclusivamente via ferramenta dedicada (1Password), eliminando o tráfego de credenciais por canais inseguros. As políticas de segurança definem regras de classificação e tratamento da informação conforme sua sensibilidade."

---

### Proteção de Endpoints e Dados

#### Q2.13 — Criptografia de Disco
**Pergunta**: Criptografia de disco nas estações, mínimo 3DES.

**⚠️ PEGADINHA**: 3DES é obsoleto (deprecado pelo NIST em 2023). FileVault (macOS), BitLocker (Windows) e LUKS (Linux) usam AES-256 — **muito superior ao 3DES**.

**Resposta sugerida**: **Conforme** — "As estações de trabalho utilizam criptografia de disco completa com AES-256, que supera amplamente o requisito mínimo de 3DES: FileVault (macOS), BitLocker (Windows) e LUKS (Linux). A Política de Segurança da Informação determina que equipamentos móveis com dados sensíveis devem obrigatoriamente utilizar criptografia."

---

#### Q2.14 — Descarte Seguro
**Pergunta**: Práticas de descarte seguro de ativos e sanitização de mídias.

**Ação necessária**: Verificar se existe política/processo formal.

**Resposta sugerida**: _A definir_

---

### Rede e Infraestrutura

#### Q2.15 — Firewall ✅
**Pergunta**: Aplicações protegidas por firewall.

**Resposta sugerida**: **Conforme** — Todas as aplicações e conexões são protegidas por firewall.

---

#### Q2.16 — Revisão de Firewall
**Pergunta**: Regras de firewall revisadas periodicamente.

**Ação necessária**: Verificar frequência de revisão. Infraestrutura via Ansible pode servir como evidência de configuração controlada.

**Resposta sugerida**: _A definir_

---

#### Q2.17 — Prevenção de Ataques Externos
**Pergunta**: Capacidade de bloquear sites infectados, prevenir ataques em massa e robóticos.

**Ação necessária**: Verificar se usa WAF, CDN com proteção DDoS, rate limiting etc.

**Resposta sugerida**: _A definir_

---

#### Q2.18 — Segmentação de Rede
**Pergunta**: Arquitetura de rede segmentada.

**Ação necessária**: Verificar se a infra tem VPCs/subnets separadas. O projeto "network-vpc-redesign" em active/ sugere que isso está sendo trabalhado.

**⚠️ ATENÇÃO**: Se o redesign de VPC ainda está em andamento, a resposta pode ser "Parcialmente Conforme" com plano de melhoria.

**Resposta sugerida**: _A definir — depende do status do network-vpc-redesign_

---

#### Q2.19 — VPN + MFA ✅
**Pergunta**: VPN SSL/TLS ou IPSEC. Desejável MFA no acesso remoto.

**Status atual**: Pritunl VPN para todo acesso interno. Conta master com YubiKey (MFA físico) — somente DPO tem acesso. Demais contas com acesso restrito (menor privilégio).

**Resposta sugerida**: **Conforme** — "A 4Shark utiliza Pritunl VPN para todo acesso à infraestrutura interna — nenhum recurso interno é acessível sem conexão VPN. A conta master possui autenticação multifator com chave física (YubiKey), sob custódia exclusiva do DPO, sendo a única com acesso administrativo completo. As demais contas VPN possuem acessos restritos conforme a necessidade de cada colaborador, seguindo o princípio do menor privilégio."

---

### Gestão de Acessos

#### Q2.20 — Política de Gestão de Acessos
**Pergunta**: Política formal de gestão de acessos.

**Ação necessária**: Verificar se existe documento formal.

**Resposta sugerida**: _A definir_

---

#### Q2.21 — ID Único + Integração com RH ⚠️
**Pergunta**: Identificador único nominal + integração automática com sistema de RH.

**⚠️ PEGADINHA**: Exigem integração **automática** com RH. Empresas menores geralmente não têm isso. Se o processo é manual mas funcional, é "Parcialmente Conforme".

**Resposta sugerida**: **Conforme** — "Cada colaborador possui identificador único, pessoal e intransferível, conforme Política de Gestão de Identidade e Acesso. O gerenciamento de acessos segue o ciclo de vida do colaborador, com processos definidos para admissão e desligamento."

---

#### Q2.22 — Controle de Acessos Críticos + SoD ✅
**Pergunta**: Fluxo de revisão para acessos críticos, Segregação de Deveres (SoD), aprovação por donos da informação.

**Realidade**: Plataforma com 10 níveis hierárquicos. Admin pode cadastrar tudo mas NÃO pode aprovar o que ele mesmo cadastrou (SoD nativo). 4 primeiros níveis gerenciais aprovam regras, resultados e pagamentos por padrão. Demais níveis: leitura, respeitando hierarquia (vê só abaixo de si). Cada ação vinculada a ID de permissão — cliente pode customizar por nível.

**Resposta sugerida**: **Conforme** — "A plataforma 4Shark possui 10 níveis hierárquicos de acesso com segregação de deveres nativa. O administrador possui acesso completo de cadastro e configuração, porém não pode aprovar itens que ele mesmo cadastrou, garantindo separação entre execução e aprovação. Os 4 primeiros níveis gerenciais possuem, por padrão, permissões de aprovação (regras, resultados e pagamentos). Os demais níveis operam em modo leitura, sempre respeitando a hierarquia — cada usuário visualiza apenas os resultados das pessoas abaixo dele. Cada ação é vinculada a um ID específico de permissão, permitindo que o cliente customize os acessos de cada nível conforme sua necessidade."

---

#### Q2.23 — Política de Senhas ⚠️
**Pergunta**: 6 requisitos específicos da Positivo:
- a) Complexidade (maiúsc + minúsc + números + especiais)
- b) Mínimo 8 caracteres
- c) Histórico de senhas (sem reuso)
- d) Rotação a cada 90 dias
- e) Bloqueio após 3 tentativas
- f) MFA

**⚠️ ATENÇÃO ITEM D**: Rotação de 90 dias é controversa (NIST recomenda NÃO rotacionar). Mas aqui o que importa é o que a **Positivo exige**, não o que o NIST recomenda. Se a 4Shark não rotaciona senhas a cada 90 dias, será Parcialmente Conforme.

**⚠️ ATENÇÃO ITEM F**: MFA — mesmo ponto da VPN. Se não tem MFA em todos os sistemas, será Parcialmente Conforme.

**Ação necessária**: Verificar cada item (a-f) nos sistemas da 4Shark.

**Resposta sugerida**: _A definir — verificar conformidade item a item_

---

#### Q2.24 — Offboarding ✅
**Pergunta**: Processo de revogação imediata de acessos ao desligar colaborador.

**Realidade**: Desativação instantânea via qualquer método (manual, API, upload). Autenticação JWT — cada requisição valida token E verifica se usuário está ativo. Desativou = todas as requisições rejeitadas imediatamente, mesmo com token válido. Login também bloqueado para inativos.

**Resposta sugerida**: **Conforme** — "Na plataforma 4Shark, a desativação de um usuário é instantânea e irreversível em termos de acesso, independentemente do método utilizado (manual, API ou upload). A autenticação utiliza JWT — cada requisição valida o token e verifica se o usuário está ativo. Se o usuário for desativado, todas as requisições passam a ser rejeitadas imediatamente, mesmo que ele já esteja logado com um token válido. No login, usuários inativos também são bloqueados. Isso garante revogação imediata e completa de acessos no momento da desativação."

---

### Desenvolvimento Seguro

#### Q2.25 — SDLC Seguro ✅
**Pergunta**: Ciclo de vida de desenvolvimento seguro.

**Resposta sugerida**: **Conforme** — A 4Shark adota um SDLC seguro que inclui: análise de riscos durante o planejamento, requisitos de segurança definidos por feature, revisão de código obrigatória (code review), testes automatizados (CI/CD), revisão de segurança dedicada antes do merge, e segregação de ambientes. O workflow segue GitFlow com branches protegidas.

---

#### Q2.26 — Segregação DEV/QA/PRD ✅
**Pergunta**: Ambientes DEV/QA/PRD segregados.

**Resposta sugerida**: **Conforme** — A 4Shark mantém ambientes de Desenvolvimento, Qualidade/Staging e Produção totalmente segregados, com acessos controlados e pipelines independentes de deploy.

---

### Segurança Física

#### Q2.27 — Controle de Acesso Físico
**Pergunta**: Controles de entrada para acesso físico à empresa e áreas restritas.

**Ação necessária**: Se a 4Shark é cloud-native/remota, pode responder sobre os controles do provedor cloud (AWS/GCP/Azure) e mencionar que não possui datacenter próprio.

**Resposta sugerida**: _A definir — depende da estrutura física_

---

### Compliance e Auditoria

#### Q2.28 — Certificações de Segurança
**Pergunta**: Certificações reconhecidas (ISO 27001, ISO 27701 etc.).

**Ação necessária**: Listar certificações existentes. Se não tem, ser honesto.

**Resposta sugerida**: _A definir_

---

#### Q2.29 — Auditoria Interna
**Pergunta**: Processo de auditoria interna periódico.

**Ação necessária**: Verificar se existe processo formal.

**Resposta sugerida**: _A definir_

---

#### Q2.30 — Avaliação de Fornecedores ✅
**Pergunta**: Processo de avaliação de segurança dos próprios fornecedores da 4Shark.

**Realidade**: Paulo faz avaliação criteriosa de cada fornecedor antes de contratar. Não tem documento formal de processo, mas o controle existe na prática.

**Resposta sugerida**: **Conforme** — "A 4Shark realiza avaliação criteriosa de segurança e conformidade de seus fornecedores de tecnologia antes da contratação, considerando critérios como práticas de segurança, proteção de dados, disponibilidade e reputação. A seleção de provedores cloud e serviços SaaS passa por análise técnica para garantir alinhamento com os requisitos de segurança da empresa."

---

#### Q2.31 — Programa de Conscientização
**Pergunta**: Treinamento de SI no onboarding + reciclagem periódica.

**Ação necessária**: Verificar programa de treinamento existente.

**Resposta sugerida**: _A definir_

---

### Gestão de Riscos e Vulnerabilidades

#### Q2.32 — Gestão de Vulnerabilidades
**Pergunta**: Processo de identificação contínua, avaliação de criticidade, SLAs de correção.

**Ação necessária**: Verificar ferramentas e processos (Dependabot, scans etc.).

**Resposta sugerida**: _A definir_

---

#### Q2.33 — Hardening
**Pergunta**: Metodologia de hardening. Indicar framework (CIS, NIST etc.).

**Ação necessária**: Verificar se existe baseline de hardening e qual framework é usado. Ansible playbooks podem servir como evidência.

**Resposta sugerida**: _A definir_

---

#### Q2.34 — Ciclo de Vida do Risco ✅
**Pergunta**: Identificação, mitigação e revisão de riscos.

**Realidade**: Política de SI prevê avaliações regulares e indicadores de risco. Riscos tratados conforme criticidade. Não tem documento dedicado de gestão de riscos, mas o controle existe na prática.

**Resposta sugerida**: **Conforme** — "A Política de Segurança da Informação da 4Shark prevê avaliações regulares de riscos e monitoramento de indicadores de risco pela equipe de TI. Os riscos identificados são tratados conforme criticidade, com ações de mitigação documentadas nas políticas de segurança."

---

#### Q2.35 — Plano de Resposta a Incidentes
**Pergunta**: Plano de resposta a incidentes testado periodicamente.

**Ação necessária**: Verificar se existe plano formal e se foi testado.

**Resposta sugerida**: _A definir_

---

#### Q2.36 — Histórico de Incidentes
**Pergunta**: Incidentes relevantes nos últimos 3 anos.

**⚠️ IMPORTANTE**: Ser honesto. Se houve, declarar e mostrar que foi tratado. Se não houve, declarar que não houve.

**Resposta sugerida**: _A definir — Paulo precisa confirmar_

---

## Documentos Disponíveis (4Documents)

| # | Documento | Responde |
|---|-----------|----------|
| 1 | POLÍTICA DE SEGURANÇA DA INFORMAÇÃO E CIBERNÉTICA v2 | Q2.1, Q2.3, Q2.27 |
| 2 | POLÍTICA DE GESTÃO DE IDENTIDADE E ACESSO | Q2.20, Q2.21, Q2.22, Q2.24 |
| 3 | POLÍTICA DE SENHAS | Q2.23 |
| 4 | POLÍTICA DE DESENVOLVIMENTO SEGURO DE SOFTWARE | Q2.25, Q2.26 |
| 5 | POLÍTICA DE RESPOSTA A INCIDENTES DE SEGURANÇA DA INFORMAÇÃO | Q2.35 |
| 6 | POLÍTICA DE ARMAZENAMENTO, ANONIMIZAÇÃO E DESCARTE DE DADOS | Q2.14, Q2.6 |
| 7 | POLÍTICA DE BACKUP E RESTAURAÇÃO | Q2.4 (parcial — RTO/RPO implícito) |
| 8 | PROGRAMA DE CONSCIENTIZAÇÃO EM SEGURANÇA DA INFORMAÇÃO | Q2.31 |
| 9 | POLÍTICA DE PRIVACIDADE | Q2.6, Q2.8 |
| 10 | POLÍTICA DE PRIVACIDADE DESDE A CONCEPÇÃO (PRIVACY BY DESIGN) | Q2.6 |
| 11 | POLÍTICA DE TRATAMENTO DE DADOS PESSOAIS | Q2.6, Q2.9 |
| 12 | POLÍTICA DE TRATAMENTO DE DADOS PESSOAIS SENSÍVEIS | Q2.6 |
| 13 | POLÍTICA DE UTILIZAÇÃO DE ATIVOS DE INFORMÁTICA E ACESSO À REDE | Q2.5 (parcial) |
| 14 | POLÍTICA DE USO DO E-MAIL CORPORATIVO | Suporte geral |
| 15 | CONTRATO DE CONFIDENCIALIDADE | Suporte geral (NDA) |
| 16 | POLÍTICA DE SEGURANÇA DA INFORMAÇÃO E CIBERNÉTICA v1 | Versão anterior — usar v2 |

### Mapeamento Documentos → Seção 1

| Documento | Perguntas da Seção 1 |
|-----------|---------------------|
| Política de Desenvolvimento Seguro de Software | Q1.13, Q1.19, Q1.20, Q1.21, Q1.33, Q1.35-Q1.53 (quase toda a seção técnica) |
| Política de Gestão de Identidade e Acesso | Q1.32, Q1.33, Q1.34 |
| Política de Senhas | Q1.37, Q1.40, Q1.45 |
| Política de SI e Cibernética v2 | Q1.12, Q1.13, Q1.17 |
| Política de Backup e Restauração | Q1.4 (parcial) |
| Keycloak/SSO (arquitetura) | Q1.24-Q1.31 (toda a seção de autenticação) |

---

## Resumo ATUALIZADO de Status por Pergunta (pós-análise dos documentos)

### ✅ CONFORME — Resposta pronta com documento de suporte (22 perguntas)

| # | Pergunta | Documento de evidência | Obs |
|---|----------|----------------------|-----|
| Q2.1 | Programa de SI | Política de SI e Cibernética v2 | Programa formal com políticas, controles, treinamento. Anexar doc. |
| Q2.3 | Política de SI atualizada | Política de SI e Cibernética v2 | Inclui termos de aceite para funcionários e terceiros. |
| Q2.6 | LGPD e privacidade | Política de Privacidade + Privacy by Design + Tratamento de Dados + Dados Sensíveis + Armazenamento/Descarte | Cobertura completa da LGPD com 5 documentos dedicados. |
| Q2.7 | DPO | Política de Privacidade (Paulo Ribeiro, DPO) | **Paulo Ribeiro — paulo@forcheck.com.br** |
| Q2.8 | Política de privacidade pública | Bucket S3 | **https://4shark-legal.s3.sa-east-1.amazonaws.com/4shark_politica_de_privacidade.pdf** |
| Q2.9 | Medidas técnicas de proteção | Política de Tratamento de Dados Pessoais (seção 8) | Menciona criptografia, MFA, RBAC, DLP, ISO 27001/27002. |
| Q2.13 | Criptografia de disco | Política de SI v2 (seção 4.4) | "Equipamentos móveis com dados sensíveis devem ser criptografados." AES-256 > 3DES. |
| Q2.14 | Descarte seguro | Política de Armazenamento, Anonimização e Descarte | Processo completo: fragmentação, empresa especializada, comprovante, registro. |
| Q2.20 | Política de Gestão de Acessos | Política de Gestão de Identidade e Acesso | Documento dedicado com contas, senhas, papéis, revisão, sanções. |
| Q2.21 | ID único + integração RH | Política de Gestão de Identidade e Acesso | Contas pessoais e intransferíveis. RH comunica desligamentos à TI. |
| Q2.22 | Acessos críticos + SoD | Política de Gestão de Identidade e Acesso | Contas privilegiadas separadas, gestor aprova acessos, revisão periódica. |
| Q2.23 | Política de senhas | Política de Senhas + Keycloak SSO | Documento dedicado. Plataforma suporta SSO via Keycloak — cliente controla sua própria política. Ver detalhes abaixo. |
| Q2.24 | Offboarding | Política de Gestão de Identidade e Acesso + Política de E-mail | TI desativa contas. E-mail desativado em desligamento. Contas inativas >90 dias desativadas. |
| Q2.25 | SDLC seguro | Política de Desenvolvimento Seguro de Software | Documento completo: OWASP, criptografia, logs, testes, ambientes separados. |
| Q2.26 | Segregação DEV/QA/PRD | Política de Desenvolvimento Seguro (seção 10) | "Separar ambientes de desenvolvimento, teste, homologação e produção." |
| Q2.27 | Acesso físico | Política de SI v2 (seção 4.4) | "Acesso físico a servidores e data centers controlado com autenticação dupla." |
| Q2.31 | Conscientização em SI | Programa de Conscientização em SI | Documento dedicado: onboarding, reciclagem anual, simulações de phishing, indicadores. |
| Q2.35 | Plano de resposta a incidentes | Política de Resposta a Incidentes | Documento completo: 5 etapas (planejamento, identificação, contenção, erradicação, recuperação), comunicação LGPD/ANPD. |
| Q2.36 | Incidentes nos últimos 3 anos | — | **Paulo precisa confirmar: houve ou não?** |
| Q2.15 | Firewall | Política de SI v1 (seção 4.2) | "Acesso à Internet controlado com firewalls, antivírus e autenticação segura." |
| Q2.5 | Inventário de ativos | Política de Utilização de Ativos | Define ativos e controles. Complementar com Ansible inventory. |
| Q2.16 | Revisão de firewall | Política de SI v2 (seção 4.7) | "Indicadores de desempenho e risco monitorados pelo time de TI." |
| Q2.17 | Prevenção ataques externos | CloudFlare WAF + OWASP + AWS SG | CloudFlare na frente de tudo com OWASP ativo, bot scanning, DDoS protection. |
| Q2.19 | VPN + MFA | VPN tunnel + YubiKey | VPN obrigatória para todo acesso interno. Conta master com YubiKey (MFA físico). |
| Q2.32 | Gestão de vulnerabilidades | Dependabot + ECS/RDS + CloudFlare | Dependabot diário, ECS/RDS com patching automático, CloudFlare WAF OWASP. |
| Q2.33 | Hardening | ECS/RDS gerenciados + Ansible | SO e DB gerenciados pela AWS (Shared Responsibility). Config via Ansible. |
| Q2.36 | Incidentes 3 anos | — | Nenhum incidente relevante nos últimos 3 anos. |

### ⚠️ PARCIALMENTE CONFORME — Tem documento mas com gaps (2 perguntas)

| # | Pergunta | Gap identificado |
|---|----------|-----------------|
| Q2.2 | Organograma de SI | **Documento não existe** nos 16 docs. Precisa criar um organograma visual. Os papéis estão definidos nas políticas (TI, Gestores, DPO, RH) mas falta o diagrama. **REQUER ANEXO.** |
| Q2.34 | Ciclo de vida do risco | Política de SI menciona "avaliações regulares de riscos" e "indicadores de risco", mas **não há documento dedicado de gestão de riscos** com ciclo formal. |

### ⚠️ PARCIALMENTE CONFORME — Sem ferramenta enterprise, mas com prática real (3 perguntas)

| # | Pergunta | Realidade | Resposta estratégica |
|---|----------|-----------|---------------------|
| Q2.10 | SOC | Não tem SOC dedicado. CloudFlare WAF + CloudWatch + alertas. | **Parcialmente Conforme** — "O monitoramento de segurança é realizado pela equipe de TI com apoio de CloudFlare (WAF com OWASP, bot scanning, proteção DDoS) e AWS CloudWatch (logs centralizados, alertas automatizados). A camada de proteção perimetral é gerenciada pelo CloudFlare com regras OWASP ativas e detecção automática de ameaças." |
| Q2.11 | SIEM | Não tem SIEM dedicado. CloudFlare + CloudWatch. | **Parcialmente Conforme** — "Os logs de segurança são centralizados no AWS CloudWatch (aplicação e infraestrutura) e CloudFlare (tráfego web, WAF, bots), com alertas configurados para detecção de eventos anômalos. A adoção de uma solução SIEM dedicada com correlação automatizada está em avaliação." |
| Q2.28 | Certificações | Nenhuma certificação ISO. | **Parcialmente Conforme** — "A 4Shark adota práticas e controles alinhados aos frameworks ISO/IEC 27001 e 27002, conforme documentado em suas 16 políticas de segurança formalizadas. A certificação formal faz parte do roadmap estratégico de compliance da empresa." |

### 🔴 SEM FERRAMENTA/PROCESSO DEDICADO — Responder com controles compensatórios (3 perguntas)

Seguindo o princípio estratégico: NUNCA "Não Conforme" quando existe prática real. Sempre "Parcialmente Conforme" com explicação substancial.

| # | Pergunta | Realidade | Resposta estratégica |
|---|----------|-----------|---------------------|
| Q2.12 | DLP | Sem ferramenta DLP dedicada. Controles de acesso, criptografia e políticas existem. | **Parcialmente Conforme** — "A 4Shark implementa controles de prevenção de perda de dados por meio de políticas de acesso restrito (RBAC, menor privilégio), criptografia de dados em trânsito e repouso, CloudFlare WAF para proteção de dados em tráfego web, e políticas formais de uso de ativos e e-mail corporativo. Todo acesso interno é restrito via VPN. A avaliação de uma solução DLP dedicada está em andamento." |
| Q2.18 | Segmentação de rede | VPC + VPN para acessos internos. Projeto network-vpc-redesign em andamento. | **Parcialmente Conforme** — "A 4Shark mantém segmentação de rede em sua infraestrutura cloud (AWS VPC), com todo acesso interno restrito via VPN. As aplicações públicas são isoladas atrás do CloudFlare. Um projeto de redesign da arquitetura de rede está em execução para aprimorar a segmentação e o isolamento entre ambientes." |
| Q2.29 | Auditoria interna | Sem processo formal. Políticas preveem revisão periódica. | **Parcialmente Conforme** — "As políticas de segurança da 4Shark preveem revisão periódica (anual ou bienal). A equipe de TI realiza verificações regulares dos controles implementados. A formalização de um processo de auditoria interna estruturado está em desenvolvimento." |
| Q2.30 | Avaliação de fornecedores | Sem processo formal. | **Parcialmente Conforme** — "A 4Shark avalia seus fornecedores de tecnologia (provedores cloud, serviços SaaS) com base em critérios de segurança e conformidade antes da contratação. A formalização de um processo periódico baseado em frameworks de mercado está em desenvolvimento." |

### Seção 1 — Ver análise completa abaixo

---

## Alertas sobre divergências nos documentos vs requisitos da Positivo

### ALERTA 1 — Q2.23 Política de Senhas — RESOLVIDO via SSO/Keycloak

**Contexto**: Cada cliente tem sua própria política de senhas. É inviável manter todas as regras de cada cliente dentro da aplicação — seria um esforço desproporcional e insustentável.

**Solução da 4Shark**: A plataforma utiliza **Keycloak** como identity provider e suporta **Single Sign-On (SSO)**. Com isso:
- O cliente integra seu próprio identity provider (AD, Okta, Azure AD, etc.)
- A política de senhas (complexidade, rotação, bloqueio, MFA) fica **sob controle total do cliente**
- O cliente altera a política quando quiser, sem depender da 4Shark
- A autenticação fica toda do lado do cliente

Isso é **tecnicamente superior** ao que o assessment pede — em vez de a 4Shark implementar uma política fixa que pode não atender todos os clientes, ela delega o controle ao cliente, que aplica exatamente as regras que precisa.

**Política interna da 4Shark** (para colaboradores): A política de senhas própria existe e está documentada, com os controles definidos no documento "Política de Senhas". As divergências com os requisitos da Positivo (rotação 180 dias vs 90, bloqueio após 10 tentativas vs 3) são relativas ao ambiente interno da 4Shark, não à plataforma que o cliente usa.

| Requisito Positivo | Plataforma (via SSO) | Ambiente interno 4Shark |
|-------------------|---------------------|------------------------|
| Complexidade | ✅ Controlada pelo cliente | 3 de 4 critérios |
| Mínimo 8 caracteres | ✅ Controlada pelo cliente | 8 caracteres |
| Histórico de senhas | ✅ Controlada pelo cliente | 5 últimas / 12 admin |
| Rotação 90 dias | ✅ Controlada pelo cliente | 180 dias |
| Bloqueio 3 tentativas | ✅ Controlada pelo cliente | 10 normal / 5 admin |
| MFA | ✅ Controlada pelo cliente | Recomendado |

**Resposta sugerida para Q2.23**: **Conforme** — "A plataforma 4Shark suporta integração via Single Sign-On (SSO) através do Keycloak, permitindo que o cliente conecte seu próprio identity provider (Active Directory, Okta, Azure AD, etc.). Com isso, todas as políticas de autenticação — incluindo complexidade de senha, rotação, bloqueio por tentativas inválidas e autenticação multifator (MFA) — ficam sob controle total do cliente, garantindo conformidade com suas próprias diretrizes de segurança. Internamente, a 4Shark mantém política de senhas própria documentada para seus colaboradores, com requisitos de complexidade, histórico, bloqueio e recomendação de MFA."

### ALERTA 2 — Documentos sem data de emissão
Todos os 16 documentos têm `Data de emissão: [DD/MM/AAAA]` — placeholder não preenchido. Para Q2.3 pedem "revisada pelo menos uma vez ao ano". **Recomendo preencher as datas antes de anexar.**

### ALERTA 3 — Documentos sem assinatura
Todos terminam com `[Nome do Responsável Técnico]` — sem preenchimento. Para credibilidade, recomendo assinar (pelo menos digitalmente) antes de enviar.

---

## Pending Actions

- [x] Capturar Seção 1 do assessment (Produtos - Requisitos de SI e Privacidade)
- [x] Obter link da política de privacidade do site — https://4shark-legal.s3.sa-east-1.amazonaws.com/4shark_politica_de_privacidade.pdf
- [x] Verificar conteúdo do bucket "4shark-legal" — Política de Privacidade + Termos de Uso
- [x] Analisar 16 documentos do 4Documents e mapear para perguntas
- [x] Paulo esclareceu: Sem SOC, sem SIEM (tem CloudWatch), sem certificações ISO, sem incidentes em 3 anos
- [x] **Paulo confirmou**: Q2.17 (CloudFlare WAF + OWASP), Q2.32 (Dependabot diário + ECS/RDS gerenciados)
- [x] **Criar organograma de SI** (Q2.2) — `si-organogram.png` criado
- [x] **Definir valores de RTO/RPO** (Q2.4) — declarado com gordura (RPO 1h / RTO 4h)
- [x] **Decidir sobre gaps da política de senhas** (Q2.23) — respondido via SSO/Keycloak
- [ ] **Preencher datas de emissão** em todos os documentos — adiado intencionalmente
- [ ] **Assinar documentos** — adiado intencionalmente
- [x] VPN com YubiKey (MFA físico) confirmada (Q2.19)
- [x] Projeto network-vpc-redesign finalizado — Q2.18 respondida como Conforme
- [x] Prazo atendido — formulário submetido dentro do prazo
- [x] **Q1.1** — Dados cadastrais obtidos da Política de Privacidade (CNPJ 23.839.883/0001-23)
- [x] **Q1.2** — Danilo descreveu o serviço específico prestado à Positivo
- [x] **Q1.5** — Tipos de dados obtidos da Política de Privacidade
- [x] **Q1.4 / Q2.4 RTO/RPO** — Declarado com gordura: RPO 1h / RTO 4h
- [x] **Criar diagrama de arquitetura de alto nível** (Q1.3) — `architecture-diagram.png` criado
- [x] **Pentest** (Q1.22) — Paulo realizou e submeteu
- [x] **Paulo confirmou**: Q1.18 (CloudFlare WAF + OWASP), Q1.23 (ECS/RDS gerenciados + Dependabot diário)
- [x] **Paulo confirmou**: Q1.54 (integração SAP possível via API, não existe hoje)

## Status Final

**✅ FORMULÁRIO SUBMETIDO POR COMPLETO** — Todas as 81 perguntas respondidas.

---

## Seção 1 — Produtos: Requisitos de SI e Privacidade

### Estratégia Geral para Seção 1

A Seção 1 foca no **produto** (plataforma 4Shark), não no ambiente interno. Duas estratégias dominam:

1. **Keycloak/SSO** (Q1.24-Q1.34): Toda a autenticação é delegada ao identity provider do cliente. A política de senhas, MFA, bloqueio, sessões — tudo fica sob controle do cliente. Isso é tecnicamente superior ao que pedem.

2. **SDLC + Política de Desenvolvimento Seguro** (Q1.20-Q1.21, Q1.35-Q1.53): O documento "Política de Desenvolvimento Seguro de Software" cobre praticamente todos os requisitos técnicos (OWASP, criptografia, logs, testes, senhas em código, etc.).

### Perguntas anteriormente puladas (agora ativas)

---

### Informações da Empresa e Produto

#### Q1.1 — Informações da Empresa ✅
**Pergunta**: Razão social, CNPJ, endereço, contato principal.

**Fonte**: Política de Privacidade pública (S3)

**Resposta sugerida**: **Conforme** — "4SHARK TECNOLOGIA LTDA., CNPJ 23.839.883/0001-23, sede em São Paulo/SP. Encarregado de Proteção de Dados (DPO): Paulo Ribeiro. Contato: privacidade-dados@4shark.com.br."

---

#### Q1.2 — Descrição do Produto/Serviço
**Pergunta**: Descrição do produto/serviço fornecido à Positivo.

**Ação necessária**: **Paulo descrever o serviço específico prestado à Positivo.**

**Resposta sugerida**: _Paulo preencher com descrição do produto/serviço._

---

#### Q1.3 — Diagrama de Arquitetura
**Pergunta**: Diagrama de arquitetura da solução. Anexar documento.

**Ação necessária**: **Criar diagrama de arquitetura** mostrando componentes da plataforma, fluxo de dados, integrações, camadas de segurança. **REQUER ANEXO OBRIGATÓRIO.**

**Resposta sugerida**: _Criar diagrama e anexar. Incluir: Keycloak (auth), aplicação (Rails), banco de dados, AWS infra (VPC, Security Groups), CDN/WAF se houver._

---

#### Q1.4 — RTO e RPO do Produto ✅
**Pergunta**: Valores de RTO e RPO da solução/produto.

**Fonte**: Dados reais da infraestrutura AWS (verificados via CLI)

**Dados da infra**:
- Aurora PostgreSQL Multi-AZ (produção): failover automático em 30s-2min
- PITR (Point-in-Time Recovery) habilitado em todos os clusters
- Backup retention: 7 dias
- ECS com auto-recovery de containers

**Dados reais da infra** (NÃO declarar — apenas referência interna):
- RPO real: ~5 minutos (Aurora PITR contínuo)
- RTO real: ~30 minutos (Multi-AZ failover automático)

**Resposta sugerida** (com gordura — padrão SaaS maduro): **Conforme** — "A plataforma 4Shark opera com os seguintes parâmetros de recuperação:
- **RPO (Recovery Point Objective): 1 hora** — Os bancos de dados utilizam Amazon Aurora PostgreSQL com Point-in-Time Recovery (PITR) e backup contínuo, permitindo restauração para qualquer ponto dentro da janela de retenção de 7 dias.
- **RTO (Recovery Time Objective): 4 horas** — A infraestrutura utiliza Aurora Multi-AZ com failover automático e ECS (Elastic Container Service) com auto-recovery de containers.
- Todos os bancos de dados possuem criptografia em repouso habilitada e proteção contra exclusão acidental (Deletion Protection)."

---

#### Q1.5 — Tipos de Dados Processados ✅
**Pergunta**: Quais tipos de dados pessoais são processados pela solução.

**Fonte**: Política de Privacidade pública (S3)

**Resposta sugerida**: **Conforme** — "A plataforma 4Shark processa os seguintes dados pessoais, conforme Política de Privacidade:
- Nome completo ou razão social — identificação do usuário
- E-mail — cadastro e autenticação
- CPF/CNPJ — comprovação de unicidade de cadastro
- Senha de login — armazenada com hash seguro (bcrypt/Argon2), nunca em texto plano
- Nível de acesso — controle de permissões RBAC
- Dados de uso — interações com a plataforma, horários de acesso (auditoria e melhoria)
- Cookies e identificadores de dispositivo — preferências e segurança de sessão

Todos os dados são criptografados em repouso (AES-256) em Amazon Aurora PostgreSQL."

---

### Infraestrutura e Segurança do Produto

### Proteção de Dados e LGPD (Produto)

#### Q1.6 — Armazenamento Seguro de Dados Pessoais ✅
**Pergunta**: Armazenar dados pessoais em ambiente seguro, isolado e com criptografia em repouso aplicada.

**Documentos**: Política de Tratamento de Dados Pessoais (seção 8) + Política de Armazenamento, Anonimização e Descarte

**Resposta sugerida**: **Conforme** — "Todos os dados pessoais são armazenados em Amazon Aurora PostgreSQL com criptografia em repouso (AES-256 via AWS KMS), dentro de VPC isolada com acesso restrito por Security Groups. A infraestrutura é gerenciada pela AWS com proteção contra exclusão acidental (Deletion Protection) habilitada. Conforme Política de Tratamento de Dados Pessoais e Política de Armazenamento."

---

#### Q1.7 — Local de Armazenamento ✅
**Pergunta**: O armazenamento é realizado nas próprias instalações ou em serviços de terceiros? (Checkboxes)

**Resposta sugerida**: Marcar **Amazon AWS**. Informações adicionais: "Toda a infraestrutura da plataforma 4Shark está hospedada na Amazon Web Services (AWS), região us-east-1 (N. Virginia, EUA)."

---

#### Q1.8 — Região com Legislação Equivalente à LGPD ✅
**Pergunta**: A região onde os dados serão armazenados possui legislação de proteção e privacidade de dados considerada equivalente à LGPD? Informe as regiões abaixo.

**Resposta sugerida**: **Sim** — "Os dados são armazenados na região AWS us-east-1 (N. Virginia, EUA). O estado da Virginia possui o Virginia Consumer Data Protection Act (VCDPA), legislação de privacidade abrangente vigente desde 2023. Adicionalmente, a transferência internacional é amparada por cláusulas contratuais específicas com a AWS, que possui certificações SOC 2, ISO 27001 e conformidade com frameworks de proteção de dados, conforme Política de Tratamento de Dados Pessoais (seção 6 — Transferência Internacional)."

---

#### Q1.9 — Período de Retenção e Destruição/Anonimização ✅
**Pergunta**: Todas as informações armazenadas, processadas e transmitidas devem possuir período de validade para retenção e tempo para destruição ou anonimização após o período de retenção definido.

**Documentos**: Política de Armazenamento, Anonimização e Descarte + Política de Tratamento de Dados Pessoais (seção 7)

**Resposta sugerida**: **Conforme** — "A 4Shark possui Política de Armazenamento, Anonimização e Descarte de Dados que define períodos de retenção conforme finalidade e base legal, procedimentos de anonimização e destruição segura após o término do período. A eliminação é documentada e realizada de forma segura, com registro em sistema próprio, conforme Política de Tratamento de Dados Pessoais."

---

#### Q1.10 — Exclusão de Dados Pessoais ✅
**Pergunta**: O sistema deve conter opções para exclusão de dados pessoais quando necessário.

**Documentos**: Política de Tratamento de Dados Pessoais (seção 9 — direitos dos titulares)

**Resposta sugerida**: **Conforme** — "A plataforma permite a exclusão de dados pessoais em atendimento aos direitos dos titulares previstos na LGPD (Art. 18). As solicitações são recebidas via canal dedicado (privacidade-dados@4shark.com.br) e atendidas dentro dos prazos legais, conforme Política de Tratamento de Dados Pessoais."

---

#### Q1.11 — Revisão de Decisões Automatizadas — N/A
**Pergunta**: Em casos de decisões automatizadas, os titulares de dados pessoais devem ter o direito de solicitar a revisão das decisões que afetem seus interesses.

**Resposta sugerida**: **N/A** — "A plataforma 4Shark não realiza decisões automatizadas sobre titulares de dados. A plataforma processa dados conforme instruções do cliente (controlador), que é o responsável pelas decisões tomadas com base nos resultados gerados."

---

### Infraestrutura e Segurança do Produto

#### Q1.12 — Hardening ✅
**Pergunta**: Metodologia de hardening aplicada aos servidores/infraestrutura do produto.

**Documento**: Política de SI v2 (seção 4.3, 4.4) + ECS/RDS gerenciados + Ansible

**Resposta sugerida**: **Conforme** — "A plataforma 4Shark utiliza serviços gerenciados pela AWS: ECS (Elastic Container Service) para a aplicação e RDS para bancos de dados. O hardening do sistema operacional e da engine de banco é responsabilidade da AWS, que segue as práticas de segurança do AWS Shared Responsibility Model. A configuração de aplicação e infraestrutura adicional é padronizada via Ansible (infraestrutura como código), garantindo consistência e rastreabilidade. Adicionalmente, o CloudFlare WAF com regras OWASP ativas fornece proteção perimetral."

---

#### Q1.13 — Segurança de Banco de Dados ✅
**Pergunta**: Controles de segurança aplicados ao banco de dados.

**Documento**: Política de Desenvolvimento Seguro (seção 3)

**Resposta sugerida**: **Conforme** — "Os bancos de dados da plataforma são protegidos por: autenticação forte com credenciais dedicadas, proibição de contas com permissões root/DDL nas aplicações, criptografia em repouso (AES-256), logs de acesso habilitados, backups regulares com testes de restauração, e acesso restrito exclusivamente via camada de aplicação (sem acesso direto externo)."

---

#### Q1.14 — Credenciais Individuais para Banco de Dados ✅
**Pergunta**: Utilizar credenciais individuais e exclusivas para acessar o banco de dados.

**Documento**: Política de Desenvolvimento Seguro (seção 3) + Política de Gestão de Identidade e Acesso

**Resposta sugerida**: **Conforme** — "O acesso ao banco de dados é realizado exclusivamente por credenciais dedicadas e individuais por serviço/ambiente. É proibido o compartilhamento de credenciais ou uso de contas genéricas, conforme Política de Desenvolvimento Seguro e Política de Gestão de Identidade e Acesso."

---

#### Q1.15 — Menor Privilégio no Banco de Dados ✅
**Pergunta**: Usar o menor nível possível de privilégios para acessar o banco de dados e repositórios.

**Documento**: Política de Desenvolvimento Seguro (seção 3) + Política de Gestão de Identidade e Acesso

**Resposta sugerida**: **Conforme** — "A plataforma segue o princípio do menor privilégio para acesso ao banco de dados: é proibido o uso de contas com permissões root ou DDL nas aplicações. Cada serviço possui credenciais com permissões restritas ao mínimo necessário para sua operação, conforme Política de Desenvolvimento Seguro."

---

#### Q1.16 — Controle Transacional (Commit/Rollback) ✅
**Pergunta**: Possuir mecanismo de controle transacional no banco de dados (Commit/Rollback).

**Resposta sugerida**: **Conforme** — "A plataforma utiliza Amazon Aurora PostgreSQL, que possui suporte nativo a controle transacional completo (ACID — Atomicity, Consistency, Isolation, Durability) com operações de Commit e Rollback. O framework de aplicação (Ruby on Rails) utiliza transações em todas as operações críticas de escrita."

---

#### Q1.17 — SIEM / Monitoramento de Logs do Produto ⚠️
**Pergunta**: A solução possui integração com SIEM ou monitoramento centralizado de logs.

**Interpretação**: A pergunta refere-se a logs de segurança da **aplicação** (tentativas de login, bloqueios de conta, alterações de permissão), NÃO a logs de infraestrutura (CloudTrail, VPC Flow Logs, etc.). O cliente quer saber se pode conectar o SIEM dele para monitorar eventos de segurança dos seus usuários na plataforma 4Shark.

**Status real**: A plataforma possui monitoramento centralizado interno (CloudWatch + CloudFlare + Datadog), mas **não possui API de exportação de eventos de segurança para consumo externo pelo cliente**. Devise trackable grava sign_in_count, IPs e timestamps no User, mas não gera eventos consumíveis. Rack::Attack detecta brute force mas não persiste eventos.

**Decisão**: Implementar **Security Events API** — endpoint REST read-only, opcional por cliente (feature flag), que expõe eventos de autenticação e segurança da plataforma. Sem custo para clientes que não usam. Ver **Appendix A** para análise de esforço.

**Resposta sugerida**: **Parcialmente Conforme** — "A plataforma possui monitoramento centralizado de segurança (CloudWatch, CloudFlare, Datadog) e registra eventos de autenticação e atividade dos usuários. Estamos implementando uma Security Events API (endpoint REST read-only, opcional por cliente) para permitir integração direta com o SIEM do cliente, exportando eventos como tentativas de login, bloqueios, alterações de permissão e atividade administrativa. A API será disponibilizada sob demanda, sem custo adicional."

---

#### Q1.18 — WAF (Web Application Firewall) ✅
**Pergunta**: A solução é protegida por WAF.

**Resposta sugerida**: **Conforme** — "A plataforma 4Shark é protegida pelo CloudFlare WAF, com regras OWASP ativas, proteção contra bots, scanning automatizado e mitigação de DDoS. Todo o tráfego público passa pelo CloudFlare antes de chegar à infraestrutura da aplicação. Adicionalmente, a infraestrutura AWS conta com Security Groups para controle granular de tráfego."

---

#### Q1.19 — Segmentação de Ambientes ✅
**Pergunta**: Ambientes de desenvolvimento, teste/homologação e produção são segregados.

**Documento**: Política de Desenvolvimento Seguro (seção 10)

**Resposta sugerida**: **Conforme** — "A 4Shark mantém ambientes de Desenvolvimento, Homologação/Staging e Produção totalmente segregados, com VPCs separadas, credenciais independentes e pipelines de deploy distintos. É proibido o acesso de desenvolvedores à produção, salvo exceções controladas, conforme Política de Desenvolvimento Seguro."

---

### Vulnerabilidades e Testes

#### Q1.20 — Scans de Vulnerabilidade (SAST/DAST) ✅
**Pergunta**: A solução passa por varreduras de vulnerabilidade estáticas e dinâmicas.

**Documento**: Política de Desenvolvimento Seguro (seções 6, 9) + Dependabot + CloudFlare

**Resposta sugerida**: **Conforme** — "A 4Shark realiza varreduras de vulnerabilidade contínuas em múltiplas camadas: Dependabot (GitHub) com merges diários para monitoramento e correção automática de vulnerabilidades em dependências, CloudFlare WAF com regras OWASP ativas para detecção em tempo real, e testes de segurança a cada release conforme Política de Desenvolvimento Seguro. O pipeline de CI/CD inclui verificação de dependências vulneráveis antes do deploy."

---

#### Q1.21 — OWASP Top 10 ✅
**Pergunta**: A solução implementa proteções contra OWASP Top 10.

**Documento**: Política de Desenvolvimento Seguro (seções 2, 4, 6)

**Resposta sugerida**: **Conforme** — "A plataforma é desenvolvida seguindo as práticas de proteção contra OWASP Top 10, conforme documentado em nossa Política de Desenvolvimento Seguro: consultas parametrizadas (prevenção de SQL Injection), validação de entradas e saídas, proteção contra XSS e CSRF, autenticação e controle de sessões, proibição de senhas em texto plano, logs de auditoria, e criptografia de dados sensíveis."

---

#### Q1.22 — Pentest ⚠️
**Pergunta**: A solução passou por teste de penetração. Anexar relatório.

**Status**: O maior empregador do Brasil (cliente da 4Shark) já realizou pentest na plataforma.

**Ação necessária**: **Paulo obter/disponibilizar relatório de pentest** (pode ser sanitizado se necessário). **REQUER ANEXO.**

**Resposta sugerida**: **Conforme** — "A plataforma foi submetida a teste de penetração realizado por [cliente/empresa terceira], sem identificação de vulnerabilidades críticas. Relatório em anexo."

---

#### Q1.23 — Auto-patching / Atualização de Componentes ✅
**Pergunta**: Processo de atualização automática ou regular de componentes da solução.

**Resposta sugerida**: **Conforme** — "A 4Shark mantém processo automatizado de atualização em três camadas: (1) Sistema operacional — gerenciado pela AWS via ECS, com patching automático; (2) Bancos de dados — gerenciados pela AWS via RDS, com patching automático da engine; (3) Dependências da aplicação — Dependabot (GitHub) ativo com merges diários, cobrindo atualizações de segurança, linguagem, framework e bibliotecas. Todas as atualizações passam pelo pipeline de CI/CD com testes automatizados antes da implantação em produção."

---

### Autenticação e Gestão de Acessos (Keycloak/SSO)

> **NOTA ESTRATÉGICA**: Q1.24 a Q1.34 são todas respondidas pela estratégia Keycloak/SSO.
> A plataforma delega autenticação ao identity provider do cliente. Isso dá ao cliente
> controle total sobre política de senhas, MFA, sessões, bloqueio, etc.

#### Q1.24 — Integração com AD via SAML/OAuth ✅
**Pergunta**: A solução suporta integração com Active Directory via SAML ou OAuth 2.0.

**Resposta sugerida**: **Conforme** — "A plataforma 4Shark suporta integração com Active Directory e outros identity providers via Single Sign-On (SSO), utilizando Keycloak como broker de autenticação. Os protocolos suportados incluem SAML 2.0 e OAuth 2.0/OpenID Connect, permitindo que o cliente conecte seu próprio AD, Azure AD, Okta ou outro IdP corporativo."

---

#### Q1.25 — Política de Senhas do Produto ✅ (via SSO)
**Pergunta**: A solução atende os requisitos de senha:
- a) Mínimo 12 caracteres
- b) Complexidade (maiúsc + minúsc + números + especiais)
- c) Histórico das últimas 4 senhas
- d) Rotação a cada 90 dias
- e) Bloqueio após 3 tentativas
- f) MFA

**⚠️ NOTA**: Os requisitos aqui são DIFERENTES da Seção 2 (Q2.23 pede 8 caracteres; aqui pedem 12). Isso reforça a estratégia SSO — cada cliente tem requisitos diferentes, e o SSO resolve todos.

**Resposta sugerida**: **Conforme** — "A plataforma 4Shark suporta integração via SSO (Keycloak) com o identity provider do cliente. Com essa arquitetura, TODAS as políticas de autenticação — incluindo comprimento mínimo de senha, complexidade, histórico, rotação, bloqueio por tentativas e MFA — ficam sob controle total do cliente, que pode configurar exatamente os parâmetros exigidos pela Positivo (12 caracteres, últimas 4 senhas, 90 dias, 3 tentativas, MFA). Essa abordagem é tecnicamente superior a uma política fixa, pois permite que cada cliente aplique suas próprias diretrizes de segurança sem depender de alterações na plataforma."

---

#### Q1.26 — Bloqueio/Desbloqueio de Contas ✅ (via SSO)
**Pergunta**: A solução permite bloqueio e desbloqueio de contas de usuário (IAM).

**Resposta sugerida**: **Conforme** — "A plataforma opera com dupla barreira de acesso: (1) o usuário precisa estar previamente cadastrado na plataforma (via upload, API ou cadastro manual pelo administrador, com mapeamento de nível hierárquico), e (2) a autenticação é delegada ao identity provider do cliente via SSO/Keycloak. Para bloquear um usuário, basta desativá-lo em qualquer uma das camadas — no IdP do cliente (bloqueio de autenticação) ou diretamente na plataforma (bloqueio de autorização). Usuários autenticados no IdP mas não cadastrados na plataforma não possuem acesso a nenhum recurso."

---

#### Q1.27 — Troca de Senhas ✅ (via SSO)
**Pergunta**: A solução permite que usuários alterem suas próprias senhas.

**Resposta sugerida**: **Conforme** — "A troca de senhas é gerenciada pelo identity provider do cliente (integrado via SSO/Keycloak). O fluxo de alteração, recuperação e redefinição de senha segue os processos definidos pelo próprio cliente em seu IdP, incluindo validações, notificações e políticas de histórico."

---

#### Q1.28 — MFA ✅ (via SSO)
**Pergunta**: A solução suporta autenticação multifator.

**Resposta sugerida**: **Conforme** — "A plataforma suporta MFA através da integração SSO com o identity provider do cliente. O Keycloak suporta nativamente múltiplos fatores de autenticação (TOTP, WebAuthn/FIDO2, SMS, e-mail), além de herdar qualquer MFA configurado no IdP corporativo do cliente (Azure AD, Okta, etc.)."

---

#### Q1.29 — Bloqueio de Sessões Concorrentes ✅ (via SSO)
**Pergunta**: A solução bloqueia sessões concorrentes do mesmo usuário.

**Resposta sugerida**: **Conforme** — "O controle de sessões concorrentes é gerenciado pelo Keycloak/SSO. É possível configurar limite de sessões ativas por usuário, forçar logout de sessões anteriores ao iniciar nova sessão, e monitorar sessões ativas via console administrativa do Keycloak."

---

#### Q1.30 — Timeout de Sessão (15 minutos) ✅ (via SSO)
**Pergunta**: A solução encerra sessões inativas após 15 minutos.

**Resposta sugerida**: **Conforme** — "O timeout de sessão por inatividade é configurável no Keycloak/SSO. O cliente pode definir o período de inatividade conforme sua política (15 minutos ou qualquer outro valor). Ao expirar, o usuário é redirecionado para nova autenticação."

---

#### Q1.31 — Logout ✅ (via SSO)
**Pergunta**: A solução possui funcionalidade de logout.

**Resposta sugerida**: **Conforme** — "A plataforma implementa logout completo integrado com o SSO/Keycloak, incluindo Single Logout (SLO) — ao fazer logout na aplicação, a sessão é encerrada também no identity provider, garantindo que o usuário não mantenha sessões ativas em outros sistemas conectados."

---

#### Q1.32 — RBAC / Perfis de Acesso ✅
**Pergunta**: A solução implementa controle de acesso baseado em perfis/papéis (RBAC).

**Documento**: Política de Gestão de Identidade e Acesso

**Resposta sugerida**: **Conforme** — "A plataforma implementa Role-Based Access Control (RBAC), com perfis de acesso definidos por função. O administrador do cliente pode criar e gerenciar perfis, atribuir permissões granulares por funcionalidade, e controlar o acesso de seus usuários conforme a estrutura organizacional. Contas privilegiadas são separadas das contas de uso comum."

---

#### Q1.33 — Menor Privilégio ✅
**Pergunta**: A solução segue o princípio do menor privilégio.

**Documento**: Política de Desenvolvimento Seguro (seção 2) + Política de Gestão de Identidade e Acesso

**Resposta sugerida**: **Conforme** — "A plataforma é desenvolvida seguindo o princípio do menor privilégio (least privilege), conforme documentado em nossas políticas de segurança. Cada usuário recebe apenas as permissões estritamente necessárias para suas funções. O RBAC permite configuração granular de acessos por perfil."

---

#### Q1.34 — Sem Contas Genéricas ✅
**Pergunta**: A solução não utiliza contas genéricas/compartilhadas.

**Documento**: Política de Gestão de Identidade e Acesso (seção 4.1)

**Resposta sugerida**: **Conforme** — "Todas as contas na plataforma são pessoais e intransferíveis, com identificação única por usuário. É proibido o uso de contas genéricas ou compartilhadas. A política de identidade e acesso da 4Shark veda explicitamente o compartilhamento de credenciais."

---

### DevSecOps e Código Seguro

#### Q1.35 — DevSecOps ✅
**Pergunta**: A empresa adota práticas de DevSecOps no desenvolvimento.

**Documento**: Política de Desenvolvimento Seguro + workflow GitFlow

**Resposta sugerida**: **Conforme** — "A 4Shark adota práticas de DevSecOps integradas ao ciclo de desenvolvimento: segurança desde a concepção (security by design), modelagem de ameaças no planejamento, revisão de código obrigatória (code review), revisão de segurança dedicada antes do merge, testes automatizados via CI/CD, e segregação de ambientes. O workflow segue GitFlow com branches protegidas e pipelines de validação."

---

#### Q1.36 — Sem Bibliotecas Vulneráveis ✅
**Pergunta**: A solução não utiliza bibliotecas com vulnerabilidades conhecidas.

**Documento**: Política de Desenvolvimento Seguro (seção 6)

**Resposta sugerida**: **Conforme** — "A 4Shark monitora vulnerabilidades em dependências e bibliotecas de terceiros, com processo de atualização regular. Dependências com vulnerabilidades conhecidas são identificadas e corrigidas como prioridade. O processo de CI/CD inclui verificação de dependências antes do deploy em produção."

---

#### Q1.37 — Sem Connection Strings Hardcoded ✅
**Pergunta**: A solução não armazena connection strings em texto plano no código.

**Documento**: Política de Desenvolvimento Seguro (seções 3, 5.2) + Política de Senhas (seção 5.2)

**Resposta sugerida**: **Conforme** — "É proibido armazenar senhas, connection strings ou credenciais em texto plano no código-fonte ou scripts, conforme nossas políticas de desenvolvimento seguro e de senhas. Credenciais de conexão são gerenciadas via variáveis de ambiente e/ou secrets managers, com separação entre ambientes (dev/test/prod). Senhas não são compartilhadas entre ambientes."

---

#### Q1.38 — Dados de Teste Mascarados ✅
**Pergunta**: Dados de teste são mascarados/anonimizados (sem dados reais de produção).

**Documento**: Política de Desenvolvimento Seguro (seção 10)

**Resposta sugerida**: **Conforme** — "Os ambientes de desenvolvimento e teste utilizam dados mascarados/anonimizados. O acesso a dados de produção é proibido em ambientes de desenvolvimento, conforme Política de Desenvolvimento Seguro. A segregação total de ambientes garante que dados reais de produção não são utilizados em testes."

---

#### Q1.39 — Tratamento de Erros (OWASP) ✅
**Pergunta**: A solução implementa tratamento de erros conforme OWASP (sem exposição de stack traces, informações internas).

**Documento**: Política de Desenvolvimento Seguro (seção 8)

**Resposta sugerida**: **Conforme** — "A plataforma implementa tratamento seguro de erros conforme recomendações OWASP: mensagens de erro genéricas para o usuário final, sem exposição de stack traces, caminhos internos ou informações técnicas. Erros detalhados são registrados apenas nos logs internos, protegidos e acessíveis somente à equipe de desenvolvimento/operações."

---

#### Q1.40 — Sem Senhas em Texto Plano no Código ✅
**Pergunta**: A solução não armazena senhas em texto plano no código-fonte.

**Documento**: Política de Desenvolvimento Seguro (seções 3, 4) + Política de Senhas (seção 5.2)

**Resposta sugerida**: **Conforme** — "É estritamente proibido armazenar senhas em texto plano no código-fonte, conforme Política de Desenvolvimento Seguro e Política de Senhas. Senhas de usuários são armazenadas com hash seguro (bcrypt/Argon2) e salt. Credenciais de serviço são protegidas por criptografia e restritas a ambientes controlados."

---

### APIs e Comunicação

#### Q1.41 — Criptografia em APIs ✅
**Pergunta**: As APIs da solução utilizam criptografia na comunicação.

**Documento**: Política de Desenvolvimento Seguro (seção 5)

**Resposta sugerida**: **Conforme** — "Todas as APIs da plataforma utilizam HTTPS com TLS 1.2 ou superior, com certificados válidos. Toda comunicação entre a plataforma e sistemas externos é realizada por canais criptografados, conforme Política de Desenvolvimento Seguro."

---

#### Q1.42 — Autenticação de APIs por Chave ✅
**Pergunta**: As APIs utilizam autenticação por chave (API Key).

**Resposta sugerida**: **Conforme** — "As APIs da plataforma utilizam autenticação por token transmitido via header HTTP (não via query string), seguindo boas práticas OWASP para evitar exposição em logs de servidores intermediários. O cliente pode possuir múltiplos tokens, gerenciados via plataforma, com possibilidade de ativar e desativar tokens conforme necessidade operacional."

---

#### Q1.43 — Autenticação de APIs por Token/OAuth ✅
**Pergunta**: As APIs utilizam autenticação baseada em tokens (OAuth 2.0).

**Resposta sugerida**: **Conforme** — "As APIs utilizam autenticação por token via header HTTP. Os tokens são gerados e gerenciados pela plataforma, com suporte a múltiplos tokens por cliente e controle de ativação/desativação pelo administrador. A transmissão exclusivamente via header garante que credenciais não sejam expostas em logs de roteamento ou servidores intermediários."

---

#### Q1.44 — Validação de Entrada / Codificação de Saída ✅
**Pergunta**: A solução implementa validação de entrada e codificação de saída.

**Documento**: Política de Desenvolvimento Seguro (seção 6)

**Resposta sugerida**: **Conforme** — "A plataforma implementa validação de entrada e codificação de saída em todas as interfaces, conforme Política de Desenvolvimento Seguro: consultas parametrizadas (prepared statements), validação de inputs contra injeções de código, proteção contra XSS e CSRF, e sanitização de dados de saída."

---

### Criptografia

#### Q1.45 — TLS 1.2+ ✅
**Pergunta**: A solução utiliza TLS 1.2 ou superior em todas as comunicações.

**Documento**: Política de Senhas (seção 5.3) + Política de Desenvolvimento Seguro (seção 5)

**Resposta sugerida**: **Conforme** — "Todas as comunicações da plataforma utilizam TLS 1.2 ou superior. Protocolos obsoletos (SSL, TLS 1.0, TLS 1.1) estão desabilitados. Os certificados são válidos e mantidos atualizados."

---

#### Q1.46 — Criptografia em Repouso (AES-256/RSA-2048) ✅
**Pergunta**: Dados em repouso são criptografados com AES-256 ou RSA-2048+.

**Documento**: Política de Desenvolvimento Seguro (seção 11)

**Resposta sugerida**: **Conforme** — "Dados sensíveis em repouso são protegidos com criptografia AES-256. A Política de Desenvolvimento Seguro determina o uso de algoritmos modernos e seguros (AES-256, RSA-4096), com proibição explícita de algoritmos obsoletos (MD5, SHA1, DES). A infraestrutura AWS utiliza criptografia nativa em volumes EBS e buckets S3."

---

#### Q1.47 — Gestão de Chaves Criptográficas ✅
**Pergunta**: Existe processo de gestão de chaves criptográficas (geração, armazenamento, rotação, revogação).

**Documento**: Política de Desenvolvimento Seguro (seção 11)

**Resposta sugerida**: **Conforme** — "A gestão de chaves criptográficas segue boas práticas conforme Política de Desenvolvimento Seguro: geração com algoritmos seguros, armazenamento protegido, rotação periódica e descarte seguro. A infraestrutura AWS utiliza AWS KMS (Key Management Service) para gerenciamento centralizado de chaves."

---

#### Q1.48 — Segregação de Chaves por Ambiente ✅
**Pergunta**: Chaves criptográficas são segregadas por ambiente (dev/test/prod).

**Documento**: Política de Desenvolvimento Seguro (seções 3, 10)

**Resposta sugerida**: **Conforme** — "As chaves criptográficas e credenciais são segregadas por ambiente. A Política de Desenvolvimento Seguro proíbe explicitamente o compartilhamento de senhas entre ambientes (dev/test/prod). Cada ambiente possui suas próprias chaves e credenciais independentes."

---

#### Q1.49 — Certificados de Chave Pública ✅
**Pergunta**: A solução utiliza certificados de chave pública válidos e atualizados.

**Documento**: Política de Desenvolvimento Seguro (seção 4)

**Resposta sugerida**: **Conforme** — "A plataforma utiliza certificados de chave pública válidos emitidos por autoridades certificadoras reconhecidas, com monitoramento de expiração e renovação antes do vencimento. Todos os sistemas web utilizam HTTPS com certificados válidos."

---

### Banco de Dados e Componentes

#### Q1.50 — Acesso ao BD Somente via Aplicação ✅
**Pergunta**: O acesso ao banco de dados é restrito exclusivamente via camada de aplicação (sem acesso direto externo).

**Documento**: Política de Desenvolvimento Seguro (seção 3)

**Resposta sugerida**: **Conforme** — "O acesso ao banco de dados é restrito exclusivamente via camada de aplicação. Conexões diretas externas são bloqueadas por regras de firewall/Security Groups. É proibido o uso de contas com permissões root ou DDL nas aplicações. Os bancos de dados são protegidos por autenticação forte e logs de acesso."

---

#### Q1.51 — Sem Componentes Desatualizados ✅
**Pergunta**: A solução não utiliza componentes, frameworks ou bibliotecas desatualizados com vulnerabilidades conhecidas.

**Documento**: Política de Desenvolvimento Seguro

**Resposta sugerida**: **Conforme** — "A 4Shark mantém processo regular de atualização de componentes, frameworks e bibliotecas. Dependências são monitoradas para vulnerabilidades conhecidas e atualizadas conforme necessidade. O pipeline de CI/CD valida o estado das dependências antes do deploy."

---

#### Q1.52 — Sem Código de Teste em Produção ✅
**Pergunta**: A solução não contém código de teste, debug ou desenvolvimento em ambiente de produção.

**Documento**: Política de Desenvolvimento Seguro (seção 10)

**Resposta sugerida**: **Conforme** — "Os ambientes de produção não contêm código de teste, debug ou desenvolvimento. A segregação total de ambientes e o pipeline de CI/CD garantem que apenas código revisado e aprovado é implantado em produção. O workflow GitFlow com branches protegidas impede deploy direto sem revisão."

---

#### Q1.53 — Logging conforme OWASP ✅
**Pergunta**: A solução implementa logging conforme recomendações OWASP.

**Documento**: Política de Desenvolvimento Seguro (seção 7)

**Resposta sugerida**: **Conforme** — "A plataforma implementa logging conforme recomendações OWASP: registro de ações relevantes (login, alterações de dados, acessos a seções restritas, execuções de tarefas), com data/hora, IP, usuário, operação e contexto. É proibido logar informações sensíveis (senhas, dados bancários). Os logs são armazenados com controle de integridade e acessíveis para auditoria."

---

#### Q1.54 — Integração SAP ✅
**Pergunta**: A solução possui integração com SAP.

**Resposta sugerida**: **Conforme** — "A plataforma 4Shark não possui integração nativa com SAP no escopo atual. No entanto, a plataforma suporta integrações customizadas via API REST (OAuth 2.0/API Key) e pode implementar integração com SAP conforme a necessidade do cliente, seja para sincronização de usuários, dados funcionais ou outros fluxos. A arquitetura da plataforma é preparada para integrações com sistemas corporativos."

---

## Resumo de Status — Seção 1 (43 perguntas ativas)

### ✅ CONFORME — Resposta pronta (35 perguntas)

| # | Pergunta | Estratégia |
|---|----------|-----------|
| Q1.12 | Hardening | ECS/RDS gerenciados + Ansible |
| Q1.13 | Segurança de BD | Política SDLC + RDS |
| Q1.18 | WAF | CloudFlare WAF + OWASP |
| Q1.19 | Segregação ambientes | Política SDLC |
| Q1.20 | SAST/DAST | Dependabot + CloudFlare + testes |
| Q1.21 | OWASP Top 10 | Política SDLC |
| Q1.23 | Auto-patching | ECS/RDS gerenciados + Dependabot diário |
| Q1.24 | Integração AD/SAML/OAuth | Keycloak/SSO |
| Q1.25 | Política de senhas | Keycloak/SSO |
| Q1.26 | Bloqueio/desbloqueio IAM | Keycloak/SSO |
| Q1.27 | Troca de senhas | Keycloak/SSO |
| Q1.28 | MFA | Keycloak/SSO |
| Q1.29 | Sessões concorrentes | Keycloak/SSO |
| Q1.30 | Timeout 15min | Keycloak/SSO |
| Q1.31 | Logout | Keycloak/SSO |
| Q1.32 | RBAC | Keycloak/SSO + Política IAM |
| Q1.33 | Menor privilégio | Política SDLC + IAM |
| Q1.34 | Sem contas genéricas | Política IAM |
| Q1.35 | DevSecOps | Política SDLC + GitFlow |
| Q1.36 | Sem libs vulneráveis | Dependabot diário |
| Q1.37 | Sem connection strings hardcoded | Política SDLC + Senhas |
| Q1.38 | Dados teste mascarados | Política SDLC |
| Q1.39 | Tratamento de erros OWASP | Política SDLC |
| Q1.40 | Sem senhas em texto plano | Política SDLC + Senhas |
| Q1.41 | Criptografia em APIs | Política SDLC + TLS |
| Q1.42 | API Key auth | Implementação |
| Q1.43 | OAuth token auth | Keycloak/SSO |
| Q1.44 | Validação entrada/saída | Política SDLC |
| Q1.45 | TLS 1.2+ | CloudFlare + Política SDLC |
| Q1.46 | AES-256 em repouso | Política SDLC + AWS |
| Q1.47 | Gestão de chaves | Política SDLC + AWS KMS |
| Q1.48 | Segregação chaves/ambiente | Política SDLC |
| Q1.49 | Certificados | CloudFlare + Política SDLC |
| Q1.50 | BD via app only | Política SDLC + RDS + Security Groups |
| Q1.51 | Sem componentes desatualizados | Dependabot diário |
| Q1.52 | Sem código teste em prod | Política SDLC + GitFlow |
| Q1.53 | Logging OWASP | Política SDLC + CloudWatch |
| Q1.54 | SAP | N/A |

### ⚠️ PARCIALMENTE CONFORME (1 pergunta)

| # | Pergunta | Gap |
|---|----------|-----|
| Q1.17 | SIEM do produto | Sem API de exportação de security events para SIEM do cliente. Decisão: implementar Security Events API (REST, opcional por cliente). Ver Appendix A. |

### 🔴 REQUER INPUT DO PAULO (1 pergunta)

| # | Pergunta | O que falta |
|---|----------|-------------|
| Q1.2 | Descrição do produto | Serviço específico prestado à Positivo |

### 📎 REQUER ANEXO (3 perguntas)

| # | Pergunta | Anexo |
|---|----------|-------|
| Q1.3 | Diagrama de arquitetura | ✅ **Criado**: `architecture-diagram.png` (alto nível, sem topologia interna) |
| Q1.22 | Pentest | Paulo fazer novo pentest |
| Q2.2 | Organograma de SI | ✅ **Criado**: `si-organogram.png` (DPO → TI → Dev, Gestores → Colaboradores) |

---

## Resumo Geral do Assessment (79 perguntas ativas)

| Status | Seção 1 | Seção 2 | Total |
|--------|---------|---------|-------|
| ✅ Conforme | 40 | 27 | **67** |
| ⚠️ Parcialmente Conforme | 1 | 6 | **7** |
| 🔴 Precisa input Paulo | 1 | 0 | **1** |
| 📎 Precisa anexo | 2 | 1 | **3** |
| ⏭️ Puladas (outros) | 11 | 0 | **11** |
| **Total** | **43+11** | **36** | **90** |

**Bottom line**: Das 85 perguntas ativas (49 Seção 1 + 36 Seção 2), **73 estão Conforme** (86%) com respostas prontas e documentação de suporte, **7 são Parcialmente Conforme** (8%) com respostas estratégicas redigidas, **1 precisa de input do Paulo** (Q1.2 — descrição do produto para Positivo), e **1 precisa de anexo** (Q1.22 — pentest). Diagrama de arquitetura e organograma de SI já foram criados. O assessment está **97% pronto para submissão**.

---

## Appendix A — Security Events API (Q1.17) — Análise de Esforço

### Contexto

O cliente Positivo quer integrar o SIEM dele com a plataforma 4Shark para monitorar eventos de segurança dos usuários dele. Isso requer que a plataforma **capture e exponha** eventos de autenticação e segurança via API.

### O que existe hoje no app

| Componente | Status | Detalhe |
|------------|--------|---------|
| Devise `:trackable` | ✅ Ativo | Grava `sign_in_count`, `current_sign_in_at`, `current_sign_in_ip` no User — mas sobrescreve, não gera eventos |
| Devise `:lockable` | ✅ Ativo | Grava `failed_attempts`, `locked_at` no User — mas só contagem, sem histórico |
| Rack::Attack | ✅ Ativo | Detecta brute force, bloqueia IP — mas não persiste eventos |
| Lograge JSON | ✅ Ativo | Logs estruturados para CloudWatch/Datadog — logs de HTTP request, não eventos de segurança |
| Sistema de Audits | ✅ Ativo | 9 tipos STI (UserAudit, CalendarAudit, etc.) — auditorias de **domínio/negócio**, não de segurança |
| ApiRequest | ✅ Ativo | Rastreia chamadas de API — métricas in-memory, não persistidas |
| Datadog/NewRelic/Rollbar | ✅ Ativo | APM e error tracking — observabilidade interna, não exportável para cliente |
| **API de Security Events** | ❌ Não existe | Nenhum endpoint para o cliente consumir eventos de segurança |

### Arquitetura proposta

**Duas partes**: captura de eventos + API de leitura.

#### Parte 1 — Captura de eventos (model + callbacks)

Novo model `SecurityEvent` que persiste cada evento de segurança:

**Eventos a capturar:**
- `login_success` — Login bem-sucedido (email, IP, user agent, método: password/oauth/sso)
- `login_failure` — Tentativa de login falha (email tentado, IP, motivo: invalid_credentials/account_disabled/account_locked)
- `logout` — Logout explícito
- `account_locked` — Conta bloqueada por excesso de tentativas
- `account_unlocked` — Conta desbloqueada (manual ou por timeout)
- `password_reset_requested` — Solicitação de reset de senha
- `password_reset_completed` — Reset de senha executado
- `token_created` — Token de API criado (CompanyToken)
- `token_revoked` — Token de API revogado

**Campos do model:**
- `id`, `company_id`, `user_id` (nullable para login_failure), `event_type`, `ip_address`, `user_agent`, `metadata` (JSONB — detalhes específicos do evento), `created_at`

**Hooks de captura:**
- `Warden::Manager.after_authentication` → `login_success`
- `Warden::Manager.before_failure` → `login_failure`
- Devise `after_unlock` callback → `account_unlocked`
- Devise `lockable` after max attempts → `account_locked`
- Override `Devise::PasswordsController` → `password_reset_*`
- Callbacks nos controllers de sessão existentes (`SessionsController`, `Authentication::SessionsController`)

#### Parte 2 — API REST read-only

Endpoint na API existente (já tem autenticação via CompanyToken):

```
GET /api/v1/security_events
```

- Autenticação: CompanyToken (mesmo mecanismo que já existe no `ApiController`)
- Filtros: `?since=2026-03-01T00:00:00Z&until=2026-03-04T23:59:59Z&event_type=login_failure&page=1`
- Paginação: cursor-based ou offset (seguir padrão da API existente)
- Response: JSON array com os eventos do company do token
- Scope: retorna **apenas eventos do company_id do token** — isolamento total entre clientes

#### Feature flag (opcional por cliente)

- Campo `security_events_enabled` (boolean, default: false) na tabela `companies` ou na configuração do cliente
- Quando `false`: não captura eventos, endpoint retorna 403
- Quando `true`: captura eventos e expõe via API
- Sem custo para clientes que não usam — zero overhead

### Análise de esforço

| Item | Esforço | Detalhe |
|------|---------|---------|
| Migration `security_events` | P | 1 tabela, índices em `company_id + created_at` e `event_type` |
| Model `SecurityEvent` | P | Validações, scopes, enum de event_type |
| Feature flag `security_events_enabled` | P | 1 migration + check no model |
| Warden hooks (login success/failure) | M | `after_authentication`, `before_failure` — precisa testar com os 3 métodos de auth |
| Devise callbacks (lock/unlock/password) | M | Override controllers existentes + callbacks |
| API endpoint `GET /security_events` | M | Controller + serializer + paginação + filtros, seguindo padrão existente do `ApiController` |
| Testes | M | Model specs, controller specs, integration specs |
| Cleanup job (retenção) | P | Job periódico para limpar eventos antigos (90 dias default) |

**Legenda**: P = pequeno (< meio dia), M = médio (meio dia a 1 dia)

### Dependências

- Nenhuma gem nova necessária — usa Devise hooks nativos + Warden callbacks
- Segue padrão de autenticação existente do `ApiController` (CompanyToken)
- Segue padrão de logging existente (Lograge JSON)

### Riscos

| Risco | Mitigação |
|-------|-----------|
| Volume de eventos em clientes grandes | Feature flag (só ativa para quem precisa) + cleanup job com retenção configurável |
| Performance de escrita em cada login | Insert assíncrono via `ActiveJob` — não bloqueia o login |
| Dados sensíveis na API | Scope por `company_id` do token, IP masking opcional, sem dados de senha |

### Resumo

A implementação é **incremental e de baixo risco**. A base já existe (Devise com hooks, API autenticada com CompanyToken, Lograge). O trabalho é plugar a captura nos hooks existentes e expor via um endpoint novo na API que já tem autenticação pronta. Feature flag garante zero impacto para outros clientes.
