# Plan: Setup app changes for ECS migration

## Context

The setup project needs changes to support ECS deployment (steps 16-17 from the unified plan). The terraform infrastructure is ready on `feature/setup-ecs-infrastructure`. Now we need the app-side changes in the `setup` repository.

## Scope

3 workstreams in the `setup` repository:

### 1. `bin/ecs` CLI tool (simplified from app)

**File**: `setup/bin/ecs`

Only the `connect` subcommand. No `run` (no runner capacity provider), no `cleanup`.

Hardcoded values (no parameters needed):
- Environment: `setup`
- Cluster: `setup-cluster`
- Service: `setup-web-service`
- Container: `setup-web`

Usage:
```
bin/ecs connect           # rails console on a running task
bin/ecs connect bash      # bash on a running task
```

When multiple tasks exist, shows a numbered list for selection (same as app).

### 2. Health check endpoint

**New file**: `setup/app/controllers/health_controller.rb`
- Inherits from `ApplicationController`
- `skip_before_action :verify_authenticity_token`
- JSON: `{ status: 'healthy' }`, HTML: `<p>healthy</p>`
- Pattern copied from app project

**New file**: `setup/app/views/health/show.html.erb`
- Simple `<p>healthy</p>`

**Modified file**: `setup/config/routes.rb`
- Add `resource :health, only: :show, controller: :health` after root

### 3. Dockerfile + version

**New file**: `setup/.github/docker/web/Dockerfile`
- Based on app's Dockerfile, simplified:
  - No graphicsmagick, graphviz, libmagickwand-dev
  - No assets:precompile (Tailwind via CDN)
- Ruby 3.4.1, bundler 2.7.1, puma

**New file**: `setup/config/version.rb`
- Required by deploy-ecs action (`grep "VERSION = " config/version.rb`)
- `Setup::VERSION = '1.0.0'`

## Files

| Action | Path |
|--------|------|
| Create | `bin/ecs` |
| Create | `app/controllers/health_controller.rb` |
| Create | `app/views/health/show.html.erb` |
| Modify | `config/routes.rb` |
| Create | `.github/docker/web/Dockerfile` |
| Create | `config/version.rb` |

## Verification

1. `bin/ecs` — check it's executable, `bin/ecs` with no args shows usage
2. Health endpoint — `bin/rails routes | grep health` shows the route
3. Dockerfile — `docker build -f .github/docker/web/Dockerfile .` builds
4. Version — `ruby -e "require './config/version'; puts Setup::VERSION"` outputs 1.0.0
