# SPIKE — Olist ERP (Tiny) Integration for Magna Tech

**Conducted by:** Engineering
**Date:** 2026-03-27 (credential spike: 2026-03-31, updated 2026-04-02; consolidated 2026-04-07; closed 2026-04-14)
**Status:** Complete — "Gestão de Aplicativos" extension installed, OAuth2 app created and credentials obtained (2026-04-14)
**Consolidated from:** `active/spike/olist-integration/SPIKE.md` + `completed/spike/olist-api-credentials/SPIKE.md`

---

## Goal

Map the Olist ERP API v3 (formerly Tiny/RP Time) to 4Shark's API and establish OAuth2 credentials for the Magna Tech client. Magna Tech has no IT team — the integration must be built by 4Shark via the Integrator. The credential setup guide was prepared for use during a call with Magna Tech's financial team member who manages their Olist account.

---

## Method

- Analyzed Olist ERP API v3 Swagger documentation (177 endpoints, 317 schemas)
- Analyzed Olist help center documentation for app setup and rate limits
- Mapped 4Shark REST API v3 resources and their attributes
- Cross-referenced available data between both systems
- Researched current Olist ERP plan tiers and their API access
- Investigated user role management and administrator identification

---

## Confirmed Scope

| Resource | Status | Notes |
|----------|--------|-------|
| Users (vendedores) | ✅ In scope | Full compatibility via `GET /vendedores` |
| Products (produtos) | ✅ In scope | Full compatibility via `GET /produtos` |
| Product Groups (categorias) | ✅ In scope | Categories mapped to ProductDocument |
| Transactions (pedidos) | ✅ In scope | Orders expand to deals (1 order = N deals) |
| Groups (teams) | ❌ Out of scope | Not available in Olist. Magna Tech has only 1 group with few people — manual creation in 4Shark recommended |
| Goals (metas) | ❌ Out of scope | Not available in Olist (expected — Olist is an ERP/e-commerce platform, not a sales incentive system). Matheus confirmed goals are not needed. If ever needed, goals would be managed directly in 4Shark (manually or via 4Shark API) |

---

## Magna Tech's Olist Account

- **Plan:** Evoluir (legacy name, equivalent to Impulsione)
- **Rate limits:** 120 requests/min, 60 write operations/min
- **Administrator:** Confirmed — admin was present on the credential setup call (2026-04-02)
- **API V3 OAuth2:** Resolved (2026-04-14) — "Gestão de Aplicativos" extension was the missing piece. Once installed, the OAuth2 app creation flow became available and credentials were successfully generated.

---

## Olist API Overview

- **Base URL:** `https://api.tiny.com.br/public-api/v3`
- **Auth:** OAuth2 (client_id + client_secret)
- **Pagination:** offset/limit (default 100)
- **App limit:** Max 5 apps per account
- **Sync strategy:** Poll-based (no webhooks in v3). Use `dataAlteracao` filters for incremental sync.

### Two API Authentication Methods

| | API V2 — Token API | API V3 — OAuth2 Apps |
|---|---|---|
| Auth | Single global token | Client ID + Client Secret per app |
| Scope control | None (full access) | 17 modules, 3 permission levels (Leitura, Incluir e editar, Excluir) |
| Plan requirement | All plans | Construa and above |
| Extension | "Token API" | "Gestão de Aplicativos" |
| How to generate | Menu → Início → Extensões da Olist → install "Token API" (Vendas section) → Menu → Configurações → aba E-commerce → Token API | Menu → Configurações → aba Geral → Aplicativos → + Novo aplicativo |
| Status | Legacy — no further updates, no estimated discontinuation date | Current, actively developed |

### Rate Limits by Plan

| Plan | Requests/min | Write ops/min |
|---|---|---|
| Avance, Construa | 60 | 30 |
| **Impulsione** | **120** | **60** |
| Domine | 240 | 100 |

### Olist Plan Tiers and API V3 Access

| # | Legacy Plan | Current Plan | Annual Revenue | API V3 Access |
|---|-------------|-------------|---------------|---------------|
| 1 | Básico / Começar | Avance | up to R$ 81k | ❌ No |
| 2 | Crescer | Construa | up to R$ 360k | ✅ Yes |
| 3 | Essencial / Evoluir | Impulsione | up to R$ 4.8M | ✅ Yes |
| 4 | Grande / Potencializar | Domine | up to R$ 78M | ✅ Yes |
| 5 | — | Protagonize | Enterprise | ✅ Yes |

API V3 is available from Construa onwards — Olist documentation states: "Disponível a partir do plano Construa".

---

## Resource Mapping

### 4Shark API Required Fields (quick reference)

- `POST /api/v3/users` requires: email, first_name, last_name, city, state, register_type, unique_register_id, password, seat_attributes
- `POST /api/v3/products` requires: name, external_id
- `POST /api/v3/deals` requires: date, external_id, installment, quantity, sold_price, status, type, user_id

### 1. Users

`GET /vendedores` → `POST /api/v3/users`

Single call. `GET /vendedores` returns a `contato` field embedded in each seller with all contact details.

**Olist fields available per seller:**
- `id` (integer) — seller ID
- `situacao` (B/A/I/E) — status
- `contato.id` — linked contact ID
- `contato.nome`, `contato.fantasia` — name
- `contato.cpfCnpj` — document number
- `contato.email` — email
- `contato.telefone`, `contato.celular` — phone numbers
- `contato.endereco.municipio` — city
- `contato.endereco.uf` — state
- `contato.endereco.endereco`, `contato.endereco.numero`, `contato.endereco.bairro`, `contato.endereco.cep` — full address

**Additional cross-reference options (not required):**
- `GET /contatos?idVendedor={id}` — filter contacts by seller
- Each contact response includes `vendedor: { id, nome }` — bidirectional link
- `GET /pedidos` includes `vendedor: { id, nome }` — orders linked to sellers

**Field mapping:**

| Olist Field | 4Shark Field | Notes |
|-------------|-------------|-------|
| vendedor.id | identifier (external_id) | Seller ID as external identifier |
| contato.nome | first_name + last_name | Parse full name |
| contato.email | email | Direct |
| contato.cpfCnpj | unique_register_id | Direct |
| contato.endereco.municipio | city | Direct |
| contato.endereco.uf | state | Direct |
| contato.tipoPessoa (F/J) | register_type | F→BR_CPF, J→BR_CNPJ |
| — | seat_attributes | Fixed: SalesRepresentative |
| — | password | Auto-generate |

**Prerequisite:** Sellers must have contact data filled in Olist (email, CPF, address). Incomplete data should be flagged for manual resolution.

### 2. Products

`GET /produtos` → `POST /api/v3/products`

**Olist fields:** id, sku, descricao, tipo, categoria, marca, precos, estoque, etc.

**Field mapping:**

| Olist Field | 4Shark Field | Notes |
|-------------|-------------|-------|
| id | external_id | Olist product ID |
| descricao | name | Product description/name |
| sku | — | Could be stored as identifier if needed |

### 3. Product Groups

`GET /categorias/todas` → ProductDocument (GraphQL)

- Olist `GET /categorias/todas` returns full category tree (id, descricao, categoriaPai, filhas[])
- Categories map to ProductDocuments for metrics segmentation

| Olist Field | 4Shark Field | Notes |
|-------------|-------------|-------|
| categoria.descricao | product_document | Via ProductDocument for grouping |

### 4. Transactions

`GET /pedidos` → `POST /api/v3/deals`

**Olist fields:** id, numeroPedido, data, situacao, valorTotalPedido, valorTotalProdutos, itens[], vendedor, cliente, etc.

**Supplementary source:** `GET /notas` — invoices could supplement transaction data.

**Olist order statuses:** 0=Aberta, 1=Faturada, 2=Cancelada, 3=Aprovada, 4=PreparandoEnvio, 5=Enviada, 6=Entregue, 7=ProntoEnvio, 8=DadosIncompletos, 9=NaoEntregue

**Field mapping:**

| Olist Field | 4Shark Field | Notes |
|-------------|-------------|-------|
| id | external_id | Olist order ID |
| data | date | Order date |
| itens[].quantidade | quantity | Per item |
| itens[].valor | sold_price | Per item |
| vendedor.id | user_id | Via UserIdentifier lookup |
| itens[].idProduto | product_id | Via Product external_id |
| cliente | client_id | Via Client external_id |
| situacao | status | See mapping below |
| — | type | Fixed: "Sale" |
| — | installment | Default: 1 (or from pagamento if available) |

**Order item expansion:** Each Olist order can have multiple items. Each item becomes a separate Deal in 4Shark. All deals from same order share the same external_id prefix with item index as suffix.

**Status mapping (proposed):**
- `executed`: Faturada(1), Aprovada(3), PreparandoEnvio(4), Enviada(5), Entregue(6), ProntoEnvio(7)
- `booked`: Aberta(0), DadosIncompletos(8)
- `disable deal`: Cancelada(2), NaoEntregue(9)

---

## Integration Architecture

```
Olist ERP (Tiny)                    4Shark Integrator                    4Shark App
─────────────────                   ─────────────────                    ──────────
GET /vendedores        ──────►      Transform + Enrich     ──────►      POST /api/v3/users
GET /contatos          ──────►      (supplement user data)

GET /produtos          ──────►      Transform              ──────►      POST /api/v3/products
GET /categorias/todas  ──────►      Map to ProductDocument  ──────►      GraphQL ProductDocument

GET /pedidos           ──────►      Expand items to deals   ──────►     POST /api/v3/deals
                                    Map statuses
                                    Link user/product
```

**Sync frequency considerations (at 120 req/min):**
- Users and Products: low frequency (daily or on-demand)
- Transactions: higher frequency (every 15-30 min during business hours)

---

## Conclusions

- **Users**: full compatibility — single call, no workaround needed
- **Products**: full compatibility
- **Transactions**: good compatibility — requires item expansion (1 order = N deals) and status mapping (proposed, pending team validation)
- **Product Groups**: good compatibility — category tree available, maps to ProductDocument

---

## OAuth2 Credential Setup Guide

> For use during call with Magna Tech admin.

### Step 1 — Verify plan

Menu → Configurações → check plan name. Must be Construa or higher (Magna Tech is Evoluir/Impulsione ✅).

### Step 2 — Verify administrator access

Menu → Configurações → aba Geral → look for "Cadastro de usuários do sistema". If visible, user is admin.

**If not admin:**
- Check login format: `vendedor@administrador` — name after @ is the admin
- Ask internally (usually the account creator / business owner, or a partner listed in the company's articles of incorporation)
- Contact Olist support as last resort

### Step 3 — Install "Gestão de Aplicativos" extension

Menu → Início → Extensões da Olist → find and install "Gestão de Aplicativos" (this is NOT the same as "Token API").

### Step 4 — Create OAuth2 app

1. Navigate to: Menu → Configurações → aba "Geral" → Aplicativos
2. Click "+ Novo aplicativo"
3. Fill in:
   - **Nome:** `4Shark Integrator`
   - **URLs de Redirecionamento:** `http://localhost:8080/oauth/tiny/callback` (temporary placeholder — Olist's own documentation uses `http://localhost` in examples. The redirect URL can be changed later by editing the app in the same screen. Must be defined by 4Shark engineering and updated when infra is ready)
4. Save → return to Apps screen → click edit on new app
5. Copy **Client ID** and **Client Secret** from "Chaves de acesso" section
6. In "Permissões do aplicativo", enable **Leitura** for:

   | Module | Reason |
   |--------|--------|
   | Contatos | Seller/contact data for user sync |
   | Produtos | Product catalog |
   | Categorias | Product grouping for metrics |
   | Pedidos de Venda | Orders/transactions |

7. Save

> Note: The `urn:ietf:wg:oauth:2.0:oob` pattern (used by Google) does NOT work here — Olist uses Keycloak which does not support it.

### Step 5 — Send credentials

Send Client ID + Client Secret to 4Shark via secure channel.

---

## Open Questions

1. **Olist contract scope** — Confirm what Magna Tech contracted with Olist (mentioned "upload only"?)
2. **Product groups full list** — Magna Tech mentioned having more product groups than initially reported — need full list for correct ProductDocument mapping
3. **Seller contact data quality** — unknown whether all Magna Tech sellers have complete data in Olist (email, CPF, address). Need to validate if sellers exist as contacts in Olist (determines user sync complexity)

---

## Next Steps

1. **Define status mapping** with the team
2. **Define redirect URL** — 4Shark engineering must define the production OAuth2 redirect URL
3. **Create PLAN.md** for integrator implementation once credential blocker and open questions are resolved

---

## Resolved Items

1. **Magna Tech's Olist plan** — Evoluir (legacy equivalent to Impulsione) — confirmed during call (2026-04-02)
2. **Administrator access** — confirmed, admin was present on the call (2026-04-02)
3. **Goals/metas** — confirmed not needed by Matheus
4. **API V3 blocker identified** — admin could only see Token API (V2), not OAuth2 app creation (V3)
5. **OAuth2 credentials obtained** — "Gestão de Aplicativos" extension installed, app created with read-only scopes (Contatos, Produtos, Categorias, Pedidos de Venda), Client ID and Client Secret delivered (2026-04-14)

---

## References

- [Aplicativos API V3 — Configurações e Utilização](https://ajuda.olist.com/hubs-e-plataformas-via-api/aplicativos-api-v3-configuracoes-e-utilizacao)
- [Planos Olist ERP](https://olist.com/planos/)
- [Usuários do ERP — Central de Ajuda](https://ajuda.olist.com/gerenciamento-da-conta/usuarios-uso-e-configuracoes)

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
