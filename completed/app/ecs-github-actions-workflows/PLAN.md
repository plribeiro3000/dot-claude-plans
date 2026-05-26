# ECS GitHub Actions Workflows

## Overview

Refactoring and standardization of GitHub Actions workflows for ECS deployment, including Dockerfiles optimization and graceful shutdown configuration.

**Branch:** `feature/ecs-github-actions-workflows`
**Target:** `develop`

---

## Phase 1: Workflow Standardization (COMPLETED)

### What was done

#### 1.1 Naming Convention
- Standardized all workflow and service names to pattern: `{env}-001-{service}`
- Environments: atento, beta, demo, shared
- Services: web, worker-system, worker-user, worker-commission, worker-commission-tiger-shark, worker-commission-white-shark, worker-migration, worker-cleansing

#### 1.2 Directory Structure
- Organized Dockerfiles into `.github/docker/` structure:
  ```
  .github/docker/
  ├── web/Dockerfile           # Web application (Puma)
  └── worker/Dockerfile        # Unified worker Dockerfile (parameterized)
  ```

  **Note:** Worker Dockerfile uses `ARG SIDEKIQ_CONFIG` to select which Sidekiq config file to use at startup.

#### 1.3 Translation
- Translated all Portuguese comments to English in Dockerfiles and workflows

---

## Phase 2: Workflow Bug Fixes (COMPLETED)

### Issues identified and fixed

#### 2.1 Duplicated build-args
- **Problem:** Some workflows had duplicated DIFFEND build-args
- **Affected:** atento-001-web, demo-001-web, shared-001-web
- **Fix:** Removed duplicate entries

#### 2.2 Orphaned TASK_DEF_ARN echo
- **Problem:** Leftover `echo` statements from previous refactoring
- **Affected:** atento-001-web
- **Fix:** Removed orphaned code

#### 2.3 Inverted step order
- **Problem:** "Wait service stable" before "Deploy ECS" (nonsensical)
- **Affected:** demo-001-web, shared-001-web
- **Fix:** Corrected order to Deploy → Wait

#### 2.4 Missing workers in orchestrators
- **Problem:** Orchestrator workflows missing some workers
- **Affected:** All orchestrator workflows
- **Fix:** Added worker-cleansing and worker-migration to all orchestrators

---

## Phase 3: Dockerfile Optimization (COMPLETED)

### Web Dockerfile

#### 3.1 Removed diffend bypass
- **Problem:** Web had complex workaround to bypass diffend during build
- **Fix:** Removed all bypass code, now matches workers

#### 3.2 Standardized with workers
- Ruby version: 3.4.1 (was 3.4.0 in PATH)
- Bundle config: `--local deployment`, `--local path`
- Bundle install: `--without development test`
- Added `COPY lib ./lib` before bundle install

#### 3.3 Removed nginx and supervisor
- **Problem:** Web Dockerfile installed nginx/supervisor but config files don't exist in repo
- **Discovery:** ecs-beta-app runs Puma directly despite having these dependencies
- **Fix:** Removed nginx, supervisor, and related configs
- **New CMD:** `["bundle", "exec", "puma", "-C", "config/puma.rb"]`
- **New EXPOSE:** 3000 (was 80)
- **New HEALTHCHECK:** `curl -f http://localhost:3000/health`

#### 3.4 Fixed yarn install error handling
- **Problem:** `yarn install || echo "..."` swallowed errors
- **Fix:** `yarn install --ignore-engines` (fails build on error)

### Worker Dockerfiles

#### 3.5 Removed unnecessary JS dependencies
- **Problem:** Workers installed nodejs, npm, yarn but don't need them (Sidekiq only)
- **Fix:** Removed from all 7 workers:
  - nodejs, npm from apt-get
  - `npm install -g yarn`
  - `COPY package.json yarn.lock`
  - `yarn install`

---

## Phase 4: Graceful Shutdown (REQUIRES AWS VERIFICATION)

### Current State - Application Side (VERIFIED)

#### Puma (Web) - OK
- **Shutdown timeout:** 8 seconds (env: `PUMA_WORKER_SHUTDOWN_TIMEOUT`)
- **Behavior on SIGTERM:** Stops accepting connections, waits for in-flight requests, graceful shutdown
- **Status:** Within ECS default stopTimeout (30s) - no changes needed

#### Sidekiq (Workers) - NEEDS ATTENTION
- **Shutdown timeout:** 25 seconds (Sidekiq default, can change with `-t` flag)
- **Behavior on SIGTERM:** Stops accepting jobs, waits for current jobs to finish, re-enqueues if timeout
- **Status:** If jobs take longer than ECS stopTimeout, they get killed mid-execution

### What Needs AWS Verification/Configuration

#### 4.1 Task Definition - stopTimeout

| Service Type | Current | Recommended | Why |
|--------------|---------|-------------|-----|
| web | ? | 30s | Puma timeout is 8s, plenty of margin |
| worker-* | ? | **300s (5 min)** | Long-running jobs need time to finish |

**How to check:**
```bash
aws ecs describe-task-definition --task-definition {task-family} \
  --query 'taskDefinition.containerDefinitions[0].stopTimeout'
```

**How to update:** Edit Task Definition JSON, set `stopTimeout: 300` for workers

#### 4.2 ECS Service - Deployment Configuration

| Setting | Current | Recommended | Why |
|---------|---------|-------------|-----|
| `minimumHealthyPercent` | ? | 100% | Always keep healthy instances during deploy |
| `maximumPercent` | ? | 200% | Allow spinning up new before killing old |
| `deploymentCircuitBreaker` | ? | enabled + rollback | Auto-rollback on failed deployments |

**How to check:**
```bash
aws ecs describe-services --cluster {cluster} --services {service} \
  --query 'services[0].deploymentConfiguration'
```

#### 4.3 Rolling Update Behavior

With recommended settings (100%/200%), deploy flow is:
1. Start new task(s) with new image
2. Wait for new task(s) to be healthy
3. Send SIGTERM to old task(s)
4. Wait `stopTimeout` for graceful shutdown
5. If not terminated, send SIGKILL
6. Old task(s) removed

**Zero downtime achieved** because new tasks are healthy before old ones are terminated.

#### 4.5 Workflow Step Order (FIXED)

All 28 worker workflows now have correct order: Deploy ECS → Wait service stable

---

## Phase 5: Build Environment Fix (COMPLETED)

### Problem Discovered

The Dockerfiles were **not receiving** `RAILS_ENV` during build. This caused **all installations and compilations** to run in development mode (Rails default).

**Impact:**
- `bundle install` ran without production optimizations
- `rails assets:precompile` compiled assets in development mode
- Internal Rails setup commands assumed development environment

**Previous deploys worked by luck**, but were technically incorrect. The application ran, but with inadequate build configurations for production.

### Fix Applied

Added `RAILS_ENV` to `build-args` in all 32 workflows:

| Variable | Production Environments | Beta Environment |
|----------|------------------------|------------------|
| `RAILS_ENV` | `production` | `development` |

**Production environments:** atento, demo, shared
**Development environment:** beta

### Web Dockerfile Changes

For asset precompilation, Rails requires a secret key. Instead of passing a real secret (which would be baked into the image - security risk), we use Rails' built-in dummy mode:

```dockerfile
ARG RAILS_ENV=production
ARG SECRET_KEY_BASE_DUMMY=1

ENV RAILS_ENV=$RAILS_ENV
ENV SECRET_KEY_BASE_DUMMY=$SECRET_KEY_BASE_DUMMY
```

`SECRET_KEY_BASE_DUMMY=1` tells Rails to generate a temporary secret internally, just for the build. The real secret comes from ECS Task Definition at runtime.

**No GitHub secrets needed for build.** This is more secure than passing real secrets.

---

## Phase 6: Dockerfile Cleanup - Remove Unnecessary ENV (COMPLETED)

### Problem Found

Worker Dockerfiles had unnecessary ENV declarations at the end:

```dockerfile
ENV DIFFEND_PROJECT_ID=${DIFFEND_PROJECT_ID}
ENV DIFFEND_SHAREABLE_ID=${DIFFEND_SHAREABLE_ID}
ENV DIFFEND_SHAREABLE_KEY=${DIFFEND_SHAREABLE_KEY}
```

### Why This Was Wrong

DIFFEND is a security tool that checks gem vulnerabilities during `bundle install`. It runs **only once, during image build**.

**Build flow:**
1. `ARG DIFFEND_*` → Receives variables from workflow
2. `bundle install` → DIFFEND runs here, using ARGs
3. Build completes → DIFFEND never runs again

**After build, these variables serve no purpose.** The container at runtime doesn't run `bundle install` again.

### Build vs Runtime Variables

| Type | Where defined | When used | Example |
|------|---------------|-----------|---------|
| **Build** | Workflow (`build-args`) + Dockerfile (`ARG`) | During `docker build` | DIFFEND_*, RAILS_ENV, SECRET_KEY_BASE_DUMMY |
| **Runtime** | Task Definition (`env` + `secrets`) | When container starts | DATABASE_URL, REDIS_URL, SECRET_KEY_BASE |

### Fix Applied

Removed `ENV DIFFEND_*` from all 7 worker Dockerfiles. Now:
- `ARG DIFFEND_*` at the top (for build only)
- **No** `ENV DIFFEND_*` at the end
- Runtime variables come 100% from ECS Task Definition

---

## Phase 7: Fix Step Order and Remove Redundant Push (COMPLETED)

### Problems Found

**1. Redundant push:**
The `docker/build-push-action@v6` with `push: true` already pushes the image. Then there's a separate `docker push` step that does nothing useful.

**2. Incorrect step order:**
```
1. Build and Push Image  ← Push of NEW :latest happens HERE
2. Determine next version
3. Tag previous image    ← Tries to version, but :latest already overwritten!
4. Push latest image     ← Redundant
```

The "Tag previous image" step was in the wrong position. By the time it runs, the old `:latest` has already been overwritten.

### Planned Fix

**New order:**
```
1. Determine next version  ← Calculate v1, v2, v3, etc.
2. Build and Push Image    ← Push new :latest
3. Tag new image           ← Add version tag to NEW :latest
4. Register Task Definition
5. Deploy ECS
6. Wait service stable
```

**Why this works:**

Each deploy tags the new image with a version. On the next deploy, that image is already versioned.

```
Deploy 1: push :latest → tag v1 (v1 is preserved)
Deploy 2: push :latest → tag v2 (v1 and v2 preserved)
Deploy 3: push :latest → tag v3 (v1, v2, v3 preserved)
```

Tags are immutable. Even after overwriting `:latest`, tags `v1`, `v2`, `v3` continue pointing to their respective images.

### Changes Required

For all 32 workflows:
1. Move "Determine next version" step to BEFORE "Build and Push Image"
2. Rename "Tag previous image" to "Tag new image"
3. Remove redundant "Push latest image" step

### Files Affected

32 workflows (8 per environment × 4 environments)

---

## Phase 9: Web Dockerfile - Convert to Single-Stage (COMPLETED)

### Problem Identified

The web Dockerfile used multi-stage build:

```dockerfile
# Stage 1 (build)
FROM ruby:3.4.1 AS build
RUN apt-get install ... libpq-dev libxml2-dev ...  # System dependencies
RUN bundle install  # Compiles native extensions
RUN assets:precompile

# Stage 2 (final)
FROM ruby:3.4.1  # Clean image, NO system libs
COPY --from=build /app /app  # Only copies files, not apt packages
HEALTHCHECK ... CMD curl ...  # curl doesn't exist!
```

**Critical issues:**
1. Native gems (pg, nokogiri) compiled against libs in stage 1, but those libs don't exist in stage 2
2. At runtime, gems fail with `LoadError: cannot open shared object file`
3. HEALTHCHECK uses `curl`, but curl was only installed in stage 1

### Why Multi-Stage Was Used

Multi-stage builds have two benefits:
1. **Smaller image** (~200-300MB less) - no compilers, dev headers
2. **Security** - fewer tools available if container is compromised

### Why We Changed to Single-Stage

1. **Risk outweighs benefit** - forgetting a runtime dependency breaks production
2. **Workers already use single-stage** - inconsistent patterns across services
3. **Marginal security gain** - attacker with container access can download tools anyway
4. **Simpler maintenance** - one place for dependencies, no duplication

### Fix Applied

Converted web Dockerfile to single-stage (same pattern as workers):

**Before:** 75 lines, 2 stages
**After:** 62 lines, 1 stage

All dependencies installed once, stay in final image. No `COPY --from=build` needed.

---

## Phase 10: PR This Branch (READY)

### Summary of Changes

**41 files changed:**
- 8 Dockerfiles in `.github/docker/`
- 32 workflow files in `.github/workflows/` (+ 4 orchestrators unchanged)

**Key improvements:**
1. Standardized naming: `{env}-001-{service}`
2. Web runs Puma directly (removed nginx/supervisor)
3. Workers don't install JS dependencies (Ruby only)
4. Yarn install fails build on error (was silently ignored)
5. Correct step order in all workflows
6. **RAILS_ENV passed during build** (critical fix for production mode)
7. **SECRET_KEY_BASE_DUMMY=1 for asset precompilation** (no secrets in build - security fix)
8. **Removed unnecessary ENV DIFFEND_* from worker Dockerfiles** (build-only variables shouldn't be ENV)
9. **Removed redundant "Push latest image" step** (docker/build-push-action already pushes)
10. **Renamed "Tag previous image" to "Tag new image"** (clarifies the actual behavior)
11. **Converted web Dockerfile to single-stage** (fixes runtime dependency issue)

---

## Checklist for Infrastructure Team (AWS)

### Before First Deploy

- [ ] **Verify/update stopTimeout for ALL worker Task Definitions**
  - Recommended: 300 seconds (5 minutes)
  - Critical for: worker-commission, worker-migration (long jobs)

- [ ] **Verify deployment configuration for ALL ECS Services**
  - `minimumHealthyPercent`: 100%
  - `maximumPercent`: 200%
  - `deploymentCircuitBreaker`: enabled with rollback

- [ ] **Verify ALB health check for web service**
  - Path: `/health`
  - Port: 3000 (changed from 80)
  - Ensure ALB target group points to port 3000

### Testing Graceful Shutdown

- [ ] **Test web graceful shutdown**
  - Deploy new version while requests are in-flight
  - Verify no 502/503 errors during deploy

- [ ] **Test worker graceful shutdown**
  - Start a long-running job
  - Deploy new version
  - Verify job completes (or re-enqueues) without data corruption

### Monitoring

- [ ] **Set up CloudWatch alarms for:**
  - ECS deployment failures
  - Task stopped with SIGKILL (indicates stopTimeout too low)
  - Unhealthy task count during deployments

---

## Phase 11: Security Review Decisions (COMPLETED)

External security review identified 8 points. Here are our decisions:

### Point 1: Secrets going into the build and image (VERY SERIOUS)

**Problem:** `SECRET_KEY_BASE` and `DIFFEND_*` being passed as build-args can be extracted from the image.

**Decision:**
- `SECRET_KEY_BASE`: **FIXED** - Not passed to build. We use `SECRET_KEY_BASE_DUMMY=1` for asset precompilation. Real secret comes from ECS Task Definition at runtime.
- `DIFFEND_*`: **ACCEPTABLE** - Required during `bundle install` to check gem vulnerabilities. Variables are `ARG` only (not `ENV`), so they are NOT baked into the final image layers.

### Point 2: Beta with RAILS_ENV=development but bundler "without development test"

**Problem:** Inconsistent - development environment but excluding development gems.

**Decision:** **FIXED**
- Changed beta workflows to use `BUNDLE_WITHOUT=test` (not "development test")
- Now beta keeps development gems, consistent with `RAILS_ENV=development`

| Environment | RAILS_ENV | BUNDLE_WITHOUT |
|-------------|-----------|----------------|
| atento/demo/shared | production | development test |
| beta | development | test |

### Point 3: jq del(.runtimePlatform...) can break

**Problem:** If `runtimePlatform` doesn't exist in task definition JSON, jq fails.

**Decision:** **FIXED**
- Added optional operator `?` to jq queries
- `.runtimePlatform.cpuArchitecture?` and `.runtimePlatform.operatingSystemFamily?`
- Now safe even if runtimePlatform doesn't exist

### Point 4: Orchestrator fires everything in parallel, no order

**Problem:** Web and workers deploy simultaneously. If there's a schema change, this can cause issues.

**Decision:** **DEFERRED**
- To be addressed with infrastructure partner (rolling deployment / CodeDeploy)
- Requires Blue/Green deployment configuration
- Documented in client document for Phase 2

### Point 5: Image versioning has race condition

**Problem:** If two deploys run simultaneously, they may choose the same vN tag.

**Decision:** **ACCEPTED**
- Not a critical issue if deploys don't run in parallel
- Versioning is for convenience, not mandatory audit trail
- User should wait for one build to finish before starting another

### Point 6: Task definition always changes .containerDefinitions[0].image

**Problem:** Assumes target container is always index 0. Fails with sidecars.

**Decision:** **FIXED**
- Changed to select container by name
- Old: `jq '.containerDefinitions[0].image = $IMAGE'`
- New: `jq '(.containerDefinitions[] | select(.name == $NAME)).image = $IMAGE'`

### Point 7: Healthchecks

**Problem:** Health checks might not work if:
- Web: `/health` route doesn't exist
- Workers: `tmp/sidekiq_ready.txt` file isn't created

**Decision:** **VERIFIED - OK**
- Web: `/health` route exists (`app/controllers/health_controller.rb`)
- Workers: Sidekiq initializer already creates file on startup and removes on shutdown (`config/initializers/sidekiq.rb` lines 29-35)

### Point 8: Node/Yarn installed via apt + npm global

**Problem:** Old node version from apt, potential inconsistencies.

**Decision:** **FIXED**
- Application uses Propshaft + Importmap-rails (no Node bundling needed)
- Removed Node.js entirely from web Dockerfile
- Deleted: `package.json`, `yarn.lock`, `.node-version`, `bin/yarn`
- Updated: CI workflow, installation scripts, documentation

---

## Phase 12: Worker Dockerfile Unification (COMPLETED)

### Problem

7 identical worker Dockerfiles differing only by CMD (sidekiq config file).

### Solution

Created unified worker Dockerfile with `ARG SIDEKIQ_CONFIG`:

```dockerfile
ARG SIDEKIQ_CONFIG
CMD ["sh", "-c", "bundle exec sidekiq -C config/${SIDEKIQ_CONFIG}"]
```

### Changes

- Created `.github/docker/worker/Dockerfile` with SIDEKIQ_CONFIG parameter
- Updated all 28 worker workflows to:
  - Use `directory: ./.github/docker/worker`
  - Pass `sidekiq_config: sidekiq_{type}.yml`
  - Add `SIDEKIQ_CONFIG=${{ matrix.service.sidekiq_config }}` to build-args
- Removed 7 old Dockerfile directories

### Result

- 35 files changed
- Net reduction of 225 lines (86 additions, 311 deletions)
- Single source of truth for worker container configuration

---

## Phase 13: Semantic Versioning for Docker Images (COMPLETED)

### Problem

The previous versioning system had issues:

1. **Race condition:** If two deploys ran simultaneously, both could choose the same `vN` tag
2. **No traceability:** Tags like `v1`, `v2`, `v3` don't tell you which commit/version they correspond to
3. **ECR dependency:** Had to query ECR to determine next version number

### Solution

Implemented semantic versioning using `VERSION-SHA` format:

1. **Created `config/version.rb`** - Single source of truth for application version
2. **Tag format:** `{VERSION}-{SHORT_SHA}` (e.g., `3.5.0-abc1234`)
3. **Always push two tags:** `:latest` and `:VERSION-SHA`

### How It Works

```yaml
- name: Determine version
  run: |
    VERSION=$(grep "VERSION = " config/version.rb | cut -d"'" -f2)
    SHORT_SHA=$(git rev-parse --short=7 HEAD)
    IMAGE_TAG="${VERSION}-${SHORT_SHA}"
    echo "IMAGE_TAG=$IMAGE_TAG" >> $GITHUB_ENV

- name: Build and Push Image
  uses: docker/build-push-action@v6
  with:
    tags: |
      ${{ matrix.service.ecr_repo }}:latest
      ${{ matrix.service.ecr_repo }}:${{ env.IMAGE_TAG }}
```

### Benefits

| Aspect | Before | After |
|--------|--------|-------|
| Tag format | `v1`, `v2`, `v3` | `3.5.0-abc1234` |
| Traceability | None | Version + commit SHA |
| Race condition | Possible | Impossible (SHA is unique) |
| ECR query needed | Yes | No |
| Rollback | Find vN tag | Find by version or SHA |

### config/version.rb

```ruby
# frozen_string_literal: true

module FourShark
  VERSION = '3.5.0'
end
```

This file follows the same pattern as the `integrator` project. Version is updated manually when releasing new versions.

### Changes Made

1. Created `config/version.rb` with `FourShark::VERSION = '3.5.0'`
2. Updated all 32 workflows to use new versioning:
   - Added "Determine version" step reading from `config/version.rb`
   - Modified tags to use `:latest` and `:${{ env.IMAGE_TAG }}`
   - Removed "Determine next version" step (consulted ECR)
   - Removed "Tag new image" step (no longer needed)

### Rollback Procedure

To rollback to a specific version:

```bash
# Find available versions
aws ecr describe-images --repository-name {repo} \
  --query 'imageDetails[*].imageTags' --output table

# Rollback by updating task definition with specific tag
# e.g., 3.5.0-abc1234 instead of :latest
```

---

## Phase 14: GitHub Actions Update (COMPLETED)

### Changes

Updated all GitHub Actions to latest versions:

| Action | Before | After |
|--------|--------|-------|
| `actions/checkout` | v3 | v4 |
| `aws-actions/configure-aws-credentials` | v2 | v4 |

Updated across all 32 workflow files.

---

## References

- [Graceful shutdowns with ECS | AWS](https://aws.amazon.com/blogs/containers/graceful-shutdowns-with-ecs/)
- [Sidekiq Graceful Shutdown in Fargate ECS](https://hsps.in/post/sidekiq-graceful-shutdown-in-fargate-ecs/)
- [Set up graceful shutdown for ECS | AWS re:Post](https://repost.aws/knowledge-center/ecs-graceful-shutdown-connection-draining-deployments)
- [Sidekiq Signals](https://github.com/sidekiq/sidekiq/wiki/Signals)
