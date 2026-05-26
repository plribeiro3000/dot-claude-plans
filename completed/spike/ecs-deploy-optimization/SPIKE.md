# SPIKE — ECS Deploy Optimization

**Conducted by:** Paulo Ribeiro
**Date:** 2026-02-19
**Status:** Research complete — pending implementation decisions

---

## Goal

Determine whether 4Shark's ~10 minute ECS deploy time can be significantly reduced, and identify which optimizations would have the highest impact based on community experience and AWS best practices.

---

## Method

- Measured current deploy breakdown (infrastructure overhead vs code execution)
- Researched community benchmarks from Scribd, Grammarly, Plaid, and AWS container heroes
- Reviewed AWS documentation on ECS task optimization and new native blue/green feature
- Compared 4Shark's current setup against community best practices checklist
- Evaluated alternative approaches (Kamal, Docker slim images, migration skipping)

---

## Evidence

### Current State (4Shark)

- **Total deploy time:** ~10 minutes (blue/green + migration + sidekiq)
- **Infrastructure overhead:** ~6-7 min (ECS scheduling, health checks, rolling updates)
- **Actual code execution:** ~3-4 min
- **Strategy:** Blue/green via CodeDeploy (web) + rolling update (sidekiq workers)
- **Already optimized:** Docker HEALTHCHECK interval=10s start-period=15s, tini init, quiet mode via TSTP, unified Dockerfile

### Community Benchmarks

| Source | Before | After | Context |
|--------|--------|-------|---------|
| Scribd (~500 tasks Fargate) | ~40 min | <20 min | Adjusted timers, skip unnecessary migrations |
| Nathan Peck (AWS container hero) | - | 2-5 min | Simple services, optimized timers |
| Community average (unoptimized) | 15-40 min | - | Default ECS/ALB settings |
| Community average (optimized) | - | 5-15 min | Tuned timers + health checks |
| **4Shark (current)** | - | **~10 min** | Blue/green + migration + 3 sidekiq workers |

### Fargate Task Startup

- Single task boot: 30-45 seconds
- Scale rate: ~23 containers/minute
- 100+ containers: ~4-7 minutes

### Biggest Time Wasters (Community Consensus)

**1. ALB Deregistration Delay (Default: 300s / 5 min!)**

The #1 villain. Most teams don't know this timer exists.

| Setting | Default | Recommended |
|---------|---------|-------------|
| Deregistration delay | 300s (5 min) | 5-30s |
| Health check interval | 30s | 5s |
| Healthy threshold count | 5 | 2 |
| Container stop timeout | 30s | 2-5s |

**2. Unnecessary Migration Runs**

Scribd saved 3 minutes per deploy by detecting via git diff whether new migration files exist before running `db:migrate`.

**3. Docker Image Size**

- Full Ruby image: ~1GB
- Slim Ruby image: ~219MB
- Optimized Rails app: 345-600MB
- Scribd reported that moderate reductions (900MB → 700MB) had no significant impact. Must be drastic (1GB → 100MB) to matter.

### ECS Native Blue/Green (July 2025)

AWS launched built-in blue/green deployments in ECS without CodeDeploy:
- Deployment lifecycle hooks for custom validation
- No additional cost (pay only for compute during deploy)
- Available in all commercial regions
- Simpler than CodeDeploy (no AppSpec, no deployment groups)

### Best Practices Comparison

**Already Implemented at 4Shark:**
- [x] tini as init process (correct signal handling for Sidekiq)
- [x] Sidekiq as separate ECS service
- [x] TSTP signal before deploy (quiet mode)
- [x] Asset precompilation in Docker build
- [x] Docker HEALTHCHECK with optimized intervals
- [x] Unified Dockerfile (single image for web + workers)
- [x] Pre-built images (build decoupled from deploy)

**Not Yet Evaluated:**
- [ ] ALB deregistration delay (check current value)
- [ ] ALB health check interval and thresholds (check current value)
- [ ] Container stop timeout (check current value)
- [ ] Skip migration when no new migration files exist
- [ ] Docker slim base image + multi-stage build
- [ ] ECS native blue/green (replace CodeDeploy)
- [ ] ECR repo consolidation (18 → 1) — already planned as item 16

**Community Recommendations (Low Priority):**
- [ ] Backward-compatible migrations (already required by blue/green)
- [ ] Sidekiq job interruption handling (`Sidekiq::Job#interrupted?`)

### Sidekiq Graceful Shutdown Notes

- ECS sends SIGTERM to PID 1
- If entrypoint uses `sh -c`, shell ignores SIGTERM and doesn't forward to Sidekiq
- Solution: use `exec` in entrypoint script or `tini` as init process (we use tini)
- Jobs longer than 25 seconds (Sidekiq default timeout) need `Sidekiq::Job#interrupted?` or Iteration pattern

### Kamal (Alternative to ECS)

- Default in Rails 8. Direct deploy to VMs via Docker, no orchestrator.
- Zero-downtime with rolling restarts. Simpler than ECS.
- Smaller teams are migrating from ECS to Kamal to reduce complexity.
- **Not relevant for 4Shark** — our infrastructure is already on ECS and the complexity is justified by the scale.

---

## Conclusions

- 4Shark's deploy time (~10 min) is within the optimized community average (5-15 min)
- The biggest potential gain is in ALB/ECS timers (deregistration delay, health check intervals) — these are the #1 time waster per community consensus and their current values at 4Shark are unknown
- Migration skipping could save ~3 min on deploys without schema changes
- Docker image slimming has low ROI unless the reduction is drastic (>50%)
- ECS native blue/green is worth evaluating as a simplification over CodeDeploy
- Kamal is not relevant for 4Shark's scale

---

## Next Steps

1. **Check current ALB/ECS timer values** across all environments — this is the highest-impact, lowest-risk investigation
2. **Evaluate ECS native blue/green** as a replacement for CodeDeploy — simplification opportunity
3. **Consider migration detection** in deploy workflow — moderate impact, low complexity
4. **Docker slim image** — only pursue if current image is >800MB

---

## Sources

### Key Technical Articles
- [Speeding up Amazon ECS container deployments - Nathan Peck](https://nathanpeck.com/speeding-up-amazon-ecs-container-deployments/)
- [Speeding up ECS Fargate deployments - Scribd Engineering](https://tech.scribd.com/blog/2021/faster-fargate-deploys.html)
- [Perfecting smooth rolling updates in ECS - Grammarly Engineering](https://medium.com/engineering-at-grammarly/perfecting-smooth-rolling-updates-in-amazon-elastic-container-service-690d1aeb44cc)
- [How we reduced deployment times by 95% - Plaid](https://plaid.com/blog/how-we-reduced-deployment-times-by-95/)

### Rails + ECS Tutorials
- [Deploying Rails with Docker and AWS Fargate - Honeybadger](https://www.honeybadger.io/blog/rails-docker-aws-fargate/)
- [Deploying Rails app with Amazon ECS - The Codest](https://thecodest.co/blog/deploying-rails-app-with-amazon-ecs/)
- [Rails + Sidekiq + Docker for AWS ECS - Salzam](https://salzam.com/rails-sidekiq-docker-application-for-aws-ecs-ecr-rds-codepipeline-and-more-complete-series/)

### AWS Documentation
- [Optimize Amazon ECS task launch time](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-recommendations.html)
- [ECS Blue/Green deployments with CodeDeploy](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-bluegreen.html)
- [Built-in blue/green deployments in ECS (Jul 2025)](https://aws.amazon.com/about-aws/whats-new/2025/07/amazon-ecs-built-in-blue-green-deployments/)
- [Choosing between ECS native vs CodeDeploy blue/green](https://aws.amazon.com/blogs/devops/choosing-between-amazon-ecs-blue-green-native-or-aws-codedeploy-in-aws-cdk/)

### Sidekiq + ECS
- [Sidekiq Graceful Shutdown in Fargate ECS](https://hsps.in/post/sidekiq-graceful-shutdown-in-fargate-ecs/)
- [Sidekiq Deployment Wiki](https://github.com/sidekiq/sidekiq/wiki/Deployment)

### Community Discussions
- [ECS task provisioning speed - AWS re:Post](https://repost.aws/questions/QUjZAzJd27SZWxXM7MgyxOZw/how-to-speed-up-provisioning-of-ecs-fargate-task)
- [ECS Deploy taking incredibly long - GitHub Issue](https://github.com/aws-actions/amazon-ecs-deploy-task-definition/issues/102)
- [Slow ECS rollout - AWS re:Post](https://repost.aws/questions/QUtuJWfRoeTuK6AKIIFPOSjA/the-rollout-update-of-new-ecs-service-version-is-slow)

### Docker Optimization
- [Rails Dockerfile Best Practices - Image Slimming](https://igor.works/blog/rails-dockerfile-best-practices-part-1-image-slimming)
- [Optimize Docker images for Rails - BetterDoc](https://dev.betterdoc.org/infrastructure/2020/02/17/optimize-docker-images-for-ruby-on-rails-applications.html)
- [Dockerfile: Shrinking from 1.6GB to 600MB - Rails GitHub Issue](https://github.com/rails/rails/issues/46855)
