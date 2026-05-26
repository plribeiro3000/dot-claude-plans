# ECS Deploy Optimization

**Based on:** SPIKE.md (completed spike at `~/.claude/plans/completed/spike/ecs-deploy-optimization/`)
**Status:** Not started — pending investigation of current values

---

## Overview

Optimize ECS deploy time (~10 min currently). The spike research concluded that the deploy is within the optimized community average (5-15 min), but there are potential gains in ALB/ECS timer tuning that haven't been evaluated yet.

---

## Phases

### Phase 1: Investigate Current Timer Values

Check current values across all environments:
- [ ] ALB deregistration delay (default 300s — the #1 time waster)
- [ ] ALB health check interval and thresholds
- [ ] ECS container stop timeout

This is the highest-impact, lowest-risk investigation. If deregistration delay is at 300s (default), reducing it to 5-30s could save minutes per deploy.

### Phase 2: Tune ALB/ECS Timers

Based on Phase 1 findings, update Terraform configs:

| Setting | Default | Recommended |
|---------|---------|-------------|
| Deregistration delay | 300s | 5-30s |
| Health check interval | 30s | 5s |
| Healthy threshold count | 5 | 2 |
| Container stop timeout | 30s | 2-5s |

### Phase 3: Evaluate ECS Native Blue/Green

AWS launched built-in blue/green deployments in ECS (July 2025) without CodeDeploy:
- Simpler than CodeDeploy (no AppSpec, no deployment groups)
- No additional cost
- Deployment lifecycle hooks for custom validation

Evaluate as a replacement for current CodeDeploy-based blue/green.

### Phase 4: Migration Detection (Optional)

Skip `db:migrate` when no new migration files exist (detected via git diff). Scribd reported ~3 min savings per deploy with this approach.

---

## Out of Scope

- **Docker slim images** — Low ROI unless current image is >800MB
- **Kamal migration** — Not relevant for 4Shark's scale on ECS
