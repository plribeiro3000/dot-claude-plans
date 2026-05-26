# PLAN - User Authentication and Management

> Reference: Standard workflow (no DDD documents)

## Objective

Set up a Rails application from scratch with Devise-based authentication supporting two user roles (admin and client), where administrators can invite new users via email and all users can reset their passwords.

## Scope

### In Scope

- New Rails application setup (project directory is currently empty)
- Devise installation and configuration (database_authenticatable, registerable, recoverable, rememberable, validatable)
- devise_invitable installation and configuration for admin-initiated user invitations
- User model with role distinction (admin vs client) using an enum
- Admin-only user listing and invitation interface
- Password reset flow for all users via email
- Role-based access control enforced at the controller level
- Standard Rails views (ERB)
- Basic email configuration using Action Mailer

### Out of Scope

- OAuth or third-party authentication (Google, GitHub, etc.)
- Two-factor authentication (2FA)
- Session management beyond Devise defaults
- API authentication (tokens, JWT)
- User profile editing beyond password management
- Audit logging of user actions
- Soft delete / deactivation of user accounts
- Any frontend JavaScript framework (React, Vue, Angular)
- Automated test suite (can be added in a follow-up)

## Inherited Engineering Standards (from `app`)

The following patterns are established in the `app` project and must be replicated in `onboarding` from day one. They are not optional — they define how 4Shark Rails projects are structured.

### `lib/application_configuration.rb`

Centralized ENV access. **No direct `ENV[]` or `ENV.fetch` anywhere else in the codebase.** Every configuration value goes through this class. For `onboarding`, it covers:

- `puma_threads` — min/max threads for Puma
- `puma_workers` — number of Puma workers (reads `WEB_CONCURRENCY`)
- `puma_port` — port (reads `PORT`)
- `puma_worker_shutdown_timeout` — reads `PUMA_WORKER_SHUTDOWN_TIMEOUT`
- `rails_environment` — reads `RAILS_ENV`
- SMTP settings (host, port, username, password, domain) — used in `production.rb`
- `app_host` — used in Action Mailer URL generation

### `config/puma.rb`

Reads all settings from `ApplicationConfiguration`, not from `ENV` directly. Key behaviors:
- `threads` set to same min/max value via `ApplicationConfiguration.puma_threads`
- `port` from `ApplicationConfiguration.puma_port`
- `workers` from `ApplicationConfiguration.puma_workers`
- `preload_app!` for Copy-on-Write memory efficiency
- `before_worker_boot` to reconnect ActiveRecord after fork
- `plugin :tmp_restart` for `rails restart`
- `log_requests` (no argument, same as app)
- Same variable names as `app`: `WEB_MAX_THREADS`, `WEB_CONCURRENCY`, `PORT`, `PUMA_WORKER_SHUTDOWN_TIMEOUT`

### `config/database.yml`

- Uses `ApplicationConfiguration` for pool size
- `pool` tied to `ApplicationConfiguration.puma_threads` — connection pool never smaller than Puma concurrency
- `prepared_statements: false` — safe default (compatible with PgBouncer if added later)
- Explicit `connect_timeout` and `checkout_timeout`

### `bin/` Scripts

| Script | Purpose |
|--------|---------|
| `bin/setup` | First-time setup: bundle, db:prepare, clear tmp. Boots server unless `--skip-server`. |
| `bin/dev` | Starts the Rails development server (single entry point). |
| `bin/databases` | Uses Foreman + `Procfile.dev.databases` to start only PostgreSQL. |
| `bin/update` | `bundle install && rails db:migrate` — keeps env up to date. |
| `bin/rubocop` | Runs RuboCop with explicit `--config .rubocop.yml` (avoids parent-dir config confusion). |

All `bin/` scripts that use dotenv do `touch "$(pwd)/.env.local"` before invoking Foreman/server, ensuring the file exists.

### `Procfile.dev.databases`

Starts only the services needed in development without running the web server. For `onboarding` (PostgreSQL only):

```
postgres: ${PG_SERVICE}
```

`PG_SERVICE` is defined in `.env.local` per developer (e.g., `pg_ctl start -D /opt/homebrew/var/postgresql@17` or a Docker command). This avoids hardcoding service startup commands that differ per machine.

### `.env` + `.env.local`

Replicates the `app` project pattern:

- **`.env`** — committed to git. Contains non-sensitive defaults that work for every developer out of the box (service names, feature flags, local URLs). Example:
  ```
  PG_SERVICE=postgres -D /usr/local/var/postgresql@17
  APP_HOST=localhost
  ```
- **`.env.local`** — gitignored, personal overrides per developer (e.g., different Postgres path, local SMTP config). Created automatically by `bin/databases` and `bin/dev` via `touch .env.local`.

### `config/initializers/`

| Initializer | Purpose |
|-------------|---------|
| `schema_dumping.rb` | Only regenerates `schema.rb` when there are new migrations (detected via `git status db/migrate/`). Avoids noise in diffs. |
| `filter_parameter_logging.rb` | Extended list of filtered params: `passw email secret token _key crypt salt certificate otp ssn`. |

### `config/environments/` Notable Settings

**`development.rb`**:
- `active_record.query_log_tags_enabled = true` — shows query origin in logs
- `disallowed_deprecation = :raise` — catches deprecations early

**`test.rb`**:
- `config.eager_load = ENV['CI'].present?` — speeds up local test runs, still eager-loads in CI

**`production.rb`**:
- `config.force_ssl = true`
- `config.silence_healthcheck_path = '/up'` — suppresses health check log noise

### Gemfile Conventions

- `# frozen_string_literal: true` at the top
- `require_relative 'lib/application_configuration'` before gems that need it
- Groups: main (production), `:development, :test`, `:test`, `:development`, `:production`
- `letter_opener` in `:development` only (never in `:test` or production)

---

## Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Role implementation | `role` enum on User model | Simple, no extra table, sufficient for two roles. A separate Role model adds complexity not justified by the current scope. |
| Devise modules | `database_authenticatable`, `recoverable`, `rememberable`, `validatable`, `invitable` | Minimal set that covers all stated requirements. `registerable` is excluded because self-registration is not a requirement — only admins can create accounts. |
| Invitation gem | `devise_invitable` | Maintained, well-integrated with Devise, handles the full invite flow (token generation, email, password setup). |
| Access control | `before_action` in ApplicationController + helpers | No authorization gem (CanCanCan, Pundit) is needed for two roles and a simple rule: admins see everything, clients see only their own data. Keeps the stack minimal. |
| Founding admin seeding | `db/seeds.rb` with hardcoded emails + `User.invite!` | There are exactly 3 known founding admins (Paulo, Danilo, Sérgio). Hardcoding their emails in seeds is the right call — ENV vars would be indirection for no reason. `invite!` sends each person an email to set their own password; no shared temporary credentials are ever created. |
| Rails version | Latest stable (Rails 7.x) | No constraint specified; use current stable. |
| Database | PostgreSQL | Standard for 4Shark projects; more robust than SQLite for a user-facing application. |

## Execution Phases

### Phase 1: Application Bootstrap

**Objective**: Create the Rails application with the required dependencies declared and all 4Shark engineering standards applied from day one.

**Components**:
- New Rails app generated at `/Users/plribeiro3000/Projects/4Shark/onboarding`
- `Gemfile` with `devise`, `devise_invitable`, `letter_opener`, `foreman` — organized by group, `frozen_string_literal: true` at top
- Database configured for PostgreSQL
- Git repository initialized with `.gitignore`
- `lib/application_configuration.rb` — centralizes all ENV access (puma threads, SMTP)
- `config/puma.rb` — reads from `ApplicationConfiguration`, `preload_app!`, `before_worker_boot`, `plugin :tmp_restart`
- `config/database.yml` — pool tied to `ApplicationConfiguration.puma_threads`, `prepared_statements: false`, explicit timeouts
- `Procfile.dev.databases` — starts only PostgreSQL via `${PG_SERVICE}`
- `bin/setup`, `bin/dev`, `bin/databases`, `bin/update`, `bin/rubocop` — all copied/adapted from `app`
- `.env` — committed, non-sensitive defaults (PG_SERVICE, APP_HOST, feature flags)
- `.env.local` — gitignored, personal overrides (auto-created by bin scripts)
- `config/initializers/schema_dumping.rb` — conditional schema dump via git status
- `config/initializers/filter_parameter_logging.rb` — extended sensitive param list
- `config/environments/development.rb` — `query_log_tags_enabled`, `disallowed_deprecation: :raise`
- `config/environments/test.rb` — `eager_load = ENV['CI'].present?`
- `config/environments/production.rb` — `force_ssl`, `silence_healthcheck_path: '/up'`, SMTP from `ApplicationConfiguration`

**Dependencies**: None — this is the starting point.

**Success Criteria**:
- [ ] `rails new` completes without errors
- [ ] `bundle install` succeeds with Devise and devise_invitable present
- [ ] `bin/setup` runs without errors (bundle + db:prepare)
- [ ] `bin/databases` starts PostgreSQL via Foreman
- [ ] `bin/dev` boots the Rails server
- [ ] `rails db:create` creates the development and test databases
- [ ] Application boots with `rails server`
- [ ] No `ENV[]` or `ENV.fetch` calls outside `lib/application_configuration.rb`
- [ ] `.env` committed with non-sensitive defaults; `.env.local` in `.gitignore`

### Phase 2: Devise Setup and User Model

**Objective**: Install Devise, generate the User model with role support, and run all migrations.

**Components**:
- Devise initializer generated (`rails generate devise:install`)
- User model generated via Devise (`rails generate devise User`)
- `role` enum column added to users table (values: `admin`, `client`; default: `client`)
- `invited_by` association on User (provided by devise_invitable migration)
- Devise views generated (`rails generate devise:views`) for customization

**Dependencies**: Phase 1 complete.

**Success Criteria**:
- [ ] `rails db:migrate` runs cleanly with all Devise and devise_invitable migrations
- [ ] `User.new.role` returns `"client"` by default
- [ ] `User.roles` returns the correct enum hash
- [ ] `User#admin?` and `User#client?` predicate methods work

### Phase 3: Action Mailer and Email Configuration

**Objective**: Configure Action Mailer so Devise can send invitation and password reset emails.

**Components**:
- `config/environments/development.rb` configured with `letter_opener` gem (or `mailcatcher`) for local email preview
- `config/environments/production.rb` prepared with SMTP placeholders (no hardcoded credentials)
- `default_url_options` set for each environment
- Devise `mailer_sender` configured in `config/initializers/devise.rb`

**Dependencies**: Phase 2 complete.

**Success Criteria**:
- [ ] Password reset email is delivered (visible in letter_opener or mailcatcher) in development
- [ ] Invitation email is delivered in development
- [ ] No credentials are hardcoded in any config file

### Phase 4: Access Control

**Objective**: Enforce role-based restrictions so only admins can access the user management area.

**Components**:
- `authenticate_user!` before_action in `ApplicationController`
- `require_admin!` helper method in `ApplicationController`, redirecting non-admins with a flash message
- `Admin::UsersController` (namespaced) — inherits admin restriction at the controller level
- Routes namespaced under `/admin`

**Dependencies**: Phase 2 complete.

**Success Criteria**:
- [ ] Unauthenticated request to any protected route redirects to sign-in
- [ ] Authenticated client visiting `/admin/users` is redirected with an error message
- [ ] Authenticated admin can access `/admin/users`

### Phase 5: Admin User Management Interface

**Objective**: Build the interface where admins list users and send invitations.

**Components**:
- `Admin::UsersController` with `index` and `create` actions
- `index` view: table listing all users (name, email, role, invitation status)
- `new` / `create` flow: form to enter email and role, triggers `User.invite!` from devise_invitable
- Flash messages for success and failure cases
- `db/seeds.rb` with hardcoded founding admin accounts (Paulo, Danilo, Sérgio) — uses `User.invite!` so each person receives an invitation email and sets their own password. No ENV vars, no temporary passwords.

**Dependencies**: Phases 3 and 4 complete.

**Success Criteria**:
- [ ] Admin can view the full user list at `/admin/users`
- [ ] Admin can submit the invitation form with a new email address
- [ ] Invitation email arrives in development mail preview
- [ ] Invited user can follow the link, set a password, and sign in
- [ ] `rails db:seed` invites the 3 founding admins without error
- [ ] Submitting an already-used email shows a validation error, not a 500

### Phase 6: Password Reset Flow Verification

**Objective**: Confirm the Devise recoverable flow works end-to-end for all users.

**Components**:
- Devise recoverable already enabled in Phase 2; this phase is verification and any view adjustments
- "Forgot password" link visible on the sign-in page
- Password reset email delivers correctly in development
- New password form accepts and saves the new password

**Dependencies**: Phase 3 complete.

**Success Criteria**:
- [ ] "Forgot password" link is present and functional on the sign-in page
- [ ] Password reset email is received in development
- [ ] User can set a new password and sign in with it
- [ ] Reset token expires after use (Devise default behavior)

### Phase 7: Changelog and Cleanup

**Objective**: Ensure the project meets team standards before the first PR.

**Components**:
- `CHANGELOG.md` created at project root (required by team policy)
- First changelog entry for the initial authentication feature
- Review of all view templates for UX consistency (flash messages, form errors)

**Dependencies**: Phases 5 and 6 complete.

**Success Criteria**:
- [ ] `CHANGELOG.md` exists and has a valid entry for this feature
- [ ] No hardcoded credentials anywhere in the codebase
- [ ] Flash messages appear correctly on all relevant actions (sign in, invite, password reset)

### Phase 8: Infrastructure — Network (Terraform: networking/)

**Objective**: Add the Onboarding VPC to the shared networking stack, following the exact same pattern as the `setup` VPC.

**Network sizing rationale**: Fargate uses awsvpc network mode — each task gets its own ENI and consumes one IP from the subnet. Max realistic load: 3 web tasks + 2 Sidekiq tasks + 1 RDS primary = ~6 IPs in the private layer. Public subnets /28 (16 IPs) for ALB and NAT. VPC /25 (128 IPs): 96 IPs allocated across 4 subnets, 32 IPs free = **25% headroom**, aligned with the AWS Well-Architected recommendation of 20–30% free for future growth.

**VPC CIDR**: `10.100.129.0/25` — 128 IPs, immediately after `setup` (`10.100.128.0/24`). No overlap with any existing VPC.

**Subnets** (within `10.100.129.0/25`):

| Name | CIDR | AZ | Usable IPs | Type | Usage |
|------|------|----|------------|------|-------|
| `onboarding-pub-a` | `10.100.129.0/28` | us-east-1a | 11 | Public | ALB, NAT Gateway |
| `onboarding-pub-b` | `10.100.129.16/28` | us-east-1b | 11 | Public | ALB (HA) |
| `onboarding-prv-a` | `10.100.129.32/27` | us-east-1a | 27 | Private | ECS tasks, RDS |
| `onboarding-prv-b` | `10.100.129.64/27` | us-east-1b | 27 | Private | ECS tasks, RDS (HA) |

**Components**:
- `networking/vpc_onboarding.tf` — VPC, subnets, IGW, NAT Gateway (in pub-a), route tables
- `networking/ssm.tf` — SSM parameters for VPC ID, CIDR, subnet IDs, route table IDs (pattern: `/networking/onboarding/*`)
- No Transit Gateway attachment — Onboarding is a standalone public app, same as Setup

**Dependencies**: None — this is the first piece.

**Success Criteria**:
- [x] `terraform plan` shows no unexpected changes to existing resources
- [x] VPC created with correct CIDR `10.100.129.0/25`
- [x] 4 subnets created (2 public /28, 2 private /27)
- [x] NAT Gateway running and private subnets route through it
- [x] SSM parameters created under `/networking/onboarding/`

---

### Phase 9: Infrastructure — Application Stack (Terraform: onboarding/)

**Objective**: Create the complete Onboarding application stack in a new `onboarding/` directory in Terraform, following the `setup/` pattern.

**Architecture overview**:
- Internet → Cloudflare → ALB (public subnets) → ECS web service (private subnets) → RDS (private subnets)
- Fargate launch type — sem EC2, sem capacity providers, sem ASG
- Sidekiq será um segundo ECS service no mesmo cluster, com desired_count=0 até ser necessário
- Blue/green deployment via CodeDeploy

**Components**:

**ECS Cluster** (`onboarding-cluster`):
- Fargate — nenhuma instância EC2 gerenciada
- Security group para tasks: ingress do ALB security group na porta 3000, egress 0.0.0.0/0

**ALB** (`onboarding-pub-lb`):
- External, in public subnets
- Cloudflare-only ingress (same as all other stacks)
- Target port: 3000, target type: `ip` (required for Fargate awsvpc)
- Health check: `/up` (Rails default health endpoint), `200-399`, interval 10s
- Blue/green target groups: `onboarding-pub-tg` (primary) + `onboarding-pub-alt-tg` (alternate)
- ACM certificate: `arn:aws:acm:us-east-1:405749097490:certificate/6789893d-2c48-452a-90ea-3f2fc9ca8e35` (`*.app4shark.com` — same cert as Setup, already valid)

**ECS Service — Web** (`onboarding-web-service`):
- Launch type: FARGATE
- Desired count: 1 (CodeDeploy manages after first deploy)
- Task: `onboarding-web` family, awsvpc network mode
- CPU: 512, Memory: 1024 MiB (adequado para Puma em app pequeno)
- Image: `405749097490.dkr.ecr.us-east-1.amazonaws.com/onboarding-web:latest`
- Port: 3000
- Network: private subnets, task security group
- CloudWatch logs: `/ecs/onboarding-web`, retention 30 days
- Deployment: CODE_DEPLOY, blue/green, bake time 2 min
- Execute command: enabled (for troubleshooting)

**ECS Service — Sidekiq** (`onboarding-sidekiq-service`):
- Launch type: FARGATE
- Desired count: 0 — não consome nada até ser ativado
- Task: `onboarding-sidekiq` family, awsvpc network mode
- CPU: 256, Memory: 512 MiB (ajustável quando Sidekiq for implementado)
- Network: private subnets, task security group (sem ALB)
- Criado agora para ter a estrutura pronta; ativado quando jobs forem introduzidos

**ECR**: `onboarding-web` repository

**CodeDeploy**: app `onboarding-web`, deployment group `onboarding-web-deployment-group`

**RDS** (`onboarding`):
- PostgreSQL 16.x
- db.t3.micro, 20 GB gp3 (auto-scale to 1000 GB)
- Private subnets, single-AZ
- Security group: ingress 5432 from VPC CIDR + VPN management (10.255.0.0/16)
- KMS encryption: same key as other stacks (`mrk-fa0cda243274491784fc7b39bead5a03`)
- Backup retention: 7 days
- Deletion protection: enabled
- Master password: AWS Secrets Manager managed

**IAM Deploy User** (`onboarding`):
- GitHub Actions CI/CD
- Permissions: ECR push, ECS update, CodeDeploy trigger

**Files**:
- `onboarding/main.tf` — ECS cluster, capacity providers, ALB, ECR, ECS service, CodeDeploy, IAM deploy user
- `onboarding/rds.tf` — PostgreSQL instance
- `onboarding/variables.tf` — variable definitions
- `onboarding/terraform.tfvars` — values
- `onboarding/output.tf` — CodeDeploy app name, ALB DNS, deploy role ARN
- `onboarding/providers.tf` — AWS provider, us-east-1

**Dependencies**: Phase 8 complete (SSM parameters must exist).

**Success Criteria**:
- [x] `terraform apply` completes without errors
- [x] ECS cluster created (Fargate — no EC2 instances, no ASGs, no capacity providers)
- [x] ALB DNS resolves and responds to health check
- [x] RDS instance running and accessible from private subnets
- [x] ECR repository created
- [x] IAM deploy user created with correct permissions
- [x] DNS record `onboarding.app4shark.com` created in Cloudflare pointing to ALB
- [x] No `latest` image deployed yet — ECS service pending until first CI/CD run

---

### Phase 10: CI/CD Pipeline — GitHub Actions ✅

**Objective**: Configure GitHub Actions to build and deploy the Onboarding application following the same workflow as `setup` and `app`.

**Components**:
- `.github/docker/Dockerfile` — production image (Ruby 3.4.1, tini, no dev tools)
- `.github/workflows/build.yml` — builds and pushes Docker image to ECR on push to `master`
- `.github/workflows/deploy.yml` — blue/green deployment via CodeDeploy with Sidekiq quiet mode, Fargate migration task, and autoscaling lock
- `.github/actions/deploy/action.yaml` — composite action to register task definition and update ECS service
- `config/version.rb` — version `0.0.0` (bumped at release time)
- `config/sidekiq.yml` — concurrency via `ApplicationConfiguration.sidekiq_threads` (ERB)
- `config/initializers/sidekiq.rb` — AR connection pool adjustment, ECS health check file, Redis URL from `ApplicationConfiguration`
- `lib/application_configuration.rb` — added `sidekiq_threads` (default 10)

**Dependencies**: Phase 9 complete.

**Success Criteria**:
- [x] Push to `master` triggers build workflow
- [x] Docker image built and pushed to ECR with `VERSION-SHORT_SHA` and `:latest` tags
- [x] CodeDeploy deployment: blue/green traffic switch, Sidekiq quiet mode, Fargate migration task
- [x] Sidekiq concurrency configurable via `SIDEKIQ_THREADS` env var
- [x] ECS health check file for Sidekiq container (`tmp/sidekiq_ready.txt`)
- [x] Single Redis (`REDIS_URL`) — no separate Sidekiq Redis needed
- [x] PR #cicd merged to develop

---

## Open Questions (Deploy)

1. ~~**Domain name**~~ — **Resolved**: `onboarding.app4shark.com`. Certificate `*.app4shark.com` já existe e está válido (ARN: `arn:aws:acm:us-east-1:405749097490:certificate/6789893d-2c48-452a-90ea-3f2fc9ca8e35`). Nenhum cert novo necessário.
2. ~~**Production SMTP**~~ — **Resolved**: Not required for initial deploy. Founding admin accounts were already created via `User.create!` with random passwords. Users will use password reset when SMTP is configured in a future iteration.
3. ~~**Sidekiq ECS service**~~ — **Resolved**: Sidekiq ECS service (desired_count=0) created in Phase 9 with structure ready; activated in a future feature branch when background jobs are introduced.

---

## Key Considerations

### Security

- The `registerable` module must NOT be included — self-registration is explicitly out of scope. Only admins create accounts.
- Devise token expiry for invitations should be reviewed (`invite_for` config). Default is 0 (never expires), which should be set to a reasonable value (e.g., 2 weeks).
- Password reset tokens expire by default after 6 hours (`reset_password_within` config) — keep this default.
- Invitation tokens for founding admins are generated via `User.invite!` in seeds — each person receives an email and sets their own password.
- All admin routes should be protected at the controller level, not just by convention.

### Email

- The application requires a working SMTP configuration in production before invitations and password resets can function.
- In development, use `letter_opener` (renders emails in the browser) to avoid needing real SMTP.
- `default_url_options[:host]` must be set correctly per environment — Devise uses it to generate links in emails.

### UX

- Invited users land on a "set your password" page — this is distinct from the password reset flow and handled by devise_invitable.
- The sign-in page should show a clear "Forgot your password?" link.
- The admin invitation form should show clear feedback when an invitation is sent successfully or when the email is already taken.

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| No SMTP configured in production | High | Document the required ENV vars clearly; app will not be functional for invites/resets without it |
| devise_invitable version incompatibility with Devise version | Medium | Pin compatible versions in Gemfile; check the gem's compatibility matrix before installing |
| First admin bootstrap in production | Medium | Seeds use `User.invite!` with hardcoded emails — requires SMTP to be configured before running `rails db:seed` in production. |
| Invitation token never expires (devise_invitable default) | Low | Explicitly set `config.invite_for` in the Devise initializer |

## Assumptions

- PostgreSQL is available in the development environment.
- Each developer configures `PG_SERVICE` in their `.env.local` to match their local Postgres setup (Homebrew, Docker, etc.).
- The production email provider (SMTP credentials) will be configured separately — outside the scope of this plan.
- The application does not need self-registration; all accounts are created by admins.
- Standard Rails ERB views are acceptable — no CSS framework is required beyond what Rails scaffolding provides (though Bootstrap or Tailwind could be added without affecting this plan).
- There is no existing codebase to migrate from — this is a greenfield Rails application.
- Engineering standards (ApplicationConfiguration, bin scripts, Puma config, etc.) are copied from the `app` project and adapted for a simpler stack (no Redis, Sidekiq, or MongoDB in scope).
