# TASKS — Integrators EC2 to ECS Fargate Migration

> **Reference:** `PLAN.md` (phases, technical decisions, VPC redesign procedure)
> **Reference:** `SPIKE.md` (research, cost analysis, evidence)

---

## Status (2026-04-13)

| Integrator | VPC Redesign | MongoDB Migration | SSM | ECS Clusters | deploy workflow | Validated | EC2 Terminated | Old Subnets |
|---|---|---|---|---|---|---|---|---|
| almaviva | done | done | done | done | done | done | done | done |
| maqnelson | done | done | done | done | done | done | done | done |
| aster-maquinas | — | — | — | — | — | — | decommissioned (contract cancelled) | — |
| commcenter | done | done | done | done (2 clusters) | done (per-env naming) | done (prod + staging) | done | done |
| redebrasil | done | done | done | done | done | done | done | done |
| atento | done | done | done | done (4 clusters) | done (per-env naming) | done (all 4 countries) | done | done |

**Note on atento (2026-04-12):** Full migration completed in a single session:
- Pre-work rename `atento-br` → `atento` (PR #323 terraform, PRs #2137 #2138 integrator)
- GitHub Environment `atento` created, `atento-br` and `atento-mx` deleted
- Build matrix updated: `atento` → `atento-br, atento-mx, atento-co, atento-cl` (PR #2139)
- VPC redesign: public infra dropped, new subnets (sa-east-1a + sa-east-1b), old subnets decommissioned
- MongoDB RS migrated to new subnets (mongo003=PRIMARY, mongo004=SECONDARY, mongo005=ARBITER), old nodes terminated
- ElastiCache deleted and recreated in new subnets
- 4 ECS clusters created (one per country: BR, MX, CO, CL) with shared ALB (host-based routing)
- 4 ECR repos created (one per country), images built and pushed
- 52 SSM secrets populated (13 per country), including per-country Rollbar tokens
- Rollbar projects created for CO and CL (BR and MX already existed)
- Route53 private hosted zone `database.windows.net` for Azure SQL VPN override
- Deploy workflows simplified: removed suffix, per-environment naming, `INTEGRATORS` repository variable as single source of truth (PR #2140)
- Deploy action renamed from `deploy-ecs` to `deploy`, redundant `service-name` input removed
- Old `deploy.yaml` (GitHub vars management) and `.github/actions/deploy/` (vars merging) deleted
- `iam_deploy` module updated to support multiple cluster names (PR #324)
- All 4 countries deployed and validated (Database.connect! confirmed on all)
- EC2 app servers terminated, DNS records removed
- Old EventBridge rule `EC2-start-integrator-atento-br` disabled
- BR schedules active (scale-up 01:55 UTC, cron 02:00 UTC)

**Note on commcenter (2026-04-13):** Full migration completed in a single session:
- VPC redesign: public infra dropped, new subnets (sa-east-1a + sa-east-1b), old subnets pending decommission
- MongoDB RS migrated to new subnets (mongo003=PRIMARY, mongo004=SECONDARY, mongo005=ARBITER), old nodes terminated
- ElastiCache deleted and recreated in new subnets
- 2 ECS clusters created (prod + staging) with shared ALB (host-based routing)
- 24 SSM secrets populated (12 prod + 12 staging)
- GitHub Environment `commcenter` cleaned (secrets only)
- Deploy workflows triggered, Database.connect! validated on both prod and staging
- Old EventBridge rule `EC2-start-integrator-commcenter` disabled
- EC2 app servers terminated (app002, staging-app001)
- Old subnets (prv-a-old, prv-b-old) decommissioned
- First automated cycle validated (2026-04-14): schedule fired correctly at 00:55 BRT; deploy failed due to wrong build, unrelated to the schedule mechanism

**Note on aster-maquinas (2026-04-14):** Infrastructure decommissioned (PR terraform#336). Destroyed: 5 EC2 instances, ElastiCache, ECR, IAM deploy user, S3 bucket, CloudWatch log groups, VPC peering, TGW attachment, subnets, route tables, SSM params, Route53 records, Rollbar projects. Kept: VPC + Site-to-Site VPN (tunnel UP) at ~$36.50/month. Final VPN drop pending customer coordination.

**Current:** Migration complete. All integrators on ECS with validated schedules. aster-maquinas decommissioned except VPN.

---

## EC2 Termination Policy

EC2 app servers are terminated **per-integrator** during the migration cleanup (Step 13). After MongoDB RS migration, the old EC2 has no MongoDB to connect to — it provides no fallback.

Per-integrator termination conditions:
1. MongoDB RS migrated and old nodes terminated
2. ECS services deployed and ALB healthy
3. Old EventBridge rule disabled, new schedules enabled
4. Old subnets decommissioned immediately after EC2 termination

---

## Phase 1: Prerequisites — DONE

All foundation work complete. See historical record below for reference.

### Done (terraform repo — PR #244, #248 merged)
- [x] `modules/ecs_service` extended with Fargate support
- [x] `modules/internal_alb` extended with `target_type` variable for Fargate IP targeting
- [x] `modules/integrator_iam` fixed: `ManageInstances` IAM statement conditional on non-empty `ec2_instance_ids`
- [x] ECR repositories created for all integrators
- [x] `modules/networking_data/outputs.tf` updated: handles `has_public_subnets = false` / `has_nat_gateway = false`

### Done (integrator repo — PRs #2038–#2047, #2057 merged)
- [x] `.github/workflows/build.yaml` — matrix build for all integrators
- [x] `.github/workflows/deploy.yaml` — legacy deploy (preserved for EC2-based integrators during transition)
- [x] `.github/workflows/run.yaml` — one-off ECS task runner
- [x] `bin/ecs` — full parity with `app/bin/ecs` (connect, run, cleanup)
- [x] `.github/docker/Dockerfile` — multi-stage production image
- [x] `.github/actions/deploy-ecs/action.yaml` — image-only deploy composite action
- [x] `.github/workflows/deploy-almaviva.yaml` — dedicated image-only workflow (reference for all others)

### Done (env vars — all integrators)
- [x] GitHub Environments configured for ALL integrators: almaviva, redebrasil, maqnelson, aster-maquinas, commcenter, atento-br
- [x] AWS credentials + all application env vars collected and populated

> **Note (2026-03-21):** Env vars are currently in GitHub Environments (old EC2 pattern). Each integrator migration must move application env vars to SSM (via `ssm.tf` + `aws ssm put-parameter`) and strip the GitHub Environment down to AWS credentials only.

### Known issue — IAM: `ecr:GetAuthorizationToken`
- Build succeeds but non-almaviva integrators may lack `ecr:GetAuthorizationToken` in their IAM deploy user policies
- Fix required before first deploy of each remaining integrator

### Schedule reference (confirmed 2026-03-16)

| Integrator | Schedule 0 (start MongoDB) | Schedule 1 (scale-up) | Schedule 2 (RunTask, +5 min) | BRT (UTC-3) |
|---|---|---|---|---|
| almaviva | `cron(50 0 * * ? *)` | `cron(55 0 * * ? *)` | `cron(0 1 * * ? *)` | 21:50 / 21:55 / 22:00 |
| aster-maquinas | TBD | `cron(55 0 * * ? *)` | `cron(0 1 * * ? *)` | — / 21:55 / 22:00 |
| atento-br | TBD | `cron(55 1 * * ? *)` | `cron(0 2 * * ? *)` | — / 22:55 / 23:00 |
| commcenter | TBD | `cron(55 3 * * ? *)` | `cron(0 4 * * ? *)` | — / 00:55 / 01:00 |
| maqnelson | TBD | `cron(25 1 * * ? *)` | `cron(30 1 * * ? *)` | — / 22:25 / 22:30 |
| redebrasil | TBD | `cron(55 1 * * ? *)` | `cron(0 2 * * ? *)` | — / 22:55 / 23:00 |
| redebrasil-extra | — | `cron(55 17 20-27 * ? *)` | `cron(0 18 20-27 * ? *)` | — / 14:55 / 15:00 (dias 20–27) |

> Source: `aws events list-rules --region sa-east-1`

---

## almaviva — DONE (historical record)

First integrator migrated. All discoveries and fixes documented here for reference.

### VPC Redesign + MongoDB Migration — done (2026-03-16)
- [x] Networking: pub-b removed, prv-a/prv-b renamed to -old, new prv-a (sa-east-1a) + prv-b (sa-east-1b) created
- [x] New SSM params `/prv_a_subnet_id` and `/prv_b_subnet_id`
- [x] mongo003/004/005 provisioned in new subnets (`integrator-almaviva/mongodb.tf`)
- [x] MongoDB 4.0.28 installed via Ansible; RS migrated: mongo003=PRIMARY, mongo004=SECONDARY, mongo005=ARBITER
- [x] Old nodes (mongo000/001/002) removed from RS, terminated, `enable_mongo = false`
- [x] app002/app003 updated with new connection string

### ECS Infrastructure — done (2026-03-17)
- [x] `integrator-almaviva/ssm.tf` created (all secrets under `/integrator-almaviva/`)
- [x] `integrator-almaviva/compute.tf` created (cluster, ALB, web, worker, runner, schedules, IAM deploy)
- [x] `main.tf` updated: `has_public_subnets = false`, `has_nat_gateway = false`, `enable_mongo = false`
- [x] DNS record `integrator-almaviva.4shark.internal` pointing to ALB

### Validation — done (2026-03-17 to 2026-03-19)
- [x] ECS web=1, worker=2 running and healthy
- [x] ALB health check passing
- [x] `bin/ecs connect` and `bin/ecs run` validated
- [x] Cron task definition registered with 51 env vars
- [x] EventBridge rule `EC2-start-integrator-almaviva` disabled
- [x] First full automated cycle (2026-03-19): scale-up 00:55 → cron 01:01 → shutdown 01:39–01:40 ✅

### Deploy pipeline — done (2026-03-21, PR #2057)
- [x] `deploy-almaviva.yaml` — image-only, no vars-json/secrets-json
- [x] GitHub Environment `almaviva` stripped to AWS credentials only

### Task sizing — done (PR #248)
- [x] Worker/runner/cron uniformized to 0.5 vCPU / 2 GB (worker peaked at 92% memory at 0.25 vCPU / 512 MB)

### Issues found and resolved during validation
1. **`aws_security_group_rule` conflict** — `aws_default_security_group` and standalone rules can't co-manage. Fix: all rules inside `aws_default_security_group` via `additional_ingress_sg_ids`.
2. **DNS `-app` suffix** — ALB DNS was inside `internal_alb` module with wrong name. Fix: made `record_name`/`private_zone_id` optional in module, moved DNS to `dns/` stack.
3. **ALB missing management VPN CIDR** — Added `10.255.0.0/16` to `alb_ingress_cidrs`.
4. **MongoDB connection string** — ECS tasks still pointing to old mongo000/001/002. Fix: updated `MONGODB` secret in GitHub Environment, redeployed.

### EC2 decommission — done
- [x] EC2 instances `almaviva/app002` and `almaviva/app003` terminated
- [x] Old subnets (prv-a-old, prv-b-old) decommissioned

---

## Multi-environment migration checklist — applies to atento (and commcenter going forward)

This is the variant procedure for clients with multiple countries or environments (atento: BR/MX/CO/CL; commcenter: prod/homologation). The networking phase (Steps 1–9) is identical to single-env. The Terraform compute layer differs (see below). References: `PLAN.md` "atento — full specification" section and `SPIKE-multi-env.md` Decisions 1–5.

### Pre-work: Rename `atento-br` → `atento`

**Why:** Everything renameable must change BEFORE the first ECS resource is created. The preflight check in `deploy-ecs.yaml` reads tag pattern `4client-{integrator}-mongo*`; if MongoDB tags still say `4client-atento-br-mongo*`, the check fails.

**Scope of rename** (from PLAN.md Decision 4):

1. Terraform stack folder: `integrator-atento-br/` → `integrator-atento/`
2. Networking vpc file: `vpc_atento_br.tf` → `vpc_atento.tf`
3. All AWS resource tags: `4client-atento-br-*` → `4client-atento-*`
4. Security group names, route table names: remove `-br` suffix
5. SSM paths: `/integrator-atento-br/*` → `/integrator-atento/{br,mx,co,cl}/*` (per-env nesting added later)
6. GitHub Environment: `atento-br` → `atento`
7. ECR repo: `integrator-atento-br` → `integrator-atento` (already exists — rename via `terraform state mv` + `aws ecr` CLI)
8. DNS record: `integrator-atento-br.4shark.internal` → per-env records per Step 24 below
9. Integrator repo `build.yaml` matrix: `"atento-br"` → `"atento"` in `INTEGRATORS` env var — **must be committed together with terraform rename** because the build pushes to ECR `integrator-{name}` and reads GitHub Environment `{name}`, both of which change in the same cutover

**Ordering constraint:** MongoDB EC2 tags MUST be renamed BEFORE the first deploy (Step 17 below) because `deploy-ecs.yaml` preflight runs immediately. If tags still say `atento-br-mongo*`, deploy fails.

**Pre-work checklist:**
- [x] Terraform folder, files, and all resource names renamed (PR #323, merged 2026-04-10)
- [x] MongoDB EC2 instance tags renamed: `4client-atento-br-mongo*` → `4client-atento-mongo*` (via `client_name` change in integrator module)
- [x] MongoDB OS hostnames changed via `hostnamectl set-hostname` on all 3 nodes
- [x] MongoDB replica set reconfigured via `rs.reconfig()` to use FQDNs `4client-atento-mongo{000,001,002}.4shark.internal:27017`
- [x] ECR repo renamed (destroy+create — repo was empty)
- [x] DNS records created for new names (mongo/redis/app); transitional `atento-br-*` records kept then dropped after app `/etc/environment` update
- [x] SSM paths updated: `/networking/integrator-atento-br/*` → `/networking/integrator-atento/*` (6 params replaced via forceNew)
- [x] App instances `/etc/environment` updated on BR, MX, CL, CO (MongoDB + Redis hostnames)
- [x] atento-co Redis db index isolated from `/0` (shared with BR) to `/3` (bugfix found during rename)
- [x] **GitHub Environment renamed**: `atento-br` → `atento`, `atento-mx` deleted (2026-04-12)
- [x] **Integrator repo `build.yaml` matrix updated**: `"atento"` → `"atento-br","atento-mx","atento-co","atento-cl"` (PR #2139, merged 2026-04-12) — each country is now a separate ECR repo
- [x] **Deploy workflows simplified**: removed suffix input, per-environment naming via `INTEGRATORS` repository variable (PR #2140, merged 2026-04-12)
- [x] **Deploy preflight fixed**: MongoDB tag pattern uses client name from `INTEGRATORS` map (PR #2141, merged 2026-04-12)
- [x] S3 state key `integrator-atento-br/terraform.tfstate` → `integrator-atento/terraform.tfstate` (PR pending)
- [ ] CloudWatch log group `/aws/lambda/EC2-start-integrator-atento-br` — cleanup (lambda managed in separate repo)

### Prerequisite: workflow `suffix` input in integrator repo

The `deploy-ecs.yaml`, `startup.yaml`, and `shutdown.yaml` workflows support an optional `suffix` input, required for atento's multi-env deployment. Reference: SPIKE-multi-env.md Q1.

**What was implemented:**
1. Optional `suffix` choice input with options `(none)`, `staging`, `br`, `mx`, `co`, `cl` (default `(none)`)
2. Service names become: `integrator-{integrator}-web${SUFFIX}-service` where `SUFFIX=-${suffix}` when non-`(none)`, else empty
3. Single-env clients (almaviva, maqnelson, redebrasil) keep working with `suffix=(none)` — names unchanged
4. `startup.yaml` / `shutdown.yaml` skip MongoDB start/stop step when `vars.AWS_INSTANCE_IDS` is empty (atento does not manage MongoDB via workflow)
5. `deploy-ecs.yaml` preflight adds a service existence check — aborts early if `integrator + suffix` combination does not exist

**Status:**
- [x] `suffix` input + service existence check in `deploy-ecs.yaml` — merged (integrator PR #2137, 2026-04-10)
- [x] `suffix` input + empty `AWS_INSTANCE_IDS` handling in `startup.yaml` and `shutdown.yaml` — merged (integrator PR #2138, 2026-04-10)

### Networking phase (VPC redesign + MongoDB connectivity)

Reuse standard Steps 1–9 from "Standard per-integrator migration checklist" below. The networking work is identical whether single-env or multi-env.

**atento-specific details:**

1. **Pre-work — Drop public infrastructure via AWS CLI** (Step 1 standard)
   - Delete public subnet `pub-b` (10.12.255.0/28)
   - Delete public route table
   - Delete SSM parameters for public subnet

2. **Rename subnets via terraform state mv** (Step 2 standard)
   - `prv-a` (10.12.255.128/26, sa-east-1a) → `prv-a-old`
   - `prv-b` (10.12.255.192/26, sa-east-1c) → `prv-b-old`

3. **Update Terraform code** (Step 3 standard)
   - Update `vpc_atento.tf` (renamed from `vpc_atento_br.tf`)
   - Remove public resources from code
   - Create new `prv-a` at 10.12.255.0/26 (sa-east-1a)
   - Create new `prv-b` at 10.12.255.64/26 (sa-east-1b, normalized from sa-east-1c)
   - Update SSM params (keep `/integrator-atento/private_subnet_ids` for integrator module — used even though `enable_mongo = true`)

4. **Apply networking stack** (Step 4 standard)

**atento MongoDB decision:** NO new MongoDB instances are created. The existing MongoDB (mongo000/001/002 in prv-a-old/prv-b-old) stays on EC2 and is reachable from new ECS subnets (same VPC, same security group). See PLAN.md "MongoDB (Decision 6 — NOT migrating)".

### Stack creation: `integrator-atento/` folder structure

Each country gets its own ECS cluster with standard service names (web, worker, runner). One shared ALB with host-based routing serves all clusters. See PLAN.md "Decision 7 — one cluster per environment".

**New files:**

- **`ssm.tf`** — SSM parameters nested by country
  - Namespace: `/integrator-atento/{br,mx,co,cl}/{SECRET_NAME}`
  - Use `for_each` with cross-product: `toset([for pair in setproduct(["br", "mx", "co", "cl"], ["SECRET_KEY_BASE", "MONGODB", ...]) : "${pair[0]}/${pair[1]}"  ])`
  - IAM policy wildcard: `arn:aws:ssm:...:parameter/integrator-atento/*` (covers all sub-paths)
  - Reference: SPIKE-multi-env.md Q2, Approach A

- **`compute.tf`** — ALB (shared), 4 ECS clusters, services per cluster, schedules, IAM deploy
  - **ALB:** One `aws_lb` resource (directly in `compute.tf`, NOT via `internal_alb` module)
    - Listener on port 80
    - One `aws_lb_listener_rule` per country with `host_header` condition
    - One `aws_lb_target_group` per country with `target_type = "ip"` (Fargate IP targeting)
  - **ECS clusters:** 4 clusters — `integrator-atento-br-cluster`, `integrator-atento-mx-cluster`, `integrator-atento-co-cluster`, `integrator-atento-cl-cluster`
  - **Services:** 3 per cluster (web, worker, runner) = 12 module calls total
    - `module "web_br"` → cluster BR, service name `integrator-atento-br-web-service`
    - `module "worker_br"` → cluster BR, service name `integrator-atento-br-worker-service`
    - `module "runner_br"` → cluster BR, service name `integrator-atento-br-runner-service`
    - (repeat for mx, co, cl)
    - Each service module receives country-specific locals: `local.env_vars_br`, `local.secrets_br`, etc.
    - Runner services always have `desired_count = 0` (on-demand via `ecs run-task`)
  - **EventBridge schedules:** Per-country Schedule 1 (scale-up) + Schedule 2 (RunTask cron)
    - No Schedule 0 (MongoDB already running)
    - BR schedule: scale-up `cron(55 1 * * ? *)`, cron `cron(0 2 * * ? *)`
    - MX, CO, CL schedules: TBD (to be confirmed from existing EventBridge rules)
  - **IAM deploy module:** One `module "iam_deploy"` for the atento client (all countries use same IAM user)

**Terraform apply:**
- [ ] `terraform plan` reviewed: creates cluster, ALB, 12 services, SSM params
- [ ] `terraform apply`

### SSM population + environment isolation

**Per-country values under `/integrator-atento/{country}/<NAME>`:**

- [ ] Populate `/integrator-atento/br/{SECRET_KEY_BASE, MONGODB, ...}` for BR
- [ ] Populate `/integrator-atento/mx/{...}` for MX
- [ ] Populate `/integrator-atento/co/{...}` for CO
- [ ] Populate `/integrator-atento/cl/{...}` for CL (even though services at desired_count=0)

Commands:
```bash
aws ssm put-parameter --name "/integrator-atento/br/SECRET_KEY_BASE" --value "..." --type SecureString --overwrite --region sa-east-1
aws ssm put-parameter --name "/integrator-atento/br/MONGODB" --value "..." --type SecureString --overwrite --region sa-east-1
# (repeat for mx, co, cl)
```

### DNS: four records in `dns/internal_dns_integrator.tf`

All four records point to the same ALB (using host-based routing):

- [ ] `integrator-atento-br.4shark.internal` → ALB IP
- [ ] `integrator-atento-mx.4shark.internal` → ALB IP
- [ ] `integrator-atento-co.4shark.internal` → ALB IP
- [ ] `integrator-atento-cl.4shark.internal` → ALB IP

### Deploy pipeline: one workflow dispatch per country

In the integrator repo, create deploy triggers per country (or use a common workflow with the `environment` input):

- [ ] Create GitHub workflow dispatch or use matrix to trigger `deploy-ecs.yaml` with `integrator=atento, environment=br`
- [ ] Repeat for `environment=mx`, `environment=co`
- [ ] One dispatch per country — they have independent upgrade cadence

### Validation: per-country

For each country (Brazil first, then MX, CO, Chile last):

1. **First deploy for the country:**
   - [ ] Trigger deploy workflow dispatch: `integrator=atento, environment=br`
   - [ ] Verify preflight check passes (MongoDB tags match `4client-atento-mongo*`)
   - [ ] Task definition registered with correct country-specific env vars
   - [ ] ECS web service updated with new image from ECR
   - [ ] ECS worker service updated; 1 Fargate task running

2. **ALB health check:**
   - [ ] ALB target group for `integrator-atento-br` receiving traffic
   - [ ] Health check status: healthy
   - [ ] `integrator-atento-br.4shark.internal` resolves to ALB
   - [ ] One-liner test: `curl -H "Host: integrator-atento-br.4shark.internal" http://<ALB_IP>/` (from management VPN)

3. **ECS Exec validation:**
   - [ ] `bin/ecs connect atento br` connects to running web task
   - [ ] `bin/ecs run atento br "bin/rake -T"` executes a rake task in runner container

4. **CloudWatch logs:**
   - [ ] Web task logs show application startup (no connection errors to MongoDB)
   - [ ] Worker task logs show job processing starting

5. **Disable old EventBridge rule (only after BR validated):**
   - [ ] Verify ECS web/worker healthy and processing jobs
   - [ ] Disable EventBridge rule `EC2-start-integrator-atento-br` (do NOT delete yet)
   - [ ] Keep new EventBridge rules for BR enabled

6. **First full automated cycle per country:**
   - [ ] Wait for Scale-up Schedule to fire (01:55 UTC = 22:55 BRT)
   - [ ] Verify web + worker tasks scale up to desired_count
   - [ ] Wait for cron Schedule (02:00 UTC = 23:00 BRT) — runner task starts
   - [ ] Verify cron task processes (CloudWatch logs) and completes
   - [ ] Verify self-shutdown fires (approx 45 min after start, application-driven)
   - [ ] Verify tasks are gone or at desired_count=0 (successful shutdown)

7. **Repeat for MX, CO and CL** (same steps as BR)

8. **EC2 app server termination (per country, after validation):**
   - [ ] `app002` (BR) — terminate only after BR ECS fully validated
   - [ ] `mx-app002` (MX) — terminate only after MX ECS fully validated
   - [ ] `co-app002` (CO) — terminate only after CO ECS fully validated
   - [ ] `cl-app002` (CL) — terminate only after CL ECS fully validated
   - [ ] Set `app_servers = {}` in `main.tf` and apply

---

## Standard per-integrator migration checklist

This is the procedure for single-environment integrators (almaviva, maqnelson, redebrasil). Steps are numbered sequentially. Execute in order. For multi-environment clients (atento, commcenter), use the "Multi-environment migration checklist" above instead.

### Step 1 — Drop public infrastructure via AWS CLI

Before touching Terraform code, manually delete using AWS CLI to avoid CIDR conflicts:
1. Delete the public subnet (`aws ec2 delete-subnet`)
2. Delete the public route table (`aws ec2 delete-route-table`) — delete routes first if needed
3. Delete SSM parameters for public subnet IDs and public route table ID (`aws ssm delete-parameter`)
**Do NOT delete the IGW.**

### Step 2 — Rename existing private subnets via `terraform state mv`

4. `terraform state mv` prv-a → prv-a-old, prv-b → prv-b-old
5. `terraform state mv` route table associations: prv_a → prv_a_old, prv_b → prv_b_old

### Step 3 — Update Terraform code + remove state for dropped resources

6. Update `networking/vpc_{client}.tf`: remove public resources from code, rename old subnets, add new prv-a (sa-east-1a) + prv-b (sa-east-1b)
7. Update `networking/ssm.tf`: remove public SSM params, add `/prv_a_subnet_id` + `/prv_b_subnet_id`. Keep `/private_subnet_ids` — it is used by the `networking_data` module which feeds `subnet_pub_b_id` (legacy required field in the integrator module). After old subnets are removed, update it to point to the new subnets.
8. `terraform state rm` for resources dropped via CLI (subnet, route table, association, route, SSM params)

### Step 4 — Apply networking stack

9. `terraform plan` + `terraform apply`

### Integrator stack (`integrator-{client}/`)

10. **Create `mongodb.tf`**: mongo003 (Primary, prv-a, t3.small, 60GB), mongo004 (Secondary, prv-b, t3.small, 60GB), mongo005 (Arbiter, prv-b, t3.micro, 20GB). All with `prevent_destroy = true`.
11. **Create `ssm.tf`**: SSM SecureString parameters under `/integrator-{client}/` + IAM policy for `ecsTaskExecutionRole`. Copy from `integrator-almaviva/ssm.tf`.
12. **Create `compute.tf`**: ECS cluster, ALB, web service, worker service, runner service, Schedule 0 (start MongoDB), Schedule 1 (scale-up), Schedule 2 (RunTask cron), IAM deploy module. Copy from `integrator-almaviva/compute.tf`, substitute names and schedules.
13. **Update `main.tf`**: `has_public_subnets = false`, `has_nat_gateway = false`, `enable_mongo = false`. Point subnets to new SSM params. Keep `app_servers` until validated.
14. **Apply** integrator stack (creates ECS + MongoDB EC2 instances)

### MongoDB migration (manual / Ansible)

11. **Install MongoDB** on mongo003/004/005 via Ansible (same version as existing cluster)
12. **Add mongo003 and mongo004** as new secondaries to existing replica set
13. **Elect mongo003 as PRIMARY**; set mongo005 as ARBITER; remove old nodes from RS
14. **Update application connection strings** (env var `MONGODB`) and validate
15. **Terminate old MongoDB instances** (mongo000/001/002); confirm `enable_mongo = false` in `main.tf`

### SSM population + deploy pipeline

16. **Populate SSM values**: `aws ssm put-parameter --name "/integrator-{client}/<NAME>" --value "<VALUE>" --type SecureString --overwrite --region sa-east-1`
17. **Create `deploy-{client}.yaml`** in integrator repo (copy from `deploy-almaviva.yaml`, substitute names)
18. **Strip GitHub Environment** to credentials only (remove all application env vars, keep `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`)

### Validation

19. **Trigger first deploy** via GitHub Actions; verify ECS services running with real image
20. **Validate**: ALB health check, CloudWatch logs, `bin/ecs connect`, `bin/ecs run`
21. **Disable old EventBridge rule** (`EC2-start-integrator-{client}`)
22. **Wait for first full automated cycle**: scale-up → cron → processing → self-shutdown
23. **Create PR** with all terraform changes

### DNS (dns/ stack)

24. **Add ALB DNS record** in `dns/internal_dns_integrator.tf`: `integrator-{client}.4shark.internal` → ALB

---

## Per-integrator specifics

Differences from the standard checklist. If not listed here, the standard checklist applies as-is.

### maqnelson

- **Topology**: 1 web (d=1) + 1 worker (d=2) + runner (d=0)
- **VPC CIDR**: 10.1.2.0/24 — new prv-a: 10.1.2.0/26 (sa-east-1a), new prv-b: 10.1.2.64/26 (sa-east-1b)
- **Schedules**: MongoDB start TBD, scale-up `cron(25 1 * * ? *)`, cron `cron(30 1 * * ? *)`
- **Note**: pub-b (10.1.2.0/28) is inside the 10.1.2.0/26 range — must be destroyed before new prv-a can be created at that CIDR

### aster-maquinas

- **Topology**: 2 web (prod + staging, d=1 each) + 2 worker (prod + staging, d=1 each) + runner (d=0)
- **SSM prefix**: `/integrator-aster-maquinas/prod/*` and `/integrator-aster-maquinas/staging/*`
- **VPC CIDR**: TBD when phase begins
- **Schedules**: MongoDB start TBD, scale-up `cron(55 0 * * ? *)`, cron `cron(0 1 * * ? *)`

### commcenter

- **Pattern**: Multi-environment (prod + staging) — see "Multi-environment migration checklist" section above (adapted for 2 environments instead of 4)
- **Clusters**: `integrator-commcenter-cluster` (prod), `integrator-commcenter-staging-cluster` (homologation)
- **Topology**: 2 web (prod + staging, d=1 each) + 2 worker (prod + staging, d=1 each) + 2 runners (d=0, one per cluster)
- **SSM namespace**: `/integrator-commcenter/*` (prod) and `/integrator-commcenter-staging/*` (homologation)
- **GitHub Environment**: `commcenter` (prod) and `commcenter-staging` (homologation)
- **VPC CIDR**: 10.1.3.0/24; new prv-a: 10.1.3.0/26 (sa-east-1a), new prv-b: 10.1.3.64/26 (sa-east-1b — normalized from sa-east-1c)
- **MongoDB**: Migrate to new subnets (standard procedure — mongo003/004/005)
  - Current: mongo000 (arbiter, 10.1.3.166, prv-a, t3.micro), mongo001 (10.1.3.245, prv-b, t3.small), mongo002 (10.1.3.180, prv-a, t3.small)
- **ALB**: Host-based routing (same pattern as atento)
- **DNS**: `integrator-commcenter.4shark.internal` (prod), `integrator-commcenter-staging.4shark.internal` (homologation)
- **Schedules (prod only)**:
  - Schedule 0 (start MongoDB): `cron(50 3 * * ? *)` — 03:50 UTC = 00:50 BRT
  - Schedule 1 (scale-up): `cron(55 3 * * ? *)` — 03:55 UTC = 00:55 BRT
  - Schedule 2 (cron RunTask): `cron(0 4 * * ? *)` — 04:00 UTC = 01:00 BRT
  - Staging: no schedules, `desired_count = 0`, deploy on demand
- **Deploy workflow**: One dispatch per environment (same as atento)
- **EC2 app servers**: `app002` (prod, stopped), `staging-app001` (homologation, stopped) — both terminate after ECS validation
- **Note**: `vpn_client_cidrs` set in `main.tf` causes SG drift — must be removed (lesson learned #4)
- **Note**: `pub-b` (10.1.3.0/28) is inside the 10.1.3.0/26 range — must be destroyed before new prv-a can be created

### redebrasil

- **Topology**: 1 web (d=1) + 1 worker (d=1) + runner (d=0)
- **VPC CIDR**: TBD when phase begins
- **Schedules**: MongoDB start TBD, scale-up `cron(55 1 * * ? *)`, cron `cron(0 2 * * ? *)`. Extra schedule: scale-up `cron(55 17 20-27 * ? *)`, cron `cron(0 18 20-27 * ? *)` (days 20–27 only)

### atento

- **Pattern**: Multi-environment (BR, MX, CO, CL) — see "Multi-environment migration checklist" section above
- **Topology**: 12 services (web, worker, runner × 4 countries); CL at `desired_count = 0`
- **SSM namespace**: `/integrator-atento/{br,mx,co,cl}/{SECRET_NAME}`
- **VPC CIDR**: 10.12.255.0/24; new prv-a: 10.12.255.0/26 (sa-east-1a), new prv-b: 10.12.255.64/26 (sa-east-1b)
- **MongoDB**: NOT migrated — stays on EC2 in -old subnets; `mongodb.tf` NOT created; `enable_mongo = true`
- **ALB**: Host-based routing, one ALB, 4 target groups; declared in `compute.tf` (not via module)
- **Schedules**: No Schedule 0 (no MongoDB start); Schedule 1 + 2 per country (BR: scale `cron(55 1 * * ? *)`, cron `cron(0 2 * * ? *)`)
- **EC2**: `app002` (BR), `mx-app002` (MX), `co-app002` (CO), `cl-app002` (CL) terminate after per-country validation.
- **Deploy workflow**: Optional `environment` input in `deploy-ecs.yaml` REQUIRED before first deploy
- **Rename pre-work**: Stack folder, files, tags, MongoDB tags, GitHub Environment, ECR repo — all must be renamed BEFORE ECS creation

---

## Phase 8: EC2 Decommission — All Integrators

> **Pre-conditions (all must be true before executing):**
> - [ ] All 6 integrators running on ECS
> - [ ] Cron jobs migrated to ECS Scheduled Tasks
> - [ ] EventBridge Schedulers created and tested
> - [ ] Application self-shutdown migrated from EC2 stop to ECS UpdateService
> - [ ] At least one full cycle per integrator verified
> - [ ] No incidents after at least 1–2 weeks of parallel operation

### Application self-shutdown migration (integrator repo)

- [ ] Locate shutdown process in codebase (calls EC2 stop API today)
- [ ] Replace with `ecs:UpdateService` (desired_count=0) targeting web + worker services
- [ ] Inject `INTEGRATOR_NAME` env var per integrator (so same code works for all)
- [ ] Ensure ECS task role has `ecs:UpdateService` permission
- [ ] Test on almaviva first, then deploy to all

### Per-integrator EC2 termination

For each integrator, in order:

- [ ] Set `app_servers = {}` in `main.tf`
- [ ] `terraform plan` → confirm EC2 removals
- [ ] `terraform apply`
- [ ] Decommission old subnets (prv-a-old, prv-b-old) in networking stack
- [ ] Remove old Lambda CloudWatch log groups (`/aws/lambda/EC2-start-integrator-{name}`)

### Final validation

- [ ] Verify all 22 Fargate tasks running across 6 integrators
- [ ] Verify all 12 EC2 app server instances terminated
- [ ] Update DNS: remove old EC2 records from `dns/internal_dns_integrator.tf`
- [ ] Compile final cost report
- [ ] Move feature folder to `~/.claude/plans/completed/terraform/integrators-ec2-to-ecs/`

---

## Pending items (post-migration)

- [ ] Regenerate module READMEs via terraform-docs (stale after variable cleanup)
