# Cleanup: Atento-001 Deploy & Infrastructure

## Context

Issues discovered during the VPC migration of app-atento-001.

## Items

### 1. Dead GitHub Environment Variable — `WEB_ECR_REPO`

- **Environment**: `atento-001` (GitHub → app repo)
- **Problem**: `WEB_ECR_REPO` is set to `atento-001-web` but the deploy workflow overrides it at line 65 with `${{ vars.ENVIRONMENT }}-app`. The variable is never read.
- **Action**: Remove `WEB_ECR_REPO` from the GitHub environment (or update it to match reality: `atento-001-app`). Check if other environments (beta-001, demo-001, shared-001) have the same dead variable.

### 2. PgBouncer — Migrate to Dedicated VPC

Two PgBouncer EC2 instances exist in the old Production VPC (`vpc-0204a1f8b5de51941`):

| Instance | IP | Name | Subnet |
|---|---|---|---|
| `i-0cf3bfce8a0724fe4` | `10.254.11.185` | `pgbouncer-atento-puma` | `subnet-043bc50dc26aeabe4` |
| `i-0f1b80edb0ea79746` | `10.254.9.233` | `pgbouncer-atento-sidekiq` | `subnet-043bc50dc26aeabe4` |

**Known issue**: Sidekiq `DATABASE_URL` currently points to the Puma PgBouncer IP instead of its own. Datadog metrics are mixed — cannot distinguish Puma vs Sidekiq database connections.

**Migration steps**:
1. Create AMIs from both instances
2. Launch new EC2s from AMIs in the dedicated VPC (`app-atento-001`)
3. Configure Security Groups — allow ECS cluster → PgBouncer, PgBouncer → RDS
4. Verify connectivity (peering if RDS is in a different VPC)
5. Update `DATABASE_URL` GitHub secrets to point to new PgBouncer IPs (fix the Sidekiq one to point to the correct Sidekiq PgBouncer)
6. Deploy with corrected database connections

### 3. Lesson Learned — New Cluster Services Must Start at desired_count=0

**Incident**: After `terraform apply` created the new ECS cluster, services were created with `desired_count=1`. Since the new cluster shares the same Redis as the old cluster, Sidekiq workers in the new cluster immediately started picking up jobs from the queue. They failed because the PgBouncer SG didn't allow the new VPC CIDR (`10.100.12.0/22`) on port 6432, causing `ActiveRecord::DatabaseConnectionError` for every job.

**Impact**: Jobs were consumed from the queue, failed, and went to Sidekiq retry. Users experienced errors until the failed jobs were retried by the old cluster's workers.

**Fix applied**:
1. Added `10.100.12.0/22` to PgBouncer SG (`sg-0d40db569f5088ef9`) on port 6432
2. Scaled all new cluster services to `desired_count=0`

**Prevention**: When creating parallel infrastructure that shares Redis/queues, always set `desired_count=0` in Terraform to prevent new workers from stealing jobs before the migration is ready. Only scale up after deploy with correct configuration.

### 4. Unused EC2 Instance

- **Problem**: There is an EC2 instance that is not being utilized.
- **Action**: Identify the instance, confirm it's unused, and terminate it.
