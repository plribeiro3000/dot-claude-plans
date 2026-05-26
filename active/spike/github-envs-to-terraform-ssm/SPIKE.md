# SPIKE — Migration of GitHub Environments variables to Terraform (SSM + Terraform code)

**Conducted by:** Engineering team
**Date:** 2026-03-21
**Status:** Research complete — pending decisions

---

## Goal

Investigate the current state of GitHub Environments configuration across all applications to answer:

1. Which applications use GitHub Environments and what variables/secrets do they have?
2. What is the current mechanism for injecting variables into ECS tasks at deploy time?
3. How is SSM Parameter Store already being used in the project?
4. What is the recommended approach to migrate all variables to Terraform (SSM for secrets, inline for non-sensitive)?
5. What are the risks and recommended migration order?

---

## Method

- Codebase analysis of all Terraform stacks and modules
- GitHub API queries for all environment variables and secret names (not values)
- GitHub Actions workflow analysis across integrator, app, setup, and onboarding repos
- Cross-referencing existing Terraform patterns with the integrator-almaviva stack (already migrated)

---

## Evidence

### 1. Terraform Stack Inventory

The project has the following stacks in `/Users/plribeiro3000/Projects/4Shark/terraform/`:

| Stack | Has ECS | Has SSM | Has GH Env | Notes |
|-------|---------|---------|------------|-------|
| `integrator-almaviva` | Yes (Fargate) | Yes (`ssm.tf`) | Yes (9 envs in repo) | **Migration DONE** — prototype for all others |
| `integrator-atento-br` | No (EC2 only) | No | Yes | EC2 module — ECS migration pending |
| `integrator-commcenter` | No (EC2 only) | No | Yes | EC2 module — ECS migration pending |
| `integrator-aster-maquinas` | No (EC2 only) | No | Yes | EC2 module — ECS migration pending |
| `integrator-maqnelson` | No (EC2 only) | No | Yes | EC2 module — ECS migration pending |
| `integrator-redebrasil` | No (EC2 only) | No | Yes | EC2 module — ECS migration pending |
| `app-atento-001` | Yes (EC2 ECS) | No | Yes | CodeDeploy blue/green |
| `app-atento-br` | No ECS resources | No | No | Infrastructure only |
| `app-beta-001` | No ECS resources | No | No | Infrastructure only |
| `app-demo-001` | No ECS resources | No | No | Infrastructure only |
| `app-shared-001` | No ECS resources | No | No | Infrastructure only |
| `setup` | Yes (EC2 ECS) | No | Yes (`Production`) | CodeDeploy blue/green |
| `onboarding` | Yes (Fargate) | No | Yes (`Production`) | CodeDeploy blue/green |
| `auth-001` | Yes (Fargate) | No (Secrets Manager) | No | Uses AWS Secrets Manager, not SSM |

**Important context:** The `integrators-ec2-to-ecs` migration is in progress (PLAN.md active). Only `integrator-almaviva` has completed the ECS Fargate migration. The remaining 5 integrators (atento-br, commcenter, aster-maquinas, maqnelson, redebrasil) still run on EC2. The migration order defined in the plan is: maqnelson → aster-maquinas → commcenter → redebrasil → atento-br.

### 2. GitHub Environments Inventory

#### repo: integrator (9 environments)

| Environment | Type | Variables | Secrets | Notes |
|-------------|------|-----------|---------|-------|
| `almaviva` | ECS Fargate | 36 | 13 | **SSM migration already done** |
| `atento-br` | EC2 | 34 | 13 | Awaiting ECS migration |
| `atento-mx` | EC2 | 34 | 13 | Sub-env of atento-br cluster |
| `aster-maquinas` | EC2 | 34 | 13 | Awaiting ECS migration |
| `aster-maquinas-staging` | EC2 | 33 | 13 | Staging variant |
| `commcenter` | EC2 | 34 | 13 | Awaiting ECS migration |
| `commcenter-staging` | EC2 | 33 | 13 | Staging variant |
| `maqnelson` | EC2 | 33 | 13 | Next in ECS migration queue |
| `redebrasil` | EC2 | 34 | 13 | Awaiting ECS migration |

**Integrator variable structure (universal across all envs):**

Non-sensitive vars (36 total for almaviva, ~34 for others) — all become Terraform `env_vars`:
```
AWS_BUCKET, AWS_ECS_CLUSTER (*), AWS_ECS_WEB_SERVICE (*), AWS_ECS_WORKER_SERVICE (*),
AWS_INSTANCE_IDS, AWS_REGION, CLIENT_AZURE, CLIENT_DATABASE, CLIENT_HOST,
CLIENT_NAME, CLIENT_PORT, CLIENT_TIMEOUT, CLIENT_USERNAME, CLIENT_WARM_UP,
DATABASE_ADAPTER, DD_APM_ENABLED, DIFFEND_ENV, DIFFEND_PROJECT_ID,
DIFFEND_SHAREABLE_ID, ENVIRONMENT, GOOGLE_CLIENT_ID, HOT_DATA_WINDOW,
INTEGRATION_MODE, JOB_METRIC_QUANTITY, MAILER_*, MINIMUM_THROUGHPUT,
MONGO_CONNECT_TIMEOUT, MONGO_PAGE_SIZE, MONGO_SERVER_SELECTION_TIMEOUT,
MONGO_SOCKET_TIMEOUT, NEW_RELIC_APP_NAME, RAILS_ENV, RAILS_SERVE_STATIC_FILES,
SIDEKIQ_THREADS, SKIP_DATABASE_VALIDATIONS, SQL_PAGE_SIZE
```
(*) `AWS_ECS_CLUSTER/WEB_SERVICE/WORKER_SERVICE` in almaviva env are legacy — not used by any current workflow.

Sensitive secrets (13 identical across all integrator envs) — become SSM SecureString:
```
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, CLIENT_PASSWORD,
DATA_DOG_API_KEY, DATA_DOG_APPLICATION_KEY, GOOGLE_CLIENT_ID (*),
GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN, MONGODB, NEW_RELIC_LICENSE_KEY,
REDIS, ROLLBAR_ACCESS_TOKEN, SECRET_KEY_BASE
```
(*) `GOOGLE_CLIENT_ID` appears in GH secrets for some envs but is non-sensitive (OAuth client ID is public). In almaviva's Terraform it's already in `env_vars`.

**Note on MONGODB and REDIS:** In almaviva's GH env these are stored as secrets, but in the Terraform `compute.tf` they appear as `env_vars` (non-sensitive plain text). This is a discrepancy — the connection strings contain hostnames/ports only (no credentials), so they are non-sensitive. They should move to Terraform `env_vars`.

#### repo: app (5 environments)

| Environment | Variables | Secrets | Notes |
|-------------|-----------|---------|-------|
| `atento-001` | 55 | 25 | EC2 ECS, CodeDeploy |
| `shared-001` | 57 | 25 | EC2 ECS, CodeDeploy |
| `beta-001` | 48 | 21 | EC2 ECS, CodeDeploy |
| `demo-001` | 46 | 21 | EC2 ECS, CodeDeploy |
| `Test` | — | — | CI only, not a deployment env |

App non-sensitive vars (sample from atento-001):
```
AWS_BUCKET, AWS_S3_REGION, BUNDLE_WITHOUT, CLUSTER_NAME, CODEDEPLOY_APP_NAME,
CODEDEPLOY_DEPLOYMENT_GROUP, CODEDEPLOY_HOOK_LAMBDA_ARN, COMMISSION_INDICATOR_AUDIT_LOCK,
COMPANY_ANONYMIZING_WINDOW, CORS_ORIGINS, DATABASE_READONLY_USERNAME, DD_APM_ENABLED,
DD_DISABLE_HOST_METRICS, DD_DYNO_HOST, DD_LOGS_ENABLED, DD_LOG_TO_CONSOLE,
DD_PROCESS_AGENT, DD_TRACE_ANALYTICS_ENABLED, DIFFEND_ENV, DISABLE_DATADOG_AGENT,
DOMAIN, ELASTICSEARCH_HOST, ELASTIC_INDEX, ELASTIC_INDEX_TTL, ENVIRONMENT,
GROUP_AUDIT_LOCK, LANG, MONGO_CLUSTER, MONGO_CONNECT_TIMEOUT, MONGO_MONITORING_IO,
MONGO_SERVER_SELECTION_TIMEOUT, MONGO_SOCKET_TIMEOUT, NEW_RELIC_AGENT_ENABLED,
NEW_RELIC_APP_NAME, PGBOUNCER_PREPARED_STATEMENTS, PG_*_TIMEOUT, PLAN_STATEMENT_AUDIT_LOCK,
RACK_ENV, RACK_TIMEOUT_*, RAILS_ENV, RAILS_LOG_TO_STDOUT, RAILS_PG_EXTRAS_PUBLIC_DASHBOARD,
RAILS_SERVE_STATIC_FILES, RESPONSIBLE_AUDIT_LOCK, SIDEKIQ_THREADS, USER_*_LOCK,
WEB_CONCURRENCY, WEB_ECR_REPO, WEB_MAX_THREADS, WEB_SERVICE_NAME
```

App sensitive secrets (atento-001 / shared-001):
```
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, CURRENCY_API_KEY, DATABASE_REPLICA_URL,
DATABASE_URL, DATA_DOG_API_KEY, DATA_DOG_APPLICATION_KEY, DD_API_KEY,
DIFFEND_PROJECT_ID, DIFFEND_SHAREABLE_ID, DIFFEND_SHAREABLE_KEY,
ELASTICSEARCH_PASSWORD, ELASTICSEARCH_USER, HIREFIRE_TOKEN,
MIGRATION_DATABASE_URL, MONGO_URL, NEW_RELIC_LICENSE_KEY, RAILS_MASTER_KEY,
REDIS_CACHE_URL, REDIS_LOCK_URL, REDIS_SIDEKIQ_URL, REDIS_URL,
ROLLBAR_CLIENT_ACCESS_TOKEN, ROLLBAR_SERVER_ACCESS_TOKEN, SECRET_KEY_BASE
```

#### repo: setup (2 environments)

`Production` environment:
- 13 vars: `CLUSTER_NAME, CODEDEPLOY_APP_NAME, CODEDEPLOY_DEPLOYMENT_GROUP, CODEDEPLOY_HOOK_LAMBDA_ARN, ENVIRONMENT, LANG, RACK_ENV, RAILS_ENV, RAILS_LOG_TO_STDOUT, RAILS_SERVE_STATIC_FILES, ...`
- 10 secrets: `AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, DIFFEND_PROJECT_ID, DIFFEND_SHAREABLE_ID, DIFFEND_SHAREABLE_KEY, RAILS_MASTER_KEY, ROLLBAR_CLIENT_ACCESS_TOKEN, ROLLBAR_SERVER_ACCESS_TOKEN, SECRET_KEY_BASE, SETUP_DATABASE_URL`

#### repo: onboarding (2 environments)

`Production` environment:
- 8 vars: `CLUSTER_NAME, CODEDEPLOY_APP_NAME, CODEDEPLOY_DEPLOYMENT_GROUP, CODEDEPLOY_HOOK_LAMBDA_ARN, ECS_PRIVATE_SUBNETS, ECS_TASK_SECURITY_GROUP, ENVIRONMENT, WEB_SERVICE_NAME`
- 14 secrets: `AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, DOMAIN, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN, MAIL_SENDER, MIGRATION_DATABASE_URL, ONBOARDING_DATABASE_URL, RAILS_SERVE_STATIC_FILES, REDIS_LOCK_URL, REDIS_SIDEKIQ_URL, REDIS_URL, SECRET_KEY_BASE`

### 3. How Variables Are Currently Injected into ECS

#### The deploy action mechanism (all repos except auth-001)

Every deploy workflow (integrator, app, setup, onboarding) calls a composite action (`.github/actions/deploy` or `.github/actions/deploy-ecs`) that does the following at deploy time:

1. Fetches the current ECS task definition from AWS
2. Converts ALL GitHub `vars` (non-sensitive) to ECS `environment` array format
3. Converts ALL GitHub `secrets` to ECS `environment` array format
4. Merges them (secrets take precedence over vars with same name)
5. **Filters out** any var/secret whose name already exists in the task def's `secrets` array (SSM-backed)
6. Replaces the entire `environment` array of the container with the merged result
7. Registers a new task definition revision
8. Updates the ECS service (or creates a CodeDeploy deployment)

**Critical implication:** After the first deploy, the ECS task definition's `environment` array is **fully owned by GitHub Actions**, not Terraform. The `ecs_service` module's `lifecycle {}` block is empty (no `ignore_changes` on `task_definition`), but the service has `ignore_changes = [task_definition]` so Terraform won't overwrite the GHA-created task def revision. The Terraform-set values only apply at initial resource creation.

#### Exception: almaviva (SSM pattern already in place)

For `integrator-almaviva`, the deploy action's filter step removes any GH secret that already exists as an SSM-backed secret in the task definition. This means:
- Variables in `ssm.tf` → injected via ECS `secrets` mechanism (from SSM at container start)
- Remaining GH vars/secrets → injected via ECS `environment` mechanism at deploy time

**Current SSM secrets in integrator-almaviva** (`ssm.tf`):
```
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, CLIENT_USERNAME, CLIENT_PASSWORD,
DIFFEND_SHAREABLE_KEY, DATA_DOG_API_KEY, DATA_DOG_APPLICATION_KEY,
GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN, NEW_RELIC_LICENSE_KEY,
ROLLBAR_ACCESS_TOKEN, SECRET_KEY_BASE, github_token
```

And in `compute.tf`, the `secrets` list references these SSM parameters via `valueFrom = aws_ssm_parameter.secrets["NAME"].arn`.

### 4. The Proposed Target Architecture

The goal is to reach a state where:

1. **Secrets (sensitive values)** → AWS SSM Parameter Store as `SecureString`, managed by Terraform (`ssm.tf`)
2. **Non-sensitive vars** → Terraform `env_vars` / `locals.env_vars` in `compute.tf` (plain text in code)
3. **Deploy workflow** → continues to use the same deploy action, but the GH env will only have:
   - `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (deploy credentials — these stay in GH secrets as they authorize the deploy itself)
   - Deploy-specific vars: `CODEDEPLOY_APP_NAME`, `CODEDEPLOY_DEPLOYMENT_GROUP`, etc.
4. **GitHub Environments** → after migration, only contain deploy infrastructure vars/secrets (not application env vars)

The almaviva pattern is the reference implementation:
- `ssm.tf`: defines `aws_ssm_parameter.secrets` with `ignore_changes = [value]`
- `ssm.tf`: grants `ecsTaskExecutionRole` permission to read SSM + KMS decrypt
- `compute.tf`: `locals.env_vars` = all non-sensitive vars as plain map
- `compute.tf`: `locals.secrets` = references to SSM parameter ARNs
- `compute.tf`: ECS modules receive `environment_variables = local.env_vars` + `secrets = local.secrets`

### 5. Variable Classification Analysis

Based on integrator-almaviva as reference:

**Should go to Terraform `env_vars` (non-sensitive):**
- Application config: `CLIENT_NAME`, `CLIENT_HOST`, `CLIENT_PORT`, `CLIENT_DATABASE`, `CLIENT_AZURE`, `CLIENT_TIMEOUT`, `CLIENT_WARM_UP`
- AWS config: `AWS_BUCKET`, `AWS_REGION`, `AWS_INSTANCE_IDS`
- Observability config: `NEW_RELIC_APP_NAME`, `DD_APM_ENABLED`, `DIFFEND_ENV`, `DIFFEND_PROJECT_ID`, `DIFFEND_SHAREABLE_ID`
- Mailer config: `MAILER_ADDRESS`, `MAILER_DOMAIN`, `MAILER_FROM`, `MAILER_PORT`, `MAILER_TO`
- Feature flags: `INTEGRATION_MODE`, `DATABASE_ADAPTER`, `ENVIRONMENT`, `RAILS_ENV`, etc.
- Infra addresses (no credentials): `MONGODB`, `REDIS` (connection strings with no auth)
- All `RAILS_*`, `SIDEKIQ_*`, `MONGO_*_TIMEOUT` config
- Deploy infra vars: `CLUSTER_NAME`, `CODEDEPLOY_APP_NAME`, `CODEDEPLOY_DEPLOYMENT_GROUP`, `CODEDEPLOY_HOOK_LAMBDA_ARN`, etc.

**Should go to SSM SecureString (sensitive):**
- Credentials: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `CLIENT_PASSWORD`, `CLIENT_USERNAME`
- API keys: `DATA_DOG_API_KEY`, `DATA_DOG_APPLICATION_KEY`, `NEW_RELIC_LICENSE_KEY`, `ROLLBAR_ACCESS_TOKEN`
- OAuth secrets: `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`
- Rails secrets: `SECRET_KEY_BASE`, `RAILS_MASTER_KEY`
- Database URLs (contain credentials): `DATABASE_URL`, `DATABASE_REPLICA_URL`, `MIGRATION_DATABASE_URL`, `ONBOARDING_DATABASE_URL`, `SETUP_DATABASE_URL`, `MONGO_URL`
- Redis URLs (if authenticated): `REDIS_URL`, `REDIS_LOCK_URL`, `REDIS_SIDEKIQ_URL`, `REDIS_CACHE_URL`
- Service API keys: `CURRENCY_API_KEY`, `HIREFIRE_TOKEN`, `DD_API_KEY`, `DIFFEND_SHAREABLE_KEY`
- Elasticsearch: `ELASTICSEARCH_PASSWORD`, `ELASTICSEARCH_USER`
- Integration-specific: `DIFFEND_SHAREABLE_KEY`, `github_token`

**Should stay only in GH Secrets (not in SSM — deploy credentials):**
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` of the deploy IAM user — these authorize the deploy itself and should remain in GH secrets. They can ALSO be in SSM for the application runtime (different use case).

### 6. KMS Key

All SSM SecureString parameters in integrator-almaviva use the same KMS key:
`arn:aws:kms:sa-east-1:405749097490:key/b16e449a-f7f9-49c1-96a6-586aed93a10d`

The `ecsTaskExecutionRole` IAM policy in `ssm.tf` grants `kms:Decrypt` on this key.

For `app-*` stacks (region `us-east-1`), a different KMS key would be needed. `auth-001` already uses `arn:aws:kms:sa-east-1:405749097490:key/5a64fa33-0a93-4352-9c62-e9edad2b87f9` for Secrets Manager.

A separate KMS key investigation may be needed for app stacks. See active spike: `kms-migration`.

### 7. Current Ownership Split (the core problem)

The issue being solved is that environment variables have two owners today:

| Owner | Controls | Mechanism |
|-------|----------|-----------|
| Terraform | Initial task definition (at `tf apply`) | `env_vars` + `secrets` in module |
| GitHub Actions | Every deploy (overwrites environment array) | GH env vars + secrets → task def |

After any deploy, GitHub Actions owns the task definition environment. Terraform `apply` would only re-establish ownership if the service were recreated (which is blocked by `ignore_changes = [task_definition]`).

**The target state:** GitHub Actions deploys continue to work the same way, but GH environments only contain deploy-infra vars. The application vars are in Terraform. Since SSM-backed secrets are filtered out by the deploy action, they survive deploys untouched. For non-sensitive vars, the GH env will simply not have them — the Terraform task def sets them at creation, and they won't be overwritten by an empty GH vars set.

**However, this creates a drift problem for non-sensitive vars:** if GH env has a var with the same name as the Terraform-set one, GH will overwrite Terraform's value on every deploy. Solution: remove the var from GH env entirely, relying on Terraform to set it via `tf apply` when it changes.

---

## Conclusions

### What was learned

1. **integrator-almaviva is the complete reference implementation.** It has `ssm.tf` + `compute.tf` with `env_vars` + `secrets`. The pattern works and is already validated in production.

2. **The deploy action has a correct SSM-aware filter.** It already skips GH secrets that exist as SSM-backed ECS secrets. This means the SSM migration path is safe — you can add SSM secrets to Terraform and the deploy action will correctly not override them.

3. **Non-sensitive vars are NOT filtered by the deploy action.** If a var exists in both GH env and Terraform, the GH env wins on every deploy. To move non-sensitive vars to Terraform, they must be removed from GH env.

4. **The 5 remaining integrators don't have ECS yet.** Their GH environments are used by the `build.yaml` workflow (for Docker build credentials and `DIFFEND_*` build args) and potentially by future ECS deploy workflows. The SSM migration for these integrators is **blocked by the EC2→ECS migration** (which is already in progress per the integrators-ec2-to-ecs plan).

5. **The app stacks (atento-001, shared-001, beta-001, demo-001) have a larger variable set** (~55 vars + 25 secrets). They use the same deploy-action pattern. The migration approach is identical to almaviva but requires careful variable classification per env (some envs have different feature flag values).

6. **setup and onboarding have smaller variable sets** (8-13 vars, 10-14 secrets) and are simpler migration candidates.

7. **auth-001 is already migrated** — it uses AWS Secrets Manager (not SSM), which is a valid alternative. No action needed.

8. **Legacy GH env vars** — `AWS_ECS_CLUSTER/WEB_SERVICE/WORKER_SERVICE` in almaviva env are not used by any current workflow. They can be deleted.

9. **Deploy credentials must stay in GH Secrets** — `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for the IAM deploy user must remain in GH secrets to authenticate the deployment. They can optionally also be in SSM for the application runtime (they serve different purposes).

### Recommended approach

**Pattern:** Replicate the integrator-almaviva pattern across all remaining stacks.

For each stack:
1. Create `ssm.tf` with `aws_ssm_parameter.secrets` for all sensitive values + IAM policy
2. Update `compute.tf` (or equivalent) to add `locals.env_vars` + `locals.secrets`
3. Remove migrated vars/secrets from GH environment
4. Run `tf apply` to create SSM placeholders
5. Populate SSM values via `aws ssm put-parameter`
6. Validate: run a deploy to confirm SSM-backed secrets are not overwritten
7. Delete GH environment (or retain minimal set for deploy infra only)

### Migration order recommendation

Given the integrators-ec2-to-ecs plan in progress, the recommended order is:

**Tier 1 — Ready now (ECS already running):**
- `setup` (small, 10 secrets) — lowest risk, good warm-up
- `onboarding` (small, 14 secrets) — similar complexity
- `app-beta-001` / `app-demo-001` (medium, 21 secrets, no `DATABASE_REPLICA_URL`)
- `app-atento-001` / `app-shared-001` (medium-large, 25 secrets)

**Tier 2 — Blocked by EC2→ECS migration:**
- Each integrator as it completes ECS migration: maqnelson → aster-maquinas → commcenter → redebrasil → atento-br

**KMS decision (2026-03-21):** Use the existing Multi-Region Key (MRK) already in use across all `us-east-1` stacks:
`arn:aws:kms:us-east-1:405749097490:key/mrk-fa0cda243274491784fc7b39bead5a03`
This key is already used by app-atento-001, app-beta-001, app-demo-001, app-shared-001, setup, and onboarding for RDS and OpenSearch encryption. No new key needed.

---

## Next Steps

1. **Decision needed:** Confirm the KMS key to use for `us-east-1` stacks (setup, onboarding, app-*). Options: (a) use existing KMS key per region, (b) create new key, (c) use AWS-managed key (`aws/ssm`). This is a prerequisite before any implementation work on Tier 1 stacks.

2. **Decision (2026-03-21):** GitHub Environments will be deleted entirely after migration. The deploy workflow will only update code (Docker image / task definition). Env vars are Terraform's exclusive responsibility — never injected by the deploy action again. Deploy credentials (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) move to repository-level or org-level secrets (not environment-scoped).

3. **Prerequisite — DONE (merged PR #263):** The `engineers-elevated` role now has KMS, SSM, and IAM permissions. Engineers can apply stacks with `ssm.tf` using `AWS_PROFILE=4shark-elevated`. See `~/.claude/plans/completed/terraform/identity-phase2/PLAN.md`.

4. **Implementation:** Use `@agent-planner` to create a PLAN.md for the Tier 1 migration (setup + onboarding + app stacks). The integrators should be handled as part of the integrators-ec2-to-ecs plan as each one completes its ECS migration.

4. **Cleanup:** Delete legacy vars `AWS_ECS_CLUSTER`, `AWS_ECS_WEB_SERVICE`, `AWS_ECS_WORKER_SERVICE` from the `almaviva` GitHub environment (these are unused).

5. **Separate question — Fargate network config for app stacks:** The app stacks use `ECS_PRIVATE_SUBNETS` / `ECS_TASK_SECURITY_GROUP` in GH env for migration tasks. These reference infra IDs that Terraform already knows. They could be read from Terraform state instead of hardcoded in GH env — but this is an optimization, not a blocker.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
