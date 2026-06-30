# COMPLIANCE — Grupo Barigui (respostas para colar no Drive)

> **Como usar**: cada item abaixo corresponde a uma linha da planilha Google Drive (`https://docs.google.com/spreadsheets/d/1f97DiXq-Zbb31AZM1z90mIvDBjRGEVhyeIFt868WKe0`). Marcar "X" em **SIM** ou **NÃO** conforme indicado, e copiar/colar o texto da **OBS** na coluna correspondente.

---

## Dados da empresa (R10–R19)

| Campo | Valor |
|-------|-------|
| Razão Social | 4SHARK TECNOLOGIA LTDA. |
| Nome Fantasia | 4Shark |
| CNPJ | 23.839.883/0001-23 |
| Endereço | `<preencher>` |
| Bairro | `<preencher>` |
| Estado/Cidade | São Paulo/SP |
| Contato | `<preencher>` |
| E-mail | `<preencher>` |
| Site | https://www.4shark.com.br |

## Atividades (R21–R24)

| Campo | Valor |
|-------|-------|
| Início das Atividades | `<preencher>` |
| Número de Funcionários Próprios | `<preencher>` |
| Número de Funcionários Terceirizados | `<preencher>` |

## Headcount por departamento (R26–R35)

| Departamento | Quantidade de colaboradores |
|--------------|-----------------------------|
| `<preencher departamento 1>` | `<preencher>` |
| `<preencher departamento 2>` | `<preencher>` |
| `<preencher departamento 3>` | `<preencher>` |
| `<preencher departamento N>` | `<preencher>` |

## Informações Financeiras (R37–R41)

| Faturamento bruto anual | Valor |
|--------------------------|-------|
| 2025 | `<preencher>` |
| 2026 | `<preencher>` |
| Previsão para 2027 | `<preencher>` |

---

## Seção 1 — Governança e Segurança Organizacional [Domínio: Maturidade]

### R45 — Certificações formais (ISO 27001, SOC 2 Tipo II, PCI-DSS ou equivalente)

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark não possui certificações formais vigentes. Adota práticas e controles alinhados aos frameworks ISO/IEC 27001 e 27002, conforme documentado em seu conjunto de políticas internas de segurança da informação.

---

### R46 — Área formal de Segurança da Informação com estrutura, orçamento e reporte hierárquico documentados

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark não possui uma área de Segurança da Informação formalizada como departamento separado, com estrutura, orçamento e reporte hierárquico nos moldes de uma organização de grande porte. A responsabilidade por SI é exercida pela liderança técnica em conjunto com o DPO, com segurança mantida como prioridade na operação diária e integrada às decisões técnicas e de produto. Em 10 anos de operação não foi registrado incidente de vazamento de dados ou comprometimento de segurança.

---

### R47 — Responsável formalmente designado para SI/Privacidade (CISO, DPO, Encarregado LGPD)

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark possui Encarregado de Proteção de Dados (DPO) formalmente designado, conforme Política de Privacidade publicada em www.4shark.com.br:
- **Nome**: Paulo Ribeiro
- **Cargo**: Co-Founder & CTO / DPO
- **E-mail**: paulo@forcheck.com.br
- **Canal de privacidade**: privacidade-dados@4shark.com.br

---

### R48 — Políticas corporativas aprovadas pela alta direção, revisão documentada em ciclo máximo de 12 meses

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém um conjunto de políticas corporativas de segurança formalmente aprovadas pela liderança executiva, cobrindo os principais domínios de um programa de Segurança da Informação. As políticas preveem revisão anual.

---

### R49 — Política de classificação da informação (pública, interna, confidencial, restrita) com critérios de rotulagem e tratamento

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark classifica a informação por tipo: dados pessoais, dados pessoais sensíveis, credenciais de acesso, código-fonte, documentos operacionais internos e documentos públicos. Para cada tipo há regras específicas de tratamento, controle de acesso, armazenamento, retenção e descarte, definidas nas políticas internas correspondentes.

---

### R50 — Programa formal de treinamento e conscientização em segurança (frequência, temas, público, taxa de conclusão)

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark conduz orientação de segurança da informação no onboarding de todos os novos colaboradores, ministrada diretamente pela liderança técnica. A reciclagem ocorre anualmente. Os temas abordados incluem princípios de segurança da plataforma, LGPD, gestão de credenciais e uso do cofre corporativo, ameaças comuns (phishing, engenharia social) e processo de resposta a incidentes. O público-alvo é a totalidade dos colaboradores. O acompanhamento da conclusão é realizado pela liderança técnica.

---

### R51 — Programa formal e documentado de gestão de riscos de segurança com metodologia, responsáveis e ciclo de reavaliação

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark não possui um programa formal e documentado de gestão de riscos com metodologia estruturada, registro de riscos e ciclo formal de reavaliação periódica nos moldes de frameworks como ISO 31000. A avaliação de riscos é exercida continuamente pela liderança técnica, integrada às decisões de arquitetura, desenvolvimento e operação, com tratamento por criticidade refletido nas políticas internas. Em 10 anos de operação essa postura resultou em zero incidentes de segurança.

---

## Seção 2 — Privacidade e Proteção de Dados

### R53 — Política de privacidade alinhada à LGPD com ROPA, bases legais e direitos dos titulares

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém Política de Privacidade publicada em www.4shark.com.br, com cobertura das bases legais aplicáveis (Art. 7 e 11 LGPD) e dos direitos dos titulares (Art. 18). Não há documento único estruturado nos moldes formais de um ROPA — os elementos correspondentes (finalidades, bases legais, períodos de retenção, transferências e compartilhamentos) estão refletidos nas políticas internas de tratamento de dados pessoais.

---

### R54 — Dados pessoais criptografados em trânsito (TLS 1.2+) e em repouso (AES-256 ou equivalente)

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: 
- **Em trânsito**: TLS 1.2+ obrigatório em todas as comunicações externas, enforçado via CloudFlare. Versões inseguras (SSL 3.0, TLS 1.0, TLS 1.1) estão desabilitadas.
- **Em repouso**: AES-256 via AWS KMS no Amazon Aurora PostgreSQL (banco de dados primário) e no Amazon S3. A criptografia é gerenciada pela AWS conforme o AWS Shared Responsibility Model.

---

### R55 — Logs de acesso e eventos relacionados a dados pessoais retidos por período mínimo de 6 meses

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark está em fase final de desenvolvimento de funcionalidade que persistirá os eventos de autenticação (data, hora e IP de cada login) em banco de dados de produção, com retenção por período superior a 6 meses. Em seguida serão executados os ciclos de testes e validação antes da disponibilização em produção.

---

### R56 — Processo documentado de retenção, anonimização e descarte seguro de dados pessoais com evidência de execução

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark realiza anonimização irreversível dos dados pessoais de usuários após 5 anos e 1 mês contados da desativação do usuário no cliente, prazo definido com base no período prescricional aplicável ao vínculo entre o titular e o nosso cliente. A anonimização cobre todos os identificadores do usuário (nome, e-mail, CPF, demais identificadores fornecidos), sem possibilidade de reversão. Os dados pessoais são armazenados exclusivamente no banco de dados relacional Postgres; as demais camadas (MongoDB, Elasticsearch, Redis) operam apenas sobre identificadores internos, sem persistência de dados pessoais. Arquivos gerados por funcionalidades de extração são automaticamente descartados 48 horas após a geração. O processo é executado de forma sistemática, com registro auditável no banco de dados.

---

### R57 — Aceitar assinar Acordo de Processamento de Dados (DPA) com obrigações de suboperadores, notificação de incidentes e auditorias

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark aceita assinar Acordo de Processamento de Dados (DPA), incluindo cláusulas sobre suboperadores, notificação de incidentes envolvendo dados pessoais (conforme LGPD Art. 48) e direitos de auditoria, mediante revisão prévia do texto contratual proposto.

---

### R58 — Realiza transferências internacionais de dados? Em caso afirmativo, qual mecanismo de adequação?

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: Sim. Toda a infraestrutura da 4Shark — aplicação e bancos de dados — está hospedada na Amazon Web Services (AWS), região us-east-1 (Norte da Virgínia, EUA). O mecanismo de adequação utilizado é a celebração de cláusulas contratuais específicas com a AWS (AWS Data Processing Addendum), conforme LGPD Art. 33, inciso II. A AWS possui certificações SOC 2 Tipo II, ISO 27001 e ISO 27018, atendendo a frameworks reconhecidos internacionalmente de proteção de dados.

---

## Seção 3 — Controle de Acesso e Identidade (IAM) — Autenticação

### R61 — SSO federado com SAML 2.0, OAuth 2.0, OpenID Connect

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A solução utiliza Keycloak como Identity Provider e suporta autenticação federada via SSO com SAML 2.0, OAuth 2.0 e OpenID Connect (OIDC). O cliente pode conectar seu próprio provedor de identidade corporativo (Active Directory, Azure AD, Google Workspace, Okta, entre outros) e centralizar a gestão de autenticação no seu IDP.

---

### R62 — Quando SSO via Google Workspace estiver ativo, a solução respeita as políticas de MFA definidas no IDP corporativo, dispensando segundo fator redundante

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: Quando o cliente utiliza SSO (Google Workspace, Azure AD ou outro IDP corporativo), o Keycloak delega a autenticação ao IDP do cliente. Todas as políticas de MFA configuradas no IDP corporativo (incluindo Google Workspace) são respeitadas integralmente, sem solicitação de segundo fator redundante na plataforma 4Shark.

---

### R63 — Em cenários sem SSO, MFA obrigatório compatível com TOTP (RFC 6238) ou FIDO2

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark não impõe MFA obrigatório como exigência da plataforma em autenticação local. A arquitetura oferece dois caminhos adequados a perfis distintos de cliente:

- **Autenticação local**: a senha do usuário é protegida com hash criptográfico (algoritmo com 16 níveis de salt mais pepper, armazenamento irreversível), com regras de complexidade (mínimo 8 caracteres, combinação de letras maiúsculas, minúsculas, números e caracteres especiais) e credencial individual e intransferível por usuário.
- **Cenário corporativo via SSO**: clientes que demandam políticas avançadas (MFA obrigatório, rotação de senhas, bloqueio por tentativas) integram seu próprio provedor de identidade corporativo via Keycloak (SAML 2.0, OAuth 2.0, OpenID Connect, LDAP), e todas as políticas de autenticação passam a ser controladas pelo IDP corporativo.

---

### R64 — Provisionamento/desprovisionamento via grupos do Active Directory ou SCIM 2.0

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark não realiza provisionamento e desprovisionamento automatizados de usuários via grupos do Active Directory nem via SCIM 2.0. Essa limitação tem origem no modelo de dados da plataforma, que opera sobre uma estrutura organizacional hierárquica em múltiplos níveis: cada usuário precisa estar posicionado em uma árvore com gestor direto definido, cargo mapeado contra a estrutura hierárquica da plataforma e perfil de permissões correspondente. Sem essas três informações simultâneas, o usuário não pode ser criado em estado funcional — apenas como registro incompleto, incapaz de acessar dados, participar de fluxos ou ser visto pelos demais usuários da hierarquia.

Provedores de identidade corporativos (AD, Azure AD, Google Workspace) tipicamente armazenam apenas atributos planos de autenticação (nome, e-mail, departamento textual), sem expressar a hierarquia organizacional e a taxonomia de cargos no formato exigido pela plataforma. Por isso, o ciclo de vida de usuários é gerenciado por integração dedicada — um canal preparado para aplicar as regras de mapeamento de cargo, posicionamento hierárquico e atribuição de permissões necessárias para que cada usuário seja criado em estado utilizável desde a primeira sessão.

Esse modelo também separa o canal de autenticação (SSO/IDP) do canal de gestão da base de usuários (integração), garantindo precisão da base licenciada e ausência de usuários cadastrados ad hoc sem rastreabilidade.

---

## Seção 4 — Controle de Acesso e Identidade (IAM) — Identidade e Ciclo de Vida (ambiente 4Shark)

### R67 — MFA obrigatório para todos os colaboradores com acesso a produção, dados de clientes e sistemas críticos

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: Sim. O acesso a recursos de produção, dados de cliente e sistemas críticos da 4Shark é controlado por múltiplas camadas com autenticação multifator obrigatória:

- **E-mail corporativo (Google Workspace) com MFA obrigatório**, atuando como provedor de SSO central — sistemas integrados como Slack e demais ferramentas SaaS herdam essa autenticação, propagando o MFA do IDP.
- **Acesso à infraestrutura interna e a bancos de dados de produção exige VPN.** O banco não é acessível diretamente do dispositivo do colaborador — o acesso ocorre via servidor dedicado dentro da rede privada do respectivo sistema, com cada sistema operando em rede isolada.
- **Princípio do menor privilégio aplicado a todos os colaboradores, incluindo a liderança técnica.** Por padrão, as contas pessoais de engenheiros possuem permissão somente de leitura em recursos AWS. Para executar ações de mutação específicas, é necessário elevar privilégio temporariamente via MFA, com sessão limitada a uma hora — esse mecanismo cobre apenas um subconjunto restrito de operações.
- **Credenciais sensíveis** são armazenadas e compartilhadas exclusivamente via cofre corporativo (1Password), com MFA habilitado.
- **Toda a infraestrutura, incluindo a concessão de permissões e papéis IAM (AWS, GitHub, Google Workspace e demais sistemas integrados), é gerenciada como código (Terraform).** Cada alteração de permissão exige modificação no repositório de infraestrutura sob revisão de código, com trilha auditável por commit.
- **Operações administrativas amplas** (alterações de permissões de identidade, mudanças estruturais de infraestrutura) requerem uso de uma conta administrativa dedicada operada exclusivamente via chave física YubiKey (MFA hardware), sob custódia da liderança técnica. Essa conta funciona em modelo break-glass — usada apenas para o ato de aplicar mudanças, com trilha completa em git e logs de execução.

Esse desenho garante que qualquer concessão ou revogação de acesso a sistema crítico passe por aprovação rastreável e por chave física custodiada, eliminando a possibilidade de elevação de privilégio fora do processo.

---

### R68 — Solução de Privileged Access Management (PAM) para credenciais privilegiadas (admin, root, service accounts)

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark não utiliza uma solução PAM (Privileged Access Management) de mercado dedicada. As funções típicas de PAM — gestão centralizada, auditoria, rotação e controle de acesso a credenciais privilegiadas — são exercidas pela seguinte arquitetura:

- **Gestão centralizada**: toda permissão privilegiada (IAM AWS, GitHub, Google Workspace e demais sistemas integrados) é declarada como código em Terraform. Não há concessão manual fora desse canal — qualquer mudança passa por commit e revisão de código.
- **Auditoria**: cada alteração de permissão fica registrada no git, com autor, data e diff. Eventos de execução do stack de identidade são preservados em logs. O AWS CloudTrail registra todas as ações executadas na conta.
- **Acesso privilegiado just-in-time**: contas pessoais de engenheiros operam sob menor privilégio com permissão somente de leitura por padrão. A elevação para ações de mutação requer autenticação multifator e é limitada a sessão de uma hora. Operações administrativas amplas requerem uso da conta break-glass operada exclusivamente via chave física YubiKey.
- **Cofre de credenciais privilegiadas**: credenciais sensíveis (senhas de banco, chaves de API, tokens de serviço) são armazenadas no AWS Systems Manager Parameter Store, com criptografia gerenciada por KMS e acesso controlado por políticas IAM. Credenciais compartilhadas pela equipe humana são gerenciadas em cofre corporativo (1Password) com MFA.
- **Rotação de credenciais**: a rotação é executada via atualização do valor no Parameter Store — a credencial não trafega pelo código nem aparece em commits. Credenciais geridas nativamente pela AWS (tokens IAM via STS, segredos em Secrets Manager) seguem a rotação automática do provedor.

Em 10 anos de operação, essa arquitetura sustentou zero incidentes de comprometimento de credenciais ou de acesso não autorizado.

---

### R69 — Ciclo de vida de acessos gerenciado por processo formal com SLA documentado (revogação ≤24h após desligamento)

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: O ciclo de vida de acessos dos colaboradores 4Shark é executado de forma centralizada via infraestrutura como código:

- **Provisionamento**: ao integrar um novo colaborador, os acessos necessários (IAM AWS, GitHub, Google Workspace) são concedidos pela liderança técnica via alteração no Terraform, com cada concessão registrada em commit. O novo colaborador recebe conta no cofre corporativo (1Password) com credenciais individuais.
- **Revogação**: ocorre no momento do desligamento, com prazo efetivo dentro de 24 horas. Envolve remoção da conta dos provedores integrados (Google Workspace, AWS, GitHub) via Terraform, revogação imediata no cofre corporativo e desativação da conta de e-mail. A propagação para sistemas que dependem do SSO Google Workspace (Slack e demais SaaS integrados) é imediata após a desativação da identidade base.
- **Revisão periódica**: tratada em item específico (próxima pergunta).

---

### R70 — Recertificação periódica de acessos com frequência máxima semestral para usuários críticos e anual para demais

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark não executa um processo formal de recertificação periódica de acessos com cadência fixa (semestral/anual) nos moldes de um programa de access review enterprise. Em contrapartida, o desenho do controle de acesso elimina o cenário típico que motiva esse processo:

- **Menor privilégio é a norma transversal**: cada colaborador opera com o nível de permissão estritamente necessário à sua função em cada sistema. Em sistemas com privilégio elevado (AWS), o padrão é permissão somente de leitura para as contas pessoais, com elevação temporária via MFA (sessão limitada a uma hora) quando necessária. Em ferramentas operacionais (Monday, GitHub, Google Workspace), cada colaborador tem o nível de acesso adequado para a execução do seu trabalho, sem privilégios de administração.
- **Propriedade administrativa centralizada na break-glass**: em todos os sistemas SaaS integrados (AWS, GitHub, Google Workspace, 1Password, Monday e demais), a conta proprietária (owner/admin) é a conta break-glass, operada exclusivamente via chave física YubiKey. Nenhuma conta pessoal — incluindo a da liderança técnica — possui privilégio de administração desses sistemas em uso diário.
- **Sem acúmulo de privilégio**: como permissão administrativa não é o estado padrão, ela não persiste. Qualquer ação privilegiada é executada via elevação temporária com MFA ou via conta break-glass.
- **Visibilidade integral**: o conjunto completo de acessos de cada colaborador está declarado em código (Terraform), com revisão por commit em cada alteração e auditoria via git.
- A revisão pontual de acessos é executada em resposta a eventos organizacionais (mudança de papel, ingresso ou saída de colaborador), sustentada pela visibilidade integral provida pela infraestrutura como código.

---

## Seção 5 — Controle de Acesso e Identidade (IAM) — Integração por API

### R73 — APIs (REST, GraphQL, SOAP)? Como é a documentação e versionamento?

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A plataforma 4Shark expõe uma API REST documentada e versionada, destinada a integrações com sistemas externos dos clientes.

- **Estilo arquitetural**: REST.
- **Autenticação**: token HTTP por cliente, transmitido no header `Authorization: Token <valor>`, com suporte a múltiplos tokens por cliente e revogação imediata por desativação individual. A comunicação ocorre exclusivamente sobre TLS 1.2+.
- **Versionamento**: por prefixo de versão na URL (atualmente `/api/v3/`), permitindo evolução com coexistência de versões anteriores e sem quebra de integrações existentes.
- **Documentação**: especificação OpenAPI 3, exposta como JSON consumível por ferramentas externas (Postman, Insomnia, geradores de cliente, Swagger UI) e via interface interativa baseada em Scalar.

---

### R74 — Integração nativa ou documentada com soluções de IAM? Qual método?

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A plataforma utiliza Keycloak como camada de identidade, suportando integração com soluções de IAM corporativas através de:

- **SAML 2.0** — federação com identity providers corporativos
- **OAuth 2.0 / OpenID Connect (OIDC)** — autenticação federada
- **LDAP** — sincronização com Active Directory e outros diretórios LDAP

---

### R75 — Integração com IAM cobre ciclo completo de vida de usuários (criação, modificação, suspensão, revogação via API) com confirmação auditável

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A integração IAM via SSO (Keycloak / SAML / OAuth / OIDC / LDAP) descrita no item anterior é dedicada ao processo de autenticação federada — recebe a asserção de identidade do provedor corporativo do cliente, valida e estabelece a sessão. O ciclo de vida de usuários (criação, modificação, suspensão e revogação) não é executado por essa camada de IAM. Conforme descrito em item anterior, o ciclo de vida da base de usuários é gerenciado por integração dedicada e separada da camada de autenticação, executada contra a API REST da plataforma a partir dos sistemas de origem do cliente.

---

### R76 — Em autenticação via LDAP, a solução controla perfis e permissões por grupos do AD, impedindo atribuição manual que bypasse a hierarquia

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A integração LDAP via Keycloak é dedicada à autenticação federada — recebe a asserção de identidade do diretório do cliente e estabelece a sessão. A atribuição de perfis e permissões na plataforma 4Shark não é derivada de grupos LDAP/AD do cliente; é estabelecida pelo modelo hierárquico interno da plataforma (cargo, gestor direto, taxonomia de níveis), gerenciado por integração dedicada conforme descrito nos itens anteriores.

---

## Seção 6 — Segurança da Solução e Arquitetura

### R78 — Ciclo de desenvolvimento seguro (S-SDLC) com Security by Design e modelagem de ameaças

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark adota práticas de Secure SDLC com requisitos de segurança integrados desde o design das features. O workflow inclui:

- Avaliação de impactos de segurança e privacidade durante o planejamento de cada feature
- Revisão de código obrigatória (code review por pares)
- Revisão de segurança dedicada antes do merge para a branch principal
- Testes automatizados (unitários e integração) executados em CI/CD a cada pull request
- Segregação completa de ambientes (Desenvolvimento, Homologação, Produção)
- GitFlow com branches protegidas e regras de aprovação obrigatória

Os princípios de Privacy by Design e Security by Design estão refletidos nas práticas internas de desenvolvimento e na cultura de revisão técnica.

---

### R79 — SAST, DAST e pentests periódicos? Frequência e executor?

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark adota as seguintes práticas de análise de segurança:

- **SAST (análise estática)**: linters de segurança e qualidade (RuboCop para backend Ruby e ESLint para frontend TypeScript/Angular) executados automaticamente em todos os pull requests via CI/CD. Pull requests de release passam por revisão adicional via GitHub Copilot.
- **DAST (análise dinâmica)**: não é realizada via ferramenta dedicada de scanning automatizado. A proteção em runtime é fornecida pela camada perimetral (CloudFlare WAF com regras OWASP).
- **Pentest**: realizado por equipe independente especializada em segurança ofensiva. O relatório executivo pode ser disponibilizado mediante NDA específico ou inclusão de cláusula no acordo vigente.

---

### R80 — Ferramenta de SCA para vulnerabilidades em dependências de terceiros (Snyk, OWASP Dependency-Check)

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark utiliza o GitHub Dependabot como ferramenta de análise de composição de software (SCA), com varredura contínua de vulnerabilidades em dependências e bibliotecas de terceiros. Os pull requests de atualização de segurança são abertos automaticamente e mergeados diariamente pela equipe técnica, garantindo que a plataforma esteja sempre na versão mais recente das dependências.

---

### R81 — Gestão de vulnerabilidades com SLA por criticidade (Crítico ≤72h, Alto ≤30d, Médio ≤90d) baseado em CVSS

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém um processo contínuo de gestão de vulnerabilidades em todo o stack:

- **Dependências de aplicação** (gems Ruby, pacotes npm, imagens Docker, GitHub Actions): varredura automática contínua via Dependabot, com pull requests de correção abertos imediatamente após a divulgação de cada vulnerabilidade. As correções são revisadas e mergeadas diariamente — a janela típica entre publicação da vulnerabilidade e correção em produção é de horas a poucos dias, equiparando-se ou superando os SLAs comuns de mercado (Crítico ≤72h, Alto ≤30 dias).
- **Sistema operacional, runtime e engine de banco de dados**: gerenciados pela AWS (Amazon ECS e Amazon RDS Aurora) com patching automático, conforme o AWS Shared Responsibility Model. Vulnerabilidades nessas camadas são corrigidas pela AWS sem necessidade de intervenção manual.
- **Camada perimetral**: o CloudFlare WAF com regras OWASP atualiza continuamente as proteções contra ataques conhecidos, bloqueando tentativas de exploração em runtime.

---

### R82 — Pentest anual por empresa terceira independente

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: O pentest da plataforma 4Shark foi realizado por empresa independente especializada em segurança ofensiva. O relatório executivo do último pentest será disponibilizado em conjunto com a devolução desta avaliação. O exercício foi conduzido em ambiente de teste que estava configurado em modo desenvolvimento na ocasião, condição que contribuiu para parte das findings identificadas; todas as findings foram remediadas e validadas em retest, com a configuração de ambiente ajustada.

---

### R83 — TLS 1.2+ em todos os serviços/APIs, versões inseguras desabilitadas, certificados válidos e monitorados

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: Todos os endpoints públicos da plataforma 4Shark (web, API, integrações) utilizam TLS 1.2 ou superior, com versões inseguras (SSL 3.0, TLS 1.0, TLS 1.1) desabilitadas via configuração do CloudFlare. Os certificados são gerenciados pelo CloudFlare com renovação automática e monitoramento contínuo de validade.

---

### R84 — Patch management com SLA por criticidade, cobertura completa do stack (SO, middleware, bibliotecas, containers)

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém patch management contínuo em todas as camadas do stack:

- **Sistema operacional e engine de banco de dados**: gerenciados pela AWS (Amazon ECS e Amazon RDS Aurora) — patches aplicados automaticamente conforme o AWS Shared Responsibility Model.
- **Bibliotecas, frameworks e middleware** (Ruby gems, pacotes npm, Puma, Sidekiq, dependências de aplicação): atualizados continuamente via Dependabot, com pull requests automáticos abertos imediatamente após cada release e mergeados diariamente.
- **Containers**: imagens base atualizadas regularmente, com rebuild automatizado via pipeline CI/CD.
- **GitHub Actions**: dependências de pipeline também monitoradas e atualizadas via Dependabot.

---

### R85 — Segregação lógica/física entre PRD, HOM e DEV com controles diferenciados e proibição de dados reais em DEV/HOM

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém os ambientes de Desenvolvimento, Homologação e Produção totalmente segregados:

- VPCs e infraestrutura AWS independentes por ambiente, com Security Groups específicos
- Credenciais próprias e independentes por ambiente (cofre, banco de dados, chaves de acesso)
- Acesso de desenvolvedores à produção restrito conforme menor privilégio
- Pipelines de deploy distintos por ambiente
- Ambientes de Desenvolvimento e Homologação operam exclusivamente com dados sintéticos de teste; não há cópia ou uso de dados produtivos em ambientes inferiores

---

### R86 — Onde os dados são armazenados (país, região, datacenter)? Infra própria, colo ou cloud pública?

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: 
- **Provedor**: Amazon Web Services (AWS) — cloud pública
- **Região**: us-east-1 (Norte da Virgínia, Estados Unidos)
- **Armazenamento**: Amazon Aurora PostgreSQL (banco de dados primário) e Amazon S3 (objetos)
- A 4Shark não opera infraestrutura própria nem colocada — toda a operação é cloud-native na AWS

---

### R87 — APIs com OAuth 2.0 + tokens de curta duração + rotação + rate limiting + validação de input + proteção OWASP API Top 10

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: 
- **Autenticação**: token HTTP por cliente, transmitido sob TLS 1.2+, com revogação imediata por desativação individual. O sistema suporta múltiplos tokens ativos por cliente, permitindo rotação controlada sem interrupção de serviço (emite-se novo token, integra-se na ponta do cliente, e o token anterior é revogado em seguida).
- **Rate limiting**: aplicado em duas camadas — CloudFlare (perimetral) e Rack::Attack (aplicação), com proteção contra abuso e brute force.
- **Validação de input**: validações em modelo e controller, com proteção contra injeção SQL via ORM (parâmetros fortes do Rails) e contra XSS via escapamento automático.
- **OWASP API Top 10**: cobertura via CloudFlare WAF com regras OWASP ativas, autorização baseada em função (RBAC) e práticas do Secure SDLC.

---

### R88 — Exportação de logs de auditoria (audit trail, access logs, eventos de segurança) para SIEM do contratante com retenção ≥12 meses

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A exportação direta de logs de auditoria para o SIEM da Contratante não está disponível atualmente. A 4Shark está em fase final de desenvolvimento da funcionalidade que persistirá os eventos de autenticação em formato consumível, com interface administrativa para extração e download desses registros.

---

## Seção 7 — Resiliência, Continuidade e Recuperação de Desastres

### R90 — HA + tolerância a falhas + SLA contratado + histórico de uptime 12 meses

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A plataforma opera com alta disponibilidade e tolerância a falhas:
- **Banco de dados**: Amazon Aurora PostgreSQL Multi-AZ com failover automático
- **Aplicação**: Amazon ECS com múltiplas instâncias por serviço e auto-recovery de containers
- **Camada perimetral**: CloudFlare (CDN + Anti-DDoS) com redundância global
- **Uptime**: superior a 99.9%
- **SLA contratado**: conforme termos do acordo de prestação de serviços vigente

---

### R91 — Backups com frequência definida, geograficamente separados, criptografados, retenção documentada

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém backups automatizados dos dados de cliente:

- **Bancos Amazon Aurora PostgreSQL**: backup contínuo via Point-in-Time Recovery (PITR) + snapshots automáticos diários
- **Retenção**: 7 dias
- **Criptografia**: AES-256 via AWS KMS
- **Armazenamento**: infraestrutura multi-AZ da AWS, com data centers fisicamente separados dentro da região us-east-1

---

### R92 — Testes de restauração com periodicidade ≥semestral, com resultados documentados (RTO alcançado, volume, sucesso/falha)

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: O processo de restauração da plataforma está implementado e operacional. A equipe técnica já executou restaurações de cluster Amazon Aurora PostgreSQL — via Point-in-Time Recovery (PITR) e via snapshots automáticos diários — garantindo o conhecimento do procedimento e a validação da capacidade.

---

### R93 — Plano de Recuperação de Desastres (DRP) e/ou Plano de Continuidade de Negócios (BCP) documentado com RTO/RPO, testado anualmente

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: Os parâmetros de recuperação da plataforma estão definidos:
- **RPO (Recovery Point Objective)**: 1 hora — sustentado por Amazon Aurora PostgreSQL com Point-in-Time Recovery contínuo e snapshots automáticos diários
- **RTO (Recovery Time Objective)**: 4 horas — sustentado por Amazon Aurora Multi-AZ com failover automático e Amazon ECS com auto-recovery de containers

---

### R94 — Proteção perimetral (WAF, IDS/IPS, Anti-DDoS)

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A plataforma é protegida por múltiplas camadas perimetrais:
- **WAF**: CloudFlare WAF com regras OWASP ativas
- **Anti-DDoS**: CloudFlare DDoS Protection com mitigação automática contra ataques L3/L4/L7
- **Firewall de rede**: AWS Security Groups com regras de menor privilégio nas VPCs

---

## Seção 8 — Monitoramento e Resposta a Incidentes [Domínio: Operações]

### R96 — Política formal de resposta a incidentes com papéis, fluxos de escalonamento e critérios de severidade

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark possui política formal de resposta a incidentes de segurança da informação, cobrindo cinco etapas (planejamento, identificação, contenção, erradicação e recuperação), com papéis e responsabilidades definidos, fluxos de escalonamento por severidade e critérios de classificação.

---

### R97 — SOC (interno ou terceirizado) com monitoramento 24x7 + SIEM com correlação de eventos

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark mantém monitoramento contínuo de segurança e disponibilidade da plataforma através de stack de observabilidade integrada — AWS CloudWatch, Datadog, New Relic, Rollbar e CloudFlare — com alertas em tempo real direcionados à equipe técnica via ferramenta de comunicação corporativa. As regras de detecção e alertas são mantidas e revisadas pela equipe técnica.

---

### R98 — Incidentes registrados, investigados com análise de causa raiz, documentados com lições aprendidas

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark possui processo formal de tratamento de incidentes que cobre registro, investigação com análise de causa raiz, documentação e identificação de lições aprendidas e melhorias. Em 10 anos de operação não foi registrado incidente de segurança. Incidentes operacionais (relacionados a disponibilidade ou performance) são tratados via post-mortem com identificação de causa raiz e ações corretivas documentadas.

---

### R99 — Notificação à Contratante em incidente envolvendo dados pessoais — processo garante notificação em ≤72h (LGPD Art. 48, GDPR Art. 33)?

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: O prazo máximo de notificação à Contratante em caso de incidente envolvendo dados pessoais é de **72 horas** após o conhecimento do incidente, conforme LGPD Art. 48 e GDPR Art. 33.

---

### R100 — SLA documentado para mitigação por criticidade (Crítico ≤4h, Alto ≤24h, Médio ≤72h), contratualmente vinculante

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark possui SLA documentado para atendimento e resolução, contratualmente vinculante:

| Severidade | Tempo de Atendimento | Tempo de Solução |
|------------|---------------------|------------------|
| Severidade 1 — Serviço completamente indisponível | 4h | 16h |
| Severidade 2 — Serviço operando parcialmente | 6h | 36h |
| Severidade 3 — Problemas que não afetam o serviço | 8h | 52h |
| Dúvidas e demais problemas | 24h | 72h |

(Horas úteis — conforme contrato vigente com o Grupo Barigui)

---

### R101 — Canal dedicado documentado para reporte de incidentes 24x7 com confirmação de recebimento

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém canal dedicado para reporte de incidentes de segurança: **security@4shark.com.br**. O canal está disponível 24 horas por dia para recebimento de comunicações, com confirmação automática de entrega. O atendimento ativo segue os SLAs contratuais aplicáveis.

---

### R102 — Após incidentes significativos, exercício de simulação (tabletop) ou revisão do plano

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark realiza revisão pós-incidente via post-mortem com identificação de causa raiz, lições aprendidas e ações corretivas documentadas. Adicionalmente, sessões de discussão de cenários de segurança e impacto operacional são integradas ao processo de revisão de segurança realizado durante o desenvolvimento de novas funcionalidades, permitindo identificar e endereçar riscos antes da ocorrência de incidentes.

---

## Seção 9 — Suporte, Operação e Gestão de Terceiros

### R104 — Equipe de suporte acessa remotamente o ambiente do Contratante via canal seguro (VPN/PAM), sessões gravadas, tempo limitado

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: A 4Shark não realiza acesso remoto ao ambiente do Grupo Barigui. O modelo de operação prevê que o cliente acessa a plataforma 4Shark.

---

### R105 — Suporte terceirizado para fornecedores em outros países? Mecanismos legais?

**Resposta**: `[ ] SIM   [X] NÃO`

**OBS**: O suporte da 4Shark é interno e nacional, prestado por equipe brasileira. Não há terceirização internacional.

---

### R106 — Segregação lógica e controles de acesso distintos entre suporte interno, terceirizado e cliente, com auditoria

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: O suporte da 4Shark é exclusivamente interno (não há terceirização). A equipe de suporte acessa a mesma plataforma utilizada pelos usuários do cliente, porém com credenciais próprias com acesso apenas de leitura, permitindo navegação para diagnóstico sem capacidade de modificação. As ações são registradas em logs centralizados para fins de auditoria.

---

### R107 — Documentação atualizada da arquitetura lógica e física, diagrama de fluxo de dados, inventário de ativos

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém:
- **Diagrama de arquitetura** da plataforma (em anexo) — componentes principais, fluxo de dados, integrações e camadas de segurança
- **Inventário de infraestrutura como código** via Ansible (configuração de servidores) e Terraform (provisionamento AWS), com fonte da verdade rastreável via controle de versão
- **Documentação interna** dos serviços e fluxos mantida continuamente

---

### R108 — Subcontratados e fornecedores de quarto nível que acessam dados passam por due diligence equivalente

**Resposta**: `[X] SIM   [ ] NÃO`

**OBS**: A 4Shark mantém política de selecionar exclusivamente fornecedores de tecnologia de grande porte e reconhecimento internacional para infraestrutura crítica, que oferecem o nível de segurança, certificações independentes e maturidade operacional necessários para sustentar a plataforma. Os fornecedores principais utilizados (AWS, CloudFlare, GitHub, Google Workspace, 1Password) possuem certificações reconhecidas internacionalmente (SOC 2 Tipo II, ISO 27001, ISO 27018) com auditoria contínua independente, e contratos com cláusulas formais de proteção de dados.

---

## Pendências antes de colar no Drive

- [ ] Paulo preencher dados cadastrais (R10–R19): endereço, bairro, contato, e-mail, telefone, headcount, faturamento
- [ ] Paulo revisar os itens marcados como NÃO (R45, R46, R51, R64, R68, R70, R81, R88, R92, R93, R97, R102, R104, R108) e confirmar se mantém NÃO ou prefere SIM em algum
- [ ] Anexar `architecture-diagram.png` quando solicitado (cobre R107)
- [ ] Após CTRL+C/V no Drive: responder à Andréia confirmando preenchimento, com Maicon e Sergio em cópia
