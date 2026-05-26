# PLAN — Setup Legacy Infrastructure Cleanup

**Status:** COMPLETED
**Completed:** 2026-02-21
**Created:** 2026-02-19
**Projects:** AWS (manual cleanup, no Terraform)
**Environment:** setup (us-east-1)

## Context

The setup app was migrated from a standalone EC2 instance to ECS on 2026-02-19. DNS was pointed to the ALB and the deploy was validated (v1.12.0). The old EC2 instance is still running as a safety net. After ~2 days of stability, it can be decommissioned.

Unlike the app environments (beta, demo, shared, atento), setup's legacy infra was created entirely by hand — no Terraform, no naming conventions. The cleanup is purely AWS Console/CLI operations.

**How the old setup worked**: The instance `setup-app001` ran in a **public subnet** (`production-pub-a`, `MapPublicIpOnLaunch: true`) with an auto-assigned public IP (`3.83.127.88`, owner: amazon). No ALB, no ELB — traffic came directly to the instance. The Cloudflare DNS pointed directly to this IP. The SG `4Shark-Setup-prd-APP` allowed ports 80/443 from `0.0.0.0/0`. The IP is **NOT an EIP** — it's ephemeral and will be released automatically on termination.

## Resource Inventory

### Legacy Resources (TO DELETE)

| # | Resource | Type | ID / Name | Details |
|---|----------|------|-----------|---------|
| 1 | `setup-app001` | EC2 Instance | `i-02c5cf1aec3ff8981` | t3a.small, running, IP 3.83.127.88 (auto-assigned, NOT EIP), launched 2025-08-12, key `4Shark-prd` |
| 2 | EBS Volume | Volume | `vol-051df57c1fee344ee` | 10 GB gp3, attached to setup-app001 (auto-deletes on termination) |
| 3 | `4Shark-Setup-prd-APP` | Security Group | `sg-06f5c07704f618bbd` | Inbound: 80, 443 (0.0.0.0/0), all traffic (10.254.0.0/16). Only ENI: setup-app001 |
| 4 | `production-setup-rds-sg` | Security Group | `sg-00f02a886ae11392c` | 0 inbound rules, 0 ENIs. Terraform-created but unused (RDS uses `4Shark-Setup-prd-db` instead) |
| ~~5~~ | ~~`/aws/lambda/codedeploy-hook-lambda-setup`~~ | ~~CloudWatch Log Group~~ | — | ~~0 bytes. Orphaned~~ — **DELETED 2026-02-19** |

### Active Resources (KEEP)

| Resource | Type | ID / Name | Managed By |
|----------|------|-----------|------------|
| `setup-web` (x2-3 instances) | EC2 (ECS) | Various | Terraform (ASG/Capacity Provider) |
| `setup-pub-lb` | ALB | Active | Terraform |
| `setup-pub-tg` / `setup-pub-alt-tg` | Target Groups | Active | Terraform |
| `setup-pub-alb-*` | Security Group | `sg-0d2fd81592f4f9795` | Terraform |
| `setup-ecs-sg` (terraform-*) | Security Group | `sg-047f7c07002d96530` | Terraform |
| `setup-web-asg` | ASG | min=1, max=3 | Terraform |
| `setup-runner-asg` | ASG | min=0, max=3, desired=0 | Terraform |
| `setup-web-app` | CodeDeploy App | Active | Terraform |
| `setup-web` | ECR Repository | Active | Terraform |
| `/ecs/setup-web` | CloudWatch Log Group | 30 day retention | Terraform |
| `setup-prd-db` | RDS Instance | PostgreSQL, active | Pre-existing |
| `4Shark-Setup-prd-db` | Security Group | `sg-0e57cacbcc2424568` | RDS (manual, KEEP — used by RDS) |
| `setup-ecs-instance-role` | IAM Role | Active | Terraform |
| `setup-codedeploy-role` | IAM Role | Active | Terraform |
| `setup-pub-ecs-bg-role` | IAM Role | Active | Terraform |
| `setup-deploy-setup` | IAM Policy | Active | Terraform |
| `setup` (app-setup) | IAM User | Active | Terraform |

## Execution Plan

### Phase 1 — Terminate EC2 Instance — DONE (2026-02-21)

Pre-checks passed: DNS resolves to Cloudflare IPs (not 3.83.127.88), health returns 200.
Instance terminated. EBS volume auto-deleted.

### Phase 2 — Delete Security Groups — DONE (2026-02-21)

Validated before deletion: 0 ENIs attached, 0 cross-references in other SGs (ingress/egress).
Both `4Shark-Setup-prd-APP` and `production-setup-rds-sg` deleted.

### Phase 3 — Delete Orphaned CloudWatch Log Group — DONE (2026-02-19)

Log group `/aws/lambda/codedeploy-hook-lambda-setup` deleted. It was auto-created by AWS Lambda (not Terraform-managed), so it wasn't destroyed when `enable_hook_lambda = false` was applied.

### Phase 4 — Validation — DONE (2026-02-21)

- `curl https://setup.app4shark.com/health` → HTTP 200
- Instance `i-02c5cf1aec3ff8981` → terminated
- SGs `sg-06f5c07704f618bbd` and `sg-00f02a886ae11392c` → not found (deleted)
- Log group `/aws/lambda/codedeploy-hook-lambda-setup` → deleted (2026-02-19)

## What This Plan Does NOT Touch

- **RDS** (`setup-prd-db`) — Database stays. SG `4Shark-Setup-prd-db` stays (used by RDS, allows 10.254.0.0/16 on port 5432)
- **Terraform-managed resources** — All ECS/ALB/ASG/CodeDeploy/ECR/IAM resources are managed by Terraform
- **Cloudflare DNS** — Already pointing to ALB, no changes needed

## Estimated Savings

| Resource | Current Cost | After Cleanup |
|----------|-------------|---------------|
| EC2 t3a.small (setup-app001) | ~$13.50/month | $0 |
| EBS 10GB gp3 | ~$0.80/month | $0 |
| **Total** | **~$14.30/month** | **$0** |

## Risks

- **Low risk**: setup-app001 has been running in parallel with ECS since today. If DNS is confirmed working for 2 days, there's no dependency on the old instance.
- **No EIP**: The public IP 3.83.127.88 is auto-assigned and will be released on termination. No risk of dangling EIP charges.
- **No AMIs**: No custom AMIs found for setup (unlike the app environments).
- **No EventBridge/Lambda**: No legacy Lambda functions or EventBridge rules for setup.
