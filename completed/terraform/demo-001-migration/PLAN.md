# Migration Plan: demo → demo-001

**Status:** Completed — All steps executed. PR #122 merged.

## Context

Create a new `demo-001/` folder following the exact pattern of `beta-001/`. The existing `demo/` folder will be deleted afterwards. Same pattern followed in the beta → beta-001 migration: new folder, not editing the old one.

## AWS State (already collected)

- **Lambda version**: `0.5.0_31ba54d`
- **ASG capacities**: web=12, commission=4, system=3, user=3, tiger-shark=12, white-shark=12, cleansing=12, migration=12 (all min=0)
- **ECS log groups**: none exist
- **Lambda log groups**: 3 exist (commission, system, user) - no retention set
- **Lambda state resources**: 25 resources in `s3://tfstateecs4shark/lambda-autoscaling/demo-001/`
- **ECS state**: in `s3://tfstateecs4shark/demo-001/`
- **No commission-balancing, no variants**
- **IAM user `app-demo-001`**: does NOT exist in AWS. Only `app-poc` exists (not managed by Terraform)
- **IAM user in old ECS state**: does NOT exist as `aws_iam_user.deploy` — old code managed it differently (via module or externally)

## Steps

### Steps 1-9: Create `demo-001/` files ✅ DONE

All 8 files created based on `beta-001/` as template, with demo-001 specific values.

### Step 10: Migrate state ✅ DONE

Two source states merged into one new target:

**Sources:**
1. ECS: `s3://tfstateecs4shark/demo-001/terraform.tfstate` (92 resources)
2. Lambda: `s3://tfstateecs4shark/lambda-autoscaling/demo-001/terraform.tfstate` (25 lambda + 1 archive)

**Target:**
- `s3://4shark-terraform-state/demo-001/terraform.tfstate` (118 resources)

**Process used (corrected from original plan):**

> **Issue found**: `terraform state mv -state=FILE` is **ignored** when a remote backend
> is configured. Terraform always reads/writes from the configured backend, not the
> local file. This made the original approach (using `-state` and `-state-out` flags)
> silently fail.

```bash
cd demo-001/

# 1. Init with new backend
terraform init

# 2. Download both old states
aws s3 cp s3://tfstateecs4shark/demo-001/terraform.tfstate ./old-ecs.tfstate
aws s3 cp s3://tfstateecs4shark/lambda-autoscaling/demo-001/terraform.tfstate ./old-lambda.tfstate

# 3. Push ECS state as base
terraform state push old-ecs.tfstate

# 4. Merge lambda resources via Python (NOT terraform state mv)
terraform state pull > remote-ecs.tfstate
python3 merge_states.py  # Parses both JSON files, copies lambda module resources into ECS state, increments serial

# 5. Push combined state
terraform state push combined.tfstate
```

### Step 11: Resolve IAM user dependency ✅ DONE

> **Issue found**: The new code defines `aws_iam_user.deploy` (resource for `app-demo-001`).
> The `iam_deploy` module receives `iam_user_name = aws_iam_user.deploy.name`, which is
> used in a `count` expression:
> ```hcl
> count = var.create_policy && var.iam_user_name != null ? 1 : 0
> ```
> When `aws_iam_user.deploy` doesn't exist in state (it was never in the old ECS state),
> Terraform treats `.name` as "resource attributes that cannot be determined until apply"
> and **blocks ALL operations** — including `terraform plan`, `terraform import`, etc.
>
> This is a known Terraform limitation. The Terraform error message itself recommends:
> "use the -target argument to first apply only the resources that the count depends on."
>
> **Root cause**: The old `demo/` code did NOT have `aws_iam_user.deploy`. The IAM user
> `app-poc` was created externally. The new `demo-001/` code adds this resource following
> the `beta-001` pattern.
>
> **AWS reality**: User `app-demo-001` does NOT exist in AWS (confirmed via CLI).
> Only `app-poc` exists (unmanaged).

**Process:**

```bash
cd demo-001/

# 1. Verify what will be created (MUST run plan first, NEVER auto-approve)
terraform plan -target=aws_iam_user.deploy

# Expected: 1 to add (aws_iam_user.deploy with name="app-demo-001")
# Must NOT show any other changes

# 2. Apply only the IAM user (user confirms interactively)
terraform apply -target=aws_iam_user.deploy

# 3. Verify the dependency is resolved
terraform state list | grep aws_iam_user
# Expected: aws_iam_user.deploy
```

### Step 12: Import CloudWatch log groups ✅ DONE

Lambda log groups exist on AWS but not in state. Now unblocked because IAM user dependency is resolved.

```bash
cd demo-001/

terraform import 'module.lambda_function["commission"].aws_cloudwatch_log_group.this[0]' /aws/lambda/Lambda-demo-001-worker-commission-autoscaling
terraform import 'module.lambda_function["system"].aws_cloudwatch_log_group.this[0]' /aws/lambda/Lambda-demo-001-worker-system-autoscaling
terraform import 'module.lambda_function["user"].aws_cloudwatch_log_group.this[0]' /aws/lambda/Lambda-demo-001-worker-user-autoscaling
```

No ECS log groups exist, so those will be created fresh.

### Step 13: Remove old IAM deploy resources from state ✅ DONE

> **Issue found**: The migrated state contains `module.iam_deploy` resources attached to
> the old IAM user `app-poc`. The new code points these to `app-demo-001`, causing Terraform
> to **destroy+replace** the policy and policy attachment. Destroying the old policy would
> break `app-poc`'s deploy permissions and take the system offline.
>
> Same issue as beta-001 migration — the old user must keep its existing permissions.
>
> **Root cause**: `module.iam_deploy.aws_iam_policy.deploy[0]` has name `app-poc-deploy-demo-001`
> and `module.iam_deploy.aws_iam_user_policy_attachment.deploy[0]` is attached to `app-poc`.
> New code wants `app-demo-001-deploy-demo-001` attached to `app-demo-001`.
>
> **Fix**: Remove these 2 resources from Terraform state so they become unmanaged (stay in AWS
> for `app-poc`), and Terraform creates fresh ones for `app-demo-001` as ADD instead of REPLACE.

**Process:**

```bash
cd demo-001/

# 1. Remove old IAM resources from state (does NOT delete from AWS)
terraform state rm 'module.iam_deploy.aws_iam_policy.deploy[0]'
terraform state rm 'module.iam_deploy.aws_iam_user_policy_attachment.deploy[0]'
```

### Step 14: Validate

```bash
terraform plan
```

**Expected changes:**
- `aws_iam_policy.deploy_s3_access` → ADD
- `aws_iam_user_policy_attachment.deploy_s3_access` → ADD
- `module.iam_deploy.aws_iam_policy.deploy[0]` → ADD (new, for app-demo-001)
- `module.iam_deploy.aws_iam_user_policy_attachment.deploy[0]` → ADD (new, for app-demo-001)
- CloudWatch log groups (ECS) → ADD (8 new log groups for services)
- CloudWatch log groups (Lambda) → CHANGE (retention updates to imported groups)
- Launch templates → CHANGE (AMI drift: data.aws_ami.ecs_optimized picks newer AMI)
- ASGs → CHANGE (launch template version update from LT changes)
- Lambda IAM policy → CHANGE (autoscaling policy statement split)

**Must NOT appear:**
- **ZERO destroys** — all destroy/replace must become pure ADD
- Any destroy/recreate of ECS cluster, services, ALB, lambdas, capacity providers, schedulers

### Step 15: Apply + verify

```bash
terraform apply
```

User reviews the plan output and confirms interactively.

### Step 16: Cleanup

- Delete temporary state files: `old-ecs.tfstate`, `old-lambda.tfstate`, `remote-ecs.tfstate`, `combined.tfstate`, `current.tfstate`
- Files `demo/` already deleted (git rm done)
- CHANGELOG already updated

### Step 17: Commit + PR

- Single commit with all changes
- PR to develop

## Files Created (all in `demo-001/`) ✅

| File | Source | Adaptations |
|------|--------|-------------|
| `providers.tf` | `beta-001/providers.tf` | Key = `demo-001/terraform.tfstate` |
| `variables.tf` | `beta-001/variables.tf` | None (identical) |
| `locals.tf` | `beta-001/locals.tf` | None (identical) |
| `output.tf` | `beta-001/output.tf` | None (identical) |
| `main.tf` | `beta-001/main.tf` | S3 policy name/description, IAM user name, policy_name_prefix |
| `lambda.tf` | `beta-001/lambda.tf` | None (identical) |
| `config.yml` | `beta-001/config.yml` | None (identical) |
| `terraform.tfvars` | New | Demo-001 specific values |

## Files Deleted ✅

| File | Reason |
|------|--------|
| `demo/` (entire folder) | Replaced by `demo-001/` |

## Issues Found During Execution

### Issue 1: `terraform state mv -state` ignored with remote backends

**Symptom**: `terraform state mv -state=old-lambda.tfstate -state-out=current.tfstate` reported "Successfully moved 1 object(s)" but resources weren't in current.tfstate.

**Root cause**: When a Terraform backend is configured, the `-state` flag is **ignored**. All state operations read/write from the configured backend, regardless of the `-state` flag. The commands were silently operating on the remote state, not on the local files.

**Fix**: Merge state JSON files directly with Python, then push the combined result.

### Issue 2: IAM user count dependency blocks all operations

**Symptom**: `terraform import` and `terraform plan` fail with:
```
Error: Invalid count argument
  count = var.create_policy && var.iam_user_name != null ? 1 : 0
The "count" value depends on resource attributes that cannot be determined until apply
```

**Root cause**: `iam_user_name = aws_iam_user.deploy.name` references a resource that doesn't exist in the migrated state. The old `demo/` code didn't define `aws_iam_user.deploy` — the IAM user `app-poc` was managed externally. The new code follows the `beta-001` pattern with an explicit IAM user resource, creating a dependency chain: `aws_iam_user.deploy` → `module.iam_deploy(iam_user_name)` → `count` expression.

**Fix**: Use `terraform apply -target=aws_iam_user.deploy` to create the IAM user first (Terraform's documented recommendation for count dependencies), then proceed with imports and full plan.

### Issue 3: Old IAM user policy destroy would break running system

**Symptom**: `terraform plan` shows 2 destroy/replace on `module.iam_deploy` resources — policy and policy attachment changing from `app-poc` to `app-demo-001`.

**Root cause**: Migrated state contains IAM deploy resources attached to old user `app-poc`. New code wants them for `app-demo-001`. Terraform plans destroy+create (replacement). Destroying the old policy would remove `app-poc`'s deploy permissions, breaking the running system.

**Fix**: Remove the 2 old resources from state (`terraform state rm`). They remain in AWS unmanaged (keeping `app-poc` functional). Terraform then creates fresh resources for `app-demo-001` as pure ADD operations. Same approach used in beta-001 migration.

## Risks

1. **State migration** - Merging ECS + Lambda states into new bucket. ✅ Mitigated: validated with `terraform state list`.
2. **IAM user creation** - `app-demo-001` is a new user. Must verify with `-target` plan before apply.
3. **CloudWatch import** - Must import existing Lambda log groups before full plan to avoid conflicts.
4. **No destructive changes** - Full plan must show zero destroys on existing infrastructure.
