# Deploy Pipeline Optimization

## Status

**Complete.** Phase 1 and Phase 2 both delivered.

---

## Completed

### Phase 1: Separate Build from Deploy + Quick Wins

- Docker HEALTHCHECK optimized: `interval=10s`, `start-period=15s` (PR #4824)
- Sidekiq quiet mode `sleep 30` removed (PR #4824)
- `build-image` reusable workflow created (PR #4825)
- `deploy-ecs` action refactored to require pre-built images, no build fallback (PR #4827)
- 4 deploy workflows refactored (PR #4827)
- Tested on Beta-001 and Demo-001

### Phase 2: Unified Image + ECR Consolidation

- Unified Dockerfile created (graphviz + tini + assets:precompile, no CMD) (PR #4830)
- ECS task definitions use `command` override instead of baked-in CMD (PR #4830)
- ECR repos consolidated from 32 to 4 (1 per environment: `{env}-app`) (App PR #4831, Terraform PRs #157 + #158)
- All CI build + deploy workflows updated
- Validated on all 4 environments

---

### Future: Fargate Migration for Workers (separate project)

- Eliminates ASG overhead entirely (currently 2-8 min per deploy)
- Workers scale in seconds instead of minutes
- **Only viable path to < 5min deploys for all environments**

---

## Constraint: ASG Scaling During Deploy

ASG overhead (2-8 min) is a hard constraint. ECS managed autoscaling has a 15-minute cooldown incompatible with burst-based Lambda scaling. The only solution is Fargate migration (separate project).

---

## References

### Workflows
- `.github/workflows/deploy-{atento,beta,demo,shared}-001.yaml`
- `.github/workflows/build-image.yaml`

### Actions
- `.github/actions/deploy-ecs/action.yaml`

### Dockerfiles
- `Dockerfile` (unified, root of repo)

### Study Data
- `KNOWLEDGE.md` — Per-step timing, Dockerfile analysis, ECR repo inventory
