# PLAN — Add Terramate Orchestration

## Status: COMPLETED

**Branch**: `feature/terramate-orchestration`
**PR**: https://github.com/4shark/terraform/pull/196
**Commit**: `feat(orchestration): add Terramate stack definitions for all root modules`

## What was done

Added Terramate orchestration layer on top of existing Terraform code. 17 new `.tm.hcl` files + CHANGELOG update. Zero changes to existing `.tf` files.

### Files created

- `terramate.tm.hcl` — Root config (git change detection against `origin/develop`)
- 16 `stack.tm.hcl` — One per root module (shared-resources, vpn, auth-001, 6 integrators, app-atento-br, 4 app-*-001, setup, dns)

### Tags scheme

- `aws`, `cloudflare`, `mongodbatlas`, `rediscloud` — providers
- `sa-east-1`, `us-east-1` — AWS regions
- `integrator`, `app`, `infra` — stack type

### Dependencies

- `shared-resources` runs first (no deps)
- `app-*-001` and `setup` run after `shared-resources`
- `dns` runs last (after integrators, vpn, app-atento-br)
- All others are independent

### Verification

All tests passed:
- `terramate list` — 16 stacks detected
- `terramate list --run-order` — correct dependency order
- `terramate list --tags` — all filters working
- `terramate list --changed` — change detection operational
- `terramate run -- terraform init -backend=false` — all 16 stacks initialized successfully
