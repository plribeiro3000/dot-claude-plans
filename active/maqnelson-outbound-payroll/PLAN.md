# PLAN — Maqnelson Outbound (Payroll Integration)

**Status**: Blocked on Maqnelson (VPN) — **ALL code is done and merged.** Phase 1 (app flow + 2-step auth, `a3c5a6e65`), Phase 2 backend + reintegrate button, and Phase 2.9 (the integration-report screen, app-webclient #6540 + user-payment cleaned of integration) are all on develop. The code serves both Atento (FPW) and Maqnelson, front included. **No code work remains.** (The `Dispatcher` spec was dropped 2026-06-30: this repo does not unit-test workers.) **All Terraform/infra (Phases 3–6) is DEFERRED until Maqnelson grants VPN access** (decision 2026-06-30): provisioning the outbound cluster before the tunnel exists only bills idle resources (ECS/EIP/NAT) with nothing to use. **The next action is entirely on Maqnelson** — the Deivid network call confirming the existing tunnel reaches `192.168.82.0/26` (Option A2, §7).
**Date**: 2026-06-30 (last update)
**Workflow**: Standard (single combined plan: app + Terraform)
**Feature directory**: `~/.claude/plans/active/maqnelson-outbound-payroll/`

> **Progress snapshot (2026-06-29)**
> - ✅ **Phase 1 — app flow + auth correction merged.** PR #5184 (structure) + PR #5190 (the contract correction): 2-step auth (`/auth/token` → `/pagamentos` with the runtime bearer), `PayrollAuthenticationRequest` (with a `status` state machine + docs diagram) linked 1:1 to the send `PayrollRequest`, static `access_token` column removed. Body structure intentionally left as-is (revalidated with Maqnelson later); end-to-end validation pending the VPN.
> - ✅ **Phase 2 — backend + front (reintegrate button) merged.** Backend: `reprocessable?`/`reintegrable?`, `reintegrate?` policy + `payroll_integration_reprocess` permission, `reintegrate` action, `reintegratePayment` mutation (app PR #5192). Front: reintegrate button on the payment view, gated on the `reintegrate` action, i18n pt-BR/es/en (app-webclient PR #6532). **Only remaining Phase 2 piece:** adapt the user-payment/integration-report screen to the Maqnelson batch-send shape (FPW's `check/execution/validation` layout doesn't fit a single batch send).
> - 🔌 **Connection = VPN, CONFIRMED by Maqnelson (Fanini)** — add `192.168.82.0/26` to the tunnel's Phase 2 + force DNS `dev-nexus.maqnelson.com.br → 192.168.82.10`; reuse of the existing integrator tunnel is the chosen shape (Option A2, §7), pending confirmation on the network call.
> - ⏸️ **Phases 3–6 (all Terraform/infra) — DEFERRED until Maqnelson grants VPN access (decision 2026-06-30).** Two gates stacked: (a) Option A2 isn't final until the Deivid call confirms the tunnel reaches `192.168.82.0/26`; (b) even once decided, **we do not provision before the tunnel exists** — terraform apply-before-merge would stand up an idle ECS cluster / EIP / NAT that bills with nothing to use. Infra starts the moment VPN access lands, then runs back-to-back (Blockers §7).
> - 🔁 **Deferred follow-up** — unify FPW `hostname` to a complete URL + migrate Atento records (originally Phase 1.7; FPW left untouched this round).

---

## 1. Objective

Build the outbound (egress) integration that pushes payroll award values ("premiação")
computed by 4Shark to Maqnelson's on-prem intermediate table ("Nexus"), over a
site-to-site VPN, following the existing `app_outbound` pattern (ADR-006) — the same
shape used today by Atento, but wired to the **shared-001** backend instead of atento-001.

The deployment is named **`app-outbound-maqnelson`** (no `-br` suffix; Maqnelson is BR-only).

**Sequencing**: develop and validate our side first; coordinate the VPN with Maqnelson
only once our side is ready.

## 2. Source material

| Source | What it gives |
|---|---|
| Gmail thread "Contrato de API - MAQNELSON" — tickets #5261 / #5342 | API contract, agreed request body, dev access, VPN instructions (Fanini, last email 25/06/2026) |
| Granola — 3 meetings (02/06, 03/06 interno, 19/06) | Interface definition, batch all-or-nothing, +1 competência rule, per-client reprocessing flag, flow 4Shark → intermediate table → payroll |
| `terraform/docs/adr/ADR-006-app-outbound-pattern.md` | The dedicated `app-outbound-<client>` pattern + naming + boundaries |
| `terraform/modules/app_outbound/` + `terraform/app-outbound-atento-br/` | The concrete reference implementation to mirror |
| `app/models/payroll_integration.rb`, `app/models/fpw_integration.rb`, `app/workers/fpw_integration/*` | The existing payroll-egress code to refactor (three-wave FPW) |

## 3. API contract (from the real YAML — `contrato-api-premiacao (1).yaml`, Fanini)

**The API is a TWO-STEP flow (2 endpoints, as Fanini's email said "apenas 2 endpoints").** The Phase 1 code implemented only step 2 with a static token — this is the bug §8 Phase 1 must correct.

**Step 1 — `POST /auth/token`** (authenticate, get the token):
```
POST  https://dev-nexus.maqnelson.com.br/.../auth/token   (exact path TBD — Fanini gave only the /pagamentos URL)
Body:     { "username": "<user_name>", "password": "<user_password>" }
200 →     { "access_token": "<JWT>", "token_type": "Bearer", "expires_in": 3600 }
401 →     { "sucesso": false, "codigo_erro": "CREDENCIAIS_INVALIDAS", ... }
```

**Step 2 — `POST /pagamentos`** (send the batch, with the token from step 1):
```
POST  https://dev-nexus.maqnelson.com.br/api/v1/premiação/pagamentos   (dev — Fanini)
Header:   Authorization: Bearer <access_token from step 1>
201 →     { "sucesso": true, "total_pagamentos": N, "competencia": "Março/2026" }
```

**Full body the YAML defines** (the values are STRINGS on our side by agreement, to avoid rounding):
```
{
  "cabecalho": {
    "data_inicio_apuracao": "2026-03-01", "data_fim_apuracao": "2026-03-31",
    "mes_competencia": 3, "ano_competencia": 2026,
    "descricao_competencia": "Março/2026", "data_geracao": "2026-04-05T10:30:00-03:00"
  },
  "pagamentos": [
    { "usuario":   { "nome": "...", "id_externo": "010494000012", "nivel_acesso": "Vendedor", "gerente_imediato": "..." },
      "pagamento": { "tipo_pagamento_descricao": "Premiação", "tipo_pagamento_id_externo": "premiacao", "premio_valor": 328.20, "premio_pontos": 0 } }
  ]
}
```

- **Batch all-or-nothing** (confirmed 19/06): integrity guaranteed on Maqnelson's side ("ou processo tudo ou não processei"). One POST for the whole batch.
- **`mes_competencia`** = exact export month from 4Shark; **Maqnelson adds +1** on their side.
- **`id_externo`** = composite external identifier (filial + matrícula) — single field, no separate subsidiária.
- **`tipo_pagamento_id_externo`** = payment type key (3 types: premiação / comissão / prêmio campanha); 4Shark configures `PaymentType.external_id` to match Maqnelson's keys (blocker #3).
- **We build the body to this contract structure with the data we actually have** — Maqnelson agreed to accept 4Shark's format ("vamos considerar esse formato de vocês", 19/06). Drop the fields we do not have (`gerente_imediato`, `premio_pontos`, subsidiária); send values as strings (avoids rounding). The exact field mapping is decided at implementation; the **real dev API is the validator** — a 400 tells us precisely what to adjust. No need to chase a prior email for the shape.
- Destination = intermediate table, **not** the payroll directly.

## 4. Integration model — FPW (three waves) vs Maqnelson (single send)

**Scope decision (2026-06-29): client-specific, not a generic umbrella.** There is no second
single-send client today and no certainty there will be one, so a `MaqnelsonIntegration` modeled
exactly like `FpwIntegration` (named after the client/solution) is the right call — simpler, faster
to deliver, easier to test. If a second, similar client appears later, generalize **then** (YAGNI).

### 4.1 Request-Reply with read-back verification — three waves (existing, FPW / Atento)

Implemented in `app/workers/fpw_integration/` as producer/consumer pairs (Sower/Grower), chained per payment:

1. **Validate** (`validate_producer` / `validate_consumer`) — check whether the record exists on the remote side.
2. **Execute** (`execute_producer` / `execute_consumer`) — create or update based on the result of wave 1.
3. **Check** (`check_producer` / `check_consumer`) — read back and confirm the final value matches what was expected.
   `finalizer.rb` closes a payment and chains the next one.

The FPW remote (SOAP) has no internal control, so 4Shark performs the full exists/upsert/verify control itself.
`FpwIntegration` is a **vendor** integration (LG FPW); vendor variations (e.g. SOAP 1.1/1.2) are already
configuration within it. **Decision: keep `FpwIntegration` as-is — no rename.** ("FPW é FPW.")

### 4.2 Maqnelson — single send (new, client-specific)

Maqnelson exposes a custom API where the control lives **on their side**: we insert into their
intermediate table, their specialists review it, and if it looks correct they push it to the payroll.
(The underlying pattern is fire-and-forget, but we are NOT building a generic abstraction — this is
Maqnelson-specific code.) Consequences for our side:

- **No data validation on our side** — no "exists?" wave, no "verify final value" wave.
- **Two-step send** — (1) `POST /auth/token` with `username`/`password` → `access_token`; (2) `POST /pagamentos` with `Authorization: Bearer <token>` and the batch body. **Guarantee it was sent** (the hand-off). That guarantee is the whole job. (The Phase 1 code skipped step 1 — see §8 correction.)
- **Token is obtained at runtime** from step 1 (JWT, `expires_in` ≈ 3600s) — **not** a static pre-stored value. The stored credentials are `user_name`/`user_password`; the static `access_token` column is the wrong model for this flow.
- **Error handling**: on a non-2xx, **do not retry** — log and stop (mark the batch `:failure`). (No re-send loop.)

### 4.3 The model — reuse existing payroll entities, NO new entity

- `PayrollIntegration` (`app/models/payroll_integration.rb:4`) is the STI base — `TYPES = %w[FpwIntegration]`.
- Add **`MaqnelsonIntegration < PayrollIntegration`** — same base as `FpwIntegration`, named after the client
  (it IS a payroll integration), exactly the FpwIntegration shape.
- **All Maqnelson flow code is grouped under `MaqnelsonIntegration::*`**, mirroring `FpwIntegration::*` (workers, etc.).
- **Reuse the existing domain models — no new entity**: `Payment` (the batch), `UserPayment` (the lines), and
  **`PayrollRequest`** (the request/response log). `PayrollRequest` is **extended** for this flow:
  - Today it is one row per `user_payment` + `action` (check/execution/validation) with a unique index → it overwrites.
  - For Maqnelson it is **one row per batch send attempt** (per `Payment`), **append-only** (every attempt kept).
  - Extension: make `user_payment` optional (`user_payment_id` nullable) + add an optional `payment` (batch) link;
    add a send `action` value; add any extra columns the send needs; conditional presence validation on
    `user_payment_id` (FPW only).
  - **The unique index `(user_payment_id, action)` stays UNTOUCHED** — it is required for the FPW 3-request scenario
    (one row per `user_payment` per action). Batch rows use `user_payment_id = NULL` (linked via `payment_id`);
    Postgres default `NULLS DISTINCT` lets multiple NULL rows coexist, so batch attempts append freely without
    weakening FPW's uniqueness.
- **Per-client differences are configuration on the record** (endpoint, auth token) — not a subclass per client.
  `tipo_pagamento` mapping stays on `PaymentType.external_id` (existing data).
- **Dispatch**: a **new entry worker** decides the flow type from the company's `payroll_integration` and enqueues
  the right flow — replacing the hardcoded `FpwIntegration::CheckProducer` at
  `integrate_payment_graphql_mutation.rb:14`. `FpwIntegration` keeps its three waves; `MaqnelsonIntegration`
  declares only the send wave.

Keep this basic — reuse the FPW machinery, extend `PayrollRequest`, do not over-design.

## 5. Architecture decisions (confirmed with engineer 2026-06-29)

1. **Dedicated stack `app-outbound-maqnelson`** (ADR-006 pattern, own VPN) pointing at
   shared-001 (image `shared-001-app:latest`, env/secrets/Redis/Hirefire from shared-001),
   running only the Maqnelson payroll Sidekiq queue. No web process.
2. **Extract `modules/shared_001_task_config`** (mirroring `atento_001_task_config`):
   refactor app-shared-001 to consume it, and the outbound stack reuses it.
3. **Single combined plan**, standard workflow.
4. **Plan with placeholders + open a formal pendency** with Maqnelson for the missing
   network data; infra can be applied with the VPN/worker left pending until data arrives.
5. **`MaqnelsonIntegration < PayrollIntegration`** (same base as `FpwIntegration`); flow code under `MaqnelsonIntegration::*`.
6. **Reuse `Payment`/`UserPayment`/`PayrollRequest`** — no new entity. `PayrollRequest` extended to batch-level + append-only, with the unique index `(user_payment_id, action)` **preserved** (batch rows use `user_payment_id = NULL`).
7. **Single batch POST**; on 500 **no auto-retry**; **reprocessing is a user-triggered flow** over failed batches.
8. **Control granularity = batch (`Payment`) level** (the API is all-or-nothing).
9. **`hostname` becomes a complete URL for BOTH flows** (drop the `host:port` split; derive host/port via `URI.parse`
   where FPW still needs it). Requires a **data migration of existing Atento FPW records** (productive).
10. **New `access_token` column (encrypted)** for the Maqnelson auth token; `user_name`/`user_password` stay FPW.

## 6. Network determination

**Connection method = VPN, CONFIRMED in writing by Maqnelson (Fanini).** His message spells out the exact requirements:

- **Access is over the VPN** — the endpoint resolves to a **private IP** (`192.168.82.10`), no public route. Access data provided by Fanini (dev): base URL `https://dev-nexus.maqnelson.com.br`, request URL `https://dev-nexus.maqnelson.com.br/api/v1/premiação/pagamentos`, reached **through the tunnel**. The stored `payroll_integration.hostname` = the **request URL** (what the Processor's `URI.parse(hostname)` consumes). Dev user/password are in ticket #5342 (not reproduced here).
- **VPN Phase 2 must include `192.168.82.0/26`** — add the customer network `192.168.82.0/26` to the tunnel's Phase 2 SA (Fanini's words: *"Incluir a rede 192.168.82.0/26 na Phase 2 da VPN"*; he offers `0.0.0.0/0` as a looser alternative — we use the specific `/26`, never the open form). Does not overlap any 4Shark CIDR → clean routing.
- **Forced DNS/host resolution `dev-nexus.maqnelson.com.br → 192.168.82.10`** on our side — Maqnelson's name does not resolve to the private IP over public DNS, so the outbound runner MUST force the mapping (hosts file or a Route53 **private hosted zone** on the outbound VPC). **This is a NEW requirement** surfaced by Fanini: the integration connects by hostname (`URI.parse(hostname)` with `hostname` = the full `https://dev-nexus…` URL), so without the override the request never reaches `192.168.82.10`. Decide hosts-file vs private-zone at Phase 5 (`ASK-DONT-DECIDE`).
- **Tunnel reuse is now likely** — "incluir a rede na Phase 2" implies an **existing** Maqnelson tunnel (the inbound integrator VPN, already live — daily integration reports succeed) whose Phase 2 we extend, rather than standing up a brand-new CGW/tunnel. This must be confirmed (same tunnel? same CGW?) and it **changes the Terraform shape** (extend an existing tunnel's Phase 2 vs ADR-006's dedicated-VPN-per-stack default) — see §9 and the open decision in §7.
- New stack VPC (sa-east-1): candidate **`10.12.0.64/26`** (groups with atento outbound `10.12.0.0/26`; **must be validated** against TGW/egress routes before apply). 2 public + 2 private subnets. (If we reuse the integrator tunnel, the VPC/attachment plan may simplify — pending the reuse confirmation.)

## 7. Blockers — pending from Maqnelson (Fanini), coordinated AFTER our side is ready

**Resolved:** connection method = **VPN** (Fanini confirmed in writing) with concrete config: add `192.168.82.0/26` to Phase 2 + force DNS `dev-nexus.maqnelson.com.br → 192.168.82.10` (see §6).

**Network placement — DECIDED (2026-06-30): reuse the existing Maqnelson network + tunnel (Option A2).** Research (`/tmp/maqnelson_outbound_network_decision_20260630.html`) confirmed the shape:
- The Maqnelson VPC (`10.1.2.0/24`, **private subnets only**) is owned by the `networking/` stack and published via SSM (`networking/vpc_maqnelson.tf`); the VPN tunnel (CGW `186.237.197.117`, routes only `192.168.90.0/26` today) is owned by `integrator-maqnelson/` via `modules/integrator`, with the VGW attached directly to the VPC.
- **The `modules/app_outbound` module CANNOT be used as-is**: it requires public subnets (the VPC has none) and **always creates its own VGW** — a second VGW on the same VPC conflicts. So the outbound stack must NOT create a VPN; it rides the integrator's tunnel.
- **A2 (chosen):** parametrize `modules/app_outbound` with `create_vpn = false` (skip VGW/CGW/connection/routes) + optional public subnets. The new `app-outbound-maqnelson` stack runs ECS in the maqnelson VPC private subnets (SSM), and the route `192.168.82.0/26` is added to **`integrator-maqnelson`'s `customer_network_cidrs`** (the integrator owns the tunnel). The maqnelson VPC becomes the per-client "Maqnelson connectivity" network (inbound + outbound) — a deliberate, documented deviation from ADR-006 (amend ADR-006 or add a new ADR for the single-client shared integrator+outbound network variant).
- **Gate before implementing:** confirm on the network call (Deivid) that the **same CGW/tunnel (`186.237.197.117`) reaches `192.168.82.0/26`** (the Nexus API), not just `192.168.90.0/26` (the DB). If the API is behind a different gateway, A2 falls and it becomes Option B (a new dedicated tunnel). **Terraform is not written until this is confirmed.**

Still pending **from Maqnelson**:

1. **Confirm the tunnel to extend** — is the API reachable over the *existing* integrator VPN (same CGW/tunnel), so we only add `192.168.82.0/26` to Phase 2? If NOT reusable, we still need the **public CGW IP + PSK + IKE/IPSec proposals** to build a new tunnel. (The earlier blocker assumed a brand-new tunnel; reuse likely removes the CGW/PSK gap.)
2. **Production endpoint + production network CIDR** (only dev `dev-nexus → 192.168.82.10` is known).
3. **`tipo_pagamento` keys** from Maqnelson to update the external identifiers on our side.

> Dev credentials (URL/user/password) are in ticket #5342 — not reproduced here.

## 8. Execution phases

> Order: app flow (done) → visualization specialization (next) → networking → shared config module → outbound stack → integration test.
> Each Terraform phase follows apply-before-merge (TERRAFORM-CONVENTIONS).
> Phases 3–6 (Terraform/VPN) are DEFERRED until VPN access (idle-cost rationale, §7); the only code left now is Phase 2.9 (report screen). (The Dispatcher spec was dropped — workers are not unit-tested in this repo.)

### Phase 1 — Application refactor + Maqnelson flow (repo `app`) — ✅ DONE (flow PR #5184 + API-call correction `a3c5a6e65`, merged to develop)

> Validated against the real contract YAML (`contrato-api-premiacao (1).yaml`) + the 19/06 meeting. The structure (STI, dispatcher, reprocess-at-worker, PayrollRequest, migrations) shipped first; the **API call was then corrected** to the 2-step token auth + contract body (`fix(payroll): authenticate the outbound payroll integration via a token endpoint`). Only residual is end-to-end field validation against the real dev API (VPN-gated) — see "Correction — DONE" below.

**Shipped (structurally correct):**
1. ✅ `MaqnelsonIntegration < PayrollIntegration` registered in `PayrollIntegration::TYPES`; flow code under `MaqnelsonIntegration::*`.
2. ✅ **`PayrollIntegration::Dispatcher`** worker decides the flow from `company.payroll_integration` and enqueues the right flow — replaced the hardcoded `FpwIntegration::CheckProducer` at `integrate_payment_graphql_mutation.rb`. The `else` branch raises **`UndefinedPayrollIntegrationException`** (no silent no-op).
3. ✅ **`MaqnelsonIntegration::Processor < TenantWorker`** (`base_queue_name :payroll`) — structure correct (join decomposition per `DATA-ACCESS.md`, no-auto-retry, marks `:failure`) **and the API call is now correct**: 2-step auth (`POST /auth/token` → parse `access_token` → `Bearer` on `/pagamentos`), contract body (`mes_competencia`/`ano_competencia`/`pagamentos[]`), per-step failure handling (auth 401 and send non-2xx both mark `:failure` + `integration_error!`, no retry). Auth + send each tracked (`PayrollAuthenticationRequest` / `PayrollRequest`) with password/token redaction.
4. ✅ **`PayrollRequest` extended** — `user_payment_id` nullable, optional `payment` link, `integration_granularity` validation (exactly one of `payment_id` / `user_payment_id`). Unique index `(user_payment_id, action)` **preserved**; batch rows use `user_payment_id = NULL` and append via Postgres `NULLS DISTINCT`. Spec + factory added.
5. ✅ **Reprocess at the worker level** — the Processor selects `:pending` **and** `:failure` `user_payments`, so re-running it reprocesses a failed batch. The trigger reuses the existing `integrate_payment` mutation (`Payment` state machine `queue_integration`: `integration_error → pending_integration`). No new mutation was built this round — **how the front surfaces this is Phase 2**.
6. ✅ **Config** — encrypted `user_name`/`user_password` (the real credentials). The token is now a **runtime JWT** fetched per run from `/auth/token` (no stored token relied upon). The `/auth/token` URL is **derived** from the stored `/pagamentos` hostname (`hostname.sub('/pagamentos', '/auth/token')`) — no separate column needed.
7. ✅ **Production-safe migrations** — split into column / FK (`validate: false`) / concurrent index (`disable_ddl_transaction!`) / `validate_foreign_key`; per-migration `statement_timeout` ENV override; `strong_migrations`-compliant (no blanket `safety_assured`). Brakeman false positive (URI.parse on `hostname`) reviewed into `config/brakeman.ignore`.

**Correction — DONE (`app` commit `a3c5a6e65`, merged to develop):**
1. ✅ **2-step auth** in `MaqnelsonIntegration::Processor` — `POST /auth/token` with `{ username: user_name, password: user_password }` → parse `access_token` → `Bearer` on the `/pagamentos` POST. Auth 401/non-2xx marks the batch `:failure` + `integration_error!` (no retry), same as the send step.
2. ✅ **Body** built to the shape we can fill from our data — `mes_competencia` / `ano_competencia` (from `payment.reference_month`) + `pagamentos[]` (`usuario_id_externo`, `tipo_pagamento_id_externo`, `premio_valor`), values as strings. (No `cabecalho`/extra contract fields — the **exact final field mapping is validated against the real dev API**, a 400 says what to adjust; this is the VPN-gated residual.)
3. ✅ **Credential model** — token held only in-memory per run (no stored token column relied upon); `user_name`/`user_password` are the stored credentials.
4. ✅ **`/auth/token` URL derived** from the stored `/pagamentos` hostname (`hostname.sub('/pagamentos', '/auth/token')`) — no separate column.
5. ✅ **Auth request entity** — `PayrollAuthenticationRequest` records each auth attempt (duration, body/headers, response) with password + token redaction; linked to the `PayrollRequest`.
6. ⏸️ **Tests** — no Processor spec (consistent with the repo convention: workers are not unit-tested; the `Dispatcher` spec was dropped for the same reason).

> **Only residual (VPN-gated):** end-to-end validation against the real dev API on `dev-nexus` — confirms the body field mapping and the `access_token` field name. Dev credentials are in ticket #5342; happens once the VPN is up.

**Deferred out of the original PR (tracked, not lost):**
- 🔁 **`hostname` → complete URL for BOTH flows + Atento data migration** (was Phase 1.7) — FPW still uses `"http://#{hostname}/lg.com.br/..."` in its 3 consumers; not unified. Follow-up only, no urgency (Maqnelson works with `URI.parse(hostname)` today).
- ⛔ **`tipo_pagamento` mapping** on `PaymentType.external_id` (was Phase 1.8) — blocked on Maqnelson keys (Blocker #3).
- ⏸️ **Dedicated Sidekiq queue / config** (was Phase 1.10) — Processor runs on `base_queue_name :payroll`; a Maqnelson-specific queue config is deferred to the outbound stack (Phase 5).
- 🧪 **`Dispatcher` spec — DROPPED (2026-06-30).** This repo does not unit-test workers: there is no `spec/workers/`, 0 specs call `perform`/`dynamic_perform_async`, and the testing policy explicitly skips chained workers. The `Dispatcher` (a thin `case` dispatch) follows that convention — no spec.

### Phase 2 — Integration visualization specialization (`app` backend ✅ MERGED #5192; `app-webclient` front ⏭️ NEXT)
> Goal: the integration view must reflect each account's payroll-integration capability. **Maqnelson supports user-triggered reintegration of a failed batch; Atento (FPW) does not.**
> **Naming (settled with the engineer):** at the **Payment** level the action is **`reintegrate`**; at the **PayrollIntegration** level the capability term is **`reprocess`**. No `can_*` methods (the codebase's only `can_reprocess?` is state-machine-generated on Commission, not hand-written).

1. ✅ **Discovery** — `ANALYSIS.md`: integration type not exposed via GraphQL; the front is blind to type (consumes only `actions`/`status`/`integrationStatus`); the integration-report/user-payment screen is FPW-3-action-shaped, not fit for Maqnelson's single batch send.

**Backend — ✅ MERGED (PR #5192):**
2. ✅ **Capability** — polymorphic **`PayrollIntegration#reprocessable?`** (`false` base/FPW, `true` Maqnelson). No type-check in GraphQL.
3. ✅ **Payment owns the question** — **`Payment#reintegrable?`** = `integration_error?` + `payroll_integration.reprocessable?` (mirrors `CommissionPolicy#reprocess?` → `record.can_reprocess?`).
4. ✅ **Policy + action** — **`PayrollIntegrationPolicy#reintegrate?`** (company-match + `record.reintegrable?` + permission), thin; `PaymentGraphqlType#actions` gains **`reintegrate`**. `create?`/`integrate` untouched (Atento unaffected).
5. ✅ **Dedicated mutation** — **`ReintegratePaymentGraphqlMutation` (`reintegratePayment`)**, reuses `integrate_by` (re-queue), authorizes `reintegrate?`.
6. ✅ **New permission** — `Action` **`payroll_integration_reprocess`** (level `resource`, resource `payroll_integration`) via migration; `reintegrate?` requires it (not `payroll_integration_creation`).
7. ✅ **Tests** — `reprocessable?` covered on fpw/maqnelson model specs. (No request spec for the mutation — the sibling `integratePayment` has none; `payment_spec` is shoulda-only so `reintegrable?` follows the convention untested.)

**Front — ⏭️ NEXT (`app-webclient`):**
8. **Reintegrate affordance** — render a **reintegrate** action gated on `payment.actions.includes('reintegrate')` → calls `reintegratePayment`; absent for FPW/Atento. Pattern Priming on sibling components.
9. **Adapt the integration report** for the Maqnelson **batch-send** shape — the user-payment/integration-report screen's `['check','execution','validation']` sort and per-action labels do not represent a single batch send; specialize the report (data + rendering) for the batch-level `PayrollRequest` (`user_payment_id = NULL`).
10. **Front tests** per the `app-webclient` convention.

> The **`Dispatcher` spec** was dropped (2026-06-30) — workers are not unit-tested in this repo (testing policy skips chained workers).

### Phase 3 — Terraform networking (repo `terraform`)
> **Resolve the reuse-vs-dedicated decision (§7) first** — it sets whether this phase extends the existing Maqnelson tunnel's Phase 2 or builds a new VPC/CGW/tunnel.
1. **VPN Phase 2** — add `192.168.82.0/26` to the tunnel's Phase 2 SA (Fanini's requirement). If reusing the integrator tunnel: add the network to that tunnel's existing config. If dedicated: build the new tunnel with this network.
2. (Dedicated path only) Create `networking/vpc_app_outbound_maqnelson.tf` — mirror `vpc_app_outbound_atento_br.tf`:
   VPC (`10.12.0.64/26`, validate), 2 pub + 2 prv subnets, IGW, route tables, TGW attachment (sa-east-1), default routes; plus the CIDR SSM output in `networking/ssm.tf`.
3. Add the customer-network route on the egress/TGW side for `192.168.82.0/26`.

### Phase 4 — Extract `shared_001_task_config` (repo `terraform`)
1. Create `modules/shared_001_task_config/` exposing `env_vars` and `secrets` outputs (extract from `app-shared-001/compute.tf` locals).
2. Refactor `app-shared-001` to consume the module (no behavior change — verify plan is a no-op on the running services).
3. The module is then reused by the outbound stack.

### Phase 5 — Outbound stack (repo `terraform`)
1. Create `app-outbound-maqnelson/` — mirror `app-outbound-atento-br/` (compute, ecr, iam, locals, main, monitoring_data, output, providers, README, stack.tm.hcl, variables):
   - `modules/app_outbound` with `client_name = "maqnelson"`, `customer_gateway_ip = <PLACEHOLDER>`, `customer_network_cidrs = ["192.168.82.0/26"]`.
   - image `shared-001-app:latest`; `task_config` from `modules/shared_001_task_config`.
   - autoscaling Lambda → shared-001 Redis lock URL + shared-001 Hirefire metrics endpoint.
   - worker service command consuming the Maqnelson payroll sidekiq config (dedicated queue config, deferred from Phase 1.10).
   - SSM data sources sourced from `shared-001` (provider alias) instead of atento-001.
2. **Force DNS `dev-nexus.maqnelson.com.br → 192.168.82.10`** for the outbound runner (Fanini's requirement, §6) — Route53 **private hosted zone** on the outbound VPC (preferred over a container hosts-file hack) or the task's DNS config. Without it the `URI.parse(hostname)` request never resolves to the private IP over the tunnel. **Decide the mechanism with the engineer (`ASK-DONT-DECIDE`).**
3. Resource naming: `4client-app-outbound-maqnelson`, cluster `app-outbound-maqnelson-cluster`, SSM `/networking/app-outbound-maqnelson/*`.

### Phase 6 — Integration test
1. With VPN up, run an end-to-end test from the outbound runner task against `dev-nexus`.
2. Validate the batch send and the guarantee-sent path; confirm a 500 does not trigger a re-send.

## 9. Risks / notes

- **VPC CIDR** `10.12.0.64/26` must be confirmed free against TGW/egress route tables before apply.
- **shared-001 refactor (Phase 4)** touches a productive multi-client stack — the plan must be a verified no-op; check the productive-environment queue before any shared-001 deploy (app/CLAUDE.md deploy rule).
- The outbound replica runs shared-001 env (multi-tenant) but the Sidekiq queue must process **only** Maqnelson payroll jobs — enforced by app-level routing + the per-client flag.
- The refactor must not change FPW/Atento behavior — its three waves stay intact; only the abstraction boundary changes.
- **VPN reuse (now likely, per Fanini)** — his "incluir a rede na Phase 2 da VPN" implies an existing Maqnelson tunnel to extend, not a new one. Confirm whether the existing integrator tunnel (VPC `10.1.2.0/24`) is the one, then extend its Phase 2 with `192.168.82.0/26`; only fall back to a dedicated tunnel (ADR-006 default) if reuse is not viable. This is the §7 open decision.
- **Forced DNS resolution `dev-nexus.maqnelson.com.br → 192.168.82.10`** is mandatory on the outbound runner (Fanini) — public DNS will not return the private IP. Private hosted zone vs hosts-file is a Phase 5 decision; without it the integration cannot reach the endpoint even with the tunnel up.
- **Atento `hostname` migration is on the productive FPW flow** — changing `hostname` to a complete URL touches the model, `check_producer` (telnet), and the 3 consumers, plus a data migration of existing Atento records. Must be a verified, careful change (no FPW behavior change; correct value before the code that reads it ships).

## 10. Next steps

**Phase 2.9 — Integration Report restructure. Backend MERGED; front PENDING.**

The "Payroll Integration Report" the FPW flow uses **is** `user-payment.component` (route `payments/:id/userPayments`, reached via the `integration_report` action) — created in app-webclient PR #5604 ("add payroll integration"); the file name is misleading, but it IS the integration report (own filters: user / paymentType / integrationStatus). It lists `user_payments`, which has no slot for a payment-level (batch) request — the structural mismatch behind every failed placement attempt. **Decision: restructure it into a listing of the payment's `payroll_requests` (the integrations), serving both types.**

- ✅ **Backend MERGED:**
  - `payrollRequests` on `PaymentGraphqlType` (app #5194).
  - app #5195: `PayrollRequest.for_payment` returns **all** of a payment's requests (per-line via `user_payment` **and** payment-level) — consumed by the top-level `payrollRequests(paymentId:)` resolver. `bulk?` capability declared **per subclass** (FPW `false` / Maqnelson `true`, no base default). `PayrollIntegrationGraphqlType` (`bulk` / `reprocessable`) exposed via `company.payrollIntegration`. Additive — deploy does **not** break the front (front doesn't use `payrollRequests(paymentId:)` yet; the company field is additive).
- ✅ **Front DONE (app-webclient PR #6540, open) — a NEW screen with its OWN permission, following the project's sub-page convention.** `PaymentIntegrationComponent` at **`payment/integration/`**, **declared in `PaymentModule`** (like `payment/show` + `payment/create` — NOT a separate top-level module), route **`payments/:paymentId/integration`** (singular), **guarded by `payrollIntegrationListing` → backend `payroll_integration_listing`** (already enforced by `PayrollIntegrationPolicy#show?`). Lists the payment's `payroll_requests` via **ONE** `payrollRequests(paymentId:)` query; `company.payrollIntegration.bulk` decides the **layout** (per-line shows a user column; batch omits it). Filters: status + action; pagination via the connection. No new i18n (reuses `payment.page.integration_report` + `payroll_request.*`). **`user-payment` CLEANED of all integration content** — the integration-status filter/column, the expandable payroll-request rows, and the integration fields removed from its HTML/TS/query/model/styles; it lists user payments only again (its real purpose: how much is paid to each user, with the user/paymentType filters). The `integration_report` button on payment-show stays pointing to `userPayments` (purely additive — no existing route/button altered). **Why a separate guarded screen:** seeing a payment does NOT imply seeing its integration report — the old embed lived on the **unguarded** `userPayments` route, so it showed integration data to users WITHOUT the integration permission. Lint green; full `ng build` validated by the Netlify preview. (History: first wrongly rebuilt `user-payment`, then made a top-level `payment-integrations` module — both corrected; the engineer meant a NEW sub-page inside `payment/`, singular `integration`.)
- History: #6536 (a "batch send" panel bolted on) → reverted (#6537). #6539 (a "Requisições de Folha" section) → closed as superseded once we confirmed the screen IS the integration report and needs the full restructure, not a bolt-on. Capability name researched from the domain (PLAN §4 + DATA-PROCESSING Processor/Producer-Consumer) → **`bulk`**.
- **Follow-up (backend): `show?` requires `integrated?`** — the report is hidden on a FAILED integration; loosen `show?` to also allow `integration_error?` so failures are inspectable before reprocessing. (`payroll_integration_policy.rb:22`.)
- **⚠️ DEPLOY ACTION ITEM — grant the new permission(s) to the Payroll-integration user.** The new report screen is gated on `payroll_integration_listing`; the `Action` exists in the backend (migration `20251225231933`) but is **not yet assigned to any user**. When this ships, **grant `payroll_integration_listing` to Gustavo Bonilla's user at Atento** — today the only user who performs Payroll integration. Without it, even he cannot open the report (the guard returns `false`). Same applies to **`payroll_integration_reprocess`** (the reintegrate button from Phase 2) — grant both to the same user at deploy. Front + backend release cut together once the front is approved.

**Doable now (next):**
2. *(Independent)* unify FPW `hostname` → complete URL + Atento data migration — a productive FPW change, careful (no behavior change). **This is item 3.**

> Note (2026-06-30): the `Dispatcher` spec was dropped — this repo does not unit-test workers (no `spec/workers/`; testing policy skips chained workers).

**Waiting on Maqnelson (no 4Shark action until they respond):**
4. The network call (Deivid) to confirm **Option A2** — that the existing tunnel (CGW `186.237.197.117`) reaches `192.168.82.0/26`, not just `192.168.90.0/26`.
5. Prod endpoint + prod CIDR; `tipo_pagamento` keys (Blocker #3); the `/auth/token` URL + dev credentials for end-to-end validation.

**Deferred until VPN access is granted (then execute back-to-back):**
6. **Phases 3–6** — write **and** apply the Terraform (A2: parametrize `modules/app_outbound` with `create_vpn=false`, run ECS in the maqnelson VPC private subnets, add `192.168.82.0/26` to `integrator-maqnelson`'s `customer_network_cidrs`, force DNS via private hosted zone), then the end-to-end integration test. **Not started before access** — apply-before-merge would bill an idle cluster.
