# Vendor Assessment Positivo — Review Round 1

**Data do feedback**: 25/03/2026
**Prazo para resubmissao**: 30/03/2026
**Revisor**: AB (Positivo)

## Motivo geral das rejeicoes

> As questoes podem ter sido rejeitadas devido a falta de compreensao, inconsistencias nas respostas fornecidas ou a ausencia de justificativas para as perguntas marcadas como "N/A" ou "Parcialmente Conforme".

---

## Perguntas rejeitadas

### Secao 1

#### Q1.17 — SIEM / Integracao com ferramentas de deteccao

**Pergunta**: Estabelecer meios de conexao com os sistemas corporativos de deteccao, prevencao e monitoramento de vulnerabilidades conhecidos como SIEM.

**Status original**: Conforme
**Problema**: Texto dizia "estamos implementando" e "sob demanda" — inconsistente com Conforme. Revisor exige funcionalidade nativa, padronizada e pronta para uso.

**Feedback do revisor**:
> Considerando que o requisito esta classificado como controle de produto, a disponibilizacao da integracao com SIEM "sob demanda" nao seria suficiente para caracterizar o seu atendimento. Espera-se que essa funcionalidade esteja disponivel de forma nativa, padronizada e pronta para uso, garantindo integracao continua com ferramentas de SIEM. Solicitamos esclarecer se a funcionalidade sera disponibilizada como padrao da solucao, bem como o prazo para sua implementacao definitiva. Caso nao haja previsao definida, solicitamos a reclassificacao do item para "Parcialmente conforme".

**Decisao**: Reclassificar para **Parcialmente Conforme**
**Nova resposta**:
> A plataforma possui monitoramento centralizado de seguranca com CloudWatch (AWS), CloudFlare (WAF, logs de trafego web) e Datadog (APM), com alertas automatizados para eventos criticos. Os eventos de autenticacao e atividade dos usuarios sao registrados internamente. A plataforma nao possui integracao nativa com ferramentas SIEM externas.

---

#### Q1.22 — Pentest

**Pergunta**: A solucao passou por teste de penetracao. Anexar relatorio.

**Status original**: Conforme
**Problema**: Relatorio enviado era vulnerability scan (automatizado), nao pentest (manual). Alem disso, datas do relatorio pareciam futuras/incorretas.

**Feedback do revisor**:
> Verificamos que o relatorio encaminhado esta datado de marco de 2026, incluindo registros de execucao e deteccao de vulnerabilidades tambem nesse periodo. Considerando a data atual, as informacoes parecem se referir a datas futuras (em especial na coluna "First Detected"). Poderiam, por gentileza, confirmar se as datas estao corretas ou se houve algum equivoco na geracao do relatorio? Adicionalmente, identificamos que o documento refere-se a um relatorio de vulnerability scan (analise automatizada), nao caracterizando um teste de intrusao (pentest). Nesse sentido, solicitamos o envio do relatorio de pentest, conforme requerido anteriormente.

**Decisao**: Reclassificar para **Parcialmente Conforme**
**Nova resposta**:
> A plataforma passa por vulnerability scans regulares com ferramentas automatizadas para identificacao e correcao de vulnerabilidades conhecidas. A 4Shark nao possui relatorio de teste de intrusao (pentest) formal recente.

---

### Secao 2

#### Q2.8 — Politica de Privacidade Publica

**Pergunta**: Link da politica de privacidade publicada.

**Status original**: Conforme
**Problema**: Resposta forneceu link direto do S3. Revisor quer saber se a politica e acessivel a partir do site institucional.

**Feedback do revisor**:
> Partindo do endereco https://www.4shark.com.br/ e possivel acessar essa Politica de Privacidade tambem?

**Decisao**: Manter **Conforme** — ajustar texto
**Nova resposta**:
> A Politica de Privacidade da 4Shark esta publicada e acessivel a partir do site institucional (https://www.4shark.com.br/), com link direto no rodape. Documento disponivel em: https://4shark-legal.s3.sa-east-1.amazonaws.com/4shark_politica_de_privacidade.pdf

**Acoes pendentes**:
- [ ] Adicionar link da politica de privacidade no rodape do site 4shark.com.br

---

#### Q2.11 — SIEM / Correlacao de Eventos

**Pergunta**: Sistema de correlacao de eventos (SIEM).

**Status original**: Parcialmente Conforme
**Problema**: Texto dizia "adocao de SIEM dedicada esta em avaliacao" — revisor nao quer promessa, quer fato. Reconhece CloudWatch e CloudFlare mas diz que nao e SIEM.

**Feedback do revisor**:
> Embora exista a centralizacao de logs e configuracao de alertas por meio do AWS CloudWatch e Cloudflare, nao foram identificadas evidencias de uma solucao de correlacao de eventos propriamente dita (SIEM), com capacidade de analise integrada entre multiplas fontes (como logs de firewall/WAF, trilhas de auditoria de infraestrutura em nuvem e eventos de endpoints), enriquecimento de eventos e deteccao contextualizada de incidentes. Adicionalmente, foi informado que a adocao de uma solucao SIEM ainda esta em avaliacao, o que reforca a ausencia atual desse controle. Dessa forma, solicitamos, por gentileza, a atualizacao da resposta para "Parcialmente conforme".

**Decisao**: Manter **Parcialmente Conforme** — ajustar texto
**Nova resposta**:
> A 4Shark utiliza CloudWatch (AWS) e CloudFlare para centralizacao de logs e configuracao de alertas automatizados. A empresa nao possui solucao SIEM dedicada com correlacao de eventos entre multiplas fontes.

---

#### Q2.12 — DLP

**Pergunta**: Prevencao contra perda e vazamento de dados.

**Status original**: Parcialmente Conforme
**Problema**: Texto dizia "avaliacao de DLP dedicada em andamento" — revisor reconhece controles compensatorios mas diz que nao caracterizam DLP.

**Feedback do revisor**:
> Embora existam controles relevantes, como criptografia, controle de acesso, uso de VPN e classificacao da informacao, nao foram identificadas evidencias de uma solucao de Prevencao contra Perda de Dados (DLP) propriamente dita, com capacidades de inspecao de conteudo, deteccao e bloqueio de exfiltracao de dados sensiveis e aplicacao automatizada de politicas de protecao. Os controles apresentados contribuem para a protecao da informacao, porem nao caracterizam integralmente uma solucao de DLP conforme o requisito. Dessa forma, solicitamos, por gentileza, a atualizacao da resposta para refletir o status de "Parcialmente conforme".

**Decisao**: Manter **Parcialmente Conforme** — ajustar texto
**Nova resposta**:
> A 4Shark implementa controles de protecao da informacao como criptografia em transito e repouso, controle de acesso restritivo (RBAC, menor privilegio), VPN obrigatoria para acesso interno e politicas de classificacao da informacao. A empresa nao possui solucao de Prevencao contra Perda de Dados (DLP) dedicada.

**Nota interna — O que e DLP**:
DLP (Data Loss Prevention) e uma categoria de ferramenta enterprise (Symantec DLP, Microsoft Purview, Forcepoint, Digital Guardian) que inspeciona conteudo em tempo real (e-mails, uploads, transferencias de arquivo), detecta dados sensiveis (CPF, cartao de credito, dados pessoais) e bloqueia automaticamente a exfiltracao. Controles como VPN, RBAC, criptografia e segmentacao de rede sao controles de seguranca validos, mas nao substituem DLP — que atua na camada de conteudo. A 4Shark nao possui e nao ha opcoes open source viaveis no mercado. A alternativa mais proxima seria AWS Macie (escaneia S3 buscando dados sensiveis, provisionavel via Terraform), mas cobre apenas S3, nao e DLP completo.

---

#### Q2.21 — ID Unico + Integracao com RH

**Pergunta**: Identificador unico nominal + integracao automatica com sistema de RH.

**Status original**: Conforme
**Problema**: Resposta falou do ambiente do produto (plataforma), nao do ambiente interno da 4Shark. Revisor quer saber como funciona internamente.

**Feedback do revisor**:
> Embora tenha sido evidenciado que cada colaborador possui um identificador unico, pessoal e intransferivel, bem como a existencia de processos para gestao do ciclo de vida de acessos, nao foram identificadas evidencias de integracao do sistema de gestao de identidades e acessos com o sistema de Recursos Humanos (RH), especialmente no que se refere a sincronizacao automatica de eventos como admissoes, desligamentos e alteracoes de cargo. Dessa forma, os controles apresentados atendem parcialmente ao requisito, uma vez que a automacao e integracao com o sistema de RH nao foram demonstradas. Solicitamos, por gentileza, a atualizacao da resposta para refletir o status de "Parcialmente conforme".

**Decisao**: Reclassificar para **Parcialmente Conforme**
**Nova resposta**:
> Cada colaborador possui identificador unico, pessoal e intransferivel. Para o time de engenharia e infraestrutura, a gestao de acessos e centralizada via Terraform (infraestrutura como codigo), cobrindo AWS, MongoDB, redes, CloudFlare, New Relic e demais servicos. A concessao e revogacao de acessos e realizada em uma unica operacao, garantindo consistencia e rastreabilidade. Os acessos seguem tres niveis de privilegio: leitura e operacoes basicas (padrao), elevacao temporaria para acoes administrativas (MFA), e conta root protegida por dispositivo fisico (break glass) para acoes destrutivas. Para funcoes operacionais que utilizam ferramentas sem provider Terraform, a gestao e manual. A 4Shark nao possui integracao automatizada entre sistema de RH e gestao de identidades — o processo e iniciado manualmente pelo gestor.

---

#### Q2.22 — Controle de Acessos Criticos + SoD

**Pergunta**: Fluxo de revisao para acessos criticos, Segregacao de Deveres (SoD), aprovacao por donos da informacao.

**Status original**: Conforme
**Problema**: Resposta falou dos 10 niveis hierarquicos do produto. Secao 2 e sobre o ambiente interno da 4Shark.

**Feedback do revisor**:
> O requisito em questao refere-se ao ambiente do fornecedor, e nao ao ambiente do cliente. O objetivo dessa secao e avaliarmos como e o ambiente de voces, entendendo as praticas de seguranca da informacao adotadas e o nivel de maturidade em relacao aos controles e requisitos mencionados.

**Decisao**: Manter **Conforme** — reescrever sobre ambiente interno
**Nova resposta**:
> A 4Shark possui controle de acessos criticos com segregacao de deveres. O fluxo segue tres etapas separadas: solicitacao pelo colaborador, aprovacao pelo gestor responsavel e execucao via conta administrativa dedicada (break glass), protegida por dispositivo fisico. Os acessos sao gerenciados via Terraform (infraestrutura como codigo) e atribuidos por grupo funcional, nao individualmente. A infraestrutura opera com tres niveis de privilegio: acesso padrao (leitura e operacoes basicas), elevacao temporaria com MFA (validade maxima de 1 hora) para acoes administrativas, e conta break glass com dispositivo fisico para acoes criticas e destrutivas. A segregacao entre quem solicita, quem aprova e quem executa esta garantida no processo.

---

#### Q2.23 — Politica de Senhas

**Pergunta**: Politica de senhas com 6 requisitos: complexidade, minimo 8 caracteres, historico, rotacao 90 dias, bloqueio 3 tentativas, MFA.

**Status original**: Conforme
**Problema**: Resposta falou do Keycloak/SSO (produto para o cliente). Secao 2 e sobre o ambiente interno da 4Shark.

**Feedback do revisor**:
> O requisito em questao refere-se ao ambiente do fornecedor, e nao ao ambiente do cliente. O objetivo dessa secao e avaliarmos como e o ambiente de voces, entendendo as praticas de seguranca da informacao adotadas e o nivel de maturidade em relacao aos controles e requisitos mencionados.

**Decisao**: Manter **Conforme** — reescrever sobre ambiente interno
**Nova resposta**:
> A 4Shark possui politica de senhas aplicada via Google Workspace para todos os colaboradores: senha forte obrigatoria, tamanho minimo de 16 caracteres, reutilizacao de senhas bloqueada e rotacao obrigatoria a cada 90 dias. O bloqueio por tentativas invalidas e gerenciado automaticamente pelo Google Workspace, que identifica tentativas suspeitas de login e exige verificacoes adicionais de identidade para garantir a autenticidade do acesso. A autenticacao multifator (MFA) e obrigatoria para todos os colaboradores com acesso a sistemas e infraestrutura.

**Configuracoes aplicadas no Google Workspace (staff)**:
| Requisito Positivo | Configuracao atual | Status |
|---|---|---|
| a) Complexidade | Senha forte obrigatoria | ✅ OK |
| b) Minimo 8 caracteres | Minimo 16 caracteres | ✅ Acima do pedido |
| c) Historico (sem reuso) | Reutilizacao bloqueada | ✅ OK |
| d) Rotacao 90 dias | 90 dias | ✅ OK |
| e) Bloqueio por tentativas | Gerenciado pelo Google Workspace | ✅ OK |
| f) MFA | Obrigatorio a partir de 30/03/2026 | ✅ OK |

---

#### Q2.24 — Offboarding

**Pergunta**: Processo de revogacao imediata de acessos ao desligar colaborador.

**Status original**: Conforme
**Problema**: Resposta falou de JWT e desativacao na plataforma (produto). Secao 2 e sobre o ambiente interno da 4Shark.

**Feedback do revisor**:
> O requisito em questao refere-se ao ambiente do fornecedor, e nao ao ambiente do cliente. O objetivo dessa secao e avaliarmos como e o ambiente de voces, entendendo as praticas de seguranca da informacao adotadas e o nivel de maturidade em relacao aos controles e requisitos mencionados.

**Decisao**: Manter **Conforme** — reescrever sobre ambiente interno
**Nova resposta**:
> No desligamento de um colaborador, a revogacao de acessos e realizada de forma imediata. A conta Google Workspace e desativada via conta administrativa dedicada (break glass), protegida por dispositivo fisico para autenticacao, o que revoga imediatamente o acesso a todas as ferramentas corporativas integradas via Single Sign-On — cobrindo tanto a equipe de engenharia quanto a de operacoes. As demais ferramentas corporativas sao administradas pela mesma conta break glass, que realiza a remocao do colaborador diretamente em cada servico. Para engenharia, os acessos a servicos de infraestrutura, repositorios de codigo (GitHub), APIs e tokens sao adicionalmente revogados via Terraform (stack identity), garantindo remocao de permissoes em todos os sistemas gerenciados. O processo garante revogacao completa e rastreavel de todos os acessos do colaborador.

---

#### Q2.28 — Certificacoes de Seguranca

**Pergunta**: Certificacoes reconhecidas (ISO 27001, ISO 27701 etc.).

**Status original**: Parcialmente Conforme
**Problema**: Resposta falou de "praticas alinhadas" e "roadmap". Revisor diz que a resposta adequada e "Nao" — tem ou nao tem certificacao.

**Feedback do revisor**:
> Embora tenha sido informado o alinhamento as praticas desses frameworks e a intencao de obtencao futura, o requisito estabelece a necessidade de certificacoes efetivamente obtidas, com validacao por auditoria independente. Dessa forma, a resposta adequada seria "Nao". Caso existam certificacoes vigentes nao mencionadas, solicitamos, por gentileza, a descricao do certificado e escopo.

**Decisao**: Reclassificar para **Nao Conforme**
**Nova resposta**:
> A 4Shark nao possui certificacoes de seguranca da informacao (ISO 27001, ISO 27701 ou equivalentes).

---

#### Q2.33 — Hardening

**Pergunta**: Metodologia de hardening. Indicar framework (CIS, NIST etc.).

**Status original**: Conforme
**Problema**: Resposta focou no shared responsibility model da AWS e Ansible. Revisor lembra que mesmo com servicos gerenciados, varias camadas sao responsabilidade do cliente (IAM, Security Groups, containers, acesso a banco, logging).

**Feedback do revisor**:
> Ressalta-se que, mesmo no modelo de responsabilidade compartilhada, permanecem sob responsabilidade do cliente diversas configuracoes de seguranca, como gestao de identidades e acessos (IAM), configuracao de rede (Security Groups e segmentacao), hardening de containers e aplicacoes, controle de acesso a bancos de dados e definicao de politicas de logging e monitoramento. Sendo assim, solicitamos, por gentileza, revisar se a resposta se mantem conforme.

**Decisao**: Reclassificar para **Parcialmente Conforme**
**Nova resposta**:
> A 4Shark aplica praticas de hardening em todas as camadas sob sua responsabilidade no modelo de responsabilidade compartilhada da AWS. A infraestrutura e segmentada com VPC dedicada por aplicacao e por ambiente, com sub-redes privadas para bancos de dados (sem acesso publico) e replicacao Multi-AZ. O acesso a infraestrutura e restrito exclusivamente via VPN com arquitetura Hub and Spoke. A gestao de identidades e acessos opera com tres niveis de privilegio, sendo a conta administrativa (break glass) protegida por dispositivo fisico, sem acesso programatico (somente via console com autenticacao fisica). Os Security Groups sao configurados com menor privilegio e toda a infraestrutura e gerenciada via Terraform e Ansible (infraestrutura como codigo), garantindo padronizacao e rastreabilidade. O monitoramento e realizado via CloudWatch (logs), Datadog e New Relic (APM). A 4Shark nao adota um framework formal de hardening (CIS, NIST), aplicando boas praticas de mercado baseadas na experiencia da equipe.

---

#### Q2.36 — Historico de Incidentes

**Pergunta**: Incidentes relevantes nos ultimos 3 anos.

**Status original**: Conforme (marcado "Sim")
**Problema**: Resposta diz que NAO houve incidentes, mas o radio button foi marcado como "Sim". Inconsistencia entre a selecao e o texto.

**Feedback do revisor**:
> Para que a resposta foi assinalada como "sim" por engano. Por gentileza, rever a resposta.

**Decisao**: Corrigir radio button para **Nao** — manter texto ✅ SUBMETIDO
**Nova resposta**:
> A 4Shark nao registrou incidentes relevantes de seguranca da informacao nos ultimos 9 anos.

---

## Resumo de acoes

### ✅ Ja submetidas

| # | Decisao | Status |
|---|---------|--------|
| Q1.17 | Parcialmente Conforme | ✅ Submetido e sinalizado como corrigido |
| Q2.36 | Nao (corrigir radio button) | ✅ Submetido e sinalizado como corrigido |

### Resposta pronta — submeter no Securiti.ai

| # | Decisao | Nova resposta definida | Acao antes de submeter |
|---|---------|----------------------|----------------------|
| Q1.22 | Parcialmente Conforme | ✅ Pronta (Paulo quer discutir com socios) | Alinhar com socios |
| Q2.8 | Conforme | ✅ Pronta | Adicionar link da politica de privacidade no rodape do site 4shark.com.br |
| Q2.11 | Parcialmente Conforme | ✅ Pronta | Nenhuma |
| Q2.12 | Parcialmente Conforme | ✅ Pronta | Nenhuma |
| Q2.21 | Parcialmente Conforme | ✅ Pronta | Nenhuma |
| Q2.22 | Conforme | ✅ Pronta | Nenhuma |
| Q2.23 | Conforme | ✅ Pronta | MFA enforcement ja ativado no Google Workspace (staff, a partir de 30/03). Rotacao trocada para 90 dias. |
| Q2.24 | Conforme | ✅ Pronta | Remover token programatico da conta break glass antes de submeter |
| Q2.28 | Nao Conforme | ✅ Pronta | Nenhuma |
| Q2.33 | Parcialmente Conforme | ✅ Pronta | Remover token programatico da conta break glass antes de submeter |

### Acoes tecnicas antes da submissao

- [ ] Adicionar link da politica de privacidade no rodape do site 4shark.com.br (Q2.8)
- [ ] Remover token programatico da conta break glass na AWS (Q2.24, Q2.33)
- [x] Avisar time no Slack para configurar MFA antes de 30/03 (Q2.23) — feito
- [ ] Paulo alinhar com socios sobre resposta da Q1.22 (pentest)
