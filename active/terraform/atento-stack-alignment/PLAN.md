# PLAN — Atento Stack Alignment (Parallel Directory Migration)

> Reference: derived from PLAN-SPIKE.md (2026-07-06); shared-001 precedent commits: `0f8bb6f` (ECR/SSM), `f118eaa` (durables), `5da46b2` (destroy), `32c5cec` (reclaim); `app-shared-001/main.tf`, `app-atento-001/` current state (2026-07-06)

## Execution progress (updated 2026-07-06)

- **Phase 0 — DROPPED** (see § Scope; no precedent, no purpose).
- **Phase 1 — DONE ✅** (PR #630, merged). New `atento-001/` parallel compute stack applied: 133 resources (cluster `atento-001-cluster` ACTIVE + 9 services at `desired_count=0` + capacity providers + ALB + CodeDeploy + Lambda schedulers + scheduled tasks), state key `atento-001/terraform.tfstate`, plan converged `No changes` (0/0/0). Note during execution: `module "ecr"` was NOT created here (repos already exist — that was the Phase-2 job); the fresh ASGs got the `AmazonECSManaged` tag on capacity-provider association and it was removed by a one-time apply (MTP=DISABLED means ECS does not re-add it → converged to match shared).
- **Phase 2 — DONE ✅** (PR #631, merged). ECR (2 repos) + SSM (20 secrets) + `aws_iam_role_policy.ecs_ssm_read` ownership migrated `app-atento-001/` → `atento-001/` via cross-state `terraform state mv` (move by base address for the for_each SSM resource + iam policy; move by indexed instance for the for_each `module.ecr`). Old stack: `module "ecr"` dropped, SSM `resource`→`data`, 3 references fixed (`compute.tf` ecs_cluster depends_on, `compute.tf` service depends_on, `github_deploy.tf` secret ref). Both stacks plan `No changes` (0/0/0), zero AWS change.
- **Phase 3 — SPLIT into sub-PRs (see § Phase 3).**
  - **Phase 3a — DONE ✅** (PR #632, merged). Core durables + coupled IAM migrated `app-atento-001/` → `atento-001/`: RDS Aurora (+ log group + data-tier SG + db subnet group), MongoDB Atlas (+ the separate `aws_ssm_parameter.mongo_url`), Redis cache+sidekiq, S3, `module.backup`, IAM deploy user + `deploy_s3_access` policy + attachment + `module.deploy_key` (github). 14-address cross-state `state mv`, both stacks `No changes` (0/0/0), zero AWS change / zero downtime. **3d (backup) and 3e (IAM) folded into 3a** due to coupling (pooler↔rds, backup↔rds, s3↔IAM). Old-stack shims added: `data.aws_rds_cluster` (pooler endpoints), `data.aws_iam_user.deploy` (compute-side grant), re-declared `module.vpc_data` (it had lived in the moved rds.tf), copied `data.terraform_remote_state.monitoring` into the new stack (backup needs it). **Gate lesson:** the first surgery missed 2 top-level resources inside moved files (`aws_db_subnet_group.app_atento_001`, `aws_ssm_parameter.mongo_url`) — the 0/0/0 gate caught them (2-add/2-destroy) before any apply; moved them, re-verified 0/0/0. Always enumerate top-level resources in moved files, not just the modules.
  - **Phase 3b — DONE ✅** (PR #633, merged). OpenSearch migrated: `git mv opensearch.tf`, moved `module.opensearch` (2-address surgery: `module.opensearch` + `aws_security_group.opensearch`) old→new. New stack's `module.task_config` `opensearch_host` switched from `data.aws_opensearch_domain.this.endpoint` → `module.opensearch.domain_endpoint` (data source removed); old stack keeps `data.aws_opensearch_domain.this` (opensearch_data.tf) for its compute + the `opensearch_endpoint` output; the 2 `opensearch_master_user/password` outputs removed (data source can't expose them). NEW plan 0/0/0; OLD plan 0 resource changes (only the 2 removed output values → null, "without changing any real infrastructure"). Domain untouched, zero downtime.
  - **Phase 3c — DONE ✅** (PR #634, merged). CloudWatch monitoring (pattern `6970efb`): `git mv monitoring.tf` old→new, moved `module.cloudwatch_monitoring` (1 module → 15 objects: ECS/RDS/OpenSearch/Lambda/cron alarms). The cron-family prefix that read `local.env` in the old stack now derives the identical `app-atento-001` from `"app-${var.environment}"` (new stack has no `local.env`). `data.terraform_remote_state.monitoring` was already in the new stack (copied in 3a for backup) — reused, not duplicated; the old stack keeps its own copy for the `rollbar_project_id` output. Alarm config unchanged — still targets the live `app-atento-001-*` resources (re-target to the new cluster is Phase 4). NEW plan 0/0/0; OLD plan 0 resource changes (only the carryover 2 opensearch outputs → null from 3b, "without changing any real infrastructure"). Zero AWS change, zero downtime.
  - **🎉 Phase 3 COMPLETE.** All ownership migrated `app-atento-001/` → `atento-001/`: ECR+SSM (P2), core durables+IAM (3a), OpenSearch (3b), monitoring (3c). The new stack now owns everything; the old stack retains only the live compute + the pooler (both serve until cutover) + 2 stale opensearch outputs (harmless, apply whenever).
  - **Phase 4 — DONE ✅** (PR #635, merged). Capacity + cron containment only — the two findings below reshaped it from the original plan:
    - **SG-whitelist step (original steps 1-2) DROPPED as MOOT.** RDS/OpenSearch data-tier ingress is CIDR-based over the shared VPC (`module.vpc_data.vpc_cidr`), Redis is Redis Cloud SaaS (`source_ips = ["0.0.0.0/0"]`), and shared never added a per-cluster SG to the data tier. The new cluster (same VPC, `networking_environment = "app-atento-001"`) already has connectivity — no whitelist needed.
    - **Monitoring re-target + cron ENABLE deferred to Phase 5 (cutover).** The `module.cloudwatch_monitoring` is singular (one `cluster_name`/`web_service_name`); it can only watch one cluster. Re-targeting it to the new cluster in Phase 4 would blind the OLD cluster, which serves 100% of traffic until the DNS flip. So monitoring flips old→new atomically at cutover. RDS/OpenSearch monitoring inputs stay `app-atento-001-*` regardless (Aurora rename is 7d; OS domain immutable).
    - **What Phase 4 actually did:** (1) new stack's 7 scheduled tasks set `state = "DISABLED"` (each cluster owns an independent EventBridge trigger — enabling now would double-fire every cron against the live old cluster); (2) capacity floors raised to the old-atento baseline (`web_min_size` 0→4, the 5 active workers 0→1, `web_max_size` 12→8 to mirror old; cleansing/migration/runner stay 0). Plan 0-add/13-change/0-destroy (6 ASGs + 7 schedules), applied clean.
    - **DEPLOY-DEPENDENCY FINDING (the crux for Phase 5):** the new cluster's ECS task definitions are terraform **bootstraps** with `command = []` — `module.ecs_services` does `command = lookup(each.value, "command", [])` and neither the `services` tfvars map nor `locals.tf` sets a command (confirmed identical in the live, working `app-shared-001`). The real Sidekiq command (`bundle exec sidekiq -C config/sidekiq_<queue>.yml`) is injected by the **app deploy pipeline** (`app` repo `deploy-atento-001.yaml`), which registers its own task-def revision and is in the service's `ignore_changes = [task_definition]`. That workflow hardcodes `CLUSTER_NAME: app-atento-001-cluster` (the OLD cluster). **The new cluster has never been deployed to** → its task defs have no command → tasks exit 1 (tini prints usage, no program). Image + env + secrets were all correct; only the command was missing.
    - **Premature step, reverted:** during validation I set `desired_count` 0→baseline expecting running tasks; they crash-looped (no command). Reverted all 6 services back to `desired_count=0`. The 9 min_size EC2 instances stay up (capacity ready for the Phase-5 deploy). Lesson: "task running" cannot be validated in Phase 4 — it depends on the deploy, which is Phase 5.
  - **Phase 5 — IN PROGRESS (cutover).** Traffic is on the new cluster and stable. Done so far:
    - **Deploy retarget** (`app` #5207 → `develop`; release **3.47.0** #5208 → `master`, tagged) — `deploy-atento-001.yaml` now targets `atento-001-*`. First deploy attempt ran from the `master` ref (pre-retarget) → hit the OLD cluster (no-op); the retarget only reached `master` via the 3.47.0 release, after which the deploy from `master` registered real task defs on the new cluster (Sidekiq commands present, revisions bumped).
    - **Deploy-user IAM** (terraform #636) — the new stack never instantiated `module.iam_deploy` (the "cagada"), so the deploy user lacked `codedeploy:CreateDeployment` on the new deployment group and the web blue/green failed with AccessDenied. Added `module.iam_deploy` to `atento-001/` mirroring every other stack. Additive, applied.
    - **🔥 OUTAGE + root cause (the big lesson):** the first DNS flip took atento DOWN. Root cause = **the connection POOLER's SG whitelists only the OLD cluster's SG on 6432** (`sg-02b23ed9dd3626fb7`); the new cluster's SG (`sg-0659e817466472932`) was not allowed → every DB query on the new web hung on connection (0 xacts/s at the pooler, `find_by` blocked ~100s, Rack::Timeout 500s). **This is exactly the "SG-whitelist step" dropped as MOOT in Phase 4** — that analysis only checked RDS/OpenSearch/Redis (CIDR/SaaS) and NEVER checked the pooler, which is SG-based. Rolled back the DNS (instant Cloudflare revert to old ALB, service restored). Fix: **terraform #637… no — #638** added `aws_security_group_rule.pooler_new_cluster_ingress` on the pooler SG for the new cluster's SG (read via `data.terraform_remote_state.atento_001`), transitional, removed when the pooler migrates in Phase 7. Validated end-to-end from a new web container: `POOLER_OPEN` (TCP) + `DB_QUERY_OK` (`rails runner` SELECT through the pooler).
    - **DNS cutover** (terraform #637, re-applied after the fix) — `dns/alb_data.tf` ALB lookup `app-atento-001-lb` → `atento-001-lb`; `atento001.app4shark.com` CNAME now targets the new ALB. Post-flip 5-min watch: 102× 200 / 3× 302, **0 timeouts / 0 500s**, pooler serving new-cluster queries (`wait ~13us`, no queuing). Stable well past the ~2-3min mark where it degraded during the outage.
    - **Worker cutover:** old 5 sidekiq workers quieted (TSTP via `aws ecs execute-command … pkill -TSTP -f sidekiq`, all logged "Received TSTP"), then old worker services scaled to `desired_count=0` (queue drained empty first). Job processing is 100% on the new cluster.
    - **Monitoring re-target** (terraform #639, merged/applied) — `atento-001/monitoring.tf` ECS/service/lambda → new cluster; RDS/OS kept on `app-atento-001`. Validated in practice: the alarms were all in ALARM (watching the now-idle old cluster) and self-resolved once pointed at the live new cluster.
    - **🔥 POOLER SG CONFLICT (second near-miss, caught by the plan gate):** the #638 fix added a STANDALONE `aws_security_group_rule` to the pooler SG, but the pooler module manages that SG with INLINE `ingress` — the classic AWS-provider inline-vs-standalone conflict. The next `app-atento-001/` apply (the cron-disable plan) wanted to REVERT the new-cluster rule → would have re-broken the pooler. Fixed (#642) by extending the `connection_pooler` module with `additional_app_security_group_ids` (default [], backward-compat) folded into its inline ingress, switching atento to it, and dropping the standalone rule. Zero-downtime migration: `terraform state rm` the standalone rule (live rule preserved), then apply — the inline block adopts the already-present rule (plan showed only an in-place description reconcile; the new-cluster SG never left the live ingress, verified both SGs present on 6432 post-apply, app served 0 errors throughout). **Lesson: never mix inline `ingress` with `aws_security_group_rule` on the same SG.**
    - **Cron flip** (terraform #640 enable-new + re-target cron alarm families; #641 disable-old) — applied #641 before the 00:00 hourly cron, so the double-fire window was avoided. Crons now run only on the new cluster; the old schedules are DISABLED.
    - **✅ Phase 5 FUNCTIONALLY COMPLETE.** Atento runs entirely on the new cluster: traffic (DNS), DB (pooler SG fixed), workers, monitoring, crons — all on `atento-001-*`. The old `app-atento-001` cluster is idle (web still up but no traffic, workers/crons off) + the pooler still lives in the old stack (serves the new cluster via the SG rule) until Phase 7.
    - **STILL PENDING:** merge #641; **cleanup debt** (worktrees: atento-mon-retarget, atento-dns-cutover, atento-dns-reflip, atento-pooler-sg, atento-pooler-sg-v2, atento-cron-enable, atento-cron-disable + branches; the dns re-flip on `feature/atento-001-dns-reflip` was a direct apply with no PR — reconciled #637's rollback drift; branch/worktree to remove); Phases 6 (destroy old compute) + 7 (reclaim slot + Aurora rename).
    - **CLEANUP DEBT:** worktrees `atento-mon-retarget`, `atento-dns-cutover`, `atento-dns-reflip` + their branches; the DNS re-flip was a direct apply on branch `feature/atento-001-dns-reflip` (no PR — it re-applied merged #637 to reconcile the emergency rollback divergence; branch/worktree to remove).
    - **Phase-4 correction:** the "SG-whitelist DROPPED as MOOT" note above is WRONG for the pooler — see the outage. Data-tier (RDS/OS/Redis) is CIDR/SaaS, but the pooler is SG-based and DID need the new cluster whitelisted.
  - **Phase 6 — DONE ✅ (destroy old compute).** Diverged from the shared precedent because of Option C (the pooler lives in the old stack and depended on the old cluster):
    - **6a (pooler repoint, #643):** the pooler's `app_security_group_id` was `module.ecs_cluster.security_group_id` (old cluster, about to be destroyed). Repointed it to the new cluster SG (`data.terraform_remote_state.atento_001.outputs.cluster_security_group_id`), dropped `additional_app_security_group_ids`. Plan showed only the pooler SG in-place, removing the old SG rule — the new cluster's rule is byte-identical before/after so it was untouched → zero downtime.
    - **6b (destroy, #644):** deleted `compute.tf` / `output.tf` / `ssm.tf` / `opensearch_data.tf`, stripped `main.tf` to locals. **KEPT `vpc_data.tf` + `rds_data.tf`** (the PLAN's shared-based list said delete vpc_data.tf — WRONG for atento; the pooler needs `module.vpc_data`). Two safety gates on the plan: (1) no `connection_pooler`/`vpc_data`/`rds_cluster` line in the destroy; (2) no `atento-001-*` (new) name in the destroy — both passed; all 141 were `app-atento-001-*`.
    - **Destroy hang lessons (three):** (1) the web ASG hung ~9min because the ECS capacity provider's `ecs-managed-draining-termination-hook` (heartbeat timeout **3600s = 1h**, DefaultResult CONTINUE) held the 4 instances in `Terminating:Wait` after its handler was destroyed — fix: `aws autoscaling complete-lifecycle-action --lifecycle-action-result CONTINUE` per instance. (2) terraform's first apply had already errored on the ASG-drain wait by then (`output = 1, want 0`) → re-plan/re-apply the leftover 7. (3) the leftover launch-template delete stuck in a provider retry loop even after the ASG was gone → `aws ec2 delete-launch-template` manually; the run's next retry caught up and completed. **For Phase-7-era teardowns: complete the drain lifecycle hook proactively, or expect the ASG destroy to wait up to 1h.** Final: old stack `plan` = No changes (0/0/0), only pooler + shims remain; app + pooler healthy throughout.
  - **STILL PENDING:** Phase 7 (7a pooler ownership → atento-001/ state; 7b file moves + S3 state copy to reclaim the `app-atento-001/` slot; 7c `module.app` convergence via `moved{}`; 7d **Aurora rename** `app-atento-001-cluster` → `atento-001-cluster`, ~5min planned DB window). Recommend fresh context — 7d carries the only planned downtime of the whole migration.
- **State-surgery recipe proven in Phase 2** (reuse for Phase 3/7a): backup both states first (`terraform -chdir=<dir> state pull > /tmp/BACKUP_*.json`, raw path — the wrapper refuses `state pull`); copy to working files; `terraform -chdir=<dir> state mv -state=<old-working> -state-out=<new-working> <addr> <addr>` (for_each resource base address moves all instances; for_each MODULE needs indexed-instance moves); verify with **raw grep on the working JSON** (NOT `state list -state=` — that reads the S3 backend, not the local file); push NEW first then OLD (`AWS_PROFILE=4shark-mfa … state push <working>`); gate = `plan` 0/0/0 on BOTH stacks.

## Objective

Migrate the `app-atento-001` production ECS stack into the canonical `atento-001` naming convention, replacing the legacy `app-*` prefix on all compute and infrastructure resources. The migration must be zero-downtime and risk-staged, ending with a single `app-atento-001/` Terraform directory that owns everything — identical to how `shared-001` ended after its migration. The parallel directory (`atento-001/`) is a transient artifact that is destroyed and reclaimed when the migration is complete.

**Current state snapshot (2026-07-06):**

- `app-atento-001-cluster` LIVE (9 ECS services, all `app-atento-001-*` prefix)
- `atento-001-connection-pooler` cluster LIVE (pooler already migrated — done)
- `connection-pooler-atento-001.4shark.internal` CNAME active
- Aurora `app-atento-001-cluster` LIVE (PG 16.13, MultiAZ, DeletionProtection: true)
- No `atento-001/` directory exists yet — parallel build NOT started

## Scope

### In scope

> **Phase 0 dropped (2026-07-06).** The prior plan opened with a "parameterize the old `app-atento-001/` stack in place" phase. This has no precedent and no purpose: the shared-001 parallel-build commit `0c5354c` created ONLY `shared-001/*` files (born parameterized) and never touched `app-shared-001/`; the old stack stayed untouched until destroy (`5da46b2`). Parameterizing the old atento stack in place buys nothing — with `var.environment = "atento-001"` it would even force a cluster rename (the opposite of zero-change). The parameterization happens in the NEW `atento-001/` stack, authored parameterized from the shared template (Phase 1). The old-stack hardcode table below is retained only as the source-of-truth config the new stack replicates.

- Phase 1: Create `atento-001/` parallel compute directory (from `app-shared-001/` template, `module "ecs_cluster"` directly per Option C, all `min_size = 0`, backend key `atento-001/terraform.tfstate`)
- Phase 2: Transfer ECR + SSM secrets ownership from `app-atento-001/` to `atento-001/` (code redefinition + manual cross-state `terraform state mv`; proven pattern: commit `0f8bb6f`)
- Phase 3: Transfer durable resource ownership (MongoDB, Redis, S3, OpenSearch reference, IAM deploy user, RDS, `github_deploy.tf`) from `app-atento-001/` to `atento-001/` (physical git renames + code redefinition + state surgery; proven pattern: commit `f118eaa`)
- Phase 4: Prepare new cluster for traffic (whitelist new cluster SG in RDS/Redis/OpenSearch ingress rules; deploy monitoring for new `atento-001-*` cluster; scale up `min_size` from 0 to production values; validate task connectivity)
- Phase 5: Traffic cutover (DNS flip from old `app-atento-001` ALB to new `atento-001` ALB; update `dns/alb_data.tf` and app repo deploy workflow)
- Phase 6: Destroy old compute from `app-atento-001/` (ECS cluster, ASGs, capacity providers, services, ALB; pooler NOT destroyed — stays in `app-atento-001/` state; proven pattern: commit `5da46b2`)
- Phase 7: Reclaim `app-atento-001/` directory slot (proven pattern: commit `32c5cec`):
  - Phase 7a: Migrate pooler ownership to `atento-001/` state (code redefinition + state surgery)
  - Phase 7b: Physical file moves + S3 state copy (`atento-001/terraform.tfstate` → `app-atento-001/terraform.tfstate`)
  - Phase 7c: Introduce `module "app"` + `moved{}` blocks (mirroring `app-shared-001/main.tf:125-133`)
  - Phase 7d: Aurora cluster rename (`app-atento-001-cluster` → `atento-001-cluster`)

### Out of scope

- SSM parameter value rotation (values kept as-is via `lifecycle { ignore_changes = [value] }`)
- MongoDB Atlas cluster/project rename — MOOT: the Atlas cluster is already named `atento-001` (`app-atento-001/mongodb.tf`: `cluster_name = "atento-001"`, `project_name = "App Atento001"`); no rename is needed at any phase
- `compute.tf` file split in `app-atento-001/` (1,017 lines; hygiene improvement, not migration-blocking; old stack is destroyed at Phase 6)
- OpenSearch domain `app-atento-001` — immutable name in AWS; only state ownership transfers, not the physical AWS resource name

---

## Current State Assessment (as of 2026-07-06)

### AWS Inventory

**ECS clusters (us-east-1) — source: `/tmp/ecs_clusters_us_east_1.json`:**

| Cluster name | Status | Notes |
|---|---|---|
| `app-atento-001-cluster` | LIVE | OLD name; 9 services running (all `app-atento-001-*`) |
| `atento-001-connection-pooler` | LIVE | Pooler cluster; correct naming; already migrated |

**No `atento-001-cluster` exists** — parallel build NOT started.

**ECS services in `app-atento-001-cluster` (9 total) — source: `/tmp/ecs_services_atento.json`:**

- `app-atento-001-web-service`
- `app-atento-001-worker-commission-tiger-shark-service`
- `app-atento-001-worker-commission-white-shark-service`
- `app-atento-001-worker-commission-service`
- `app-atento-001-worker-system-service`
- `app-atento-001-worker-user-service`
- `app-atento-001-worker-cleansing-service`
- `app-atento-001-worker-migration-service`
- `app-atento-001-runner-service`

**Aurora RDS (us-east-1) — source: `/tmp/rds_clusters.json`:**

| Identifier | Engine | Version | MultiAZ | Status | DeletionProtection |
|---|---|---|---|---|---|
| `app-atento-001-cluster` | aurora-postgresql | 16.13 | true | available | true |

Endpoint: `app-atento-001-cluster.cluster-cvw5l7p4adp1.us-east-1.rds.amazonaws.com`

### Phase 0 DONE / NOT DONE Table

Current config of the old `app-atento-001/` stack. The old stack is NOT edited (Phase 0 dropped) — this table is the source-of-truth the NEW `atento-001/` stack replicates in parameterized form when authored from the shared template at Phase 1. "NOT DONE" here means "hardcoded in the old stack; the new stack parameterizes it."

| Item | Status | File:line |
|---|---|---|
| Module rename `networking_data` → `vpc_data` (call-site) | DONE | `connection_pooler.tf:63`, `compute.tf:307,403,404` |
| DNS decoupling in `dns/alb_data.tf` | DONE (ALB name update still needed at Phase 5 cutover) | `dns/alb_data.tf:1-4` uses `data "aws_lb"` |
| Connection pooler | DONE (ahead of plan) | `connection_pooler.tf:58-131`; `identifier = "atento-001"` at line 61 |
| `local.env = "app-atento-001"` (hardcoded string) | NOT DONE | `compute.tf:26` |
| `lambda_cluster_name = "app-atento-001-cluster"` | NOT DONE | `compute.tf:319` |
| `lambda_tags.Environment = "app-atento-001"` | NOT DONE | `compute.tf:321-323` |
| `policy_name_prefix = "app-atento-001"` | NOT DONE | `compute.tf:843` |
| Scheduler role ARN suffix `"app-atento-001-ecs-scheduler-role"` | NOT DONE | `compute.tf:952` |
| Service capacity_provider map keys `"app-atento-001-*-service"` | NOT DONE | `compute.tf:291-299` |
| `name_prefix = "app-atento-001"` in `module "public_alb"` | NOT DONE | `compute.tf:429` |
| `networking_environment = "app-atento-001"` in `rds.tf` | NOT DONE | `rds.tf:7` |
| `cluster_name = "app-${var.environment}-cluster"` in `monitoring.tf` (`app-` prefix hardcoded) | NOT DONE | `monitoring.tf:16` |
| `web_service_name = "app-${var.environment}-web-service"` in `monitoring.tf` (`app-` prefix hardcoded) | NOT DONE | `monitoring.tf:19` |
| `variable "networking_environment"` added to `variables.tf` | NOT DONE | `variables.tf` (absent) |
| `variable "manage_iam"` added | NOT DONE | `variables.tf` (absent); `compute.tf:417` hardcodes `true` |
| `variable "lambda_scheduler_state"` added | NOT DONE | `variables.tf` (absent) |
| `variable "services"` added | NOT DONE | `variables.tf` (absent) |
| `output "alb_dns_name"` added | NOT DONE | `output.tf` (absent) |

---

## Chosen Approach

**Direction:** Option C — `atento-001/` calls `module "ecs_cluster"` directly (no `module "app"`, no second pooler); pooler stays in `app-atento-001/` state throughout the parallel build and cutover window; converges into `module "app"` via in-place `moved{}` blocks at Phase 7c, mirroring `app-shared-001/main.tf:125-133`.

**Rationale (from engineer):** Option C eliminates live-pooler state surgery from the most dangerous phase of the migration (parallel build + traffic cutover). The pooler runs entirely untouched — no cross-state surgery before the build, no SG access gap during the window. The Phase 7 convergence uses the same proven same-state `moved{}` pattern that shared-001 used. The full stack (compute + durables + pooler) ends in a single `app-atento-001/` state file under `module "app"`, identical to the shared-001 end state, which is the correct convergence per the proven single-stack reclaim precedent.

**Source patterns referenced:**
- `app-shared-001/main.tf:125-133` — canonical intra-state `moved{}` blocks (Phase 7c convergence pattern)
- `app-shared-001/main.tf:67-123` — full `module "app"` call (identifier, environment, vpc_id, subnet_ids, tags, cluster parameters, pooler databases list, CNAME, image)
- `app-atento-001/connection_pooler.tf:76` — `extra_ingress_cidrs = ["10.12.0.0/26"]` (cross-region outbound VPC CIDR; carry into `atento-001/` cluster config)
- `app-atento-001/connection_pooler.tf:104` — live CNAME `connection-pooler-atento-001.4shark.internal` (must NOT be duplicated by any second pooler)
- `git show 32c5cec -- shared-001/providers.tf` — deleted parallel dir backend key: `key = "shared-001/terraform.tfstate"` (parallel directory always used its own S3 object)
- `git show 32c5cec -- app-shared-001/terraform.tfvars` — `web_min_size = 0` comment: "all min=0 during parallel migration to avoid paying for idle EC2 instances. Scaled up per service during cutover."

---

## Execution Phases

### State Surgery Mechanism (Applies to Phases 2, 3, and 7a)

Each ownership-transfer phase follows an identical four-step pattern. The surgery is manual and NOT recorded in git:

1. Git commit the code changes (NO apply yet)
2. Manual cross-state surgery: for each resource being transferred, run:
   `terraform state mv -state-out=<dest>/terraform.tfstate 'source.address' 'dest.address'`
   Enumerate every address from `terraform state list` before and after each move.
3. `terraform apply` in the source stack → plan MUST show zero changes (0 to add, 0 to change, 0 to destroy)
4. `terraform apply` in the destination stack → plan MUST show zero changes

Any non-zero plan in steps 3 or 4 means the state surgery missed a resource. **Do NOT continue until both plans are clean.**

---

### Phase 0 — DROPPED

Parameterizing the old `app-atento-001/` stack in place has no precedent (shared-001 commit `0c5354c` created only `shared-001/*`, never touching `app-shared-001/`) and no purpose (the parallel directory is authored parameterized from scratch; with `var.environment = "atento-001"` an in-place edit would force a cluster rename). The parameterization now lives entirely inside Phase 1 — the new `atento-001/` stack is authored parameterized from the `app-shared-001/` template, replicating the old stack's config (the hardcode table above) in `var.environment`-driven form. The old stack is left untouched until Phase 6.

---

### Phase 1 — Create `atento-001/` Parallel Directory (Compute-Only)

**Objective:** Author a new `atento-001/` Terraform directory as a compute-only stack using `app-shared-001/` as the template. Holds its own backend state file. All ECS services start at `min_size = 0` to avoid paying for idle EC2 during the migration window. Per Option C, this directory does NOT contain `module "app"` — it calls `module "ecs_cluster"` directly.

**Proven precedent:** `git show 32c5cec -- shared-001/providers.tf` — deleted parallel dir had its own state key; `git show 32c5cec -- app-shared-001/terraform.tfvars` — `web_min_size = 0` comment during parallel window.

**Key configuration decisions for `atento-001/`:**

| Parameter | Value | Source |
|---|---|---|
| Backend state key | `atento-001/terraform.tfstate` | Mirrors deleted `shared-001/providers.tf` key |
| Module call | `module "ecs_cluster"` directly | Option C (locked) |
| `identifier` / `local.env` | `"atento-001"` | Resources created as `atento-001-*` |
| All service `min_size` | `0` | shared-001 precedent |
| `extra_ingress_cidrs` | `["10.12.0.0/26"]` | `app-atento-001/connection_pooler.tf:76` — cross-region outbound VPC CIDR |
| Durables | `data` sources only (NOT `resource`) | Ownership stays in `app-atento-001/` until Phase 3 |
| Pooler | NOT CREATED | Option C — no second pooler; old pooler stays in `app-atento-001/` state |

**ECS services to include (all 9):**
`web`, `worker-system`, `worker-user`, `worker-commission`, `worker-commission-tiger-shark`, `worker-commission-white-shark`, `worker-cleansing`, `worker-migration`, `runner`

**Steps:**
1. Create `terraform/atento-001/` directory with backend config (`key = "atento-001/terraform.tfstate"`)
2. Author all config files from `app-shared-001/` template; carry over atento-specific values (all 9 services, `extra_ingress_cidrs`, OpenSearch references, monitoring.tf with parameterized names)
3. `terraform plan` on `atento-001/` — verify: cluster and services show as creates; NO `module.connection_pooler` in plan; durables appear as data sources only
4. `terraform apply` on `atento-001/` — `atento-001-cluster` created; all 9 services at `min_size = 0`; pooler stays in `app-atento-001/` state, untouched

**Dependencies:** None — first executable phase. Pre-condition: `app-atento-001/` baseline `terraform plan` = 0/0/0 (verified 2026-07-06).

**Success criteria:**
- [ ] `atento-001-cluster` exists in AWS (9 services, all `atento-001-*` prefix)
- [ ] `terraform plan` on `atento-001/` = 0/0/0 after apply (no `module.connection_pooler` present)
- [ ] `terraform plan` on `app-atento-001/` = 0/0/0 (old stack undisturbed)
- [ ] All new services at `min_size = 0` (no EC2 charges yet)

---

### Phase 2 — Transfer ECR + SSM Secrets Ownership

**Objective:** Move ownership of ECR repositories and SSM parameters from `app-atento-001/` state to `atento-001/` state via code-only redefinition + manual cross-state `terraform state mv`. No AWS resources are created or destroyed — only state addresses change.

**Proven precedent:** `git show 0f8bb6f` — ECR + SSM transfer for shared-001.

**Code changes:**

`app-atento-001/main.tf` — remove `module "ecr"` block (ownership dropped); add `data "aws_ecr_repository"` reference if ARN is still needed:
```hcl
# REMOVE from app-atento-001/main.tf:
module "ecr" {
  source       = "../modules/ecr"
  repositories = local.ecr_repositories
  tags         = local.tags
}
```

`atento-001/main.tf` — change from `data "aws_ecr_repository"` to `module "ecr"` (ownership assumed):
```hcl
# ADD to atento-001/main.tf — resource replaces data source:
module "ecr" {
  source       = "../modules/ecr"
  repositories = local.ecr_repositories
  tags         = local.tags
}
```

`app-atento-001/ssm.tf` — change `resource` → `data` for each SSM parameter; remove the ECS SSM read IAM policy (moves to `atento-001/ssm.tf`).

`atento-001/ssm.tf` (new file) — `resource` blocks with `lifecycle { ignore_changes = [value] }`:
```hcl
resource "aws_ssm_parameter" "some_param" {
  name  = "/atento-001/..."
  type  = "SecureString"
  value = "placeholder"
  lifecycle {
    ignore_changes = [value]
  }
}
resource "aws_iam_role_policy" "ecs_ssm_read" { ... }
```

**Apply sequence:** follows the State Surgery Mechanism — commit → surgery (`app-atento-001/` → `atento-001/`) → verify 0/0/0 in both stacks.

**Dependencies:** Phase 1 complete and `atento-001/` plan is 0/0/0.

**Success criteria:**
- [ ] `terraform plan` on `app-atento-001/` = 0/0/0 after surgery + apply (ECR and SSM now data sources)
- [ ] `terraform plan` on `atento-001/` = 0/0/0 after surgery + apply (ECR and SSM now resource owners)

---

### Phase 3 — Transfer Durable Resource Ownership (SPLIT into sub-PRs)

**Why split (decided 2026-07-06):** atento's durable layer is larger than shared's single `f118eaa` move — it additionally has `module.backup` (cross-region RDS backup), `module.cloudwatch_monitoring` (opensearch/rds alarms), dedicated data-tier SGs (`aws_security_group.opensearch`, `aws_security_group.rds_app_atento_001`), the RDS log group (`aws_cloudwatch_log_group.rds_postgresql`), and a split redis (`redis_cloud_cache` + `redis_cloud_sidekiq`). The shared-001 migration itself split these across separate commits (`f118eaa` durables, `a9614ef` opensearch, `6970efb` monitoring). One giant state surgery moving ~50 resources at once is far riskier than several small, individually-verified moves. Each sub-PR = its own `git mv` + state surgery + `0/0/0` gate on both stacks, following the proven State Surgery Mechanism (§ above) and the Phase-2 recipe (§ Execution progress).

**Common rule for every sub-phase:** `git mv` the file(s) `app-atento-001/` → `atento-001/`; fix references in the OLD stack (durable output refs → `data` source or removed); keep resource names UNCHANGED (RDS `cluster_identifier = "app-atento-001-cluster"`, OpenSearch `domain_name = "app-atento-001"` — both stay, renamed only at Phase 7d / never); cross-state `state mv` old→new; verify `plan` 0/0/0 on BOTH stacks; commit → PR → apply-gate.

- **Phase 3a — Core durables (rds, mongodb, redis cache+sidekiq, s3).** Pattern `f118eaa`. `git mv` `rds.tf`, `mongodb.tf`, `redis.tf`, `s3.tf`. Move `module.rds_aurora_cluster` (cluster + 2 instances + `aws_cloudwatch_log_group.rds_postgresql` + `aws_security_group.rds_app_atento_001`), `module.mongodb_atlas` (project/cluster/users/ip-access/backup-schedule), `module.redis_cloud_cache`, `module.redis_cloud_sidekiq`, `module.s3_bucket` (+ all sub-resources). MongoDB Atlas cluster already named `atento-001` — no rename. RDS `cluster_identifier` stays `app-atento-001-cluster`.
- **Phase 3b — OpenSearch.** Pattern `a9614ef`. `git mv` `opensearch.tf`. Move `module.opensearch` (domain + ssm master params + random) + `aws_security_group.opensearch`. Domain name `app-atento-001` immutable — stays. In the NEW stack, switch the `module.task_config` `opensearch_host` input from `data.aws_opensearch_domain.this.endpoint` (Phase-1 data source) to `module.opensearch.domain_endpoint` and remove the data source.
- **Phase 3c — CloudWatch monitoring.** Pattern `6970efb`. Move `module.cloudwatch_monitoring` (opensearch/rds alarms) — verify whether it references durable outputs now in the new stack (it must live where its referenced durables are). Confirm scope against `6970efb` before executing.
- **Phase 3d — Backup.** Move `module.backup` (cross-region RDS backup: vaults, plan, selection, KMS, alarms). No shared commit reference (shared may not have had it at that time) — study whether it moves with RDS (3a) or standalone; confirm before executing.
- **Phase 3e — IAM deploy user + deploy policy + github_deploy.** Move `aws_iam_user.deploy`, `aws_iam_policy.deploy_s3_access` (references `module.s3_bucket.bucket_arn` — needs 3a done first), `aws_iam_user_policy_attachment.deploy_s3_access`, `module.deploy_key` (+ `git mv github_deploy.tf`). OLD stack: `resource aws_iam_user.deploy` → `data.aws_iam_user.deploy` (pattern `f118eaa` main.tf); old `module.iam_deploy` then references the data source. Depends on 3a (s3 in new stack) + Phase 2 (SSM in new stack, already done).

**Sub-phase ordering:** 3a → 3b → 3c → 3d → 3e (3e last: depends on s3 from 3a). Each is engineer-gated at its apply.

**Success criteria (per sub-phase):**
- [ ] `git mv` done; OLD-stack references updated to data/removed
- [ ] cross-state `state mv` complete; raw-grep verified in the working JSON
- [ ] `terraform plan` on BOTH stacks = 0/0/0 after surgery
- [ ] resource names unchanged (RDS/OpenSearch keep `app-atento-001-*`)

---

### Phase 4 — Prepare New Cluster for Traffic — DONE ✅ (PR #635, merged)

**What it did (final scope):** set the 7 scheduled tasks to `state = "DISABLED"` and raised the per-service capacity floors to the old-atento baseline. Two planned steps were dropped/deferred, and one blocking dependency was discovered — all recorded under § Execution progress → Phase 4. Summary:

- **SG whitelist (was steps 1-2): DROPPED as MOOT.** Data-tier ingress is CIDR-based over the shared VPC (RDS/OpenSearch) or Redis Cloud SaaS; the same-VPC new cluster already has connectivity. Pooler CNAME resolution was already a non-issue (same VPC, existing zone association).
- **Monitoring re-target (was step 3): DEFERRED to Phase 5.** `module.cloudwatch_monitoring` is singular — re-targeting it before cutover would blind the still-live old cluster. It flips old→new atomically at cutover.
- **Scale-up (steps 4/6): DONE via two knobs.** `min_size`/`max_size` in tfvars (ASG capacity, applied by terraform) + `aws ecs update-service --desired-count` at runtime (service task count — terraform holds `desired_count` in `ignore_changes`, so it is set operationally, per Lessons Learned Incident 1).
- **Task-run validation (steps 5/7): NOT possible in Phase 4 — moved to Phase 5.** The new cluster's task defs are terraform bootstraps with `command = []`; the Sidekiq command is injected only by the app deploy pipeline (see the Phase-5 deploy step). Without a deploy, tasks exit 1. `desired_count` was set to baseline during validation, crash-looped, and was reverted to 0; the min_size EC2 capacity stays up for the Phase-5 deploy.

---

### Phase 5 — Deploy to New Cluster, then Cut Over Traffic — NEXT

**Objective:** Make the new cluster functional by deploying the app to it (registering real task defs with the Sidekiq commands), validate it under real running tasks, then flip DNS from the old `app-atento-001` ALB to the new `atento-001` ALB. After this phase, production traffic and the app deploy pipeline both target the new cluster; the old cluster receives no traffic and no deploys.

**Why deploy-first (the Phase-4 finding):** terraform only creates bootstrap task defs (`command = []`); the real command (`bundle exec sidekiq -C config/sidekiq_<queue>.yml` per worker, plus the current image) is registered by the `app` repo's `deploy-atento-001.yaml`, which lives in the service's `ignore_changes = [task_definition]`. That workflow currently hardcodes `CLUSTER_NAME: app-atento-001-cluster` and `*_SERVICE_NAME: app-atento-001-*` (env block, lines ~66-75) and builds the Sidekiq task defs from its `SIDEKIQ_SERVICES` matrix. The new cluster has never been deployed to, so it cannot run tasks until this workflow is retargeted and run.

**Deploy/traffic coupling:** retargeting `deploy-atento-001.yaml` to `atento-001-*` means the OLD cluster stops receiving deploys. Since the old cluster serves all traffic until the DNS flip, the deploy-to-new and the DNS flip must be close together, with an app **deploy freeze** across the window (no app PRs merged/deployed between the retarget and the flip) — otherwise a hotfix in the window lands on a cluster that is not (yet / any longer) serving traffic.

**Steps:**
1. **Retarget the deploy workflow** (`app` repo PR): in `deploy-atento-001.yaml`, change the `CLUSTER_NAME` + every `*_SERVICE_NAME` env var from `app-atento-001-*` to `atento-001-*`. This is the single source of the cluster/service targeting. Confirm the `SIDEKIQ_SERVICES` matrix (`configuration_file` per worker) still matches the new service names.
2. **Announce a deploy freeze** for the atento app across the cutover window.
3. **Set `desired_count` to baseline** on the new services (`aws ecs update-service`: web 4, the 5 active workers 1 each) — capacity is already up from Phase 4.
4. **Run the retargeted deploy** → registers real task defs (with commands), CodeDeploy blue/green for web, rolling for workers. Validate: all services reach `runningCount = desiredCount`; app ECS tasks reach the pooler CNAME `connection-pooler-atento-001.4shark.internal`; smoke test (web request, login, basic API) on the new ALB directly.
5. **Re-target monitoring** (`atento-001/monitoring.tf`): change the ECS/service/lambda inputs from `app-${var.environment}` to `${var.environment}` (RDS/OpenSearch inputs STAY `app-atento-001-*` — Aurora rename is 7d, OS domain immutable). Apply `atento-001/`. Confirm alarms for the new cluster are not in ALARM.
6. **Flip DNS:** update `dns/alb_data.tf:4` `name = "app-atento-001-lb"` → the new ALB name (`atento-001` `name_prefix`), plan `dns/` (confirm CNAME retargets), apply `dns/` → Route53 points at the new ALB. Rollback path is a fast Route53 revert.
7. **Enable the new cluster's schedules + disable the old:** set the new `atento-001/scheduled-tasks.tf` `module.scheduled_task` back to `state = "ENABLED"` (remove the Phase-4 `DISABLED` line) and set the OLD `app-atento-001/` schedules to DISABLED, so crons run on exactly one cluster. Apply both.

**Dependencies:** Phase 4 complete (capacity up, crons contained); app-repo access to edit `deploy-atento-001.yaml`.

**Success criteria:**
- [ ] `deploy-atento-001.yaml` targets `atento-001-cluster` / `atento-001-*` services
- [ ] Retargeted deploy ran; all new services `runningCount = desiredCount` at baseline with real task defs (command present)
- [ ] Smoke test passing on the new cluster; pooler reachable
- [ ] `atento-001/` monitoring re-targeted to the new cluster; alarms not in ALARM
- [ ] Route53 resolves to the new `atento-001` ALB; zero errors attributable to the flip
- [ ] New cluster schedules ENABLED, old cluster schedules DISABLED (crons on one cluster only)

---

### Phase 6 — Destroy Old Compute from `app-atento-001/`

**Objective:** Remove the ECS cluster, ASGs, capacity providers, task definitions, services, and ALB from `app-atento-001/`. The pooler (`module.connection_pooler`) is explicitly NOT destroyed — it stays in `app-atento-001/` state and continues serving.

**Proven precedent:** `git show 5da46b2 --stat` and `git show 5da46b2 -- app-shared-001/main.tf`

Commit `5da46b2` deleted these files from `app-shared-001/` (equivalent action for `app-atento-001/`):
```
compute.tf   (1023 deletions)
output.tf    (14 deletions)
ssm.tf       (32 deletions)
vpc_data.tf  (4 deletions)
```
And stripped `app-shared-001/main.tf` to a minimal locals block. After the equivalent for atento, `app-atento-001/main.tf` retains only:
```hcl
locals {
  environment = var.environment
  tags = {
    Environment = "atento-001"
    Automation  = "terraform"
  }
}
```

**What remains in `app-atento-001/` state after Phase 6:**
- `module.connection_pooler` and all its associated resources (Secrets Manager secrets, the pooler ECS service in the separate `atento-001-connection-pooler` cluster)
- `providers.tf`, `variables.tf`, `terraform.tfvars` (stack config files)
- Durables are in `atento-001/` state (migrated at Phases 2–3), NOT here

**Safety check:** `terraform apply` in `app-atento-001/` → destroys old ECS cluster. Verify the plan shows ONLY compute resources being destroyed, NOT the pooler. If `module.connection_pooler` appears in the destroy plan, STOP — investigate before applying.

**Dependencies:** Phase 5 complete; traffic fully on new cluster; rollback window closed.

**Success criteria:**
- [ ] `app-atento-001-cluster` no longer exists in AWS
- [ ] Old ALB `app-atento-001-lb` destroyed; `dns/alb_data.tf` already points to new ALB (from Phase 5)
- [ ] `module.connection_pooler` intact and serving (`atento-001-connection-pooler` cluster still LIVE)
- [ ] `terraform plan` on `app-atento-001/` = 0/0/0 after destroy (pooler and stack config only)

---

### Phase 7 — Reclaim `app-atento-001/` Slot + `module.app` Convergence

**Objective:** The culminating phase. All resources converge into a single `app-atento-001/` state file under the canonical `module.app` structure, and the `atento-001/` directory is destroyed. This mirrors how shared-001 ended after its migration (commit `32c5cec`).

**7d (Aurora rename) DROPPED — the Aurora keeps the `app-` prefix.** Ground truth: `app-shared-001/rds.tf:85` and `app-demo-001/rds.tf:49` both keep `cluster_identifier = "app-<env>-cluster"` — the other app stacks did NOT rename their Aurora in their migrations. `atento-001/rds.tf:51` is already `cluster_identifier = "app-atento-001-cluster"`, consistent with the convention. Renaming a live Aurora forces an endpoint DNS change + mandatory pooler restart for zero convention benefit. The Aurora stays `app-atento-001-cluster`. This removes the only planned downtime from the entire migration — Phase 7 is now fully no-downtime state/file surgery.

**One PR (engineer decision):** 7a/7b/7c ship in a single PR (`feature/atento-001-phase7-reclaim`), mirroring the shared reclaim which was one commit (`32c5cec`). For atento the three are not cleanly separable anyway — moving the pooler into the cluster's stack requires rewiring the pooler's references from `remote_state` → direct `module.*`, which IS the `module.app` convergence. The config change is committed together; the live state surgery (7a state mv + 7b S3 copy) runs at the apply flow; the 7c `moved{}` plan is the hard gate (must be 0/0/0).

**Option C specifics at this phase:**
- `atento-001/` state contains: ECS cluster (`module.ecs_cluster`), ECR, SSM, IAM, MongoDB, Redis, S3, OpenSearch, RDS
- `app-atento-001/` state contains: `module.connection_pooler` only
- The `moved{}` blocks in Phase 7c require BOTH `module.ecs_cluster` AND `module.connection_pooler` to be in the SAME state file — Phase 7a migrates the pooler first

---

#### Phase 7a — Migrate Pooler Ownership to `atento-001/` State

**Objective:** Transfer `module.connection_pooler` from `app-atento-001/` state to `atento-001/` state. After this sub-step, `atento-001/terraform.tfstate` is the single source of truth for ALL resources. `app-atento-001/` state is empty (or contains only provider-level metadata).

**Placement decision (resolved):** Phase 7a is a sub-step within Phase 7 (grouped reclaim flow), not a standalone Phase 6b. All reclaim work is grouped together after destroy.

**Steps:**
1. `git mv app-atento-001/connection_pooler.tf atento-001/connection_pooler.tf` — physical file move; the block remains `resource "module" "connection_pooler"` (no redefinition needed; `atento-001/` assumes ownership of resources previously in `app-atento-001/` state)
2. Remove any remaining pooler references from `app-atento-001/main.tf` if any exist
3. Manual state surgery (NOT in git): for each resource under `module.connection_pooler.*` in `app-atento-001/` state, run:
   `terraform state mv -state-out=../atento-001/terraform.tfstate 'module.connection_pooler.X' 'module.connection_pooler.X'`
4. Verify: `terraform apply` in `app-atento-001/` → zero changes (state empty or only locals); `terraform apply` in `atento-001/` → zero changes (pooler already in state, no delta)

**Pooler resources to migrate (enumerate from `terraform state list`):**
- `aws_secretsmanager_secret.connection_pooler_userlist` (`connection_pooler.tf:7`)
- `aws_secretsmanager_secret.connection_pooler_datadog_stats_password` (`connection_pooler.tf:24`)
- `aws_secretsmanager_secret.connection_pooler_datadog_api_key` (`connection_pooler.tf:41`)
- `module.connection_pooler.*` (all resources under the module)
- `aws_route53_zone_association.connection_pooler_outbound_cloud_map` (`connection_pooler.tf:119`)
- `aws_route53_zone_association.internal` (`connection_pooler.tf:128`)

**Dependencies:** Phase 6 complete (old cluster destroyed).

**Success criteria:**
- [ ] `terraform plan` on `app-atento-001/` = 0/0/0 after surgery + apply (state empty)
- [ ] `terraform plan` on `atento-001/` = 0/0/0 after surgery + apply (pooler in state, no delta)

---

#### Phase 7b — Physical File Moves + S3 State Copy

**Objective:** Move all Terraform source files from `atento-001/` into `app-atento-001/` via git renames. Delete all root-level files from `atento-001/`. Copy the S3 state object so that `app-atento-001/terraform.tfstate` holds the complete merged state.

**Proven precedent:** `git show 32c5cec --stat` — file-move pattern for shared-001:
```
{shared-001 => app-shared-001}/compute.tf
{shared-001 => app-shared-001}/mongodb.tf
{shared-001 => app-shared-001}/opensearch.tf
{shared-001 => app-shared-001}/rds.tf
{shared-001 => app-shared-001}/redis.tf
{shared-001 => app-shared-001}/s3.tf
{shared-001 => app-shared-001}/ssm.tf
{shared-001 => app-shared-001}/output.tf
shared-001/main.tf                  (deleted)
shared-001/providers.tf             (deleted)
shared-001/terraform.tfvars         (deleted)
shared-001/variables.tf             (deleted)
shared-001/.terraform.lock.hcl     (deleted)
```
Equivalent for atento: `{atento-001 => app-atento-001}/compute.tf`, etc.

**S3 state copy (manual, NOT in git):**
```
COPY:  4shark-terraform-state/atento-001/terraform.tfstate
    →  4shark-terraform-state/app-atento-001/terraform.tfstate
```

**Direction confirmed:**
- Source: `git show 32c5cec -- shared-001/providers.tf` — `key = "shared-001/terraform.tfstate"` (deleted parallel dir key)
- Destination: `app-shared-001/providers.tf:30` (current) — `key = "app-shared-001/terraform.tfstate"`

Back up both state files before copying. Confirm `app-atento-001/providers.tf` backend key is already `"app-atento-001/terraform.tfstate"` before the copy; update if not.

**Dependencies:** Phase 7a complete (both stacks at 0/0/0; `atento-001/` owns all resources).

**Success criteria:**
- [ ] All `atento-001/` source files moved to `app-atento-001/` via `git mv`
- [ ] All root-level Terraform files in `atento-001/` deleted (directory vacated)
- [ ] S3 state copied in correct direction: `atento-001/` → `app-atento-001/`
- [ ] `app-atento-001/providers.tf` backend key confirmed as `"app-atento-001/terraform.tfstate"`

---

#### Phase 7c — Introduce `module "app"` + `moved{}` Blocks

**Objective:** Replace standalone `module "ecs_cluster"` + `module "connection_pooler"` in the new `app-atento-001/main.tf` with a single `module "app"` call. Add `moved{}` blocks to update state addresses in-place without recreating any resource. Gate: `terraform plan` MUST show 0/0/0 before apply.

**Source pattern — `app-shared-001/main.tf:125-133`:**
```hcl
moved {
  from = module.ecs_cluster
  to   = module.app.module.ecs_cluster
}

moved {
  from = module.connection_pooler
  to   = module.app.module.connection_pooler
}
```

These are INTRA-STATE moves only. After Phase 7a, both `module.ecs_cluster` (from `atento-001/`, now in `app-atento-001/` state via the S3 copy) and `module.connection_pooler` (also migrated at 7a into the same state) reside in `app-atento-001/terraform.tfstate`. The `moved{}` blocks translate the old state addresses to the new `module.app.*` addresses.

**`module "app"` configuration reference:** `app-shared-001/main.tf:67-123` — the full `module "app"` call. For atento: `identifier = "atento-001"` and the pooler databases list comes from `app-atento-001/connection_pooler.tf:83-100` (writer: `atento001_master`, reader: `atento001_follower`).

**Arg-parity verified (all confirmed zero-change) — the `module "app"` call must reproduce atento's current standalone pooler config exactly:**
- `app_security_group_id`: standalone reads `data.terraform_remote_state.atento_001.outputs.cluster_security_group_id`; inside `module.app` it becomes `module.ecs_cluster.security_group_id` — same SG (`sg-0659e817466472932`), identical value.
- `extra_ingress_cidrs = ["10.12.0.0/26"]`: atento MUST pass this (the sa-east-1 outbound worker reaches the pooler by CIDR). **Deviation from shared** — `app-shared-001/main.tf` does NOT pass `extra_ingress_cidrs`. Omitting it on atento would change the pooler ingress rule.
- `max_client_conn`: default 4000 in both `modules/app/variables.tf` and `modules/connection_pooler/variables.tf` — standalone doesn't pass it, `module.app` passes its default 4000; identical.
- Pooler secrets (userlist, datadog stats password, datadog api key) + `aws_route53_zone_association.internal` + `aws_route53_zone_association.connection_pooler_outbound_cloud_map` stay STANDALONE in `app-atento-001/connection_pooler.tf` (shared shape at `app-shared-001/connection_pooler.tf`); the outbound association repoints to `module.app.pooler_cloud_map_hosted_zone_id`. These are already in `app-atento-001/` state — no state move for them.

**Gate:** `terraform apply` at this step MUST show a zero-change plan (only address renames in state; no resource creation or destruction). If the plan shows any resource changes, STOP and diagnose before applying.

**Dependencies:** Phase 7b complete (S3 state copied; all files in `app-atento-001/`).

**Success criteria:**
- [ ] `terraform plan` on `app-atento-001/` = 0/0/0 after `moved{}` blocks (gate — do NOT apply if non-zero)
- [ ] `app-atento-001/` state owns both `module.app.module.ecs_cluster` and `module.app.module.connection_pooler`
- [ ] `atento-001/` directory is empty (vacated in Phase 7b)

---

#### Phase 7d — Aurora Cluster Rename — DROPPED

**Not performed.** Ground truth from the other app stacks shows the Aurora deliberately keeps the `app-` prefix:
- `app-shared-001/rds.tf:85` — `cluster_identifier = "app-shared-001-cluster"`
- `app-demo-001/rds.tf:49` — `cluster_identifier = "app-demo-001-cluster"`
- `atento-001/rds.tf:51` — `cluster_identifier = "app-atento-001-cluster"` (already consistent)

The convention canonicalizes compute / cluster / ALB / services but leaves the Aurora identifier prefixed, because renaming a live Aurora forces an endpoint DNS change + mandatory pooler restart for zero convention benefit. Atento's Aurora is already aligned with shared/demo. No rename action exists or is needed. Dropping 7d removes the only planned downtime from the entire migration.

---

## Technical Decisions

| Decision | Choice | Rationale (from engineer / from draft) |
|----------|--------|----------------------------------------|
| Pooler strategy during parallel window | **Option C** — `atento-001/` uses `module "ecs_cluster"` directly; no second pooler; pooler stays in `app-atento-001/` state through Phase 6; converges via intra-state `moved{}` at Phase 7c mirroring `app-shared-001/main.tf:125-133` | Eliminates live-pooler state surgery from the most dangerous migration phase; pooler runs entirely untouched during build and cutover; follow-up convergence uses the proven same-state moved-block pattern |
| Aurora rename | **DROPPED — no rename** | The other app stacks keep `cluster_identifier = "app-<env>-cluster"` (`app-shared-001/rds.tf:85`, `app-demo-001/rds.tf:49`); atento's Aurora is already `app-atento-001-cluster`, consistent. Renaming forces an endpoint DNS change + pooler restart for zero benefit. Removes the only planned downtime |
| New parallel stack template | **`app-shared-001/`** | Services-map-driven, proven pattern; already correctly parameterized |
| Phase 7a placement | **Sub-step 7a within Phase 7** (grouped reclaim flow, not a standalone Phase 6b) | Operational preference: all reclaim work grouped together after destroy; engineer chose grouped flow |
| MongoDB Atlas cluster name | **MOOT — no rename at any phase**; Atlas cluster already named `atento-001` (`cluster_name = "atento-001"`, `project_name = "App Atento001"` in `app-atento-001/mongodb.tf`); `mongodb.tf` migrates ownership at Phase 3 only | Atlas cluster name was already correctly set; no rename action exists or is needed |
| Datadog/monitoring timing | **Phase 4 (before cutover)** — `monitoring.tf` is terraform-managed and must target new `atento-001-*` names before Phase 5 DNS flip | `monitoring.tf:16` (`cluster_name`) and `monitoring.tf:19` (`web_service_name`) both reference the cluster; monitoring must be active on the new cluster before traffic arrives; `app-` prefix parameterized at Phase 0 |
| Pooler CNAME DNS resolution from new cluster | **Non-issue — no second zone association needed**; `atento-001/` uses `networking_environment = "app-atento-001"` (`rds.tf:7`) → same physical dedicated VPC (`vpc-030497c296befc066`); pooler's `aws_route53_zone_association.internal` (`connection_pooler.tf:128`) already associates that VPC with the internal zone | Resolved fact; no infrastructure action required at Phase 4 validation |
| `github_deploy.tf` placement | **Moves at Phase 3** alongside the IAM deploy user | `github_deploy.tf:8-19` references `aws_iam_user.deploy.name` and `aws_ssm_parameter.secrets["AWS_SECRET_ACCESS_KEY"]`; coupled to IAM (Phase 3) and SSM (Phase 2); cannot remain in `app-atento-001/` once IAM user moves |
| Phase 0 (parameterize old stack in place) | **DROPPED** — no precedent, no purpose | shared-001 `0c5354c` created only `shared-001/*`, never touched `app-shared-001/`; parameterization happens in the new stack (Phase 1); an in-place edit with `var.environment = "atento-001"` would force a cluster rename |

---

## Options Considered and Rejected

- **Option A (live-pooler state surgery before parallel build):** ~30+ pooler resources must be enumerated by exact Terraform address and moved cross-state before any new cluster exists; one wrong address maps to a destroy of a live production pooler resource on the next apply; the SG coupling at `connection_pooler.tf:65` creates an access gap window between new-stack apply and traffic drain. Rejected as high-risk on the live pooler during the most dangerous migration phase.

- **Option B (two simultaneous poolers):** Both the existing `app-atento-001/` pooler and a new `module "app"` pooler would claim CNAME `connection-pooler-atento-001.4shark.internal` (`connection_pooler.tf:104`) — Route53 conflict; app connection failures. Not viable.

- **Compute-only split (the prior PLAN.md):** The previous 6-phase plan moved only compute to the new stack and left durables (RDS, Redis, MongoDB, S3, OpenSearch, IAM user) in `app-atento-001/` permanently. This diverges from the proven single-stack reclaim precedent (shared-001 commit `32c5cec`) where ALL resources end in the `app-shared-001/` directory. A permanent durable split creates an indefinitely bifurcated state that can never be reclaimed. Rejected in favor of the full 7-phase migration.

- **In-place `moved{}` blocks from the start (no parallel directory):** ECS cluster name is a `ForceNew` attribute in AWS; Terraform cannot rename it in-place — destroy + create is required. The same-state `moved{}` approach used for shared-001 only worked because the AWS ECS cluster name did NOT change there. Not applicable to atento where the cluster must change from `app-atento-001-cluster` to `atento-001-cluster`.

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| New cluster SG not whitelisted before cutover | ECS tasks cannot reach RDS/Redis/OpenSearch → database connectivity failure immediately after DNS flip | Phase 4 is a mandatory explicit preparation step; validate task health and pooler reachability before Phase 5 DNS flip |
| State surgery misses a resource (Phases 2, 3, or 7a) | `terraform apply` shows resource recreation or destroy in the wrong stack | `terraform state list` before and after each `state mv`; both plans MUST show 0/0/0 before continuing; never skip the verify step |
| `moved{}` blocks applied before pooler is in same state file | Terraform cannot find `module.connection_pooler` address → apply error | Phase 7a (pooler state migration) must complete with 0/0/0 applies in BOTH stacks before Phase 7b; never skip 7a |
| S3 state copy in wrong direction | `app-atento-001/terraform.tfstate` overwritten with empty state → all resources become unmanaged | Always copy `atento-001/` → `app-atento-001/`; back up both state files before the copy; confirm direction matches `32c5cec` precedent |
| Aurora rename causes RDS endpoint DNS change; pooler not restarted | Pooler cannot connect to RDS after rename → app DB errors | Restart pooler ECS service explicitly after rename; schedule Phase 7d during off-hours; verify Route53 CNAME update before restart |
| OpenSearch domain `app-atento-001` confused as mutable name | Engineers attempt to rename → AWS rejects → plan halts | OpenSearch domain name is IMMUTABLE; only state ownership transfers (Phase 3), not the physical name; documented in Technical Decisions and Out of Scope |
| `dns/alb_data.tf` ALB name not updated at cutover | DNS stack breaks when old ALB is destroyed at Phase 6 | Include `dns/alb_data.tf:4` update in the Phase 5 cutover PR, BEFORE the old ALB destroy in Phase 6; gate: `terraform plan` on `dns/` must resolve to new ALB |
| Pooler CNAME conflict during Phase 1 parallel window | If `module "app"` were accidentally used in `atento-001/`, Route53 CNAME collision | Option C is locked — `atento-001/` calls `module "ecs_cluster"` only, never `module "app"`; enforced in plan review gate at Phase 1 |

---

## Lessons Learned from shared-001 Migration (Feb–April 2026)

These incidents occurred during shared-001's parallel migration. Documented here so atento does not repeat them.

### Incident 1: ECS services left at desired_count=0 post-migration

Worker services (`worker-commission`, `worker-system`, `worker-user`) were created with `desired_count = 0` during the parallel migration and left dead afterward. Autoscaling Lambdas base their decisions on metrics from running tasks — no tasks, no metrics, no scale-up. CloudWatch alarms were in ALARM but treated as "expected during migration." Workers sat dead until an engineer manually intervened with `aws ecs update-service`.

**Why it happened:** `desired_count` is in the `ignore_changes` lifecycle of the ECS service module — initial creation uses the code value; subsequent changes are managed out-of-band. Creating with `desired_count = 0` means autoscaling never kicks in, even after migration is complete.

**How to avoid in atento:** At Phase 4 step 6, explicitly run `aws ecs update-service --cluster atento-001-cluster --service <each service> --desired-count <baseline>` for each of the 9 services immediately after scaling up `min_size`. Validate `runningCount = desiredCount` for every service. Confirm all CloudWatch alarms are NOT in ALARM before proceeding to Phase 5.

### Incident 2: ALB rename blocked by `replace_triggered_by`

During shared-001 alignment, an ALB rename caused the `ecs_service` module's `replace_triggered_by = [terraform_data.lb_config]` to trigger — target group rename → TG replacement → new ARN → `terraform_data.lb_config` replaced → ECS service replaced (destroy + create; no `create_before_destroy`) → 5-15 min downtime across all services.

**Resolution for atento:** ALB final naming is accepted as residual tech debt and is OUT of scope. The new `atento-001/` stack's ALB is authored correctly from the template (no rename needed). The old ALB is simply destroyed at Phase 6. No ECS service replacement is triggered.

---

## Operational Checklist

### Before Phase 1 apply (parallel build)

- Confirm `terraform plan` on `app-atento-001/` = 0/0/0 baseline (Phase 1 pre-condition; verified 2026-07-06)
- Verify `min_size` values in `atento-001/terraform.tfvars` are all `0` (not production values — scale-up happens at Phase 4)
- Verify plan shows ONLY ECS cluster resources creating; NO `module.connection_pooler`; durables appear as data sources only
- Open ECS console for `app-atento-001-cluster` (baseline monitoring reference during parallel window)

### Before Phase 4 apply (SG whitelist + monitoring + scale-up)

- Confirm Phase 3 both stacks at 0/0/0 (durables ownership transferred)
- Get new cluster SG ID from `atento-001/` outputs before editing ingress rules
- Confirm monitoring.tf targets `atento-001-cluster` and `atento-001-web-service` (not `app-atento-001-*`)
- After scale-up: explicitly set `desired_count` to operational baseline for all 9 services (Incident 1 prevention)

### During Phase 5 cutover (DNS flip)

- ECS console open for `atento-001-cluster` — check `runningCount` vs `desiredCount` for all services
- ALB target health: new ALB targets healthy before flipping
- CloudWatch alarms: all `atento-001-*` alarms NOT in ALARM?
- Application logs: any errors after DNS flip?

### Rollback ready (Phase 5)

- Route53 revert ready: flip record back to `app-atento-001` ALB DNS name (no state changes needed, fast)
- Old cluster: keep at operational `desired_count` until Phase 6 explicitly drains it — do NOT set to zero until traffic validation is complete and rollback window is closed

### Before Phase 7a (pooler state surgery)

- Confirm Phase 6 complete: `app-atento-001-cluster` destroyed; pooler still LIVE
- Run `terraform state list` in `app-atento-001/` and enumerate every `module.connection_pooler.*` address before surgery
- Back up both state files before any surgery

### Before Phase 7b (S3 state copy)

- Confirm Phase 7a: both stacks at 0/0/0; `atento-001/` state contains all resources
- Back up both S3 state objects before copying
- Copy direction: `atento-001/terraform.tfstate` → `app-atento-001/terraform.tfstate` (parallel dir is source, slot is destination)

### Before Phase 7c apply (moved{} blocks)

- Gate: `terraform plan` on `app-atento-001/` MUST show 0/0/0 before apply
- If any resource shows as create/change/destroy: STOP and diagnose — do NOT apply

### Post-migration validation (required before declaring done)

- All 9 ECS services: `runningCount = desiredCount` at expected operational baseline
- Zero CloudWatch alarms in ALARM state for `atento-001-*` resources
- Application smoke test passing (web request, login flow, basic API)
- App repo deploy workflow succeeds on an end-to-end test deployment to `atento-001-cluster`
- `terraform plan` on all affected stacks (`app-atento-001/`, `dns/`) = 0/0/0
- `atento-001/` directory no longer exists in the repository

---

## Assumptions

- `app-atento-001/terraform.tfstate` is drift-free (baseline `terraform plan` = 0/0/0, verified 2026-07-06) before Phase 1 begins
- The shared-001 migration commits (`0f8bb6f`, `f118eaa`, `5da46b2`, `32c5cec`) are the authoritative precedent; each phase's surgery pattern is derived directly from those commits
- The physical dedicated VPC for the atento-001 environment is `vpc-030497c296befc066`; both the old and new cluster operate in this VPC, which is already associated with the internal hosted zone via `connection_pooler.tf:128`

---

## Internal References

### Codebase (cited file:line)

- `app-atento-001/compute.tf:26` — `local.env = "app-atento-001"` (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/compute.tf:291-299` — service capacity_provider map keys hardcoded `"app-atento-001-*-service"` (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/compute.tf:319` — `lambda_cluster_name = "app-atento-001-cluster"` (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/compute.tf:321-323` — `lambda_tags.Environment = "app-atento-001"` (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/compute.tf:399-420` — `module "ecs_cluster"`: `environment = local.env` (line 414), `manage_iam = true` (line 417, hardcoded)
- `app-atento-001/compute.tf:429` — `module "public_alb"` `name_prefix = "app-atento-001"` (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/compute.tf:843` — `policy_name_prefix = "app-atento-001"` in `module "iam_deploy"` (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/compute.tf:952` — `"app-atento-001-ecs-scheduler-role"` hardcoded ARN suffix (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/connection_pooler.tf:7` — `aws_secretsmanager_secret.connection_pooler_userlist` (Phase 7a migration)
- `app-atento-001/connection_pooler.tf:24` — `aws_secretsmanager_secret.connection_pooler_datadog_stats_password` (Phase 7a migration)
- `app-atento-001/connection_pooler.tf:41` — `aws_secretsmanager_secret.connection_pooler_datadog_api_key` (Phase 7a migration)
- `app-atento-001/connection_pooler.tf:61` — `identifier = "atento-001"` (DONE)
- `app-atento-001/connection_pooler.tf:65` — `app_security_group_id = module.ecs_cluster.security_group_id` (SG coupling; Phase 7c: new cluster SG replaces old via `module.app`)
- `app-atento-001/connection_pooler.tf:76` — `extra_ingress_cidrs = ["10.12.0.0/26"]` (cross-region outbound VPC CIDR; carry into `atento-001/` cluster config)
- `app-atento-001/connection_pooler.tf:104` — `internal_record_name = "connection-pooler-atento-001.4shark.internal"` (live CNAME; must NOT be duplicated by any second pooler)
- `app-atento-001/connection_pooler.tf:119` — `aws_route53_zone_association.connection_pooler_outbound_cloud_map` (Phase 7a migration)
- `app-atento-001/connection_pooler.tf:128` — `aws_route53_zone_association.internal` (`vpc_id = module.vpc_data.vpc_id`); this association already covers the dedicated VPC (`vpc-030497c296befc066`), making the pooler CNAME resolvable from the new cluster (non-issue at Phase 4)
- `app-atento-001/github_deploy.tf:8-19` — references `aws_iam_user.deploy.name` and `aws_ssm_parameter.secrets["AWS_SECRET_ACCESS_KEY"]`; moves to `atento-001/` at Phase 3
- `app-atento-001/mongodb.tf` — `cluster_name = "atento-001"`, `project_name = "App Atento001"` (already correctly named; moot rename)
- `app-atento-001/monitoring.tf:16` — `cluster_name = "app-${var.environment}-cluster"` (`app-` prefix hardcode; Phase 0 NOT DONE)
- `app-atento-001/monitoring.tf:19` — `web_service_name = "app-${var.environment}-web-service"` (`app-` prefix hardcode; Phase 0 NOT DONE)
- `app-atento-001/rds.tf:7` — `networking_environment = "app-atento-001"` (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/rds.tf:58` — `cluster_identifier = "app-atento-001-cluster"` (immutable until Phase 7d)
- `app-atento-001/variables.tf` — no `networking_environment`, `manage_iam`, `lambda_scheduler_state`, `services` variables (hardcoded in old stack; new stack parameterizes)
- `app-atento-001/output.tf` — no `alb_dns_name` output (hardcoded in old stack; new stack parameterizes)
- `dns/alb_data.tf:1-4` — `data "aws_lb" "atento_001"` with `name = "app-atento-001-lb"`; updated in Phase 5 cutover PR before Phase 6 destroy
- `app-shared-001/main.tf:67-123` — `module "app"` call (identifier, environment, vpc_id, subnet_ids, tags, cluster config, pooler databases list, CNAME, image)
- `app-shared-001/main.tf:125-133` — canonical intra-state `moved{}` blocks: `from = module.ecs_cluster / to = module.app.module.ecs_cluster` and `from = module.connection_pooler / to = module.app.module.connection_pooler`
- `app-shared-001/providers.tf:28-31` — end-state backend key after reclaim: `key = "app-shared-001/terraform.tfstate"`

### Shared-001 precedent commits

- `git show 0f8bb6f` — ECR/SSM ownership transfer: `module "ecr"` removed from `app-shared-001/main.tf`; `resource "aws_ssm_parameter"` → `data "aws_ssm_parameter"` in `app-shared-001/ssm.tf`; new `shared-001/ssm.tf` with `lifecycle { ignore_changes = [value] }`; cross-state surgery performed manually between commit and apply (not recorded in git)
- `git show f118eaa` — durable resources: physical git renames `{app-shared-001 => shared-001}/mongodb.tf,rds.tf,redis.tf,s3.tf`; IAM user changed resource → data in source stack; `cluster_identifier = "app-shared-001-cluster"` kept intact (not renamed during migration)
- `git show 5da46b2 --stat` and `git show 5da46b2 -- app-shared-001/main.tf` — destroy compute: deleted `compute.tf` (1023 lines), `output.tf`, `ssm.tf`, `vpc_data.tf`; stripped `main.tf` to minimal `locals { environment, tags }` block; pooler NOT deleted
- `git show 32c5cec` — reclaim: physical file moves from `shared-001/` → `app-shared-001/`; new consolidated `main.tf` with `module.app`; `terraform.tfvars` restored `web_min_size = 1` (comment: "all min=0 during parallel migration to avoid paying for idle EC2 instances. Scaled up per service during cutover."); deleted all `shared-001/` root-level Terraform files
- `git show 32c5cec -- shared-001/providers.tf` — deleted parallel dir backend key: `key = "shared-001/terraform.tfstate"` (the parallel directory always used its own S3 object)

### AWS inventory files (queried 2026-07-06)

- `/tmp/ecs_clusters_us_east_1.json` — `app-atento-001-cluster` LIVE; `atento-001-connection-pooler` LIVE; no `atento-001-cluster`
- `/tmp/rds_clusters.json` — `app-atento-001-cluster` LIVE (Aurora PG 16.13, MultiAZ, DeletionProtection: true); endpoint: `app-atento-001-cluster.cluster-cvw5l7p4adp1.us-east-1.rds.amazonaws.com`
