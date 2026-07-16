# SPIKE — PgBouncer on ECS (replace the manual EC2 pooler)

**Date:** 2026-06-29 · **Status:** research for planning · **Repo:** `terraform`

## Question

How should PgBouncer be deployed so it (a) keeps protecting Postgres from connection-storm bursts, (b) stops being a hand-managed EC2 pet / single point of failure, and (c) lives in Terraform like everything else — given a micro-sized pooler is enough for the load?

## Decision already taken

Run PgBouncer as a **small ECS service (2 tasks) behind internal service discovery**, per the market research (community-recommended for ECS shops; centralized pooler is the funnel that caps backend connections during bursts; 2 tasks removes the SPOF). RDS Proxy was the managed alternative but rejected on cost for this scale. This SPIKE designs the *how*.

## Current state (grounded)

- **The PgBouncer EC2 instance is NOT in Terraform** — only its security group is (`app-shared-001/rds.tf:47-80`: SG `app-shared-001-pgbouncer`, ingress 6432 from VPC + SSH 22 from the VPN management CIDR). The instance, `pgbouncer.ini`, and `userlist.txt` are hand-managed on the box (a pet). Its credential is the "PgBouncer PostgreSQL" item in 1Password.
- **Transaction pooling** is in use — the app sets `PGBOUNCER_PREPARED_STATEMENTS = "false"` (`app-shared-001/compute.tf:41`), required for transaction mode.
- **The app reaches the DB via `DATABASE_URL`**, stored in **SSM Parameter Store** (`app-shared-001/ssm.tf:9` + `compute.tf:70`: `valueFrom = aws_ssm_parameter.secrets["DATABASE_URL"].arn`). This URL's host currently points at the PgBouncer pet. **Repointing to the new pooler = updating this one parameter.**
- **Backend (Postgres) master** is RDS-managed in **Secrets Manager** (`rds!cluster-*`, `manage_master_user_password = true` in `app-shared-001/rds.tf`). PgBouncer's backend connection must read from there.
- **Stacks with a PgBouncer today:** `app-shared-001`, `app-beta-001`, `app-demo-001` (and `app-atento-001` via the `atento_001_task_config` module).
- **Service-discovery precedent already exists** in the repo: `auth-001/ecs.tf` uses it — a pattern to follow rather than invent.

## Target architecture (proposed)

- A reusable **`pgbouncer` Terraform module** (mirrors the `cross_region_backup` precedent: one module, called per stack), producing:
  - An **ECS service** with **2 tasks** of a PgBouncer container, sized micro (256 CPU / 512 MB is plenty for a pooler).
  - **Service discovery** (AWS Cloud Map) giving a stable internal DNS name, e.g. `pgbouncer.<stack>.local:6432`, resolving across both tasks (load-balanced, HA).
  - **Config as code**: `pgbouncer.ini` (transaction mode, pool sizes) baked into the image or rendered to SSM; **userlist/auth** sourced from the RDS-managed Secrets Manager secret (`auth_query` against Postgres, or a generated userlist) so there is no hand-maintained password file.
  - A **security group** replacing the current one (6432 from the app SG; no SSH — it is a container now).
- The app's `DATABASE_URL` SSM parameter is updated to the service-discovery endpoint.

## Migration approach (per stack)

1. **Extract the current config** from the EC2 pet — read `pgbouncer.ini` + `userlist.txt` (pool sizes, mode, auth) so the ECS version reproduces behavior exactly. (The "buscar as credenciais nos pgbouncer atuais" step — done via SSM Session Manager / SSH on the pet, by the engineer.)
2. **Stand up the ECS PgBouncer** alongside the pet (new service-discovery endpoint), without touching the app yet.
3. **Repoint** the app's `DATABASE_URL` to the new endpoint; redeploy the app tasks.
4. **Validate** under load (bursts handled, pool caps hold, no session-feature breakage).
5. **Decommission** the EC2 pet + its SG; retire the "PgBouncer PostgreSQL" 1Password item if the new auth no longer needs it.

## Open decisions (for the engineer)

1. **Launch type** — Fargate (no host to manage, simplest) vs ECS on the existing EC2 capacity (cheaper if spare capacity, but couples to the ASG). Recommendation: **Fargate** for a tiny always-on pooler.
2. **Discovery mechanism** — Cloud Map service discovery (DNS) vs ECS Service Connect vs an internal NLB. Recommendation: **Cloud Map** (matches the `auth-001` precedent, no LB cost).
3. **PgBouncer image** — community image (`edoburu/pgbouncer`, `bitnami/pgbouncer`) vs a 4Shark-built image in ECR. Recommendation: confirm per the secure-image policy.
4. **Auth model** — `auth_query` (PgBouncer queries Postgres for credentials, no userlist file) vs a generated `userlist.txt` from the SM secret. Recommendation: **`auth_query`** (no secret file to maintain).
5. **Rollout order** — start on a low-risk stack (`demo-001` or `beta-001`) before `shared-001` (productive). Recommendation: **demo → beta → shared → atento**.

## Risks

- **Cutover is a DB-path change** — a bad `DATABASE_URL` repoint breaks every app task. Mitigate: stand up new pooler first, validate connectivity, repoint, keep the pet until validated (fast rollback = revert the parameter).
- **Transaction-mode caveats** — LISTEN/NOTIFY, session-locked migrations, long cursors fight transaction pooling. Confirm the app has no such code paths on the pooled connection (prepared statements already disabled, so likely fine).
- **HA of discovery** — 2 tasks across AZs; confirm Cloud Map returns both and the client reconnects on task replacement.
