# Deploy Time Optimization Study

> **Date**: 2026-02-16
> **Goal**: Reduce deploy time to under 5 minutes
> **Scope**: All 4 environments (Atento-001, Beta-001, Demo-001, Shared-001)
> **Project**: app (Ruby on Rails backend)

## Data Sources

GitHub Actions runs analyzed:
- **Atento-001**: https://github.com/4shark/app/actions/runs/21961019142
- **Beta-001**: https://github.com/4shark/app/actions/runs/21988766182
- **Demo-001**: https://github.com/4shark/app/actions/runs/21996031471
- **Shared-001**: https://github.com/4shark/app/actions/runs/21932173734

Workflow files analyzed:
- `.github/workflows/deploy-atento-001.yaml`
- `.github/workflows/deploy-beta-001.yaml`
- `.github/workflows/deploy-demo-001.yaml`
- `.github/workflows/deploy-shared-001.yaml`
- `.github/actions/deploy-ecs/action.yaml`
- `.github/docker/web/Dockerfile`
- `.github/docker/worker/Dockerfile`

---

## 1. Current Total Deploy Times

| Environment | Branch | Total Time | Workers Count |
|-------------|--------|------------|---------------|
| **Atento-001** | develop | **10m 39s** | 5 workers |
| **Beta-001** | develop | **15m 25s** | 3 workers |
| **Demo-001** | master | **9m 59s** | 3 workers |
| **Shared-001** | feature/* | **14m 49s** | 3 workers |

---

## 2. Detailed Time Breakdown Per Phase

### Atento-001 (10m 39s) — 2026-02-12 19:24:12 → 19:34:51

| Phase | Start | End | Duration |
|-------|-------|-----|----------|
| Validate Secrets | 19:24:17 | 19:24:21 | 4s |
| Setup | 19:24:25 | 19:24:29 | 4s |
| Acquire Autoscaling Lock | 19:24:33 | 19:24:48 | 15s |
| Sidekiq Quiet Mode | 19:24:52 | 19:25:34 | **42s** |
| ├─ Send TSTP to Sidekiq | 19:24:55 | 19:25:32 | 37s (includes 30s sleep) |
| Prepare and Migrate | 19:25:37 | 19:27:57 | **2m 20s** |
| ├─ Build/Push Web Image | 19:25:41 | 19:26:32 | **51s** |
| ├─ Install redis-cli | 19:26:32 | 19:26:42 | 10s |
| ├─ Run DB Migrations | 19:26:42 | 19:27:52 | **1m 10s** |
| Deploy Web (CodeDeploy create) | 19:28:01 | 19:28:13 | 12s |
| Deploy Sidekiq (parallel matrix) | 19:28:17 | 19:34:00 | **5m 42s** |
| ├─ worker-user (deploy-ecs) | 19:28:24 | 19:33:11 | 4m 47s |
| ├─ worker-commission-white-shark | 19:28:29 | 19:33:33 | 5m 4s |
| ├─ worker-commission-tiger-shark | 19:28:28 | 19:33:34 | 5m 6s |
| ├─ worker-system | 19:28:27 | 19:33:34 | 5m 7s |
| ├─ worker-commission (LONGEST) | 19:28:26 | 19:33:52 | **5m 26s** |
| Resume Web Deployment | 19:34:04 | 19:34:15 | 11s |
| Traffic Shift | 19:34:18 | 19:34:23 | 5s |
| Validate All Services | 19:34:28 | 19:34:32 | 4s |
| Deployment Success | 19:34:37 | 19:34:51 | 14s |

**Notes**: Atento has 5 workers with ASG scaling (scale up before deploy, scale down after). The ASG scaling adds overhead waiting for new EC2 instances.

### Beta-001 (15m 25s) — 2026-02-13 13:34:42 → 13:50:07

| Phase | Start | End | Duration |
|-------|-------|-----|----------|
| Validate Secrets | 13:34:48 | 13:34:52 | 4s |
| Setup | 13:34:56 | 13:35:01 | 5s |
| Acquire Autoscaling Lock | 13:35:06 | 13:35:20 | 14s |
| Sidekiq Quiet Mode | 13:35:25 | 13:36:05 | **40s** |
| ├─ Send TSTP to Sidekiq | 13:35:28 | 13:36:03 | 35s (includes 30s sleep) |
| Prepare and Migrate | 13:36:11 | 13:44:09 | **7m 58s** |
| ├─ Build/Push Web Image | 13:36:15 | 13:39:37 | **3m 22s** ← CACHE MISS |
| ├─ Install redis-cli | 13:39:37 | 13:39:48 | 11s |
| ├─ Run DB Migrations | 13:39:48 | 13:44:02 | **4m 14s** ← VERY SLOW |
| Deploy Web (CodeDeploy create) | 13:44:14 | 13:44:21 | 7s |
| Deploy Sidekiq (parallel, WITH ASG) | 13:44:26 | 13:49:04 | **4m 38s** |
| ├─ worker-commission (deploy-ecs) | 13:44:30 | 13:48:54 | 4m 24s |
| ├─ worker-user (deploy-ecs) | 13:44:29 | 13:48:53 | 4m 24s |
| ├─ worker-system (LONGEST) | 13:44:28 | 13:48:59 | **4m 31s** |
| Resume Web Deployment | 13:49:09 | 13:49:17 | 8s |
| Traffic Shift | 13:49:21 | 13:49:26 | 5s |
| Validate All Services | 13:49:34 | 13:49:37 | 3s |
| Deployment Success | 13:49:43 | 13:50:06 | 23s |

**Notes**: Beta is the slowest. Web image had cache miss (3m 22s build). Migrations took 4m 14s (larger database or complex migration). Has ASG scaling for workers (all 4 environments do). **Beta-001 uses `rails-env: development`** while all other environments use `rails-env: production` — this affects the bundle (included gems), asset compilation, and potentially build time and behavior.

### Demo-001 (9m 59s) — 2026-02-13 17:19:59 → 17:29:58

| Phase | Start | End | Duration |
|-------|-------|-----|----------|
| Validate Secrets | 17:20:04 | 17:20:07 | 3s |
| Setup | 17:20:11 | 17:20:14 | 3s |
| Acquire Autoscaling Lock | 17:20:19 | 17:20:39 | 20s |
| Sidekiq Quiet Mode | 17:20:45 | 17:21:25 | **40s** |
| ├─ Send TSTP to Sidekiq | 17:20:48 | 17:21:22 | 34s (includes 30s sleep) |
| Prepare and Migrate | 17:21:30 | 17:26:00 | **4m 30s** |
| ├─ Build/Push Web Image | 17:21:33 | 17:22:30 | **57s** |
| ├─ Install redis-cli | 17:22:30 | 17:22:41 | 11s |
| ├─ Run DB Migrations | 17:22:41 | 17:25:54 | **3m 13s** |
| Deploy Web (CodeDeploy create) | 17:26:06 | 17:26:13 | 7s |
| Deploy Sidekiq (parallel, WITH ASG) | 17:26:18 | 17:28:51 | **2m 33s** |
| ├─ worker-commission (deploy-ecs) | 17:26:21 | 17:28:25 | 2m 4s |
| ├─ worker-system (deploy-ecs) | 17:26:22 | 17:28:26 | 2m 4s |
| ├─ worker-user (LONGEST) | 17:26:22 | 17:28:45 | **2m 23s** |
| Resume Web Deployment | 17:28:56 | 17:29:03 | 7s |
| Traffic Shift | 17:29:09 | 17:29:17 | 8s |
| Validate All Services | 17:29:22 | 17:29:26 | 4s |
| Deployment Success | 17:29:32 | 17:29:57 | 25s |

**Notes**: Demo is the fastest overall. Good cache hit on web image (57s). Has ASG scaling (all 4 environments do), but ASG overhead was minimal — workers stabilized in ~2min. Migration is still 3m+ though.

### Shared-001 (14m 49s) — 2026-02-12 03:15:33 → 03:30:22

| Phase | Start | End | Duration |
|-------|-------|-----|----------|
| Validate Secrets | 03:15:37 | 03:15:39 | 2s |
| Setup | 03:15:43 | 03:15:46 | 3s |
| Acquire Autoscaling Lock | 03:15:50 | 03:16:08 | 18s |
| Sidekiq Quiet Mode | 03:16:11 | 03:17:01 | **50s** |
| ├─ Send TSTP to Sidekiq | 03:16:13 | 03:16:59 | 46s (includes 30s sleep) |
| Prepare and Migrate | 03:17:04 | 03:20:48 | **3m 44s** |
| ├─ Build/Push Web Image | 03:17:08 | 03:20:00 | **2m 52s** ← PARTIAL CACHE |
| ├─ Install redis-cli | 03:20:00 | 03:20:15 | 15s |
| ├─ Run DB Migrations | 03:20:15 | 03:20:42 | **27s** |
| Deploy Web (CodeDeploy create) | 03:20:52 | 03:20:58 | 6s |
| Deploy Sidekiq (parallel, WITH ASG) | 03:21:01 | 03:29:32 | **8m 30s** |
| ├─ worker-commission (deploy-ecs) | 03:21:09 | 03:23:08 | 1m 59s |
| ├─ worker-user (deploy-ecs) | 03:21:09 | 03:23:11 | 2m 2s |
| ├─ worker-system (LONGEST) | 03:21:12 | 03:29:24 | **8m 12s** ← OUTLIER |
| Resume Web Deployment | 03:29:36 | 03:29:42 | 6s |
| Traffic Shift | 03:29:45 | 03:29:50 | 5s |
| Validate All Services | 03:29:54 | 03:29:58 | 4s |
| Deployment Success | 03:30:01 | 03:30:21 | 20s |

**Notes**: Shared has ASG scaling for workers. worker-system took 8m 12s - likely waiting for a new EC2 instance to launch in the ASG. The other two workers finished in ~2min. Migrations were fast (27s). Build had partial cache (2m 52s).

---

## 3. Summary: Time Distribution by Phase

| Phase | Atento | Beta | Demo | Shared | Average |
|-------|--------|------|------|--------|---------|
| Pre-deploy overhead | ~23s | ~23s | ~26s | ~23s | ~24s |
| Sidekiq Quiet Mode | 42s | 40s | 40s | 50s | **43s** |
| Build/Push Web Image | 51s | 3m 22s | 57s | 2m 52s | **2m 0s** |
| DB Migrations | 1m 10s | 4m 14s | 3m 13s | 27s | **2m 16s** |
| Deploy Web (trigger) | 12s | 7s | 7s | 6s | ~8s |
| **Deploy Sidekiq** | **5m 42s** | **4m 38s** | **2m 33s** | **8m 30s** | **5m 21s** |
| Post-deploy | 34s | 39s | 44s | 35s | ~38s |

**Top 3 bottlenecks by average time:**
1. Deploy Sidekiq (wait for services stable): **5m 21s** (50% of total)
2. DB Migrations: **2m 16s** (21% of total)
3. Build/Push Web Image: **2m 0s** (19% of total)

---

## 4. Critical Finding: Redundant Docker Builds

### Current State

Each environment builds **N+1 Docker images** of the same Rails application:

| Environment | Docker Builds per Deploy | Separate ECR Repos |
|-------------|------------------------|--------------------|
| Atento-001 | **6** (1 web + 5 workers) | 6 |
| Beta-001 | **4** (1 web + 3 workers) | 4 |
| Demo-001 | **4** (1 web + 3 workers) | 4 |
| Shared-001 | **4** (1 web + 3 workers) | 4 |

### Why This Is Wasteful

The web and worker Dockerfiles are nearly identical:

```
# Web Dockerfile                        # Worker Dockerfile
FROM ruby:3.4.1                         FROM ruby:3.4.1
# Same system deps                      # Same system deps (+tini)
# Same bundle install                   # Same bundle install
# Same COPY . .                         # Same COPY . .
RUN bundle exec rails assets:precompile # (no assets:precompile)
CMD ["bundle", "exec", "puma", ...]     # CMD [..., "sidekiq", "-C", "config/${SIDEKIQ_CONFIG}"]
```

Key insight: `SIDEKIQ_CONFIG` is passed as a build ARG but the CMD reads it from the **runtime environment** (`${SIDEKIQ_CONFIG}`). The ECS task definition already sets environment variables, so this value doesn't need to be baked into the image.

**Full Dockerfile differences** (relevant for unified image in Phase 3):

| Difference | Web Dockerfile | Worker Dockerfile |
|------------|----------------|-------------------|
| graphviz | Yes (system dep) | No |
| tini | No | Yes (init process) |
| RAILS_ENV build arg | Yes | No |
| SECRET_KEY_BASE_DUMMY | Yes (for assets:precompile) | No |
| SIDEKIQ_CONFIG build arg | No | Yes (but read from runtime env) |
| assets:precompile | Yes | No |

### Cache Fragmentation

The `deploy-ecs` action uses `cache-from: type=registry,ref=${{ inputs.ecr-repo }}:buildcache`. Each ECR repo has its OWN build cache. The web image cache is **not shared** with workers.

### ECR Repos Across All Environments (Same AWS Account: 405749097490)

```
405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-web (implied)
405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-worker-commission
405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-worker-commission-tiger-shark
405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-worker-commission-white-shark
405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-worker-system
405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-worker-user
405749097490.dkr.ecr.us-east-1.amazonaws.com/beta-001-worker-commission
405749097490.dkr.ecr.us-east-1.amazonaws.com/beta-001-worker-system
405749097490.dkr.ecr.us-east-1.amazonaws.com/beta-001-worker-user
405749097490.dkr.ecr.us-east-1.amazonaws.com/demo-001-worker-commission
405749097490.dkr.ecr.us-east-1.amazonaws.com/demo-001-worker-system
405749097490.dkr.ecr.us-east-1.amazonaws.com/demo-001-worker-user
405749097490.dkr.ecr.us-east-1.amazonaws.com/shared-001-worker-commission
405749097490.dkr.ecr.us-east-1.amazonaws.com/shared-001-worker-system
405749097490.dkr.ecr.us-east-1.amazonaws.com/shared-001-worker-user
+ web repos for beta, demo, shared (from vars.WEB_ECR_REPO)
```

---

## 5. Critical Finding: ASG Scaling Overhead

**All 4 environments** include ASG scale-up/scale-down during worker deploys:

```yaml
# Steps in ALL worker deploys (all 4 environments):
- Scale up ASG for rolling deployment    # Double desired capacity
- Save current task definition
- Run deploy-ecs action                  # Build + push + register + update + wait stable
- Rollback to previous task definition   # (only on failure)
- Scale down ASG after deployment        # Restore original capacity
```

Impact: ASG scaling waits for new EC2 instances to launch, which can add 2-8 minutes. Shared worker-system took 8m 12s (likely waiting for instance). Demo/Beta had lower overhead (workers in Beta/Demo often have min_size=0, so ASG behavior differs).

---

## 6. Critical Finding: `wait services-stable` Dominates Worker Deploy Time

Inside the `deploy-ecs` action for each worker, the time breakdown is approximately:

| Step | Time |
|------|------|
| Setup + AWS + ECR login | ~5s |
| Docker Buildx setup | ~3s |
| Build and Push Image | 10-30s (cache hit) to 1-3min (cache miss) |
| Register Task Definition | ~3s |
| Update ECS Service | ~3s |
| **Wait services-stable** | **2-8 minutes** |

The `aws ecs wait services-stable` polls until:
1. ECS scheduler places new task on instance (~10-30s)
2. Docker pulls image (~30s-2min depending on size and cache)
3. Container starts (~10-30s for Rails/Sidekiq boot)
4. Health check passes (interval=30s, retries=3 → up to 90s)
5. Old container drains and stops (~0-30s)

---

## 7. Critical Finding: Hardcoded 30s Sleep in Sidekiq Quiet Mode

```bash
# Line 299 of deploy workflow:
echo "Waiting 30s for in-progress jobs to complete..."
sleep 30
```

This sleep is unconditional regardless of whether jobs have already completed.

---

## 8. Migration Time Variance

| Environment | Migration Time | Notes |
|-------------|---------------|-------|
| Atento-001 | 1m 10s | Normal |
| Beta-001 | **4m 14s** | Very slow - larger DB or complex migration |
| Demo-001 | **3m 13s** | Slow - includes ECS task startup for migration runner |
| Shared-001 | 27s | Fast - small DB |

Migration runs as a one-off ECS task (`aws ecs run-task` with `db:migrate` command override). The time includes:
1. ECS places migration task (~10-30s)
2. Docker pull (~30s-1min)
3. Container boot + Rails init (~10-20s)
4. Actual migration execution (variable)
5. Container stops

---

## 9. Workflow Architecture (Current)

```
trigger (workflow_dispatch)
  │
  ▼
validate-secrets
  │
  ▼
setup (export sidekiq config)
  │
  ├──────────────────┐
  ▼                  ▼
acquire-lock    (waits for setup)
  │
  ▼
sidekiq-quiet-mode (TSTP + 30s sleep)
  │
  ▼
prepare-and-migrate
  ├─ BUILD WEB IMAGE (docker build+push)
  ├─ REGISTER WEB TASK DEF
  └─ RUN MIGRATIONS (ECS run-task)
  │
  ▼
deploy-web (CodeDeploy create, pauses at BeforeAllowTraffic)
  │
  ▼  (deploy-sidekiq needs: [setup, deploy-web])
deploy-sidekiq (matrix, parallel)
  ├─ worker-1: BUILD + PUSH + REGISTER + UPDATE + WAIT
  ├─ worker-2: BUILD + PUSH + REGISTER + UPDATE + WAIT
  ├─ worker-3: BUILD + PUSH + REGISTER + UPDATE + WAIT
  └─ worker-N: BUILD + PUSH + REGISTER + UPDATE + WAIT
  │
                 ▼
          resume-deployment (signal CodeDeploy to continue)
                 │
                 ▼
          traffic-shift (monitor CodeDeploy)
                 │
                 ▼
          validate (check all results)
                 │
                 ▼
          success (release lock, cleanup SSM)
```

---

## 10. Analysis: ECR Centralization

### Proposal

Replace 18 ECR repositories with **1 central ECR repository** (e.g., `4shark/app`).

**Current**: Each service has its own ECR → each service builds and pushes its own image.
**Proposed**: One ECR → one build, one push. All services reference the same image with different CMD.

### Technical Requirements

1. **Unified Dockerfile**: Merge web and worker Dockerfiles into one
   - Include `graphviz` (system dep needed for web)
   - Include `tini` (needed for workers)
   - Include `assets:precompile` (needed for web, harmless for workers)
   - No hardcoded CMD — let ECS task definition specify command
2. **SIDEKIQ_CONFIG via ECS environment only**: Remove from Docker build args
3. **ECS Task Definitions**: Already support `command` override and environment variables
4. **Cross-environment access**: All environments use same AWS account (405749097490) so no cross-account issues

### Expected Impact

| Item | Before | After | Savings |
|------|--------|-------|---------|
| Docker builds per deploy | N+1 (web + workers) | **0** (pre-built) | 2-5 min |
| ECR push operations | N+1 per deploy | **0** (pre-pushed) | 30s-1min |
| Image pull on EC2 | Cold cache per repo | **Layers already cached** | 30s-1min |
| Build cache | Fragmented (per repo) | **Centralized** | Faster builds |

### Risk Assessment

- **Low risk**: ECS task definitions already support CMD override and env vars
- **Migration effort**: Medium — need to update task definitions and deploy-ecs action
- **Rollback**: Easy — can keep old ECR repos during transition

---

## 11. Analysis: Separate Build Pipeline from Deploy Pipeline

### Proposal

Split the current monolithic deploy workflow into two pipelines:

```
Pipeline 1 — CI/Build (triggered on push to develop/master):
  1. Build unified Docker image (~2min)
  2. Push to central ECR (~30s)
  3. Tag: {version}-{sha}
  4. Image is "ready for deploy"

Pipeline 2 — Deploy (triggered manually via workflow_dispatch):
  1. Reference existing image by tag (NO build)
  2. Register task definitions
  3. Run migrations
  4. Deploy all services
```

### Expected Impact

| Phase (current) | Current Time | After Separation |
|-----------------|-------------|------------------|
| Build/Push Web Image | 51s - 3m 22s | **0s** (already done in CI) |
| Deploy Sidekiq (includes build) | 2m 33s - 8m 30s | **2-3min** (only update+wait) |

### Technical Requirements

1. CI pipeline builds on push to develop/master
2. Deploy pipeline accepts image tag as input parameter
3. `deploy-ecs` action modified to skip build steps when image already exists
4. Image tag passed through all jobs

### Risk Assessment

- **Low risk**: Decouples build from deploy, which is industry best practice
- **Consideration**: Need to ensure the exact image that was tested in CI is what gets deployed

---

## 12. Analysis: ASG Scaling — Hard Constraint

**All 4 environments** scale up ASG before deploying workers:
- Double desired capacity → wait for new EC2 instances → deploy → scale back down
- This adds 2-8 minutes depending on instance availability
- Atento and Shared see the most overhead due to larger instance types and more workers
- Beta and Demo have lower overhead (workers often at min_size=0, faster scale-up)

### Why ASG Scaling Cannot Be Removed

The custom Lambda + ASG autoscaling exists because **ECS Service Auto Scaling on EC2 has a 15-minute cooldown**. The system works in bursts — paying for 17 minutes of EC2 to use 1 minute is unacceptable. The Lambda bypasses this by managing ASG directly with a Redis lock.

During deploy, workflows double ASG capacity because existing instances don't have spare capacity to run old + new tasks simultaneously.

**Options investigated and ruled out:**

1. **`minimumHealthyPercent: 50`** — Already set in Terraform (`deployment_minimum_healthy_percent = 50`). Does NOT work because `enable_managed_scaling = false` on all capacity providers, and post-2023 ECS starts new tasks FIRST (`maximumPercent: 200%`). New tasks go PENDING indefinitely when there's no spare EC2 capacity. Confirmed in practice.
2. **ECS managed autoscaling** — Has a 15-minute cooldown that conflicts with burst-based Lambda scaling.
3. **Remove ASG scaling from deploy** — Deploys hang waiting for capacity that never materializes.

**The only viable long-term solution is Fargate migration for workers** (separate project), which eliminates ASG entirely.

---

## 13. Analysis: Additional Optimizations

### 13.1 Optimize Health Checks

Current worker health check:
```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD test -f /app/tmp/sidekiq_ready.txt || exit 1
```

With `interval=30s` and `retries=3`, worst case is 90s just for health checks to pass.

**Proposal**: Reduce interval to 10-15s and add `start-period` to allow initial boot time.

**Savings**: ~20-40s per service stabilization.

### 13.2 Remove Hardcoded Sleep

Replace `sleep 30` in Sidekiq Quiet Mode with polling:
```bash
# Instead of blind sleep, poll Sidekiq busy count
for i in $(seq 1 30); do
  BUSY=$(check_sidekiq_busy_count)
  if [ "$BUSY" = "0" ]; then break; fi
  sleep 1
done
```

**Savings**: Up to ~20s when jobs finish quickly.

### 13.3 Multi-Stage Docker Build (Smaller Image)

Current image based on `ruby:3.4.1` (full Debian) with build-essential still present.

**Proposal**: Multi-stage build — compile in build stage, copy to slim runtime stage.

**Savings**: ~30-60s on image pull (smaller image = faster pull).

### 13.4 Pre-Pull Images on EC2 Instances

Configure a cron or ECS daemon task to periodically pull the latest image.

**Savings**: ~1min on container startup (image layers already on disk).

### 13.5 Parallel Migration + Deploy

If migrations are backward-compatible (required for blue/green anyway), run migrations in parallel with worker deploys instead of sequentially.

**Savings**: Up to 4min (migration time no longer on critical path).

---

## 14. Proposed Target Architecture

```
CI Pipeline (on push to develop/master):
  1. Build unified image (web+worker)     → ~2min
  2. Push to central ECR                  → ~30s
  3. Tag: {version}-{sha}

Deploy Pipeline (workflow_dispatch):
  1. Validate Secrets                     → ~5s
  2. Setup + Acquire Lock                 → ~15s
  3. Sidekiq Quiet Mode (polling)         → ~15s (no fixed sleep)
  4. Register Task Defs (all services)    → ~10s (parallel, ref existing image)
  5. Run Migrations ─────────┐
  6. Deploy Web → Workers ───┤ parallel  → bottleneck varies per env
  7. Resume + Traffic Shift  ┘           → ~10s
  8. Validate + Cleanup                   → ~15s
```

**Realistic estimates (Phases 1+2, ASG overhead preserved):**

| Environment | Current | After Phases 1+2 | Bottleneck |
|-------------|---------|-------------------|------------|
| Atento-001 | 10m 39s | **~5m 39s** | Workers (ASG) |
| Beta-001 | 15m 25s | **~5m 42s** | Migrations |
| Demo-001 | 9m 59s | **~4m 41s** | Migrations |
| Shared-001 | 14m 49s | **~8m 25s** | Workers (ASG) |

> To reach <5min for all environments, Fargate migration for workers is needed (separate project).

---

## 15. Action Plan by Priority

| # | Action | Impact | Effort | Time Savings | Environments Affected |
|---|--------|--------|--------|-------------|----------------------|
| 1 | **Centralized ECR + unified image** | HIGH | Medium | 2-5min | All |
| 2 | **Separate build from deploy** | HIGH | Medium | 1-3min | All |
| 3 | **Optimize health checks** | Medium | Low | 30-60s | All |
| 4 | **Remove 30s sleep** (use polling) | Low | Low | ~20s | All |
| 5 | **Parallel migrations + deploy** | HIGH | Medium | 1-4min | All (especially Beta, Demo) |
| 6 | **Multi-stage Docker build** | Medium | Medium | 30-60s | All |
| 7 | **Pre-pull images on EC2** | Medium | Low | ~1min | All |

> ASG scaling during deploy is a hard constraint (see Section 12). Only Fargate migration (separate project) eliminates it.

### Minimum Viable Combination for < 5 minutes

- **Demo-001**: Actions #1 + #2 + #5 reach target (~4m 41s)
- **Beta-001**: Actions #1 + #2 + #5 get close (~5m 42s). Beta's bottleneck is migration time (4m 14s).
- **Atento-001/Shared-001**: All actions help but <5min requires Fargate migration (ASG overhead dominates)

---

## 16. Estimated Results After Optimization

See PLAN.md "Estimated Results Summary" for the authoritative, phase-by-phase estimates. Summary:

| Environment | Current | After Phase 1 | After Phases 1+2 | Bottleneck |
|-------------|---------|---------------|-------------------|------------|
| Atento-001 | 10m 39s | ~8m 33s | **~5m 39s** | Workers (ASG) |
| Beta-001 | 15m 25s | ~10m 48s | **~5m 42s** | Migrations |
| Demo-001 | 9m 59s | ~7m 47s | **~4m 41s** | Migrations |
| Shared-001 | 14m 49s | ~10m 42s | **~8m 25s** | Workers (ASG) |

> Achieving <5min for Atento and Shared requires Fargate migration (eliminates ASG entirely).

---

## 17. What Does NOT Change

- Blue/green deployment with CodeDeploy for web service
- Sidekiq quiet mode (important for graceful shutdown)
- Redis lock for autoscaling prevention
- ECS cluster and service structure
- CodeDeploy BeforeAllowTraffic hook pattern
- SSM parameter-based signaling

---

## 18. Open Questions

1. What is the actual Docker image size? (Affects pull time estimates)
2. Are EC2 instances using optimized AMI with Docker layer caching?
3. Are migrations always backward-compatible? (Required for parallel migration strategy)
4. Why did Beta-001 migration take 4m 14s? (Data size or migration complexity?)
5. Why did Shared-001 worker-system take 8m 12s? (ASG instance launch? Spot instance?)
6. Is there a reason each worker has its own ECR repo? (Historical? Compliance?)
7. What are the current ECS health check settings in the target group? (Separate from Docker HEALTHCHECK)
