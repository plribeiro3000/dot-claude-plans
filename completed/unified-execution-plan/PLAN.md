# Unified Execution Plan

## Detailed Plans

- Deploy Pipeline Optimization: `active/app/deploy-pipeline-optimization/PLAN.md`
- Setup ECS Migration: `completed/setup-ecs-migration/PLAN.md`
- EC2 Decommission: `completed/app/ec2-decommission-cron-console/PLAN.md`

All three are independent (different repos, different files).

---

## Done

| # | What | Date | Delivered |
|---|------|------|-----------|
| 1 | Collect crontabs from EC2 instances | 2026-02-17 | Crontab data → ECS Scheduled Tasks config |
| 2 | Create `bin/ecs` CLI tool (`connect` + `run`) | 2026-02-17 | Console access via ECS Exec on all 4 envs |
| 3 | Terraform: `modules/ecs_scheduled_task/` module | 2026-02-18 | Reusable module for EventBridge + ECS RunTask |
| 4 | Deploy scheduled tasks to all 4 environments | 2026-02-18 | 22 cron jobs running on Fargate |
| 5 | Lambda autoscaling v0.6.1 (min_size bug fix) | 2026-02-18 | Terraform drift eliminated |
| 6 | Update deploy workflows to register cron task defs | 2026-02-18 | PR #4818 |
| 7 | Terminate 4 legacy EC2 instances + delete 4 SGs | 2026-02-18 | EC2 decommission complete |
| 8 | Finalize 4 infra cleanup plans | 2026-02-18 | beta, demo, shared, atento — all done |
| 16 | Create health check endpoint + `config/version.rb` in setup app | 2026-02-19 | PR #216 merged |
| 17 | Create Dockerfile + deploy workflow for setup app | 2026-02-19 | PR #216 merged |
| 18 | Terraform: create setup ECS cluster, ALB, CodeDeploy, ECR | 2026-02-19 | Terraform applied, all resources created |
| 19 | Cloudflare CNAME + GitHub environment + first deploy of setup | 2026-02-19 | DNS live, deploy validated (v1.12.0) |
| 9 | Docker HEALTHCHECK `interval=10s` + `start-period=15s`, remove `sleep 30` from quiet mode | 2026-02-19 | PR #4824 merged, validated on Beta (quiet mode 40s → 9s) |
| 10 | Create `build-image` reusable workflow (build + push to ECR on push to develop/master) | 2026-02-19 | PR #4825 merged |
| 11-12 | Modify `deploy-ecs` action + refactor 4 deploy workflows to use only pre-built images | 2026-02-19 | PR #4827 merged |
| 13 | Test on Beta-001 and Demo-001 | 2026-02-19 | Both deploys successful |
| 14-15 | Unified Dockerfile (no CMD) + `command` override in all deploy workflows, remove dead `sidekiq-config` input | 2026-02-19 | PR #4830 merged, validated on Beta and Demo (with new image) |
| 16 | Consolidate ECR repos to 1 per environment (32 → 4) | 2026-02-20 | Terraform PR #157 (create repos), App PR #4831 (update CI), Terraform PR #158 (remove old repos). Applied on all 4 envs. |

---

## Milestones

| After step | State |
|------------|-------|
| 19 | Setup app live on ECS, cron on ECS, `bin/ecs` working, legacy EC2 terminated |
| 9 | Deploys ~55s faster (HEALTHCHECK + quiet mode sleep removed) |
| 13 | Deploys 2-5 min faster (build removed from critical path) |
| 15 | Single unified image, no default CMD (fail-fast), command override everywhere |
| 16 | Single ECR repo per environment (32 → 4) |

**All items complete.** Unified execution plan finished.
