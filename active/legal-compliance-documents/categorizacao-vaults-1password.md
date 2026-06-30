# CATEGORIZAÇÃO DOS ITENS — 1PASSWORD (working / estado atual)

**Documento de trabalho INTERNO.** Registro do estado da reorganização dos vaults + da consolidação das credenciais de banco. Atualizado 2026-06-29. Não contém valores — só títulos e decisões.

## Decisões tomadas

1. **Credenciais de banco saem do 1Password e consolidam na AWS** (opção A da pesquisa — fonte única é o anti-drift recomendado pela comunidade; Secrets Manager pra DB por causa da rotação/RDS). Ver a lista de "pode apagar" abaixo.
2. **Vault `Break-Glass Administration` criado e travado** no responsável de TI (usuário direto + grupo Owners = só ele; grupo Administrators revogado, então o Emerson não vê).
3. **1Password SSO + vaults por IaC: parado** (Teams Starter; SSO exige Business = SSO-tax; provider oficial não gerencia membership). Registrado na ANALYSIS com gatilho de revisão.
4. **Marketing**: rotação a cada desligamento de parceiro já é prática (event-driven) — sem gap.
5. **Comercial**: sem colaborador, fora do ciclo de vida; ferramentas comerciais não governadas por ora.

## Credenciais de banco → consolidar na AWS

**Onde cada uma vive na AWS** (confirmado no Terraform):
- App PostgreSQL → **Secrets Manager** (`rds!*`, RDS-managed, rotação nativa).
- App MongoDB → **SSM Parameter Store** (`MONGO_URL` por stack; o app lê de lá via `valueFrom`).
- Integrator client DBs → **SSM Parameter Store** (`CLIENT_PASSWORD` por stack integrator).
- [Auth001] PostgreSQL → **Secrets Manager** auth-001 (usado pelo Keycloak).

### Lista "PODE APAGAR" (engenheiro apaga manualmente)

**Confirmadas na AWS — o app lê de lá, a cópia no 1Password é redundante (16):**
- [Atento001] PostgreSQL · [Demo001] PostgreSQL · [Shared001] PostgreSQL · [Beta001] PostgreSQL · [Onboarding] PostgreSQL · [Setup] PostgreSQL  *(Secrets Manager rds!*)*
- [Atento] MongoDB · [Beta001] MongoDB · [Demo001] MongoDB · [Shared] MongoDB  *(SSM `MONGO_URL`)*
- [Almaviva] Integrator Database · [Atento BR] Integrator Database · [Commcenter] Integrator Database · [Maqnelson] Integrator Database · [RedeBrasil] Integrator Database  *(SSM `CLIENT_PASSWORD`)*
- [Auth001] PostgreSQL  *(Secrets Manager auth-001 / Keycloak)*

**Mortos — cliente sem infra, dropar direto (3):**
- [Aster Maquinas] Integrator Database · 4Shark Integrator Valecard (Admin) · 4Shark Integrator Valecard (Cliente)

> Nota de honestidade: confirmado que a credencial **vive na AWS** (o app usa de lá); não foi feito o byte-a-byte (engenheiro decidiu apagar). Risco residual pro sistema rodando = nulo, porque a cópia viva é a da AWS.

**MANTER:**
- `PgBouncer PostgreSQL` — é a credencial do próprio pooler (acesso de infra), não uma senha de banco duplicada.
- `[Atento] MongoDB - OLD` — confirmar se é lixo (provável drop) antes de apagar.

## Vault Break-Glass — o que ainda deve ir pra lá

Criado e travado. **Os bancos NÃO vão pra cá** (vão pra AWS, acima). Faltam mover (pendente decisão):
- Auth 001 4shark (KeyCloak) — admin do Keycloak
- VPN 4Shark Admin (Pritunl)
- Beta-001 / Demo-001 / Personal AWS Access key
- [4Shark] / [Atento BR] / [Maqnelson] Autenticação · Setup Authentication

## PgBouncer — decisão separada

Item do 1Password **fica**. A modernização (PgBouncer pet EC2 → serviço ECS) virou um plano próprio: `~/.claude/plans/active/terraform/pgbouncer-ecs-migration/` (SPIKE + PLAN). 5 decisões em aberto lá.

## Ainda em aberto (re-bucketing dos outros itens)

- **Financial Administration** (novo vault?): Heroku Billing, Registro BR.
- **Logins de cliente/integração** (`[?]` Operações vs Technology): SSO emails, OneTrust, LG, contas Google, Pague Menos, etc.
- **Design/Conteúdo** (`[?]`): Figma, Adobe, Zeplin, DeepL.
- Mover as joias da coroa não-DB pro Break-Glass (lista acima).
