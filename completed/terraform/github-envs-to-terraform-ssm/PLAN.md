# PLAN — GitHub Environments to Terraform SSM Migration (Tier 1)

> Reference: SPIKE.md (`~/.claude/plans/active/spike/github-envs-to-terraform-ssm/SPIKE.md`)
> Reference implementation: `integrator-almaviva/ssm.tf` + `integrator-almaviva/compute.tf`

## Status (2026-03-21)

**ALL TERRAFORM PHASES COMPLETE — 6 stacks migrated**

| Phase | Stack(s) | Params | PR | Status |
|-------|----------|--------|----|--------|
| 1 | `setup` | 10 | — | ✅ Applied + populated |
| 2 | `onboarding` | 11 | — | ✅ Applied + populated |
| 3 | `app-beta-001`, `app-demo-001` | 19 each | #266 merged | ✅ Applied + populated |
| 4 | `app-atento-001`, `app-shared-001` | 22 each | #267 merged | ✅ Applied + populated |
| 5 | Cross-plan update (`integrators-ec2-to-ecs`) | — | — | ✅ Done |

**Validated 2026-03-21**: All 6 stacks confirmed with `terraform plan` showing "No changes" and all SSM
parameters populated (no PLACEHOLDER values remaining).

**Pending (GitHub Actions + repo cleanup)**:
- Strip GitHub Environments to only `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` in `setup`, `onboarding`, and `app` repos — remove all other secrets/vars
- Fix `deploy-ecs` action in each repo: remove env var injection, only update `.image` in task def
- Fix Dockerfiles in `setup` and `app`: remove DIFFEND ARGs, add `.diffend.yml` to COPY (already exists in both repos)

---

## Objective

Move all application environment variables out of GitHub Environments and into Terraform.
Sensitive variables become SSM SecureString parameters managed in `ssm.tf`.
Non-sensitive variables become inline `locals.env_vars` in `compute.tf` (or `main.tf`/`terraform.tfvars`
depending on the stack's existing pattern).

After migration, GitHub Environments are **stripped** — they keep only `AWS_ACCESS_KEY_ID` and
`AWS_SECRET_ACCESS_KEY` (the deploy user credentials the GitHub Actions runner needs to authenticate
with AWS). All other secrets and variables are removed from the GitHub Environment.

The deploy action is fixed to **only update the Docker image** in the task definition. It never touches
the `environment` or `secrets` arrays. On each deploy, the action fetches the current task def,
updates only the `.image` field, and registers a new revision — preserving all Terraform-managed
env vars from the previous revision intact.

## Scope

### In Scope

- `setup` — 1 service (web), 10 secrets, 13 vars
- `onboarding` — 1 service (web), 14 secrets, 8 vars
- `app-beta-001` — multiple services, 21 secrets, ~48 vars
- `app-demo-001` — multiple services, 21 secrets, ~46 vars
- `app-atento-001` — multiple services, 25 secrets, ~55 vars
- `app-shared-001` — multiple services, 25 secrets, ~57 vars
- Update `integrators-ec2-to-ecs` PLAN.md to reference this pattern for Tier 2

### Out of Scope

- Integrator stacks (atento-br, commcenter, aster-maquinas, maqnelson, redebrasil) — blocked by EC2→ECS migration
- `integrator-almaviva` — already migrated (this is the reference implementation)
- `auth-001` — uses AWS Secrets Manager, not SSM; no action needed
- GitHub Actions workflow code changes beyond removing env vars from the environment
- Moving deploy credentials (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) to org-level — that is a GitHub admin action, not Terraform

## Key Decisions (closed — do not reopen)

| Decision | Choice |
|----------|--------|
| KMS key for all Tier 1 stacks (us-east-1) | Existing MRK `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03` |
| GitHub Environments after migration | Strip to deploy credentials only: keep `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`, remove everything else |
| Deploy credentials | Remain in the GitHub Environment — these are runner credentials, not application secrets |
| Pattern | Replicate integrator-almaviva exactly: `ssm.tf` + `locals.env_vars` in compute file |
| Env vars ownership after migration | Terraform exclusively — deploy action no longer injects env vars |
| Deploy action behavior | Only updates `.image` in task def — never touches `environment` or `secrets` arrays; previous task def revision is the source of truth for env vars |
| DIFFEND configuration | Remove ARG DIFFEND_* from Dockerfiles and build args in actions; rely on `.diffend.yml` file already present in each repo (copied via `COPY Gemfile Gemfile.lock .diffend.yml ./`) |
| Elevated IAM profile | `AWS_PROFILE=4shark-elevated` required for all stacks with `ssm.tf` (PR #263 merged) |

## Variable Classification

### setup

**SSM SecureString (`ssm.tf`)**
```
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
DIFFEND_PROJECT_ID, DIFFEND_SHAREABLE_ID, DIFFEND_SHAREABLE_KEY,
RAILS_MASTER_KEY, ROLLBAR_CLIENT_ACCESS_TOKEN, ROLLBAR_SERVER_ACCESS_TOKEN,
SECRET_KEY_BASE, SETUP_DATABASE_URL
```

**Terraform `env_vars` (`main.tf` locals or `terraform.tfvars`)**
```
CLUSTER_NAME, CODEDEPLOY_APP_NAME, CODEDEPLOY_DEPLOYMENT_GROUP,
CODEDEPLOY_HOOK_LAMBDA_ARN, ENVIRONMENT, LANG,
RACK_ENV, RAILS_ENV, RAILS_LOG_TO_STDOUT, RAILS_SERVE_STATIC_FILES
```

> Note: Deploy-infra vars (CLUSTER_NAME, CODEDEPLOY_*) can stay in the service definition
> in `terraform.tfvars` or be added to a dedicated locals block — either approach is valid.
> Prefer adding a `locals.env_vars` block in `main.tf` consistent with the almaviva pattern.

---

### onboarding

**SSM SecureString (`ssm.tf`)**
```
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
DOMAIN, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN,
MAIL_SENDER, MIGRATION_DATABASE_URL, ONBOARDING_DATABASE_URL,
RAILS_SERVE_STATIC_FILES (*), REDIS_LOCK_URL, REDIS_SIDEKIQ_URL, REDIS_URL,
SECRET_KEY_BASE
```

> (*) `RAILS_SERVE_STATIC_FILES` appears in GH secrets for onboarding — it is non-sensitive.
> Move to `env_vars`. Classified here as it was stored as a GH secret; confirm current value before migrating.

**Terraform `env_vars`**
```
CLUSTER_NAME, CODEDEPLOY_APP_NAME, CODEDEPLOY_DEPLOYMENT_GROUP,
CODEDEPLOY_HOOK_LAMBDA_ARN, ECS_PRIVATE_SUBNETS, ECS_TASK_SECURITY_GROUP,
ENVIRONMENT, WEB_SERVICE_NAME,
RAILS_SERVE_STATIC_FILES (move here from secrets after confirmation)
```

---

### app-beta-001 and app-demo-001

Both environments share the same variable structure. Values differ per environment.

**SSM SecureString (`ssm.tf`)**
```
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
CURRENCY_API_KEY, DATABASE_URL, DATA_DOG_API_KEY, DATA_DOG_APPLICATION_KEY,
DD_API_KEY, DIFFEND_PROJECT_ID, DIFFEND_SHAREABLE_ID, DIFFEND_SHAREABLE_KEY,
HIREFIRE_TOKEN, MIGRATION_DATABASE_URL, MONGO_URL,
NEW_RELIC_LICENSE_KEY, RAILS_MASTER_KEY,
REDIS_CACHE_URL, REDIS_LOCK_URL, REDIS_SIDEKIQ_URL, REDIS_URL,
ROLLBAR_CLIENT_ACCESS_TOKEN, ROLLBAR_SERVER_ACCESS_TOKEN, SECRET_KEY_BASE
```

> Note: beta-001 and demo-001 do not have `DATABASE_REPLICA_URL`, `ELASTICSEARCH_*`.

**Terraform `env_vars`**
```
AWS_BUCKET, AWS_S3_REGION, BUNDLE_WITHOUT, CLUSTER_NAME,
CODEDEPLOY_APP_NAME, CODEDEPLOY_DEPLOYMENT_GROUP, CODEDEPLOY_HOOK_LAMBDA_ARN,
COMMISSION_INDICATOR_AUDIT_LOCK, COMPANY_ANONYMIZING_WINDOW, CORS_ORIGINS,
DATABASE_READONLY_USERNAME, DD_APM_ENABLED, DD_DISABLE_HOST_METRICS,
DD_DYNO_HOST, DD_LOGS_ENABLED, DD_LOG_TO_CONSOLE, DD_PROCESS_AGENT,
DD_TRACE_ANALYTICS_ENABLED, DIFFEND_ENV, DISABLE_DATADOG_AGENT, DOMAIN,
ELASTIC_INDEX, ELASTIC_INDEX_TTL, ELASTICSEARCH_HOST, ENVIRONMENT,
GROUP_AUDIT_LOCK, LANG, MONGO_CLUSTER, MONGO_CONNECT_TIMEOUT, MONGO_MONITORING_IO,
MONGO_SERVER_SELECTION_TIMEOUT, MONGO_SOCKET_TIMEOUT, NEW_RELIC_AGENT_ENABLED,
NEW_RELIC_APP_NAME, PGBOUNCER_PREPARED_STATEMENTS, PG_*_TIMEOUT,
PLAN_STATEMENT_AUDIT_LOCK, RACK_ENV, RACK_TIMEOUT_*, RAILS_ENV,
RAILS_LOG_TO_STDOUT, RAILS_PG_EXTRAS_PUBLIC_DASHBOARD, RAILS_SERVE_STATIC_FILES,
RESPONSIBLE_AUDIT_LOCK, SIDEKIQ_THREADS, USER_*_LOCK,
WEB_CONCURRENCY, WEB_ECR_REPO, WEB_MAX_THREADS, WEB_SERVICE_NAME
```

---

### app-atento-001 and app-shared-001

Both share the same variable structure. Values differ per environment.
These have a larger set due to `DATABASE_REPLICA_URL`, `ELASTICSEARCH_*`.

**SSM SecureString (`ssm.tf`)** — same as beta/demo plus:
```
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
CURRENCY_API_KEY, DATABASE_REPLICA_URL, DATABASE_URL,
DATA_DOG_API_KEY, DATA_DOG_APPLICATION_KEY, DD_API_KEY,
DIFFEND_PROJECT_ID, DIFFEND_SHAREABLE_ID, DIFFEND_SHAREABLE_KEY,
ELASTICSEARCH_PASSWORD, ELASTICSEARCH_USER,
HIREFIRE_TOKEN, MIGRATION_DATABASE_URL, MONGO_URL,
NEW_RELIC_LICENSE_KEY, RAILS_MASTER_KEY,
REDIS_CACHE_URL, REDIS_LOCK_URL, REDIS_SIDEKIQ_URL, REDIS_URL,
ROLLBAR_CLIENT_ACCESS_TOKEN, ROLLBAR_SERVER_ACCESS_TOKEN, SECRET_KEY_BASE
```

**Terraform `env_vars`** — same as beta/demo (same non-sensitive set, different values).

---

## Execution Phases

### Phase 1: setup

**Objective**: Smallest stack, 1 service, 10 secrets. Establishes the pattern for all app stacks.

**Stack location**: `terraform/setup/`

**What changes**:
- New file `setup/ssm.tf`: 10 SSM SecureString parameters + IAM policy for `ecsTaskExecutionRole`
  - KMS key: `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
  - SSM path prefix: `/setup/`
- Update `setup/main.tf`: add `locals.env_vars` block with the 10 non-sensitive vars
- Update service definition to pass `environment_variables = local.env_vars` and `secrets = local.secrets`
  - The `setup-web-service` entry in `terraform.tfvars` currently uses `env = {}` (empty). Add the locals block in `main.tf` and wire it into the `ecs_services` module via `environment_variables`.
  - The `secrets` field on the `ecs_services` module is already supported (`lookup(each.value, "secrets", [])`). A top-level `secrets` variable/local is needed or the `ecs_services` call receives `secrets = local.secrets` directly.

**Steps**:
1. Create feature branch
2. Export current env var values from the ECS task definition (source of truth — already running in production)
3. Write `ssm.tf` + update `main.tf`
4. `terraform plan` with `AWS_PROFILE=4shark-elevated`
5. Get approval, `terraform apply <planfile>` — creates SSM parameters and updates task def reference in code; no deploy triggered, running containers unaffected
6. Populate SSM values: `aws ssm put-parameter` for each of the 10 secrets (values from step 2)
7. Update deploy workflow (setup repo) to stop injecting env vars from GH environment
8. Delete GitHub Environment `Production` from the setup repo
9. Move deploy credentials to repository-level GH secrets

> No application deploy is required. The running ECS tasks continue using the existing task definition.
> The Terraform change only creates SSM parameters and updates the Terraform code representation.
> The new task definition (referencing SSM) takes effect on the next normal release deploy.

**Dependencies**: None — first migration, no other phase required.

**Success Criteria**:
- [x] `setup/ssm.tf` created and applied without errors
- [x] 10 SSM parameters exist in `/setup/` path in us-east-1
- [x] IAM policy attached to `ecsTaskExecutionRole` grants `ssm:GetParameters` + `kms:Decrypt`
- [ ] GitHub Environment `Production` deleted from setup repo
- [ ] Deploy credentials moved to repository-level GH secrets
- [ ] Deploy workflow updated to not inject env vars from GH

---

### Phase 2: onboarding

**Objective**: Fargate stack (same launch type as almaviva). 14 secrets, 8 vars.

**Stack location**: `terraform/onboarding/`

**What changes**:
- New file `onboarding/ssm.tf`: 13 SSM parameters (14 GH secrets minus `RAILS_SERVE_STATIC_FILES` which moves to `env_vars`) + IAM policy
  - KMS key: `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
  - SSM path prefix: `/onboarding/`
- Update `onboarding/main.tf` (or equivalent): add `locals.env_vars` + `locals.secrets`
  - Confirm actual value of `RAILS_SERVE_STATIC_FILES` from current ECS task definition before classifying

**Steps**: Same as Phase 1 (adjusted for onboarding stack).

**Dependencies**: Phase 1 complete.

**Success Criteria**:
- [x] `onboarding/ssm.tf` created and applied without errors
- [x] 11 SSM parameters exist in `/onboarding/` path (DOMAIN and MAIL_SENDER not used — confirmed from running task def)
- [x] IAM policy attached to `ecsTaskExecutionRole` grants `ssm:GetParameters` + `kms:Decrypt`
- [ ] GitHub Environment `Production` deleted from onboarding repo
- [ ] Deploy credentials moved to repository-level GH secrets
- [ ] Deploy workflow updated to not inject env vars from GH

---

### Phase 3: app-beta-001 and app-demo-001

**Objective**: Migrate both non-production app environments. They share the same variable structure.

**Stack locations**: `terraform/app-beta-001/`, `terraform/app-demo-001/`

**What changes** (same for both):
- New file `ssm.tf`: ~21 SSM parameters + IAM policy
  - KMS key: `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
  - SSM path prefix: `/app-beta-001/` and `/app-demo-001/` respectively
- Update `compute.tf`: add `locals.env_vars` block + `locals.secrets` list
  - Wire into the existing `module "ecs_services"` loop via `environment_variables` and `secrets`
  - Both stacks already have `compute.tf`; env vars are currently empty (`env = {}`)

**Steps**: Same as Phase 1. Apply beta-001 first, then demo-001.

**Dependencies**: Phase 2 complete.

**Success Criteria**:
- [x] `app-beta-001/ssm.tf` and `app-demo-001/ssm.tf` created and applied (PR #266)
- [x] 19 SSM parameters each in `/beta-001/` and `/demo-001/` paths — all populated
- [x] `terraform plan` shows "No changes" on both stacks (validated 2026-03-21)
- [ ] GitHub Environments `beta-001` and `demo-001` deleted from the app repo
- [ ] Deploy workflow updated to not inject env vars from GH

---

### Phase 4: app-atento-001 and app-shared-001

**Objective**: Migrate the two production app environments.

**Stack locations**: `terraform/app-atento-001/`, `terraform/app-shared-001/`

**What changes** (same for both):
- New file `ssm.tf`: ~25 SSM parameters + IAM policy
  - KMS key: `arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
  - SSM path prefix: `/app-atento-001/` and `/app-shared-001/` respectively
- Update `compute.tf`: add `locals.env_vars` block + `locals.secrets` list

> Note for atento-001: has `DATABASE_REPLICA_URL` and `ELASTICSEARCH_*` not present in beta/demo.
> Export values from the running ECS task definition, not from GH env.

**Steps**: Same as Phase 1. Apply atento-001 first, then shared-001.

**Dependencies**: Phase 3 complete.

**Success Criteria**:
- [x] `app-atento-001/ssm.tf` and `app-shared-001/ssm.tf` created and applied (PR #267)
- [x] 22 SSM parameters each in `/atento-001/` and `/shared-001/` paths — all populated
- [x] `terraform plan` shows "No changes" on both stacks (validated 2026-03-21)
- [ ] GitHub Environments `atento-001` and `shared-001` deleted from the app repo
- [ ] Deploy workflow updated to not inject env vars from GH

---

### Phase 5: Cross-Plan Update

**Objective**: Update the integrators-ec2-to-ecs PLAN.md to reflect that env var management
is settled. Integrator stacks must follow this pattern when each one completes its ECS migration.

**What changes**:
- Update `~/.claude/plans/active/terraform/integrators-ec2-to-ecs/PLAN.md`:
  - Replace the "Env var management" technical decision row from
    `GitHub Actions secrets injected at deploy time` to
    `SSM Parameter Store (SecureString) + Terraform env_vars — same pattern as integrator-almaviva`
  - Add a note to the Phase 1 prerequisites (or to each per-integrator phase) that:
    each integrator's `compute.tf` must include `env_vars` and `secrets` from the start,
    referencing SSM parameters via `ssm.tf` — GitHub Environments are not created for new integrators
  - Reference this plan: `github-envs-to-terraform-ssm/PLAN.md`

**Dependencies**: Phases 1–4 complete (this documents the settled pattern after Tier 1 is done,
but the PLAN.md update can be done at any point after Phase 1 to unblock integrator work).

**Success Criteria**:
- [x] `integrators-ec2-to-ecs/PLAN.md` updated with correct env var strategy (2026-03-21)
- [x] Per-integrator phases reference SSM + Terraform as the env var mechanism
- [x] No mention of creating new GitHub Environments for integrators in the updated plan

---

## Per-Stack Deploy Workflow Change

After each stack's Terraform migration, the deploy workflow and action for that application must be updated:

### What changes in the `deploy-ecs` action (setup, onboarding, app repos)

- Remove inputs `secrets-json` and `vars-json`
- Remove the "Register Task Definition" block that generates `env-merged.json` and replaces `.environment`
- Keep only: fetch current task def → update `.image` → register new revision
- The `environment` and `secrets` arrays in the task def are **never touched by deploys**

### What changes in the deploy workflows (setup, onboarding, app repos)

- GitHub Environment stays — do NOT delete it
- Remove from GitHub Environment: all secrets and vars **except** `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- Hardcode all infrastructure vars (CLUSTER_NAME, ENVIRONMENT, WEB_SERVICE_NAME, CODEDEPLOY_*, etc.)
  directly in the workflow `env:` block — these are non-sensitive and stable per environment
- Remove `secrets-json: ${{ toJSON(secrets) }}` and `vars-json: ${{ toJSON(vars) }}` from all action calls

### What changes in the Dockerfiles (setup, app repos)

- Remove `ARG DIFFEND_PROJECT_ID`, `ARG DIFFEND_SHAREABLE_ID`, `ARG DIFFEND_SHAREABLE_KEY`
- Add `.diffend.yml` to the COPY that already copies Gemfile: `COPY Gemfile Gemfile.lock .diffend.yml ./`
- The `.diffend.yml` file already exists in both repos with the correct values

### Why the GitHub Environment is kept (not deleted)

The runner needs `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` to authenticate with AWS on every deploy
(push to ECR, register task def, CodeDeploy). These are **deploy user credentials**, not application secrets.
Keeping them in the GitHub Environment (scoped to the environment's protection rules) is correct and intentional.

---

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| KMS key | Existing MRK `mrk-fa0cda243274491784fc7b39bead5a03` (us-east-1) | Already used for RDS/OpenSearch encryption in all Tier 1 stacks; no new key needed |
| SSM path prefix | `/<stack-name>/<VAR_NAME>` | Consistent with almaviva pattern; easy IAM scoping per stack |
| `ignore_changes = [value]` | Yes (on all SSM parameters) | Values are populated out-of-band via `aws ssm put-parameter`; Terraform must not reset them on next apply |
| Non-sensitive vars placement | `locals.env_vars` in compute file | Consistent with almaviva; values visible in code review; no encryption overhead |
| Source of truth for current values | ECS task definition (not GH env) | Running task def has the actual values in use; GH env may be stale or inconsistent |
| Migration order | setup → onboarding → beta/demo → atento/shared | Smallest stacks first to validate the pattern; production last |
| No forced deploy during migration | Terraform apply only creates SSM params + updates code; running tasks unaffected | The new task definition (referencing SSM) takes effect on the next normal release deploy |

## Assumptions

- All Tier 1 stacks currently pass GH env vars via the deploy action (not initial Terraform creation) — confirmed by spike
- The `ecsTaskExecutionRole` exists and is the execution role for all Tier 1 task definitions — confirmed from code
- The MRK `mrk-fa0cda243274491784fc7b39bead5a03` is already used for data encryption in all Tier 1 stacks — confirmed by spike
- Current env var values are exported from the running ECS task definition (not GH env) before each stack migration
- The deploy workflow changes (removing env var injection) are coordinated with the application teams
- `app-beta-001` and `app-demo-001` do not have `DATABASE_REPLICA_URL` or `ELASTICSEARCH_*` secrets — confirmed from spike
- `app-atento-001` and `app-shared-001` have identical variable names (only values differ) — confirmed from spike
