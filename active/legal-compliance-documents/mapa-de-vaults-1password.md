# MAPA DE VAULTS — 1PASSWORD (acesso por grupo)

**Documento INTERNO** — não client-facing. Descreve a estrutura de vaults do 1Password como grupos de acesso, onde a **participação no vault = o acesso**. Suporta a Camada C do *Procedimento de Gestão do Ciclo de Vida de Identidade* (o "lista viva" e o "como revogar" da Camada C). Não contém credenciais — apenas a estrutura.

## Regra de roteamento — qual login vai em qual vault

- Conta de **POC**, de **homologação** (cliente pré-go-live) ou **produtiva compartilhada** (cliente em operação assistida) → **Platform Administration**
- Login de **plataforma de infraestrutura** → **Technology Administration**
- Ferramenta de **marketing** (incl. acesso de parceiros externos) → **Marketing Administration**

Não há vault company-wide.

## Vaults

| Vault | O que contém | Membros | Ação no offboarding |
|---|---|---|---|
| **Platform Administration** | logins das contas de **POC**, de **homologação** (clientes pré-go-live) e **produtivas compartilhadas** de clientes em **operação assistida**, compartilhados com o time | Operações (time todo) | remover a pessoa do vault |
| **Technology Administration** | logins em **plataformas de infraestrutura** | Responsável de TI + Emerson | remover do vault + rotacionar as credenciais compartilhadas que a pessoa via |
| **Marketing Administration** | **ferramentas de marketing**, com acesso compartilhado a agências/autônomos (parceiros externos) | Sócio comercial + parceiros externos de marketing | remover do vault + **rotacionar as credenciais compartilhadas** — feito a cada desligamento de parceiro/agência/autônomo |
| **Shared (Do not use)** | vault descontinuado — não deve ser usado | — | a ser removido |

## Como deveria ser

1. **Vault crítico separado.** O break-glass, as senhas-master de banco, o admin do Keycloak e os segredos de compliance/data-privacy são, por política, restritos ao responsável de TI. Eles **não devem** estar no Technology Administration (onde o Emerson também tem acesso). O correto é um vault **"Break-glass / Crítico"** restrito apenas ao responsável de TI, com essas credenciais movidas para lá.

## Notas

- A estrutura aplica menor privilégio por grupo (Operações ≠ Engenharia ≠ Marketing). Este documento torna a regra explícita e auditável, para que onboarding/offboarding a referenciem.
- A participação nos vaults é gerida no admin do 1Password (Console UI) — não por IaC nem SSO no plano atual (Teams Starter). A trilha de auditoria é o histórico de participação nos vaults.

## Credencial intencionalmente FORA do 1Password (chave de git push em disco)

- **Chave SSH de GitHub (`~/.ssh/github`)** — mantida **em disco, não no agent biométrico do 1Password**, por decisão individual e **opt-in por engenheiro** (Paulo, 2026-07-06), para permitir `git push` remoto via Claude Code Remote Control (o prompt biométrico não pode ser satisfeito de um celular). Trade-off aceito: fora do gate do 1Password; mitigado por branch protection + PR review, e o blast radius do git push é baixo/reversível. Regra de governança: só credenciais **remote-able** (baixo blast radius, reversíveis) saem para disco; as **machine-bound** (Terraform/AWS, SSH de infra `kp-4shark`, etc.) ficam biométricas. Service Accounts do 1Password seriam a alternativa "vaulted", mas não estão disponíveis no Teams Starter. Detalhe em `~/.claude/plans/active/remote-git-access/PLAN.md` e no spike `credential-risk-classification`.
