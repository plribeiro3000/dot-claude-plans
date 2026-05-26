# Bring Lambda Autoscaling Env Vars Into Terraform

## Problem

The `lambda-ecs-autoscaling` module declares `lifecycle { ignore_changes = [environment] }` and exposes no input for env vars. Every Lambda autoscaler env var across all 5 app stacks is set manually via AWS Console/CLI after `terraform apply`. There is no source-of-truth in code, no review trail, no diff on change, and the values drift silently from what an engineer assumed.

This blocks operational work: tuning `MAXIMUM_CAPACITY` for a new client requires logging into the Console; an apply that recreates the function would silently lose all env vars; `terraform plan` does not show pending env-var changes.

## Scope

**In scope — 15 Lambdas across 5 stacks:**

| Stack | Region | Lambdas |
|---|---|---|
| `app-atento-001` | us-east-1 | system, user, commission, commission-tiger-shark, commission-white-shark |
| `app-beta-001` | us-east-1 | system, user, commission |
| `app-demo-001` | us-east-1 | system, user, commission |
| `app-shared-001` | us-east-1 | system, user, commission |
| `app-outbound-atento-br` | sa-east-1 | payroll |

**Lambda packages and their env var contracts** (from `~/Projects/4Shark/lambda/*/lambda_function.rb`):

| Package | Required vars | Optional (with defaults) |
|---|---|---|
| `worker-autoscaling` | `AUTO_SCALING_GROUP_NAME`, `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `METRICS_ENDPOINT`, `PROCESS_NAME`, `REDIS_URL` | `AWS_REGION`, `JOBS_PER_PROCESS`, `EMPTY_QUEUE_CHECK_THRESHOLD`, `REDIS_KEY_TTL`, `REDIS_TIMEOUT` |
| `worker-commission-autoscaling` | same as `worker-autoscaling` | adds `BALANCING_LAMBDA_NAME`, `HTTP_OPEN_TIMEOUT`, `HTTP_READ_TIMEOUT`, `JOB_HISTORY_POINTS`, `JOB_HISTORY_TAIL_POINTS`, `OVER_CAPACITY_PRESSURE_PERCENTAGE_LIMIT`, `REDIS_TTL` |
| `worker-commission-balancing` | `ECS_CLUSTER_NAME`, `REDIS_URL` | `AWS_REGION`, `JOB_HISTORY_POINTS`, `JOBS_PER_PROCESS`, `LOCK_TTL`, `REDIS_TIMEOUT` |
| `worker-payroll-autoscaling` | `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `METRICS_ENDPOINT`, `PROCESS_NAME`, `MINIMUM_CAPACITY`, `MAXIMUM_CAPACITY`, `REDIS_URL` | `AWS_REGION`, `EMPTY_QUEUE_CHECK_THRESHOLD`, `REDIS_KEY_TTL`, `REDIS_TIMEOUT` |

**`REDIS_URL` handling:** stored as plain Lambda env var (option a). The credential leaks to anyone with `lambda:GetFunctionConfiguration` — protection is delegated to IAM. Phase 0 verifies the engineer baseline cannot read env vars without MFA. A future migration to AWS Parameters and Secrets Lambda Extension is out of scope for this plan.

**Out of scope:**
- Changes to the Lambda Ruby code (env var contracts stay as-is)
- The autoscaling logic itself (capacity rules, scheduling cadence)
- The `lambda-iam` module
- Lambdas that are not autoscalers (e.g., `Lambda-app-atento-001-codedeploy-hook`)
- Migration of `REDIS_URL` to SSM/Lambda Extension (separate plan, future)

## Decisions

Resolved with the engineer:

1. **`REDIS_URL` storage**: option (a) plain env var. The engineer-baseline IAM design correctly gates env var reads behind MFA (verified in Phase 0). One known exception: `paulo@4shark.com.br` has `AdministratorAccess` attached directly to the user, bypassing the MFA gate. Engineer accepted this temporarily ("manter como admin por hora ate ficar redondo") — to be revisited when the migration is complete and the model is fully validated. Emerson's user inherits only from the `engineers` group and is correctly gated.
2. **`commission_variants` shape**: refactored from `list(string)` to `map(object(...))` so each variant accepts independent tunables. Each client's volume profile differs and the variable exists exactly for that purpose.
3. **Per-stack capacity**: every operational tunable (`JOBS_PER_PROCESS`, `MAXIMUM_CAPACITY`, `MINIMUM_CAPACITY`, etc.) is a Terraform `variable` with a sensible default; per-stack values come from `terraform.tfvars`.
4. **`variable` over `local`**: all tunables go through `variable` so they appear in `tfvars` for per-stack override. After this migration, follow up to standardize existing `local` definitions across the repo (kaizen).
5. **Single PR for module refactor**: module change is its own PR, applied as a no-op against the first stack (beta-001) to validate; subsequent stacks each get their own PR.

## Approach

Refactor the module to accept env vars as input, capture each Lambda's current values from AWS, then migrate stacks one at a time with zero-drift applies.

### Phase 0 — IAM verification

Before any code change, confirm that the engineer baseline (no MFA) cannot read Lambda env vars:

```bash
unset AWS_PROFILE
aws lambda get-function-configuration --function-name Lambda-app-atento-001-worker-system-autoscaling --region us-east-1 --query 'Environment.Variables'
```

Expected: `AccessDeniedException`. If it succeeds, baseline IAM has a gap that must be fixed in `identity/` before this plan continues. The grep against `identity/` policies suggests the gap does not exist (`lambda:GetFunctionConfiguration` lives only in `policy_engineer_terraform_services.tf` which requires MFA), but runtime check is mandatory — IAM evaluation includes group memberships and other policies the grep cannot see.

Same check for SSM and Secrets Manager (these aren't used today but the verification is cheap):

```bash
aws ssm get-parameter --name /any/path --region us-east-1
aws secretsmanager get-secret-value --secret-id any-secret --region us-east-1
```

Both must return `AccessDenied` without MFA.

### Phase 1 — Snapshot

**Status: COMPLETE.** Snapshot captured at `/tmp/lambda_env_snapshot_20260505/` (15 JSON files, one per Lambda). Verification script at `/tmp/verify_lambda_env_vars.sh` confirmed every Lambda has all required env vars per its Ruby package contract — zero pre-existing gaps.

**Universe of keys to migrate** (configured today, smaller than the full Ruby ENV contract — optionals not set use Ruby defaults):

| Package | Keys actually configured |
|---|---|
| `worker-autoscaling` (system, user) — 6 lambdas | `AUTO_SCALING_GROUP_NAME`, `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `JOBS_PER_PROCESS`, `METRICS_ENDPOINT`, `PROCESS_NAME`, `REDIS_URL` |
| `worker-commission-autoscaling` (commission + 2 variants in atento-001) — 8 lambdas | same 7 keys |
| `worker-payroll-autoscaling` (payroll) — 1 lambda | `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `JOBS_PER_PROCESS`, `MAXIMUM_CAPACITY`, `METRICS_ENDPOINT`, `MINIMUM_CAPACITY`, `PROCESS_NAME`, `REDIS_URL` |

The Terraform variables only need to model these keys. Optional vars in the Ruby code that aren't set today (`EMPTY_QUEUE_CHECK_THRESHOLD`, `JOB_HISTORY_POINTS`, `OVER_CAPACITY_PRESSURE_PERCENTAGE_LIMIT`, etc.) stay unset — adding them later means appending to the variable map.

**Original capture script:** `/tmp/snapshot_lambda_env_vars.sh` (re-runnable for post-apply verification).

```bash
mkdir -p /tmp/lambda_env_snapshot_<timestamp>
for fn in <list of 16>; do
  aws lambda get-function-configuration --function-name "$fn" --region "$region" \
    --profile 4shark-mfa --query 'Environment.Variables' --output json \
    > "/tmp/lambda_env_snapshot_<timestamp>/${fn}.json"
done
```

Cross-check each snapshot against the Ruby code's required-var list — any missing required var is a pre-existing bug that must be fixed before migration. Already-known shape from the investigation in this plan: all 13 stacks-app lambdas share the same set of vars; only payroll has `MINIMUM_CAPACITY`/`MAXIMUM_CAPACITY`.

### Phase 2 — Big-bang migration (single PR)

**Strategy revision (2026-05-05):** the original phased approach (module-only PR first, then per-stack PRs) was found unworkable during execution. `lifecycle.ignore_changes` is module-level — once removed, every stack consuming the module is affected simultaneously. The first plan against `app-beta-001` showed `0 to add, 21 to change, 0 to destroy`, including 3 Lambdas with all env vars being wiped to `null` (because `var.environment_variables = {}` default → dynamic block doesn't render → Terraform interprets as "no env vars desired"). Engineer chose option A: do everything in a single PR.

**The single PR contains:**

1. **Module refactor** (`modules/lambda-ecs-autoscaling/`):
   - Add `environment_variables` input (`map(string)`, sensitive, default `{}`)
   - Add `dynamic "environment"` block keyed on `length(var.environment_variables) > 0`
   - Remove `lifecycle { ignore_changes = [environment] }`
   - Update README

2. **Per-stack wiring** — for each of the 5 stacks, populate `environment_variables` with values matching the Phase 1 snapshot exactly. Sources of truth:
   - Required infrastructure-derived values (`ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `AUTO_SCALING_GROUP_NAME`, `PROCESS_NAME`) → interpolated from existing Terraform resources/locals
   - Stack-level config (`REDIS_URL`, `METRICS_ENDPOINT`) → new `variable` declarations + values in `terraform.tfvars`
   - Tunables (`JOBS_PER_PROCESS`, `MINIMUM_CAPACITY`, `MAXIMUM_CAPACITY`) → new `variable` declarations with sensible defaults
   - For atento-001 only: refactor `commission_variants` from `list(string)` to `map(object(...))` for per-variant tunable overrides

3. **Validation criterion**: `terraform plan` against each stack must show **zero changes** to Lambda env vars across all 15 Lambdas. Pre-existing drift on unrelated resources (e.g., 18 ASG/launch template drifts surfaced in beta-001) is reported but does not block this PR — those are separate issues to triage on their own.

**Migration order in the PR** (this is just the order in which files are edited; all changes ship together):
- Module refactor first (already in progress in this worktree)
- beta-001 → demo-001 → shared-001 → outbound-atento-br → atento-001

**Apply order** (after PR is opened and engineer approves each plan):
- One stack at a time. Same order. Each apply is its own command, reviewed independently.
- If any apply touches a Lambda env var unexpectedly, abort and re-snapshot before proceeding.

Each stack still follows the per-stack template below for its file edits:

#### 3a. Variables (`variables.tf`)

For each Lambda's tunable env vars, declare a Terraform variable with a sensible default. Example for a `worker-autoscaling` Lambda (system/user):

```hcl
variable "worker_system_jobs_per_process" {
  type    = number
  default = 500
}

variable "worker_system_redis_url" {
  type      = string
  sensitive = true
}
```

The required infrastructure-derived vars (`ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `AUTO_SCALING_GROUP_NAME`, `PROCESS_NAME`) are NOT variables — they come from existing Terraform resources via interpolation.

`METRICS_ENDPOINT` and `REDIS_URL` are per-stack variables (each stack has its own HireFire token and Redis instance).

#### 3b. `commission_variants` refactor

Change from `list(string)` to `map(object(...))`:

```hcl
variable "commission_variants" {
  type = map(object({
    jobs_per_process                        = optional(number, 500)
    job_history_points                      = optional(number, 60)
    job_history_tail_points                 = optional(number, 10)
    over_capacity_pressure_percentage_limit = optional(number, 125)
    empty_queue_check_threshold             = optional(number, 3)
  }))
  default = {}
}
```

In `terraform.tfvars` (atento-001 example):

```hcl
commission_variants = {
  tiger-shark = {
    jobs_per_process = 500
  }
  white-shark = {
    jobs_per_process = 500
  }
}
```

The same pattern applies to base lambdas — each gets its own tunable map (or grouped as a similar `var.base_lambdas`). Final shape decided at execution time based on what reads cleanest.

#### 3c. Wire env vars into the module

In `lambda.tf` (or `compute.tf`), build a per-Lambda env var map and pass it to the module:

```hcl
locals {
  lambda_env_vars = {
    "system" = {
      AUTO_SCALING_GROUP_NAME = aws_autoscaling_group.worker_system.name
      ECS_CLUSTER_NAME        = local.lambda_cluster_name
      ECS_SERVICE_NAME        = module.ecs_services.service_arns["${local.environment}-worker-system-service"]
      METRICS_ENDPOINT        = var.metrics_endpoint
      PROCESS_NAME            = "worker_system"
      REDIS_URL               = var.redis_url
      JOBS_PER_PROCESS        = tostring(var.worker_system_jobs_per_process)
    }
    # ... per Lambda ...
  }
}

module "lambda_function" {
  # ... existing ...
  environment_variables = local.lambda_env_vars[each.key]
}
```

#### 3d. Plan and apply

Per the Terraform Conventions in this repo:
1. Open the PR
2. `terraform plan -out=/tmp/terraform_plan_<stack>_<timestamp>.tfplan 2>&1 | tee /tmp/terraform_plan_<stack>_<timestamp>.txt`
3. **Expected diff**: only `aws_lambda_function.this.environment` changes (one per Lambda in the stack); zero adds, zero destroys
4. Capture the structured summary, surface to engineer, **wait for explicit approval** before apply
5. `terraform apply <plan-file>` from `4shark-mfa` profile
6. Post-apply: re-snapshot the Lambdas, diff against pre-apply snapshot — must be byte-identical (modulo key order)
7. Smoke test: enqueue a job, observe scale-up; let queue drain, observe scale-down
8. Merge

### Phase 4 — Kaizen follow-up (future PR, out of scope here)

After all 5 stacks are migrated, audit the repo for `local` definitions of values that should be `variable` per the decision in this plan. Standardize. Track as a separate task.

## Working environment

All execution work for this plan happens in a **git worktree**, not in the main `~/Projects/4Shark/terraform/` checkout. The main checkout is shared across other Claude sessions and engineers — switching branches there mid-flight breaks their state.

Pattern for each phase that touches code:

```bash
git -C ~/Projects/4Shark/terraform worktree add ../terraform-lambda-env-vars feature/lambda-env-vars-<phase>
```

Each stack PR gets its own branch inside the same worktree (or a fresh worktree per PR if multiple are in flight). After merge, run `/merge-cleanup` and then `git worktree remove` to drop the working copy.

## Risks

| Risk | Mitigation |
|---|---|
| Apply silently wipes an env var that was set manually but missed in capture | Pre-apply snapshot of every Lambda, post-apply diff. PR review checks that `local.lambda_env_vars` covers every key in the snapshot. |
| Removing `ignore_changes = [environment]` causes drift on every plan if values still differ | First plan after refactor MUST be reviewed line-by-line. If anything unexpected appears, abort and re-snapshot. |
| `REDIS_URL` becomes visible in `terraform show` / state file / PR diff | `sensitive = true` on the variable. Value lives in `terraform.tfvars` (git-ignored or vault-managed per repo convention — verify before commit). |
| Engineer baseline can read env vars without MFA (Phase 0 fails) | Stop the migration. Open separate PR in `identity/` to move `lambda:GetFunctionConfiguration` to MFA layer if it leaked. Resume after fix. |
| Variant Lambdas (tiger-shark, white-shark) need different tunables and the existing `for_each` pattern can't represent it | Resolved — `commission_variants` becomes `map(object(...))` with per-variant fields. |
| Pre-existing required-var bug surfaces (e.g., a Lambda missing `PROCESS_NAME` in AWS today) | Phase 1 snapshot diff catches this; surface as separate fix before migration. |

## Phases

1. **Phase 0 — IAM verification** ✅: confirmed baseline IAM gates env var reads behind MFA (Paulo's AdministratorAccess override accepted temporarily).
2. **Phase 1 — Snapshot** ✅: 15 Lambdas captured at `/tmp/lambda_env_snapshot_20260505/` and persisted to plan folder. Zero pre-existing gaps.
3. **Phase 2 — Big-bang migration** (in progress, single PR): module refactor + 5 stacks populated + `terraform plan` showing zero Lambda env var changes per stack + apply each stack independently with engineer approval.
4. **Phase 3 — Kaizen** (separate plan, future): standardize remaining `local` tunables to `variable` across the repo.

## Deliverables per stack PR

- Updated `variables.tf` with per-Lambda tunable variables
- Updated `terraform.tfvars` with current values (snapshot from Phase 1)
- Updated `lambda.tf`/`compute.tf` wiring `environment_variables` into the module
- Captured `terraform plan` text output saved to `/tmp/`
- Pre-apply env var snapshot retained in plan folder for audit
- Post-apply env var snapshot showing zero drift
- Changelog entry: `Changed → Lambda autoscaler configuration`
