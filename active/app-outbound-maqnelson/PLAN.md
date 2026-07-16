# PLAN — app-outbound for Maqnelson (Option A: inside the integrator VPC)

**Date:** 2026-07-14 (revised after the 08:00 meeting + codebase research)
**Feeds from:** `SPIKE.md` (this folder) — decision: **Option A**, confirmed to the customer in the meeting.
**Goal:** Run the Maqnelson outbound service (pushes award/payment data to the Nexus API) inside the `integrator-maqnelson` VPC, reusing the existing VGW site-to-site VPN.
**Deadline:** **Monday 2026-07-20** — report to Fanini either "ready for production" or the blocking bugs with an estimate.

---

## ⏭️ NEXT — the release runbook (all code is merged; this is the engineer's part)

**Both code PRs are merged** ([#5236](https://github.com/4shark/app/pull/5236) columns, [#5235](https://github.com/4shark/app/pull/5235) models + workers). `develop` is at `af05ca391`. What follows is one operation on `atento-001`, in this order. Full detail in **Phase 6.3 / 6.4**.

| # | Step | Gate before the next step |
|---|------|---------------------------|
| 1 | **Disable the outbound autoscaling Lambda** (`atento-001`) — the worker sits at `0/0`, so it stays there and anything triggered queues in Redis | Lambda confirmed off |
| 2 | Cut the release → deploy `atento-001` | Deploy green |
| 3 | **Backfill `scheme` + `path`** — the script in 6.3, via `bin/ecs run`. One row | It printed `OK`, **and the assembled URL matches `execute_consumer.rb:70`** — `http://<hostname>/lg.com.br/svc/servicodeeventosdofuncionario`. If it differs, STOP |
| 4 | **Run the verification** — the second script in 6.3 | **Prints nothing.** Any `STILL NULL` line means step 5 would break payroll |
| 5 | **Re-enable the Lambda** — the queue drains against populated configuration | Worker scales, jobs succeed |

**Why the Lambda and not the deploy's own lock:** `deploy-payroll-worker.yaml:98` takes a Redis autoscaling lock with a 900s TTL — that covers the deploy, not the deploy-plus-backfill window, which can run an hour. Engineer's call, and it is the right one.

**Why this is one release and not two:** see 6.4. Shipping the columns and the code together needs the window closed operationally; shipping them in two releases costs two full cycles against a Monday deadline.

**Then Phase 7** (`shared-001`, no record exists yet — created directly in the new shape):

| Column | Value |
|---|---|
| `hostname` | `dev-nexus.maqnelson.com.br` — **host only**, no scheme, no path |
| `scheme` | `https` |
| `path` | `/api/v1/premiacao/pagamentos` — **no accent**, the collection uses plain ASCII |
| `authentication_path` | `/api/v1/entrar` |
| `email` / `user_password` | from Maqnelson's e-mail — **record only**, never code/Terraform/PR. Flag the password for rotation: it transited e-mail |

**Two things still unproven, and homologation is what proves them:** the token field in the login response (`processor.rb:72` assumes `access_token`; the collection has no response example and the string appears nowhere in it — a 401 on the payments POST after a successful login is this), and the workers' behaviour generally — **this project has no worker specs**, so the 3829 green model examples prove the validations, not the request.

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
3. **Worker/queue → `MaqnelsonIntegration::Processor` on `payroll_tiger_shark`,** launched like the Atento outbound: `sidekiq -C config/sidekiq_payroll_tiger_shark.yml`. **Engineer's call (2026-07-15): reuse the Atento lane rather than introduce a new one** — "vamos de tiger shark, igual ta no ambiente atento hoje". The lane is free in shared-001 (no company uses a suffix today; they all sit on the bare `commission` queue), and reusing it means the sidekiq config and the HireFire dyno already exist — zero new app code for the lane itself. The name is shared with the Atento stack but nothing else is: each reads its own environment's Redis, so neither sees the other's jobs.
   - **A superseded earlier decision** picked `white_shark` to keep the lane visually distinct from atento-001's in dashboards and logs. That distinctness was not worth a second lane to maintain; the Redis separation already guarantees isolation.
   - **Was blocked on the queue-suffix split below — no longer.** The split shipped (Phase 4, releases 3.52.0 + 3.53.0), so the payroll lane is now assignable without handing Maqnelson a commission lane for free. Phase 7 sets it.

## The queue-suffix problem — one variable governs two domains

`app/app/models/tenant_worker/queue.rb:23` derives **every** TenantWorker's queue from a single company attribute:

```ruby
"#{@worker.base_queue_name}#{@company.commission_queue_suffix}"
```

So `commission_queue_suffix` routes the commission workers (`base_queue_name :commission`) **and** the payroll/outbound worker (`base_queue_name :payroll`) alike. Supporting facts:

- **The suffix is the dedicated-lane mechanism.** `db/schema.rb:532` — `t.index ["commission_queue_suffix"], name: "index_companies_on_commission_queue_suffix", unique: true`. One company owns a suffix exclusively; `NULL` (the shared-001 default today) means the bare queue.
- **It is a commission-domain concept.** `app/app/workers/partial_commission/finalizer.rb:21-24` groups companies by `commission_queue_suffix` and fans commission work out per suffix.

**The consequence:** setting a suffix on Maqnelson's company to give the outbound its `payroll_tiger_shark` queue **also** moves their commission jobs to `commission_tiger_shark` — a dedicated commission lane the customer is not paying for.

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
| Outbound infrastructure — terraform stack (5.1) | ✅ Applied (22 added, 0 changed, 0 destroyed) — PR [#702](https://github.com/4shark/terraform/pull/702) merged |
| Outbound infrastructure — app config: sa-east-1 dual-push (5.2) | ✅ Done — PR [#5233](https://github.com/4shark/app/pull/5233) merged; needs a release to populate the sa-east-1 mirror (the build only runs on `master`) |
| Outbound infrastructure — terraform: switch the lane to `payroll_tiger_shark` (5.3) | ✅ Applied (1 added, 1 changed, 1 destroyed) and verified on AWS — PR [#704](https://github.com/4shark/terraform/pull/704) merged |
| Outbound infrastructure — `deploy-shared-001` payroll caller (5.4) | ✅ Done — PR [#5234](https://github.com/4shark/app/pull/5234) merged |
| Parameterize the payroll endpoints + align with the reworked contract (6) | ⬜ **Planned, not started.** Supersedes PR [#5235](https://github.com/4shark/app/pull/5235) (hardcoded scheme + paths — rejected). Expand/contract: PR A (migrations) → engineer populates Atento's `request_url` → PR B (models + workers). Scope now includes FPW |
| `payroll_integration` record for Maqnelson (hostname + credentials) | ⬜ To do (DB config) |
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

### Phase 5 — Stand up the outbound infrastructure

**One phase, one outcome: the outbound exists and is able to run.** The lane it consumes (`payroll_tiger_shark`) is inert until Phase 7 sets the company's record, so nothing here processes a job — but nothing here may be missing either, or the infra comes up green and silently does nothing.

**The lane is `payroll_tiger_shark` — the same one Atento uses (engineer's call, 2026-07-15).** No new lane is introduced: the sidekiq config and the HireFire dyno already exist in the app and need no change. The lane is shared by name only — each stack reads its own environment's Redis (`shared-001` here, `atento-001` there), so the two never see each other's jobs, and no other `shared-001` service consumes `payroll_tiger_shark` (verified: `grep payroll` over `terraform/app-shared-001/` is empty), so this stack is its only consumer.

`app-outbound-atento-br` is the reference for every piece. It is a complete, working instance of exactly this shape: an ECS Fargate cluster in sa-east-1 running one Sidekiq worker service against a dedicated payroll queue, scaled by a Lambda that reads the app's HireFire endpoint, pulling its image from a regional ECR mirror. Read it before writing — the deltas below are the only differences.

**The three deltas vs the Atento outbound:**

1. **Network** — the tasks run in the **integrator-maqnelson VPC**, not a VPC of their own. Resolve it via `module.networking_data` with `networking_environment = "integrator-maqnelson"`.
2. **No VPN, no VGW, no zone association** — they already exist (Phases 1 and 2). Do **NOT** instantiate `modules/app_outbound`: it creates `aws_vpn_gateway`, `aws_customer_gateway`, `aws_vpn_connection`, `aws_vpn_connection_route`, `aws_route53_zone_association`, and `aws_default_security_group` — every one of them either already exists or is owned by the integrator module. It would collide on all six.
3. **Config source** — `module.task_config` points at `../modules/shared_001_task_config` (Phase 3), not `atento_001_task_config`; the cross-region provider alias, the SSM parameters, the HireFire host, and the ECR image all resolve to **shared-001** instead of atento-001.

**Because the Atento outbound's default SG comes from `modules/app_outbound`, which we are not instantiating, this stack declares its own** — a dedicated `aws_security_group` for the outbound tasks (egress all, so traffic to the Nexus host follows the private RT to the VGW; ingress from the management VPN SGs for debugging). Never touch the VPC's default SG — it belongs to the integrator module.

#### 5.1 — Terraform: `terraform/app-outbound-maqnelson/`

Scaffold the stack, file-for-file against the reference:

| File | What it carries |
|---|---|
| `providers.tf` | sa-east-1 + a cross-region alias to shared-001 (us-east-1) for the SSM reads; S3 backend at `app-outbound-maqnelson/terraform.tfstate` |
| `locals.tf` | names (`cluster_name`, `service_name`, `task_family`, `container_name`, `lambda_name`), the shared-001 image, the lambda artifact version, and the tags |
| `main.tf` | `module.networking_data` → `integrator-maqnelson`; the dedicated `aws_security_group`; the dns remote state |
| `ecr.tf` | the sa-east-1 mirror of `shared-001-app` (see 5.2 — the workflow must push to it) |
| `compute.tf` | ECS cluster; worker service (`sidekiq -C config/sidekiq_payroll_tiger_shark.yml`, `desired_count = 0`); runner service (`desired_count = 0`, for `bin/ecs run`); autoscaling Lambda; EventBridge scheduler at `rate(1 minute)`; tasks in the integrator VPC's private subnets |
| `iam.tf` | the Lambda role + the EventBridge scheduler role |
| `monitoring_data.tf` | the rollbar project id from the monitoring remote state |
| `variables.tf` | `payroll_jobs_per_process` / `payroll_maximum_capacity` / `payroll_minimum_capacity` |
| `output.tf`, `stack.tm.hcl`, `README.md` | the stack declaration and its docs |

`plan`, then **apply-before-merge**.

**✅ Done.** Applied: **22 added, 0 changed, 0 destroyed** — the zero-destroy is the evidence that no pre-existing network resource of `integrator-maqnelson` was touched. Verified in AWS: `app-outbound-maqnelson-cluster` is `ACTIVE` with its 2 services at `desired_count = 0`. PR [#702](https://github.com/4shark/terraform/pull/702) open, awaiting the engineer's merge.

Three findings the implementation forced, none of which the plan had anticipated:

- **No module needed changing, and nothing was made optional.** `modules/integrator` does not create the VPC — it *receives* `vpc_id` and creates the VPN, Redis, the default SG and the zone association. The VPC comes from a separate `networking` stack that publishes its ids to SSM, and `modules/networking_data` is pure `data "aws_ssm_parameter"` — it creates nothing. So deploying into the integrator's VPC is simply "read the same SSM ids and do not call `modules/app_outbound`" — the composition already supported it.
- **`data "terraform_remote_state" "dns"` was dropped from `main.tf`.** The reference stack carries it only to pass `internal_zone_id` into `modules/app_outbound`, which does the zone association. Not instantiating that module — and the zone already associated in Phase 2 — makes it dead code.
- **The management VPN SG ids are reusable as-is.** `integrator-maqnelson/main.tf:38` already passes the same two ids, which proves they are referenceable from inside that VPC; every integrator stack uses them.

#### 5.2 — App: the sa-east-1 dual-push on `build-shared-001`

`.github/workflows/build-image.yaml` — mirrors the `build-atento-001` job: an `ECR_REGISTRIES` override listing both regions plus the sa-east-1 configure/login step pair. The tag-composition loop already iterates the registry list, so no other step changes. Before this, `build-shared-001` published only to us-east-1 and the sa-east-1 mirror from 5.1 would stay empty — the Fargate task would have no image to pull.

**This is the only app change the lane needs.** The sidekiq config and the HireFire dyno were originally scoped here as new `white_shark` pieces; reusing the Atento lane (see the phase preamble) removed both — they already exist.

#### 5.3 — Terraform: point the stack at `payroll_tiger_shark`

The 5.1 stack was applied against the then-planned `white_shark` lane. Two references change: the worker service's `command` (`config/sidekiq_payroll_tiger_shark.yml`) and the Lambda's `PROCESS_NAME` (`worker_payroll_tiger_shark`), plus the README/variables prose. Plan is clean — `1 to add, 1 to change, 1 to destroy`: the Lambda updates in-place and the task definition gets a new revision (ECS task defs are immutable, so terraform models a revision bump as replace). The service is at `desired_count = 0`, so no running task is disrupted.

#### 5.4 — App: the `deploy-shared-001` payroll caller — GAP FOUND 2026-07-15

**The terraform task definition is only the bootstrap; the service never adopts a new revision on its own.** `modules/ecs_service/main.tf:152` carries `ignore_changes = [task_definition]` (CodeDeploy owns it during deploys), so `terraform apply` creates the revision and the service stays pinned to the old one. The deploy is what moves it — and `deploy-payroll-worker.yaml:202` does not inherit terraform's command, it builds its own from a `sidekiq_config_file` input. **The config file name therefore lives in three places: the sidekiq yml, the terraform command, and the deploy caller's input.**

`deploy-shared-001.yaml` has no payroll job at all (`grep payroll|sa-east-1|deploy-payroll-worker` → empty). The Atento equivalent is `deploy-atento-001.yaml:1001-1011`, which passes cluster/service/family/container/ecr_repo/`sidekiq_config_file`/environment into the reusable `deploy-payroll-worker.yaml`.

Without this caller the outbound worker sits on its bootstrap revision forever and no deploy ever carries code to it — the same green-and-does-nothing failure the rest of Phase 5 exists to close.

**Resolved: mirror Atento in full — all four jobs (engineer's call, 2026-07-15).** PR #5234.

| Job | Role |
|-----|------|
| `deploy-payroll` | Calls the reusable `deploy-payroll-worker.yaml` with this stack's cluster/service/family/container/ECR and `sidekiq_config_file: sidekiq_payroll_tiger_shark.yml` |
| `deploy-runner-payroll` | Refreshes the runner task def so `bin/ecs run` picks up current code — needed by the Phase 8 homolog test |
| `rollback-main-on-payroll-failure` | Main-app succeeded, payroll failed → roll main-app's workers back |
| `rollback-payroll-on-main-failure` | Payroll succeeded, main-app failed → roll payroll back |

Both deploy jobs take `needs: validate-secrets` only, so a failure on one track never cancels the other. The `validate` job gains both in its `needs` and status checks; `capture-pre-deploy-state` needed no change (its `state` output already exists and the rollback job consumes it as-is).

**The cross-track rollback carries a shared-environment consequence, accepted deliberately.** In `atento-001` the environment is dedicated, so rolling the whole main-app back when payroll fails affects one client. `shared-001` serves many: the same job means a failure of this one outbound worker rolls back the Sidekiq workers of **every** client in the environment. The alternative — deploy jobs only, letting the outbound sit one version behind until the next deploy — was surfaced and declined in favour of never letting the two tracks diverge on code version.

**Verified against the reference before merge:** with cluster and environment names normalized, all four jobs are byte-identical to their `atento-001` counterparts; every `needs` resolves to a real job; the inputs passed to the reusable workflow match its declared contract (no missing required, no undeclared extras).

**Known debt — the payroll jobs are single-client, not a list (deferred by the engineer, 2026-07-15: "a gente resolve a lista quando for o momento").** The main workers already scale by list: `SIDEKIQ_SERVICES` (a JSON env) feeds `deploy-sidekiq` through `matrix: worker: ${{ fromJSON(needs.setup.outputs.sidekiq_services) }}` with `fail-fast: false`, so adding a worker is one JSON entry. The payroll jobs are hardcoded — inherited from `atento-001`, where a single outbound is a sound premise because the environment is dedicated. **`shared-001` is multi-client, so the premise does not hold here**: a second client's outbound would today mean duplicating all four jobs (~265 lines of it being the rollback pair).

Converting the two deploy jobs to a matrix is mechanical (same shape as `deploy-sidekiq`). **The rollback pair is not** — `rollback-main-on-payroll-failure` guards on `needs['deploy-payroll'].result`, which under a matrix becomes the aggregate result across all clients. "One client's outbound failed" would then roll back the main app exactly as "the only client's outbound failed" does today. That is a semantics change on top of the shared-environment consequence already accepted above, and needs an explicit decision — not a refactor.

#### Ordering inside the phase

The Terraform apply is safe first: every service is created at `desired_count = 0`, so nothing tries to pull an image that is not there yet.

1. ✅ **5.1** Terraform stack — PR #702 merged; apply verified on AWS (cluster `app-outbound-maqnelson-cluster` ACTIVE, 2 services).
2. ✅ **5.2** App dual-push — PR #5233 merged into `develop`.
3. ✅ **5.3** Terraform lane switch — PR #704 merged; applied (`1 added, 1 changed, 1 destroyed`).
4. ✅ **5.4** Deploy caller — PR #5234 merged.
5. ⬜ **Release** — the build only runs on `master`, so the sa-east-1 mirror stays empty until 5.2/5.4 ship in a release. Merging into `develop` does not populate it. **This is the only step left in Phase 5.**
6. **Phase released** once the mirror carries the image, a deploy has moved the service onto a `tiger_shark` task definition, and the HireFire endpoint answers for `worker_payroll_tiger_shark`.

**Verified on AWS after the 5.3 apply (2026-07-15):** task definition at revision 2 with `config/sidekiq_payroll_tiger_shark.yml` in its command; Lambda `PROCESS_NAME = worker_payroll_tiger_shark`; the service still points at revision **1** with `desiredCount: 0` — expected, and the live demonstration of the `ignore_changes` behaviour documented above. The deploy from 5.4 is what moves it, and the first run of that deploy happens at the release in step 5.

### Phase 6 — Parameterize the payroll endpoints (and align with the customer's reworked contract)

**Supersedes PR [#5235](https://github.com/4shark/app/pull/5235)** — that PR fixed the contract but hardcoded `https://` and both paths in the worker. Rejected by the engineer, 2026-07-15: *"quando não for HTTPS você não pode colocar isso fixo... a URL inteira tem que ser dinâmica. O path também tem que estar configurável... esse código vai executar para todo mundo... pode ser que amanhã a Maqnelson mude essa porra, eu não quero ter que fazer um deploy só porque eles mudaram a URL."* Correct: a hardcode is worse than the `.sub` it replaced — the `.sub` was at least changeable via the record.

#### 6.1 — What the collection actually changed

Source of truth: the Postman collection `Nexus — Premiação Comercial`, attached to Thiago's 2026-07-14 e-mail (the e-mail body carries no contract — only the attachment does; the Gmail MCP cannot download attachments, the engineer saved it to `~/Downloads/`).

| | Implemented before | Collection (2026-07-14) |
|---|---|---|
| Auth URL | `hostname.sub('/pagamentos', '/auth/token')` → `/api/v1/premiacao/auth/token` | `POST /api/v1/entrar` |
| Auth body | `{ username:, password: }` | `{ "email": "", "senha": "" }` |
| Payments body | `{ mes_competencia, ano_competencia, pagamentos[{ usuario_id_externo, tipo_pagamento_id_externo, premio_valor }] }` | **identical — no change** |

The `.sub` derivation is structurally unreachable: `/entrar` is a sibling of `/premiacao`, not of `/pagamentos`.

#### 6.2 — The target shape: every endpoint comes from the record

**Engineer's decision (2026-07-15):** keep `hostname`, keep `user_name`, add `email`; push the base validations down to the subclass that actually needs each one — *"o FPW valida o username, o Maqnelson valida o email, cada um valida o seu"*. Scope extends to FPW: *"talvez seja a hora de repensar esse código do Atento para ele também ser mais esperto — se o Atento mudar URL amanhã, já está tudo parametrizado, não precisa ficar fazendo código."*

**The endpoint is assembled from three columns — `hostname` stays the single source of truth for the host.**

```ruby
"#{payroll_integration.scheme}://#{payroll_integration.hostname}#{payroll_integration.path}"
```

**A full-URL column was designed, written, and rejected — twice.** First as `payment_url`: a word absent from the domain (`PayrollRequest` enumerizes its actions as `check`/`execution`/`validation`; `PayrollAuthenticationRequest` is its own model — nothing is called "payment"), and factually wrong for FPW, whose single SOAP endpoint serves all three actions. Renamed to `request_url`, then rejected again on the real defect: **a full URL duplicates the host that `hostname` already holds.** Update one and not the other and the `check_producer` telnet probe silently tests a different host than the request reaches. Three columns keep one source of truth per fact.

| Column | Status | FpwIntegration | MaqnelsonIntegration |
|---|---|---|---|
| `hostname` | exists | **`host:port`, required.** Load-bearing — `check_producer.rb:19-23` opens `Net::Telnet.new('Host' => .host, 'Port' => .port)` as a TCP reachability probe. It is NOT an HTTP header, and it CANNOT become a URL. Observed value is `<private-ip>:<port>` | required — same role |
| `scheme` | **new** | `http` — the value hardcoded in the three consumers today | `https` |
| `path` | **new** | `/lg.com.br/svc/servicodeeventosdofuncionario` — the value hardcoded today | `/api/v1/premiacao/pagamentos` |
| `authentication_path` | **new** | unused → NULL — FPW authenticates inside the SOAP envelope, it has no auth endpoint | `/api/v1/entrar` |
| `user_name` | exists | required (SOAP `<dto:Usuario>`) | unused → NULL |
| `email` | **new**, encrypted deterministic | unused → NULL | required (login body `email`) |
| `user_password` | exists | required (SOAP `<dto:Senha>`) | required (login body `senha`) |

**Why `scheme` is not optional:** FPW is `http` and Maqnelson is `https`. With only `hostname` + `path`, the scheme stays a literal in the worker — the exact defect that got the first attempt rejected (*"quando não for HTTPS você não pode colocar isso fixo"*). `path` carries no prefix by the engineer's call: it already lives on `payroll_integration`, so `payroll_integration.path` says enough.

**`scheme` is validated against a whitelist** (engineer's call): `PayrollIntegration::SCHEMES = %w[http https].freeze`, with `validates :scheme, presence: true, inclusion: { in: SCHEMES }` on both subclasses — the shape `FpwIntegration::SOAP_VERSIONS` and `PayrollIntegration::TYPES` already use. The constant sits on the base because both types validate it (unlike `SOAP_VERSIONS`, which is FPW-only and lives there). This makes `htpp` or a trailing space fail at save time instead of surfacing as a connection error mid-payroll.

**A trap found by auditing the diff, not by CI: the three FPW consumers never set `use_ssl`.** Harmless while the scheme was the literal `http://`; a live defect the moment the scheme became configurable — setting `scheme = 'https'` would pass validation and then send the SOAP envelope, credentials included, in plaintext. Fixed in the same PR by adding `http.use_ssl = uri.scheme == 'https'` to all three, matching the Maqnelson processor. **No worker specs exist in this project, so nothing would have caught this** — the model suite (3829 examples) proves the validations, not the request.

**Validation moves (`payroll_integration.rb:9`):** `validates :hostname, presence: true` comes off the base and lands on `FpwIntegration`. The base keeps only `validates :type`. `MaqnelsonIntegration` drops `validates :user_name` and gains `email` + the endpoint columns.

**Worker changes — zero interpolation of literals, zero hardcode:**

```ruby
# maqnelson_integration/processor.rb
authentication_uri = URI.parse("#{payroll_integration.scheme}://#{payroll_integration.hostname}#{payroll_integration.authentication_path}")
uri                = URI.parse("#{payroll_integration.scheme}://#{payroll_integration.hostname}#{payroll_integration.path}")
authentication_request.body = { email: payroll_integration.email, senha: payroll_integration.user_password }.to_json

# fpw_integration/{check,validate,execute}_consumer.rb — all three carry the identical line today
- uri = URI.parse("http://#{payroll_integration.hostname}/lg.com.br/svc/servicodeeventosdofuncionario")
+ uri = URI.parse("#{payroll_integration.scheme}://#{payroll_integration.hostname}#{payroll_integration.path}")

# fpw_integration/check_producer.rb — UNCHANGED (telnet probe still needs host/port from hostname)
```

Scheme, host, port and path all come from the record. A customer moving an endpoint becomes an UPDATE, not a deploy — for both integrations.

#### 6.3 — Data migration for the live Atento records ⚠️ RUN BEFORE THE CODE DEPLOY

**This is the load-bearing step and the reason this phase is expand/contract.** Atento's FPW integration is **live in production**. The moment `execute_consumer` reads `request_url` instead of interpolating `hostname`, a record with `request_url IS NULL` makes `URI.parse(nil)` raise on every payment job. The column must be populated **while the old code is still running**.

**Discovery — RUN, not assumed (2026-07-15).** The engineer ran the read-only discovery script; the earlier version of this section was written on unverified assumptions and is superseded by the observed state:

| Observed | Value | What it settles |
|---|---|---|
| Records found | **1** | The migration targets a single row, not a fleet |
| Type | `FpwIntegration` (id 1, company 1351) | **No `MaqnelsonIntegration` row exists** → Phase 7 creates it directly in the new shape; no Maqnelson data migration |
| `hostname` shape | `<private-ip>:<port>` — **no scheme, no path** | `hostname` holds the host and nothing else, so `scheme` and `path` are genuinely absent from the record today and must be backfilled. Had a scheme been embedded, the assembled URL would have produced `http://http://…` |
| `host` / `port` split | resolves cleanly to IP + port | Confirms `hostname` is `host:port` and **must not become a URL** — the `check_producer` telnet probe depends on the split |
| `user_name` / `user_password` | both present | FPW's SOAP credentials are intact; nothing to backfill there |

**Environment scope — settled (engineer, 2026-07-15): the discovery was run in `atento-001`, and it is the only environment with a payroll integration running.** `payroll_integrations` is per-environment (each of `beta-001` / `demo-001` / `shared-001` / `atento-001` has its own database), so this matters: step 3 below runs **once, in `atento-001`, against one row**. `shared-001` holds no payroll integration yet — Phase 7 creates the Maqnelson one there, already in the new shape.

**Both values are literals the code carries today — nothing external is needed.** `scheme` is the `http` hardcoded in the three consumers; `path` is the `/lg.com.br/svc/servicodeeventosdofuncionario` hardcoded beside it. The backfill copies the code's own constants into the record so the code can stop carrying them.

```ruby
# Populate scheme and path for every existing FPW record.
# Both values are lifted verbatim from fpw_integration/execute_consumer.rb:70,
# so the assembled URL is byte-identical to what the current code builds.
fpw_scheme = 'http'
fpw_path = '/lg.com.br/svc/servicodeeventosdofuncionario'

payroll_integration_ids = PayrollIntegration.where(type: 'FpwIntegration').ids
puts "targeting #{payroll_integration_ids.size} FpwIntegration record(s)"

payroll_integration_ids.each do |payroll_integration_id|
  payroll_integration = PayrollIntegration.find(payroll_integration_id)
  updated = payroll_integration.update(scheme: fpw_scheme, path: fpw_path)
  assembled_url = "#{fpw_scheme}://#{payroll_integration.hostname}#{fpw_path}"
  puts "#{payroll_integration_id} | #{assembled_url} | #{updated ? 'OK' : payroll_integration.errors.full_messages.join(', ')}"
rescue StandardError => error
  puts "#{payroll_integration_id} | ERROR | #{error.message}"
end
```

```ruby
# Verification — must print zero rows before the code deploy proceeds.
PayrollIntegration.where(type: 'FpwIntegration').where(scheme: nil).or(
  PayrollIntegration.where(type: 'FpwIntegration').where(path: nil)
).ids.each do |payroll_integration_id|
  puts "STILL NULL: #{payroll_integration_id}"
end
```

**The backfill prints the assembled URL per row — compare it against `execute_consumer.rb:70` before re-enabling the Lambda.** The whole point is that the URL does not change, only where it comes from. Expected for the single row: `http://<the record's hostname>/lg.com.br/svc/servicodeeventosdofuncionario`. If it differs, stop — the record is not what the discovery showed. The verification above is the separate gate: it must print nothing.

Per `SCRIPT-DISCIPLINE.md`: lowercase variables (never constants — they leak between console runs), per-record iteration with per-record logging, non-bang `update` so one bad row does not halt the loop, and a verification pass that re-reads what the mutation touched. **No Maqnelson data migration exists** — its `payroll_integration` record has not been created yet (that is Phase 7, which will be created directly in the new shape).

#### 6.4 — Ordering: one release, guarded by an autoscaling window (engineer's call, 2026-07-15)

**The two-release expand/contract below was replaced.** The original plan shipped the columns in one release and the code in another. The engineer collapsed it into **one release, with the danger window closed operationally instead of temporally**: *"a desativar lambda é para garantir: se a gente demorar uma hora, que seja pelo menos nessa uma hora, não vai ter um agravante de alguém mandar rodar e cagar toda a integração e os dados."*

**The danger this closes.** With code and columns in the same release, there is a real gap between the deploy landing and the backfill finishing. In that gap the new code reads `scheme`/`path` that are still NULL — `URI.parse("://<host>")` — and **today is a payroll day for the live integration**. Disabling the outbound autoscaling Lambda holds the worker at `desired_count = 0` for the whole operation, so anything triggered in that window queues in Redis instead of running against empty configuration. It drains, correctly, once the Lambda comes back.

**Why the deploy's own lock is not enough.** `deploy-payroll-worker.yaml:98` takes a Redis autoscaling lock (`ecs_scaling:lock:<cluster>`, TTL 900s) as its first job — but that covers the *deploy*, not the deploy-plus-backfill window, which can run an hour. The manual disable is a wider guard, deliberately.

**Two releases were the wrong trade anyway**: two full release/deploy cycles today, against a Monday deadline, to avoid a window that a Lambda toggle closes outright.

| # | Step | Who | Gate before proceeding |
|---|------|-----|------------------------|
| 1 | ✅ **PR A — columns only** — [#5236](https://github.com/4shark/app/pull/5236) merged | Claude | ✅ |
| 2 | ✅ **PR B — models + workers** — [#5235](https://github.com/4shark/app/pull/5235) **merged**, rewritten in place over the superseded approach | Claude | ✅ |
| 3 | **Disable the outbound autoscaling Lambda** (`atento-001`) — the worker is at `0/0` today, so it stays there | Engineer | Lambda confirmed off |
| 4 | Merge PR B → cut release → deploy `atento-001` | Engineer | Deploy green |
| 5 | **Backfill `scheme` + `path`** (6.3 script) and run the verification | Engineer | **Zero rows returned** |
| 6 | **Re-enable the Lambda** — the queue drains against populated configuration | Engineer | Worker scales, jobs succeed |

**Superseded reasoning, kept so it is not re-derived:** an earlier read of this concluded PR A's deploy was risk-free (true — no code read the columns) and therefore that the Lambda dance was unnecessary. That was right about PR A in isolation and wrong about the operation: PR A alone delivers nothing, and the risk lives in the combined window, which is what the engineer was pointing at.

| # | Step | Who | Gate before proceeding |
|---|------|-----|------------------------|
| 1 | ✅ **PR A — migrations only** — [#5236](https://github.com/4shark/app/pull/5236) **merged**. Four `add_column` migrations (nullable): `scheme`, `path`, `authentication_path`, `email`; `db/schema.rb` regenerated. **No model or worker change.** Nothing reads the new columns. | Claude | ✅ |
| 2 | Merge PR A → release → deploy | Engineer | Columns exist in production |
| 3 | **Populate `request_url` on every FPW record** (6.3 script, by hand via `bin/ecs run`), then run the verification script | Engineer | **Zero rows returned by the verification query** |
| 4 | **PR B — models + workers.** Validation moves, `encrypts :email`, Maqnelson processor, the three FPW consumers, specs, `brakeman.ignore` re-anchor, CHANGELOG | Claude | CI green |
| 5 | Merge PR B → release → deploy | Engineer | FPW keeps working; Maqnelson ready for Phase 7 |

**Step 3 is not optional and cannot be folded into step 5.** A single deploy would ship the reading code and the empty column together, and every Atento payment job would raise until the engineer finished typing.

**Why the migration cannot populate the column itself:** the value depends on `hostname`, which is not encrypted — so a data migration *could* technically do it. It is kept manual because the engineer asked for it (*"posso fazer na mão os comandos"*) and because a data-touching migration on a live table is the shape `RAILS-MIGRATIONS.md` steers away from. If that preference changes, folding step 3 into a data migration inside PR A is viable and would remove the manual gate.

#### 6.5 — Still open: the token response field

`processor.rb:72` assumes `access_token`. The collection cannot confirm it: no response example, empty test script, `token` collection variable blank, and the string `access_token` appears nowhere in the 95KB file. Left as-is deliberately — inventing tolerance for several field names without evidence is worse than letting the Phase 8 run answer it. **Ask Thiago, or discover it in homologation.**

**Still open — the token response field.** `processor.rb:72` assumes `access_token`. The collection cannot confirm it: no response example, empty test script, `token` collection variable blank, and the string `access_token` appears nowhere in the 95KB file. Left as-is deliberately — inventing tolerance for several field names without evidence is worse than letting the Phase 8 run answer it. **Ask Thiago, or discover it in homologation.**

**Also found, no action:** the collection exposes 6 read endpoints we do not consume (list/detail/deactivate `lotes`, payment detail, payment version history). The `PATCH /lotes/{id}/inativar` suggests re-send has an official path — worth knowing when re-processing comes up.

**Trap that will recur — Brakeman fingerprints are content-addressed, so editing an ignored line breaks its ignore.** The first CI run of PR #5235 failed on `Brakeman (Security)` with two `File Access — Model attribute used in file name` warnings on the two lines the fix touched. It was **not** a new vulnerability: `config/brakeman.ignore` already carried both as engineer-triaged false positives (`hostname` is an HTTP endpoint, not a filesystem path — the sibling FPW integration has three identical ignores). Brakeman fingerprints a warning by the *code of the line*; changing the line changes the fingerprint, the ignore entry orphans (surfacing as `Obsolete Ignore Entries` in the report), and the warning resurfaces red.

**The fix belongs in the same PR, never a separate one** — the new fingerprints only match code that exists on that branch, so an ignore-only PR against `develop` would land already-obsolete entries and leave the original PR red until both merged. The ignore file must move with the line it ignores. Procedure: run `bundle exec brakeman -f json`, read the `fingerprint` of each surfaced warning, replace the obsolete entry's `fingerprint`/`line`/`code` in `config/brakeman.ignore`, keep (and re-word, if the code's meaning shifted) the `note`, and confirm `Security Warnings: 0` with no obsolete entries. Do not add new suppressions this way — only re-anchor decisions the team already made.

### Phase 7 — `payroll_integration` record + payroll lane for Maqnelson (DB config)

- **Payroll lane → `_tiger_shark`** (the new attribute from Phase 4). ✅ **Already set by the engineer on 2026-07-15** — the value is inert until the `payroll_integration` record below exists. The commission lane stays `NULL` — the customer keeps the shared `commission` queue they pay for.

- Create/point the company's `payroll_integration` (type `MaqnelsonIntegration`) with:
  - `hostname` = **the host alone — no scheme, no path.** For homologation: `dev-nexus.maqnelson.com.br`. **This changed in Phase 6 (PR #5235)** — the old instruction ("the full request URL, must end in `/pagamentos`") is dead: the worker now owns both paths, matching the base model's `host`/`port` contract and the sibling FPW integration. A full URL here would break `payroll_integration.host`, which returns `hostname.split(':').first`.
  - `user_name` / `user_password` = the Nexus access credentials from Maqnelson's e-mail. These live **only** in the record — never in code, Terraform, or a PR. Note the worker now sends them as `email` / `senha`; the column names are unchanged.
- Because the password transited e-mail, flag it to Maqnelson for rotation once wired.
- **The path spelling lost its accents**: the collection uses `/api/v1/premiacao/pagamentos` (plain ASCII), not `premiação` as `SPIKE.md:14` recorded from the older source. This is now hardcoded in the worker, so it is no longer a data-entry risk — but the SPIKE's value is stale, do not copy from it.

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
- **Timeline** — 20/07 is the commitment. The split (Phase 4) is **done and deployed**, so its fallback (ship on the bare `payroll` queue, add the lane later) is no longer needed. Phase 5 is now the critical path and the least-bounded piece.
- **Infra that comes up green and does nothing** — the outbound's failure mode is silence, not error. The autoscaling Lambda reads a HireFire dyno by name; the worker consumes a queue named in a sidekiq config; the task pulls an image from a regional mirror; the service only leaves its bootstrap task definition when a deploy caller moves it. Any one of the four missing and the stack still applies cleanly, the service still sits at `desired_count = 0`, and nothing ever runs. This is why every one of them is inside Phase 5 rather than a later step — they were missed twice, each time because "the infra" was read as "the terraform".
- **The lane name lives in three places, and terraform owns only one of them** — the sidekiq yml, the terraform task-definition `command`, and the deploy caller's `sidekiq_config_file` input. `modules/ecs_service/main.tf:152` puts `task_definition` in `ignore_changes`, so terraform's revision is a bootstrap the running service never adopts; `deploy-payroll-worker.yaml:202` rebuilds the command from its own input. A change applied in terraform alone looks successful and changes nothing about what the service actually runs. Any future lane change must move all three together.

## Out of scope

- No new VPN, no Transit Gateway change, no proxy (rejected in `SPIKE.md`).
- Do not convert the VPN routes to `0.0.0.0/0` (conflicts with the TGW egress default route — proven in the meeting).
