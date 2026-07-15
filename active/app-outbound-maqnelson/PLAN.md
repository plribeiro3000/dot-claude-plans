# PLAN — app-outbound for Maqnelson (Option A: inside the integrator VPC)

**Date:** 2026-07-14 (revised after the 08:00 meeting + codebase research)
**Feeds from:** `SPIKE.md` (this folder) — decision: **Option A**, confirmed to the customer in the meeting.
**Goal:** Run the Maqnelson outbound service (pushes award/payment data to the Nexus API) inside the `integrator-maqnelson` VPC, reusing the existing VGW site-to-site VPN.
**Deadline:** **Monday 2026-07-20** — report to Fanini either "ready for production" or the blocking bugs with an estimate.

---

## Context from the meeting — "4shark - VPN - api", 2026-07-14 08:00

Participants: Paulo Ribeiro (4Shark); Deivid Pereira, Paulo Fanini, Thiago Alves (Maqnelson).

- **Architecture confirmed to the customer:** *"vou subir uma cópia da aplicação na rede que está a VPN"* — the outbound app instance runs **inside the VPC that holds the VPN**, in sa-east-1. Option A is a commitment, not just an internal preference.
- **VPN route settled — two specific routes, not `0.0.0.0/0`:** Deivid proposed `0.0.0.0/0` (Maqnelson enforces access by their own policies). It **conflicted with 4Shark's existing `0.0.0.0/0` default route** (private RT → Transit Gateway for centralized egress, `networking/vpc_maqnelson.tf:69-75`). Resolution: keep **both specific routes** — `192.168.90.0/26` (legacy DB) + `192.168.82.0/26` (Nexus).
- **Connectivity validated live:** reached `192.168.82.10:80` through the tunnel from a task in the integrator VPC (source `10.1.2.x`, dynamic — Fargate assigns at startup; Deivid accepted, they filter by their own policies). Legacy DB route re-tested, still works.
- **DNS required:** the Nexus host is internal and only answers to its domain — *"você não consegue acessar pelo domínio, porém ela só responde pro domínio"*. For ECS Fargate the mechanism is the Route53 private zone, not `/etc/hosts` (see `dns/internal_dns_atento_vpn.tf`: *"The EC2 instances used /etc/hosts for this; ECS Fargate uses Route53"*).
- **App code already exists** (confirmed in the codebase — see below).
- **Contract updated during the call:** Thiago sent a reduced-attribute contract by e-mail (2026-07-14) + the Postman collection.
- **`dev-nexus` is HOMOLOGATION.** Fanini: *"quando for pra produção é tranquilo a gente virar o caminho"*.
- **Test protocol:** Fanini authorized running integrations freely, but **notify Fanini before sending a test load** (state the total); afterwards **both sides cross-check**.

---

## What already exists (codebase research, 2026-07-14)

The app side is **built**, not pending:

- **`app/app/models/maqnelson_integration.rb:3`** — `class MaqnelsonIntegration < PayrollIntegration`, with `validates :user_name, presence: true` and `validates :user_password, presence: true`; `bulk?` and `reprocessable?` both true.
- **`app/app/workers/maqnelson_integration/processor.rb:8-9`** — `class Processor < TenantWorker` with `base_queue_name :payroll`. Follows the Processor topology and the data-access rules (`with_uncached_connection` per access, IDs-only, join decomposition).
- **The contract is already implemented** (`processor.rb:29-40`) and matches the e-mailed contract exactly:
  ```ruby
  {
    usuario_id_externo: user.primary_identifier_value,
    tipo_pagamento_id_externo: payment_type.external_id,
    premio_valor: user_payment.billable_money.to_s
  }
  # body: { mes_competencia:, ano_competencia:, pagamentos: [...] }
  ```
- **Auth flow exists** (`processor.rb:42-74`): POSTs `{ username, password }` to the token endpoint, then Bearer-authenticates the payload POST. Both `PayrollAuthenticationRequest` and `PayrollRequest` are persisted with the password/token redacted.
- **Queue derivation** (`app/app/workers/tenant_worker.rb:106-125`): the queue resolves **per company** via `Queue.new(self, company)` → `payroll_<shard>`.

### Corrections this research forces on the earlier plan

1. **The Nexus credential does NOT go to SSM.** It lives on the company's **`payroll_integration` record** — `user_name` / `user_password` (`maqnelson_integration.rb:4-5`), read at `processor.rb:50`. The earlier "put it in shared-001 SSM" phase was wrong and is removed.
2. **The endpoint is DB config, not infra.** `payroll_integration.hostname` holds the request URL (`processor.rb:76`), and the token URL is **derived** from it: `hostname.sub('/pagamentos', '/auth/token')` (`processor.rb:42`). **Constraint: the hostname must end in `/pagamentos`**, otherwise auth resolves to the wrong URL. This also makes the homologation→production switch a **DB change**, not an infra change (unless the production host sits on a different subnet).

---

## Decisions — resolved (no open questions)

1. **Stack shape → dedicated `terraform/app-outbound-maqnelson/` stack.** Precedent: `app-outbound-atento-br` is its own stack with its own state key (`app-outbound-atento-br/providers.tf:24`). It deploys compute *into* the integrator VPC, resolving the network via `module.networking_data` with `networking_environment = "integrator-maqnelson"` (the same way `integrator-maqnelson/main.tf:11-17` resolves its own).
2. **Task config → extract `modules/shared_001_task_config`.** `modules/atento_001_task_config` exists **precisely because** the Atento outbound needed to share atento-001's env — its own comment: *"reused by app-atento-001 and app-outbound-atento-br"*. Same move. **Done** — no-op plan on shared-001.
3. **Worker/queue → `MaqnelsonIntegration::Processor` on `payroll_white_shark`,** launched like the Atento outbound: `sidekiq -C config/sidekiq_payroll_white_shark.yml`. Engineer's call: the lane is a free choice ("tanto faz") because **no company in shared-001 uses a suffix today** — they all sit on the bare `commission` queue. `white_shark` is picked over `tiger_shark` so the lane names stay visually distinct from the atento-001 stack's in dashboards and logs; both are free in this database (the unique index is per-database, and the stacks have separate ones).
   - **Blocked on the queue-suffix split below** — assigning the suffix before the split hands Maqnelson a dedicated commission lane for free.

## The queue-suffix problem — one variable governs two domains

`app/app/models/tenant_worker/queue.rb:23` derives **every** TenantWorker's queue from a single company attribute:

```ruby
"#{@worker.base_queue_name}#{@company.commission_queue_suffix}"
```

So `commission_queue_suffix` routes the commission workers (`base_queue_name :commission`) **and** the payroll/outbound worker (`base_queue_name :payroll`) alike. Supporting facts:

- **The suffix is the dedicated-lane mechanism.** `db/schema.rb:532` — `t.index ["commission_queue_suffix"], name: "index_companies_on_commission_queue_suffix", unique: true`. One company owns a suffix exclusively; `NULL` (the shared-001 default today) means the bare queue.
- **It is a commission-domain concept.** `app/app/workers/partial_commission/finalizer.rb:21-24` groups companies by `commission_queue_suffix` and fans commission work out per suffix.

**The consequence:** setting a suffix on Maqnelson's company to give the outbound its `payroll_white_shark` queue **also** moves their commission jobs to `commission_white_shark` — a dedicated commission lane the customer is not paying for.

**The column is not the problem.** `commission_queue_suffix` is correctly named and correctly scoped: it is the commission pipeline's lane, and 24 of the 25 base queue names are that pipeline. The defect is `queue.rb:23` reading it for `:payroll` too. So the fix is a **new column for payroll** (Phase 4), not a rename and not a generalization.

This is a **prerequisite**, not a follow-up — the giveaway happens the moment the suffix is set.

---

## Status board

| Item | Status |
|---|---|
| VPN route (`192.168.82.0/26`) | ✅ Done, validated live, PR #696 merged |
| App: model + worker + contract + auth flow | ✅ Exists |
| Internal DNS override (`dev-nexus.maqnelson.com.br`) | ✅ Applied (2 added, 0 changed, 0 destroyed) — PR #698 open |
| `modules/shared_001_task_config` (extract from app-shared-001) | ✅ Done, no-op plan on shared-001 — PR #699 open |
| Split the tenant queue suffix (commission vs payroll) | ✅ Done — PRs #5226 / #5228 / #5230; shipped in 3.52.0 (column) + 3.53.0 (routing) |
| Outbound compute stack (in the integrator VPC) | ⬜ To do |
| `sidekiq_payroll_white_shark.yml` | ⬜ To do |
| `payroll_integration` record for Maqnelson (hostname + credentials) | ⬜ To do (DB config) |
| Contract diff vs Thiago's reduced version | ⬜ To do |
| Homolog end-to-end test (notify Fanini first) | ⬜ To do |
| Production endpoint switch | ⬜ Later, with Maqnelson |

---

## Execution phases

### Phase 1 — VPN route — ✅ DONE

- Terraform: `integrator-maqnelson/main.tf:44` — `customer_network_cidrs = ["192.168.90.0/26", "192.168.82.0/26"]`. The `integrator` module derives the tunnel static route (`modules/integrator/vpn.tf:93`) and the private-RT route → VGW (`modules/integrator/routing.tf:5`).
- **PR [#696](https://github.com/4shark/terraform/pull/696) merged**; branch and worktree cleaned up.
- AWS ground truth: VPN connection `vpn-0f139221de4133cfd`, state `available`, carries both routes.
- Do **not** convert these to `0.0.0.0/0` — it collides with the private RT's default route to the Transit Gateway.

### Phase 2 — Internal DNS override (dns/) — ✅ DONE

- `dns/internal_dns_maqnelson_vpn.tf`, molded on `dns/internal_dns_atento_vpn.tf`: Route53 private hosted zone associated with the **integrator-maqnelson VPC** (`vpc-0d8b6d6a5819c0b21`), `A` record `dev-nexus.maqnelson.com.br` → `192.168.82.10`, TTL 60.
- **The zone is scoped to the full hostname, not to `maqnelson.com.br`** — the apex is the customer's corporate domain and carries public hosts (their website); a zone at the apex would shadow them inside the VPC. Each new VPN-reachable host under this domain gets its own zone (~US$ 0.50/mo each), so the production hostname in Phase 10 is a new zone, not a new record.
- Applied: 2 added, 0 changed, 0 destroyed. **PR [#698](https://github.com/4shark/terraform/pull/698) merged**; branch and worktree cleaned up.

### Phase 3 — Extract `modules/shared_001_task_config` — ✅ DONE

- Inline env/secrets moved from `app-shared-001/compute.tf` into `modules/shared_001_task_config`, mirroring `modules/atento_001_task_config`'s interface (`cluster_name` + optional `opensearch_host` in; `env_vars` + `secrets` out). `app-shared-001` re-pointed at it (`locals.tf`, `scheduled-tasks.tf`).
- **Gate passed:** `terraform plan` on shared-001 → *"No changes. Your infrastructure matches the configuration."*
- Two traps handled: shared-001's `opensearch_host` carries a **trailing slash** (atento's does not) — copying atento verbatim would have rewritten a productive task definition; and the module's string ARNs drop the implicit dependency on the SSM parameters **this** stack owns, so `module.app` gained `depends_on = [aws_ssm_parameter.secrets, aws_ssm_parameter.mongo_url]` — the mitigation the module README prescribes for the owning stack.
- **PR [#699](https://github.com/4shark/terraform/pull/699)** open, awaiting merge.
- Follow-up left untouched (out of scope): `app-shared-001/locals.tf` uses single-letter iterators in the services comprehension.

### Phase 4 — Give payroll its own queue lane (app) — PREREQUISITE — ✅ DONE (shipped 3.52.0 + 3.53.0)

`commission_queue_suffix` is **correctly named and correctly scoped** — it is the commission pipeline's lane. The defect is that `queue.rb:23` reads it for *every* TenantWorker, so payroll rides on the commission lane. The fix is a new column for payroll, not a rename.

**The split is cleanly 2-way** (`grep base_queue_name` across `app/workers/`):

- **`:payroll`** — 9 workers. The only outlier; gets the new lane.
- **The other 24 base queue names** — `commission_setup`, `deal_indexation`, `deal_metrification`, `deal_accumulation`, `indicator_*`, `ranking_incentive_calculation`, `limiter_*`, `redemption_*`, `commission_*_caching`, `user_payment_type_*_caching`, `money_sanitization` — are the commission pipeline (they match the queue list in `config/sidekiq_commission_white_shark.yml`). They keep `commission_queue_suffix` untouched.

Steps:

1. **Migration** — ✅ done. `payroll_queue_suffix` on `companies`, nullable + unique index, mirroring `commission_queue_suffix`. Shipped in **release 3.52.0** and deployed to all 4 environments (this was Deploy 1).
2. **Code** — ✅ done, PR **#5228**. `TenantWorker::Queue#queue_suffix` picks the column by the worker's `base_queue_name` (`:payroll` → the payroll column; everything else → commission).
   - **Decision taken at implementation** (the plan deliberately left the mechanism open): the lane is **inferred, not declared**. An earlier cut added a mandatory `queue_suffix_source` declaration to all 82 workers; it was discarded. The queue name a worker declares *already* says which process it belongs to — the sidekiq configs partition the queues along exactly that line, one config per process — so a per-worker declaration is a **second source of truth for a fact the first already determines**, and two sources can disagree (a worker declaring `:payroll` while sitting on a commission queue would route to a queue no config consumes). Inference derives from the queue name itself and cannot contradict itself.
   - **The cost accepted:** commission is the silent default (everything not `:payroll`). A *second* payroll queue added in future must be added to the `if` in `queue.rb` — otherwise it silently takes the commission suffix.
3. **Missing `base_queue_name` now raises** — PR **#5228**. A worker on the dynamic path without a declared queue name used to enqueue to a queue named after the suffix alone (no consumer, job sits forever, silent). `Queue#name` raises `MissingBaseQueueNameException` before the enqueue.
4. **Eligibility-module workers corrected** — PRs **#5228** / **#5230**, surfaced by step 3. Eight workers declared a static queue *and* were enqueued dynamically (the mix `tenant_worker.rb:16` forbids), on a queue (`commission_processing`) that no sidekiq config consumed while hire_fire autoscaled it. Each now declares the queue of its own domain — `Metric::Sower/Grower` → `deal_metrification`, `AccumulatedDeal::*V2` → `deal_accumulation` (both reuse their class's existing queue), `EligibilityPeriod::*` → `eligibility_period_calculation`, `DealEligibility::*` → `deal_eligibility_calculation` (both new, unconsumed, matching the module's inactive state). The stale hire_fire entries were dropped. A `NameError` in `EligibilityPeriod::Sower`'s fan-out was fixed (#5230). No client has the module enabled — zero behavior change.
5. **Data (engineer, by hand — one record each, no data migration in code):** ✅ done.
   - **atento-001**: `payroll_queue_suffix` = `_tiger_shark`, matching its `commission_queue_suffix`, so `payroll_tiger_shark` keeps resolving for the existing outbound.
   - **shared-001**: Maqnelson (company 97) set to `_tiger_shark` as an interim value — inert while Phase 7 has not created the `payroll_integration` record, so no payroll job is ever enqueued for them. Phase 7 sets the final lane. Every other company stays `NULL` → bare `payroll`, unchanged.
6. **`partial_commission/finalizer.rb:21-24`** — ✅ verified untouched. It reads `commission_queue_suffix` directly off the Company and never constructs a `Queue`, so the split does not reach it; it keeps fanning commission out by the commission lane.

**Deploy ordering — this needs two deploys (expand/contract), not one.** The ephemeral migration task runs *before* the new code goes live, so a single deploy would leave a window where the column exists as `NULL` and the new code already reads it — atento's payroll jobs would route to the bare `payroll` queue, which no worker consumes. They would pile up silently (no error, no alert). Order:

1. **Deploy 1** — ✅ done. Migration only, shipped as release **3.52.0**, deployed to all 4 environments. Nothing read the new column yet; behavior unchanged.
2. **Engineer sets the records** — ✅ done (step 5 above).
3. **Deploy 2** — ✅ shipped as release **3.53.0** (PR #5231 merged to master, tag `3.53.0` on the `chore(release)` commit, back-merged into develop). The `queue.rb` switch (#5228) and the eligibility fix (#5230) went out to the 4 environments; the engineer checked each Sidekiq queue depth before triggering, per the `sidekiq quiet` gate in `app/CLAUDE.md`. Both company records already carried their values, so the switch read what existed — the window the two-deploy ordering exists to avoid never opened.

Per `DEPLOYMENT-STRATEGY.md` this is a legitimate phased change: the queue derivation is an in-flight contract, and breaking it orphans enqueued jobs rather than failing loudly.

### Phase 5 — Outbound compute (new stack, into the integrator VPC)

Mirror `app-outbound-atento-br/compute.tf`, with three deltas: network points at the integrator VPC, config comes from `shared_001_task_config`, and **no VPN/VGW is created** (it already exists).

- Scaffold `terraform/app-outbound-maqnelson/` (`providers.tf` sa-east-1 + cross-region alias to shared-001; `locals.tf`; `main.tf`; `compute.tf`; `iam.tf`; `output.tf`; `stack.tm.hcl`; `README.md`).
- `main.tf`: resolve the integrator VPC via `module.networking_data` (`networking_environment = "integrator-maqnelson"`); a **dedicated** `aws_security_group` for the outbound tasks (egress all, so traffic to `192.168.82.10` follows the private RT to the VGW; ingress from the management VPN SGs for debugging). Do **not** instantiate `modules/app_outbound` (its VPN/DNS assumptions do not fit) and do **not** touch the VPC's default SG (owned by the integrator module).
- `compute.tf`: ECS cluster, worker service running `sidekiq -C config/sidekiq_payroll_white_shark.yml`, runner service (`desired_count = 0`, for `bin/ecs run`), autoscaling Lambda + EventBridge scheduler; tasks in the **integrator VPC private subnets**; env/secrets from `module.task_config`.
- `locals.tf` tags: `Project = "app-outbound"`, `Environment = "outbound-maqnelson"`, `Client = "maqnelson"` (mirror `app-outbound-atento-br/locals.tf:17-21`).
- `plan`, apply-before-merge.

### Phase 6 — App: sidekiq payroll config + contract diff

- Create `app/config/sidekiq_payroll_white_shark.yml` mirroring `sidekiq_payroll_tiger_shark.yml` (queue `payroll_white_shark`, concurrency from `ApplicationConfiguration.sidekiq_threads`).
- Diff the implemented contract (`processor.rb:29-40`) against Thiago's reduced-attribute version from the 2026-07-14 e-mail + Postman collection. The current body already matches the e-mailed contract — expect a small attribute diff, not a rewrite.

### Phase 7 — `payroll_integration` record + payroll lane for Maqnelson (DB config)

- Set the company's **payroll lane** to `_white_shark` (the new attribute from Phase 4). The commission lane stays `NULL` — the customer keeps the shared `commission` queue they pay for.

- Create/point the company's `payroll_integration` (type `MaqnelsonIntegration`) with:
  - `hostname` = the homologation request URL — **must end in `/pagamentos`** so `processor.rb:42` derives the token URL correctly.
  - `user_name` / `user_password` = the Nexus access credentials from Maqnelson's e-mail. These live **only** in the record — never in code, Terraform, or a PR.
- Because the password transited e-mail, flag it to Maqnelson for rotation once wired.

### Phase 8 — Homologation end-to-end test

- **Notify Fanini first**, stating the total being sent (agreed protocol).
- Scale the worker up, trigger the payment integration, confirm 2xx and that `PayrollRequest` / `PayrollAuthenticationRequest` rows record success.
- **Cross-check with Maqnelson on both sides.** Confirm the integrator's DB access (`192.168.90.0/26`) is unaffected.

### Phase 9 — Report by Monday 2026-07-20

- Report to Fanini: "ready for production", or the blocking bugs + estimated fix time.

### Phase 10 — Production switch (later, with Maqnelson)

- Primarily a **DB change**: update `payroll_integration.hostname` to the production URL (still ending in `/pagamentos`).
- Infra only if the production host sits on a **different subnet** — then a VPN route (`customer_network_cidrs`) + a Phase-2 addition on Maqnelson's side + a new private zone for the production hostname (per the scoping decision in Phase 2). Confirm with Deivid.

---

## Risks / watch-items

- **The queue-suffix split touches every tenant queue in every environment** — `queue.rb:23` is the single derivation point for all TenantWorkers. A regression there silently misroutes jobs to a queue no worker consumes (they pile up, they do not error). Backward compatibility for every existing company is the gate.
- **Setting the payroll lane before the split gives away a commission lane** — the giveaway is immediate and billing-relevant, not cosmetic. Phase 4 blocks Phase 7.
- **Shared blast radius** — outbound and integrator share the VPC and the `10.1.2.0/24` CIDR (accepted per SPIKE §5). The dedicated outbound SG keeps the security surface separate.
- **`hostname` must end in `/pagamentos`** — the token URL is derived by string substitution (`processor.rb:42`); a hostname without that suffix silently breaks auth.
- **No fixed source IP** — Fargate assigns the task IP at startup. Accepted by Deivid. If Maqnelson ever demands a fixed source IP, that is a new design problem — surface it, do not improvise.
- **Credential hygiene** — the Nexus password transited e-mail; treat as compromised-pending-rotation.
- **Timeline** — 20/07 is the commitment. The split (Phase 4) is now on the critical path and is the least-bounded piece; if it slips, the fallback is to ship the outbound on the bare `payroll` queue (no lane, no giveaway) and add the lane after — worth deciding early rather than at the deadline.

## Out of scope

- No new VPN, no Transit Gateway change, no proxy (rejected in `SPIKE.md`).
- Do not convert the VPN routes to `0.0.0.0/0` (conflicts with the TGW egress default route — proven in the meeting).
