# BLUEPRINT — Maqnelson outbound: dedicated subnets inside the integrator VPC (routing-isolated)

## Decision (2026-07-24): dedicated SUBNETS in the existing integrator VPC — NOT a new VPC

The engineer chose to keep the outbound cluster in the **existing integrator-maqnelson VPC** and carve **two new dedicated subnets** for it there — NOT a new VPC. No new VPC, no new customer VPN. Isolation is by **routing**: the two new subnets get their own route table, and only that table carries the route to the production database; the integrator's own subnets never get it. A new-VPC approach was built and fully reverted (PRs #815 apply, #818 revert) after a terminology mix-up — "rede separada" meant a separate subnet, not a separate VPC.

**IP budget (confirmed against live AWS, 2026-07-24):** the integrator VPC is `10.1.2.0/24` (256 addresses). The two existing subnets occupy the lower half (`10.1.2.0/26` + `10.1.2.64/26` = `10.1.2.0–.127`). The upper half `10.1.2.128–.255` is entirely free. The two new subnets — `10.1.2.128/28` (sa-east-1a) + `10.1.2.144/28` (sa-east-1b) — use 32 addresses (11 usable each after the 5 AWS-reserved), leaving 96 free. Each Fargate task takes one IP, so 22 task capacity across both AZs with redundancy, far above the ~2 today / ~8 projected.

**Sequenced execution:**
1. ✅ **Networking — dedicated subnets. APPLIED 2026-07-24, PR [terraform#820](https://github.com/4shark/terraform/pull/820) open awaiting merge.** The two `/28` subnets in the integrator VPC (`app-outbound-maqnelson-prv-a/b` per ADR-010, NOT the legacy `4client-`), their own route table `app_outbound_maqnelson_prv` + associations, the default (TGW egress) and Management routes, SSM wiring under `/networking/app-outbound-maqnelson/`. Plan was `9 to add, 0 change, 0 destroy`; apply clean. CIDRs confirmed free against live AWS. **Merge is the engineer's.**
2. ✅ **Scoped database path — APPLIED (both halves).**
   - **Network half** — PR [terraform#822](https://github.com/4shark/terraform/pull/822) (merged): cross-region peering integrator VPC ↔ shared-001 codified in Terraform; DB route (`10.100.0.0/22`) ONLY on `app_outbound_maqnelson_prv`; shared-001 return routes ONLY to `10.1.2.128/27`.
   - **Database-environment half** — PR [terraform#823](https://github.com/4shark/terraform/pull/823) (APPLIED 2026-07-24, open awaiting merge): pooler SG accepts `10.1.2.128/27` on the listen port (via `extra_ingress_cidrs`); the pooler's Cloud Map zone is associated with the integrator VPC (via a sa-east-1 provider alias + the `pooler_cloud_map_hosted_zone_id` output) so the pooler host resolves end to end. Plan `1 add, 1 change (SG ingress, additive), 0 destroy`; apply clean.
3. ✅ **Customer routes on the outbound route table — APPLIED + MERGED.** PR [terraform#825](https://github.com/4shark/terraform/pull/825): the two customer CIDRs → the integrator's VGW, codified. Plan `2 add`, apply clean.
4. ✅ **app-outbound-maqnelson stack repoint — APPLIED + MERGED 2026-07-24, PR [terraform#824](https://github.com/4shark/terraform/pull/824).** Both services moved from the integrator's shared subnets to the dedicated ones. Plan `0 add, 2 change in-place, 0 destroy`; apply clean. **Verified live**: the worker service runs in `app-outbound-maqnelson-prv-a` (`10.1.2.128/28`) + `-prv-b` (`10.1.2.144/28`).

**INFRA COMPLETE + MERGED (all 5 PRs).** The outbound tasks run in the dedicated subnets with routes to the database (scoped to those subnets) and to the customer (over the integrator's existing VPN), and nothing else in the integrator VPC can reach production data. Networking rework done — the remaining work is Phase 8 homologation (engineer-driven), unblocked below.

## Phase 8 homologation — access + authentication CONFIRMED; final payment push is the only step left

**Access confirmed (2026-07-24).** From the outbound environment the console boots (it reaches the shared-001 DB) and the auth probe reaches the customer Nexus (customer routes in place). The two paths the networking rework had to deliver — DB and customer — are both live.

**Authentication confirmed (2026-07-24).** The auth probe hit the customer Nexus and got HTTP 200 with a valid token. This surfaced and closed a token-field bug on the way: the access token is at `data.tokenAcesso` in the response, not the assumed `access_token` (fixed on `MaqnelsonIntegration::Processor`, merged app#5261). A blank-token guard + `data`-key redaction followed (merged app#5262): if authentication ever fails to return a token, the processor halts the integration, marks the payments `failure`, and sets the payment to `integration_error` (reprocessable) — the systemic auth-failure control this outbound needs precisely because it is a single zonal push (all-or-nothing), unlike the distributed FPW flow.

**Only the final payment push remains — awaiting the customer.** The customer is sending the ID of an existing platform payment to test against. Once it arrives, the test is: run the outbound push for that one payment ID from the outbound environment and confirm it lands correctly on the customer side. This is engineer-driven and coordinated with the customer (it writes real data to their Nexus), so it is not run unattended.

### Test procedure — ready to run the moment the payment ID arrives

**Entry point (read from `app/workers/maqnelson_integration/processor.rb`, 2026-07-24):** `MaqnelsonIntegration::Processor#perform(payment_id)` — a `TenantWorker` on the `:payroll` queue that takes a single `payment_id` and runs the whole auth → build payload → push flow inline. `TenantWorker#with_company_id` only sets the thread var that routes the *queue*; the instance `perform` reads the global DB directly, so calling `.new.perform(payment_id)` synchronously in a console needs no tenant switch. Run it **synchronously in a console in the outbound environment** (`bin/ecs run app-outbound-maqnelson 'bundle exec rails console'`) — not `dynamic_perform_async` — so the result and timing come back immediately instead of through the queue.

**State-machine gate (read from `app/models/payment.rb`):** `perform` calls `payment.start_integration!` first, and `start_integration` only transitions from `pending_integration` (or `integrating`). So the payment MUST be in `pending_integration` before the run. `finish_integration` → `integrated` is the success end-state; `integration_error` is the failure end-state. The customer's ID is customer input — pre-flight it before mutating.

**Phase 1 — pre-flight (read-only, confirms the customer's premise before any push):**

```ruby
payment_id = <ID_QUE_O_CLIENTE_ENVIAR>
payment = Payment.find(payment_id)
payment.status                                      # must be pending_integration to run as-is
payment.company.payroll_integration.class.name      # expect "MaqnelsonIntegration" (right endpoint/credentials)
payment.user_payments.group(:integration_status).count   # there must be pending (or failure) rows to send; billable_money: 0 gets skipped
```

If `status` is `final` (exported, never integrated) or `integration_error` (a prior failed attempt), move it to `pending_integration` first — this is the sanctioned reprocess path:

```ruby
payment.queue_integration!   # final | integration_error -> pending_integration
```

If `status` is already `integrated`, there is nothing to test — do NOT run (the processor would hit `start_integration!` from `integrated`, which has no transition, raise, and land the payment in `integration_error`).

**Phase 2 — the push (the one mutating call):**

```ruby
MaqnelsonIntegration::Processor.new.perform(payment_id)
```

**Phase 3 — verification + measurement:**

```ruby
payment.reload.status                                                   # "integrated" = success ; "integration_error" = failure
PayrollRequest.where(payment_id: payment_id, action: :execution).last   # .status, .duration (the measure), .response_body (customer's response)
PayrollAuthenticationRequest.where(payment_id: payment_id).last         # finished (auth ok) vs error
payment.user_payments.group(:integration_status).count                  # success / skipped / failure breakdown
```

Success = payment `integrated`, the execution `PayrollRequest` `success`, and the user_payments moved to `success`/`skipped`. Any failure lands the payment in `integration_error` (reprocessable via `queue_integration!`), with the reason preserved in the `PayrollRequest`/`PayrollAuthenticationRequest` rows — re-running is safe: only `pending`/`failure` user_payments are re-sent, so a partial success is not double-pushed.

**FPW auth-failure decision (2026-07-24, settled): leave FPW as-is.** FPW is a distributed Producer/Consumer flow, so a per-record failure is the correct behavior there — some records failing while others succeed is expected. A live probe confirmed the LG/FPW SOAP API authenticates inline per call and returns HTTP 500 + a `Senha inválida` Fault on a bad credential, which the existing consumer `else` branch already marks as `integration_status: :failure`. The systemic halt (this Maqnelson pattern) is NOT ported to FPW — the zonal all-or-nothing shape that justifies it does not apply to a distributed flow.

### Manual dry-run — when the customer never sends an ID, pick the latest existing payment ourselves

The customer did not send a payment ID and stopped responding (WhatsApp + a group, no reply). Decision (engineer, 2026-07-30): pick an existing payment from the Maqnelson company ourselves and integrate it **manually, step by step in the outbound console**, watching each step's result before committing — because the push writes a real payroll value to the customer's Nexus. Minimize the footprint by sending a **single `user_payment`** first, so the customer has one clean record to validate ("subiu o valor?") and then delete. Only after that succeeds do we do the full load. The handshake is: run the manual push → ask them to confirm the value went up → on confirmation, ask them to delete the test record → then run the full integration.

The manual walkthrough is **zero-side-effect on our side, by hard requirement (engineer, 2026-07-30): the engineer will not write an undo script.** It reproduces the `Processor` flow as plain console reads + HTTP calls but persists NOTHING locally — it does NOT call `start_integration!` / `update_all` / `finish_integration!` (no state flip) AND does NOT create the `PayrollRequest` / `PayrollAuthenticationRequest` audit rows the `Processor` normally saves. Every observation is a `puts` to the terminal. The **only persisted effect anywhere is the single POST to the customer's Nexus** (the one record they validate and delete). This is the whole reason for not using `.new.perform(payment_id)`: `perform` flips our state and writes the audit rows inline, which would then need cleanup. If a step raises, the console prints the backtrace and there is still nothing to undo.

**Discovery — find the company and the latest candidate payment (read-only):**

```ruby
company = Company.find(97)                                         # Maqnelson company_id (engineer, 2026-07-30)
company.payroll_integration.class.name                            # confirm "MaqnelsonIntegration"
company.payments.order(id: :desc).limit(10).pluck(:id, :status)   # pick the latest with sendable user_payments
```

**Build the payload without mutating anything (unrolled from `Processor#perform`):**

```ruby
payment = Payment.find(<ID_ESCOLHIDO>)
payroll_integration = company.payroll_integration
user_payments = payment.user_payments.with_integration_status(:pending, :failure).where.not(billable_money: 0).order(:id).limit(1)   # ONE record first
pagamentos = user_payments.map { |up| { usuario_id_externo: up.user.primary_identifier_value, tipo_pagamento_id_externo: up.payment_type.external_id, premio_valor: up.billable_money.to_s } }
body = { mes_competencia: payment.reference_month.month.to_s, ano_competencia: payment.reference_month.year.to_s, pagamentos: pagamentos }
pp body
```

**Authenticate (external call, read-only on their side) and push (the real write):** unrolled from `Processor#perform` lines 42-108 — same auth path, token at `data.tokenAcesso`, `Bearer` push to `payroll_integration.path`. Inspect `response.code` / `response.body`. Do NOT flip DB state until the customer confirms the value landed; then either leave our side as-is for the full load or set the touched `user_payments` to `:success` by hand.

**Result — manual single-record push SUCCEEDED (2026-07-30).** Auth returned HTTP 200; the push returned HTTP 201 with `{"sucesso":true,"mensagem":"Lote processado com sucesso.","total_pagamentos":1,"mes_competencia":6,"ano_competencia":2026}` for one commission record (competência 6/2026). Nothing was persisted on our side (no state flip, no `PayrollRequest`/`PayrollAuthenticationRequest` rows). The full outbound path — networking, auth, payload, push — is proven end to end against the real customer Nexus. **Open handshake:** ask the customer to confirm the value landed on their side, then ask them to delete the test record, then run the full load.

**Next phase (after the single push is validated): full load.** Send every pending `user_payment` of the payment (drop the `.limit(1)`), or run the synchronous `.new.perform(payment_id)`. The "UserCommission / Commissioning" the engineer mentioned is the source-of-value question for that full load — to be pinned down when we get there, not now.

**Follow-up (engineer, 2026-07-24):** revisit the atento-br outbound after this — it likely peers its VPC broadly to `app-atento-001` for the database and may grant wider production-DB access than intended; apply the same scoping.

---

## SUPERSEDED — the separate-VPC alternative (built then reverted)

*(Kept for the record. NOT the chosen path — a terminology mix-up led to building a dedicated VPC, which was reverted. The chosen path is dedicated subnets, above.)*

## Goal

Keep the outbound payroll cluster in the **integrator-maqnelson VPC** (no new VPC, no new customer VPN) while giving it a network path to the **shared-001 database** — WITHOUT exposing the rest of that VPC (customer VPN side + integrator workloads) to the production database. Isolation is by **routing**: dedicated subnets + a dedicated route table that is the ONLY place the shared-001 route lives.

## Confirmed facts (read from live AWS + terraform, 2026-07-24)

- Integrator VPC `4client-maqnelson` = `10.1.2.0/24`. Two private subnets today: `prv-a` `10.1.2.0/26`, `prv-b` `10.1.2.64/26`, both on route table `maqnelson_prv` (`rtb-0d2a44868566b3774`). Free space: `10.1.2.128`–`.255`.
- The outbound tasks currently SHARE those integrator subnets (`app-outbound-maqnelson` reads `networking_data.private_ids`). That is why SG-only isolation is insufficient — the DB route would sit on the shared RT.
- `maqnelson_prv` routes today: `192.168.82.0/26` + `192.168.90.0/26` → VGW `vgw-0a4e249fccdc268b8` (customer network, **hand-added out of band**, `origin: CreateRoute`, tolerated by `ignore_changes=[route]`); `10.255.0.0/16` → management peering `pcx-0cfc2971e1dedf0cc`; `0.0.0.0/0` → TGW (egress). Propagation OFF.
- The customer VPN routes are NOT in terraform. `modules/integrator/vpn.tf` creates only `aws_vpn_connection_route` (the tunnel's static routes), never the VPC-route-table `aws_route`. So the VPC routes to the customer are a **manual step** in the existing design.
- Cross-region peerings here are "created out of band and imported" (`networking/peering.tf` header). The atento outbound → app-atento-001 DB peering is not even in terraform. So the integrator↔shared-001 peering is a **manual step** too, consistent with precedent.
- shared-001 VPC = `10.100.0.0/22` (us-east-1). Its pooler publishes `connection-pooler-shared-001.4shark.internal` (CNAME in `4shark.internal`) → `connection-pooler.shared-001.internal` (AWS Cloud Map private namespace, associated only with the shared-001 VPC).

## Design — dedicated outbound subnets in the integrator VPC

Two dedicated private subnets for the outbound tasks: `10.1.2.128/28` (sa-east-1a) + `10.1.2.144/28` (sa-east-1b), on their OWN route table `maqnelson_outbound_prv`. That RT carries:

- `local` (automatic)
- `192.168.82.0/26` + `192.168.90.0/26` → VGW `vgw-0a4e249fccdc268b8` (so the outbound still reaches the customer Nexus) — **manual, matching the existing hand-added pattern**
- `10.255.0.0/16` → management peering — terraform
- `0.0.0.0/0` → TGW egress — terraform
- **`10.100.0.0/22` → the new cross-region peering to shared-001** — the route is terraform, the peering is manual/imported

The integrator's existing RT `maqnelson_prv` is **left untouched** — it never gets the `10.100.0.0/22` route, so the customer VPN side and the integrator's own workloads have NO path to the DB. That is the whole security guarantee: routing, not SG.

## Sequenced execution

**PR 1 — networking stack** (`networking/`): the two dedicated subnets, `maqnelson_outbound_prv` route table (`ignore_changes=[route]` like its sibling) + associations + the terraform-managed routes (management, egress). SSM wiring so the app stack consumes the new subnet ids. TGW attachment: the new subnets ride the existing maqnelson TGW attachment (same VPC) — confirm whether the attachment's subnet list needs the new subnets or the VPC-level attachment already covers them.

**Manual step A — cross-region peering** integrator-maqnelson VPC ↔ shared-001 VPC, created from the requester side + accepted (the established out-of-band pattern), then the `10.100.0.0/22 → pcx` route added to `maqnelson_outbound_prv` and the return route `10.1.2.128/28`+`10.1.2.144/28 → pcx` on the shared-001 side (scoped to the outbound subnets ONLY, never the whole integrator VPC).

**Manual step B — customer VGW routes** on `maqnelson_outbound_prv` (`192.168.82.0/26` + `192.168.90.0/26` → VGW), matching how the existing RT's customer routes are hand-managed.

**PR 2 — app-shared-001 stack**: pooler security-group rule allowing ONLY `10.1.2.128/28`+`10.1.2.144/28` on the pooler port; associate the `shared-001.internal` Cloud Map namespace's private zone with the integrator VPC so the outbound resolves `connection-pooler.shared-001.internal`.

**PR 3 — app-outbound-maqnelson stack**: repoint the ECS services from `networking_data.private_ids` (shared integrator subnets) to the new dedicated subnet ids.

**Customer coordination**: none for the DB path (internal). The customer VPN already exists — no new tunnel, unlike the reverted dedicated-VPC approach.

## What this guarantees

Cuts the two paths the engineer named: the customer network and the integrator's own workloads have no route to the production DB (the route lives only on the outbound subnets' RT; the shared-001 return route + pooler SG accept only those subnets). Irreducible residual: a compromised outbound TASK has the DB access it legitimately needs — unavoidable, and unrelated to the VPC-sharing question.

## Open item to confirm before PR 1

The TGW attachment subnet list: the existing `aws_ec2_transit_gateway_vpc_attachment.maqnelson` lists `maqnelson_prv_a`/`prv_b`. A Fargate task's egress default route (`0.0.0.0/0 → TGW`) needs the TGW reachable from the new subnets — confirm whether the attachment must add the new subnets or whether one attachment subnet per AZ suffices for the VPC.
