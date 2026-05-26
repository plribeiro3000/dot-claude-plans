# Variable Validation for Blue/Green Deployment Workflow

**Status:** Completed — Implemented across all 4 deploy workflows (beta-001, demo-001, shared-001, atento-001).

## Context

The Lambda project (`worker-autoscaling`) implements a pattern where all required environment variables are validated at the start of execution. If any variable is missing, the process fails immediately with a clear error message instead of failing mid-execution with a cryptic error.

```ruby
# Lambda pattern for required variables
ecs_cluster_name = ENV.fetch('ECS_CLUSTER_NAME') { raise 'ECS_CLUSTER_NAME is required.' }

# Lambda pattern for optional variables with defaults
aws_region = ENV.fetch('AWS_REGION', 'us-east-1')
```

This same pattern should be applied to the GitHub Actions workflow to prevent deployment failures mid-process due to missing secrets or configuration.

## Problem Statement

Currently, the workflow has partial validation:
- **Redis URLs**: Already validated with fallback chain and clear error message
- **AWS credentials**: No validation - would fail with generic AWS CLI error mid-deployment
- **GitHub secrets**: No early validation - failures occur when the secret is first used

A failure mid-deployment (e.g., during `deploy-sidekiq`) leaves the system in an uncertain state, requiring manual intervention.

## Required Secrets Analysis

### Critical Secrets (deployment will fail without these)

| Secret | Used In | Current Validation |
|--------|---------|-------------------|
| `AWS_ACCESS_KEY_ID` | All jobs with AWS operations | None - fails on first AWS CLI call |
| `AWS_SECRET_ACCESS_KEY` | All jobs with AWS operations | None - fails on first AWS CLI call |
| `REDIS_LOCK_URL` or `REDIS_SIDEKIQ_URL` | `acquire-lock`, `success`, `cleanup-on-failure` | Has fallback chain but incorrectly includes `REDIS_URL` |

### Redis URL Strategy (Important)

The current implementation has an incorrect fallback chain: `REDIS_LOCK_URL → REDIS_SIDEKIQ_URL → REDIS_URL`

**This is wrong because:**
- `REDIS_URL` is the generic cache Redis with eviction policy
- Locks stored in a cache Redis can be evicted, causing autoscaling conflicts
- Production environments MUST use dedicated Redis (either `REDIS_LOCK_URL` or `REDIS_SIDEKIQ_URL`)
- The fallback to `REDIS_URL` was intended only for dev/staging convenience, but should not be codified as standard behavior

**Correct validation:**
1. Check if `REDIS_LOCK_URL` exists → use it
2. Else, check if `REDIS_SIDEKIQ_URL` exists → use it
3. Else → **ERROR** (do NOT fallback to `REDIS_URL`)

### Environment Variables (defined in workflow)

These are hardcoded in the workflow `env:` section and don't need runtime validation:
- `AWS_REGION`
- `CLUSTER_NAME`
- `ENVIRONMENT`
- `WEB_SERVICE_NAME`
- `WEB_ECR_REPO`
- `CODEDEPLOY_APP_NAME`
- `CODEDEPLOY_DEPLOYMENT_GROUP`
- `CODEDEPLOY_HOOK_LAMBDA_ARN`
- `SIDEKIQ_SERVICES`

## Proposed Options

### Option A: Add `validate-secrets` Job at Workflow Start (Recommended)

Create a new job that runs first in the workflow and validates all required secrets.

```yaml
jobs:
  validate-secrets:
    name: Validate Secrets
    runs-on: ubuntu-latest
    environment: poc
    steps:
      - name: Validate required secrets
        run: |
          ERRORS=()

          # AWS credentials
          if [ -z "${{ secrets.AWS_ACCESS_KEY_ID }}" ]; then
            ERRORS+=("AWS_ACCESS_KEY_ID is required")
          fi
          if [ -z "${{ secrets.AWS_SECRET_ACCESS_KEY }}" ]; then
            ERRORS+=("AWS_SECRET_ACCESS_KEY is required")
          fi

          # Redis URL for locks (REDIS_LOCK_URL or REDIS_SIDEKIQ_URL required)
          # NOTE: REDIS_URL (generic cache) is NOT acceptable - it has eviction policy
          if [ -z "${{ secrets.REDIS_LOCK_URL }}" ] && \
             [ -z "${{ secrets.REDIS_SIDEKIQ_URL }}" ]; then
            ERRORS+=("REDIS_LOCK_URL or REDIS_SIDEKIQ_URL is required (REDIS_URL is not acceptable - cache Redis has eviction policy)")
          fi

          if [ ${#ERRORS[@]} -gt 0 ]; then
            echo "============================================"
            echo "  MISSING REQUIRED SECRETS"
            echo "============================================"
            for ERROR in "${ERRORS[@]}"; do
              echo "  - $ERROR"
            done
            echo ""
            echo "Configure these secrets in GitHub Environment: poc"
            exit 1
          fi

          echo "[OK] All required secrets are configured"

  setup:
    needs: validate-secrets
    # ... rest of setup job
```

**Pros:**
- Fails fast before any deployment actions
- Clear, centralized error messages
- Easy to maintain and extend
- Follows Lambda pattern

**Cons:**
- Adds one more job to the workflow (minimal overhead)

### Option B: Validate in `setup` Job

Add validation step at the beginning of the existing `setup` job.

```yaml
jobs:
  setup:
    name: Setup
    runs-on: ubuntu-latest
    environment: poc  # Must add environment to access secrets
    outputs:
      sidekiq_services: ${{ steps.export.outputs.sidekiq_services }}
    steps:
      - name: Validate required secrets
        run: |
          # Same validation logic as Option A

      - name: Export Sidekiq services config
        id: export
        run: |
          # ... existing logic
```

**Pros:**
- No additional job
- Fewer resources used

**Cons:**
- Requires adding `environment: poc` to `setup` job (currently doesn't have it)
- Mixes concerns (validation + configuration export)

### Option C: Validate in Each Job Independently

Add validation step at the start of each job that needs secrets.

**Pros:**
- Jobs are self-contained

**Cons:**
- Duplicated code across multiple jobs
- Validation happens multiple times
- Not a "fail fast" approach

## Recommendation

**Option A (dedicated `validate-secrets` job)** is recommended because:

1. **Follows the Lambda pattern**: Validates everything at the start, before any side effects
2. **Clear separation of concerns**: Validation is isolated from deployment logic
3. **Single point of failure**: If secrets are missing, workflow fails immediately with a clear message
4. **Easy to extend**: Adding new required secrets only requires editing one place
5. **Clean job graph**: The validation job becomes a clear prerequisite in the workflow visualization

## Implementation Notes

### Job Dependencies

The `validate-secrets` job should be the first job in the chain:

```
validate-secrets → setup → acquire-lock → sidekiq-quiet-mode → ...
```

### Secret Access Pattern

The workflow uses `environment: poc` to access secrets. The `validate-secrets` job must have this environment configured.

### Error Messages

Error messages should be clear and actionable:
- Name the missing secret
- Specify where to configure it (GitHub Environment: poc)
- For Redis, explain the fallback chain

### Testing

After implementation, test by:
1. Temporarily removing a required secret
2. Running the workflow
3. Verifying it fails at `validate-secrets` with a clear message

## Files to Modify

- `.github/workflows/deploy-bluegreen-poc.yaml`
  - Add new `validate-secrets` job
  - Update `setup` job to depend on `validate-secrets`
  - **Fix Redis fallback chain**: Remove `REDIS_URL` from fallback, only use `REDIS_LOCK_URL` → `REDIS_SIDEKIQ_URL`
  - Update error message in `acquire-lock` to reflect the correct Redis requirements
  - Update `success` and `cleanup-on-failure` jobs with same Redis logic

- `.github/workflows/DEPLOY-BLUEGREEN.md`
  - Update Required Secrets section to remove `REDIS_URL` from fallback chain
  - Clarify that `REDIS_LOCK_URL` or `REDIS_SIDEKIQ_URL` is required (cache Redis not acceptable)

## Summary of Changes

1. **Add `validate-secrets` job** - Validates all required secrets at workflow start
2. **Fix Redis fallback chain** - Remove `REDIS_URL` from fallback, require dedicated Redis
3. **Update documentation** - Reflect correct Redis requirements

## Questions for Review

1. Should we keep the Redis validation in `acquire-lock` as defense-in-depth, or is `validate-secrets` sufficient?
2. Are there other secrets used by the `deploy-ecs` action that should be validated?
