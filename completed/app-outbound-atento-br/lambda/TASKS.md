# TASKS — app-outbound-atento-br Migration (lambda/) ✅ ALL DONE

> **Reference:** `~/.claude/plans/active/app-outbound-atento-br/PLAN.md`
> **Status (2026-05-05):** Phase 1 (delta read) and Phase 4 (`worker-payroll-autoscaling` v0.9.0) ✅ delivered (lambda#47). Phase 7c (regional bucket migration) ✅ delivered (lambda#49). Phase 8.5 (binary-scale refactor v0.10.0) ✅ delivered (lambda#53 + lambda#54 release). No pending lambda-side work for this migration.

---

## Phase 8.5 — Binary-Scale Refactor ✅ DELIVERED

> **Delivered via:**
> - lambda#53 — `feat(payroll-autoscaling): scale to max on any queued job` (replaced lines 86-102 of `lambda_function.rb` with the binary jump; removed unused `JOBS_PER_PROCESS` read; updated README + CHANGELOG)
> - lambda#54 — `[0.10.0] - 2026-05-05` (release PR; CHANGELOG promoted to `## [0.10.0]`; `git hf release finish` created tag `0.10.0`)
> - `bin/publish_lambdas` — uploaded `worker-payroll-autoscaling/0.10.0_0989a3e.zip` to both `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1`
> - terraform#394 — bumped `lambda_version` in `app-outbound-atento-br/locals.tf` to `0.10.0_0989a3e`; Lambda `lastModified = 2026-05-05T14:36:57Z`

The original step-by-step plan is preserved below for historical reference.

---

## Phase 8.5 — Original Plan (now delivered)

**Goal:** v0.10.0 of `worker-payroll-autoscaling`. On any non-empty queue tick, jump straight to `MAXIMUM_CAPACITY`. Scale-down hysteresis unchanged.

**Steps:**

1. **Edit `lambda/worker-payroll-autoscaling/lambda_function.rb`** — replace lines 86-102 (scale-up branch). Current logic:
   ```ruby
   if jobs_in_queue.positive?
     required_capacity = (jobs_in_queue.to_f / jobs_per_process).ceil
     new_capacity = required_capacity.clamp(minimum_capacity, maximum_capacity)
     if unlocked && new_capacity > current_capacity
       ecs_client.update_service(cluster: ..., service: ..., desired_count: new_capacity)
       ...
   ```
   Replace with:
   ```ruby
   if jobs_in_queue.positive?
     if unlocked && current_capacity < maximum_capacity
       ecs_client.update_service(cluster: ecs_cluster_name, service: ecs_service_name, desired_count: maximum_capacity)
       REDIS.del(redis_key)
       LOGGER.info("ECS Service: #{ecs_service_name} | Scale UP (binary): #{current_capacity} → #{maximum_capacity} | Jobs: #{jobs_in_queue}")
     else
       LOGGER.info("ECS Service: #{ecs_service_name} | Already at max or locked | Current: #{current_capacity}")
     end
   ```
   Scale-down branch (lines 103-119) and the rest stay intact. The `jobs_per_process` local can be deleted (no longer referenced).

2. **Update `lambda/worker-payroll-autoscaling/README.md`** — describe the binary scale rule. Note that `JOBS_PER_PROCESS` is no longer read by this Lambda.

3. **Update `lambda/CHANGELOG.md`** — under `## [Unreleased]` (or new `## [0.10.0]` once tagged), add:
   ```
   ### Changed
   - Payroll autoscaling now scales to MAX immediately on any queued job; scale-down hysteresis preserved
   ```

4. **Release** — run `lambda/bin/publish_lambdas` (the script dual-pushes to `4shark-lambda-artifacts-us-east-1` and `4shark-lambda-artifacts-sa-east-1` since lambda#49). Capture the resulting S3 key — should be `worker-payroll-autoscaling/0.10.0_<sha>.zip`.

5. **Hand off to Terraform side:** report the new artifact key so `terraform/app-outbound-atento-br/compute.tf` can be updated (Phase 8.5 Terraform task).

6. **Validate after Terraform apply:**
   - Empty queue invocation → log `Already at minimum capacity`
   - Enqueue 1 test job in `payroll_tiger_shark` → next 1-min Lambda tick should set `desired_count = 5` (atento-001's `MAXIMUM_CAPACITY`), not gradual
   - Drain the queue → 3 consecutive empty ticks scale back to 0

**Affected files:** `lambda/worker-payroll-autoscaling/lambda_function.rb`, `lambda/worker-payroll-autoscaling/README.md`, `lambda/CHANGELOG.md`

**Effort:** 0.5 day. **Risk:** LOW — single conditional branch change; previous artifact stays in S3 for one-line rollback.

**Per-client tuning:** `MAXIMUM_CAPACITY` is already env-var driven on the Lambda (atento-001 = 5). Future clients pick their own MAX in Terraform — no code change.

---

## Historical task list (Phase 1 + Phase 4, ✅ delivered as lambda#47 / v0.9.0)

The detailed checklist below is preserved as historical reference for how the original Phase 1 (delta read) and Phase 4 (`worker-payroll-autoscaling` v0.9.0) work was structured. All tasks are complete.

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved**
- [ ] **Base branch:** `develop` • **Working branch:** `feature/app-outbound-atento-br` (should already exist)
- [ ] **Phase 0 (EC2 inventory) complete** — queue name, PROCESS_NAME, and environment variables documented
- [ ] **Local environment:** Ruby, Bundler, Redis (local or accessible for manual test) set up

---

## 1) Step by Step (atomic tasks)

### Task 1 — Phase 1: Read and document existing `worker-autoscaling` Lambda
- **Objective:** Understand the existing `worker-autoscaling` Lambda code to identify the exact ASG-specific calls that must be removed for the Fargate variant.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/lambda/worker-autoscaling/lambda_function.rb` in full
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/lambda/worker-autoscaling/README.md` for context
  - [ ] Inspect how `app-atento-001` wires the Lambda via `modules/lambda-ecs-autoscaling` (check `app-atento-001/compute.tf` and `terraform/modules/lambda-ecs-autoscaling/` definition)
  - [ ] Document the following in a temporary note (can be shared with the user or kept in memory):
    - [ ] All `Aws::AutoScaling::Client` instantiations and method calls
    - [ ] The `AUTO_SCALING_GROUP_NAME` env var and where it's used
    - [ ] How `min_size`, `max_size`, and `desired_capacity` are read from the ASG
    - [ ] How `update_auto_scaling_group` is called to change capacity
    - [ ] The queue-depth and busy-worker polling logic (these stay unchanged)
    - [ ] The `ecs_scaling:lock:*` Redis key check (stays unchanged)
    - [ ] The `ecs_scaling:empty_checks:*` hysteresis counter logic (stays unchanged)
    - [ ] Environment variables: which ones are ASG-specific vs. generic (e.g., `AUTO_SCALING_GROUP_NAME` is removed; `MINIMUM_CAPACITY`, `MAXIMUM_CAPACITY` are kept)
    - [ ] AWS region default (currently `us-east-1` in the existing Lambda — must be `sa-east-1` for outbound)
- **Affected files/areas:** `/Users/plribeiro3000/Projects/4Shark/lambda/worker-autoscaling/lambda_function.rb`, `/Users/plribeiro3000/Projects/4Shark/lambda/worker-autoscaling/README.md`
- **Completion criteria:** A clear list of changes documented, ready to guide Task 2. No actual code written yet.
- **Observations:** This is a **research task** — the goal is understanding, not implementation. Take time to read thoroughly; unclear points should be noted and presented to the user if needed.

### Task 2 — Phase 1: Document Lambda interface design and ASG-to-Fargate delta
- **Objective:** Create a documented summary of what the Fargate variant will look like, before writing any code.
- **Actions (checklist):**
  - [ ] Create a temporary design document (can be a comment in the PLAN or a separate file) summarizing:
    - [ ] **Removed:** all `Aws::AutoScaling::Client` calls and `AUTO_SCALING_GROUP_NAME` env var
    - [ ] **Changed:** `MINIMUM_CAPACITY` and `MAXIMUM_CAPACITY` now read directly from `ENV` (not from ASG)
    - [ ] **Changed:** `AWS_REGION` default from `us-east-1` to `sa-east-1` (for the outbound Lambda)
    - [ ] **Kept:** queue-depth polling via `METRICS_ENDPOINT`, busy-worker check via `PROCESS_NAME`, Redis lock/counter keys, ECS calls via `ecs:UpdateService`
    - [ ] **New ECS calls:** instead of ASG's `update_auto_scaling_group`, use `Aws::ECS::Client#update_service` with `desired_count` parameter
    - [ ] **Final env vars list:** `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `METRICS_ENDPOINT`, `PROCESS_NAME`, `MINIMUM_CAPACITY`, `MAXIMUM_CAPACITY`, `AWS_REGION`, `REDIS_URL`, `EMPTY_QUEUE_CHECK_THRESHOLD`
  - [ ] Present this design document to the user for approval before proceeding to code implementation (Task 3)
- **Affected files/areas:** Temporary design note (for review, not committed)
- **Completion criteria:** Design document complete and reviewed with user; no implementation concerns or ambiguities remain
- **[HOLD POINT]** Pause here and present the design to the user for approval before writing code.

### Task 3 — Phase 4: Copy and adapt Lambda code
- **Objective:** Create the new `worker-payroll-autoscaling` Lambda as a Fargate-native variant of `worker-autoscaling`.
- **Actions (checklist):**
  - [ ] Create directory `lambda/worker-payroll-autoscaling/` if it doesn't exist
  - [ ] Copy `lambda/worker-autoscaling/lambda_function.rb` to `lambda/worker-payroll-autoscaling/lambda_function.rb`
  - [ ] Remove all `Aws::AutoScaling::Client` references and imports:
    - [ ] Delete `require 'aws-sdk-autoscaling'` (or similar) from the top of the file
    - [ ] Remove all `@autoscaling_client = Aws::AutoScaling::Client.new(region:)` instantiations
    - [ ] Delete all calls to `describe_auto_scaling_groups` and `update_auto_scaling_group`
  - [ ] Replace ASG-based capacity reads with env-var-based reads:
    - [ ] Change lines like `auto_scaling_group.min_size` to `ENV['MINIMUM_CAPACITY'].to_i`
    - [ ] Change lines like `auto_scaling_group.max_size` to `ENV['MAXIMUM_CAPACITY'].to_i`
  - [ ] Replace ASG scaling calls with ECS calls:
    - [ ] Delete `@autoscaling_client.update_auto_scaling_group(...)` calls
    - [ ] Replace with `@ecs_client.update_service(cluster: cluster_name, service: service_name, desired_count: new_count)`
    - [ ] Ensure `@ecs_client` is already instantiated (should be from the existing code)
  - [ ] Update `AWS_REGION` default from `us-east-1` to `sa-east-1`:
    - [ ] Find the line `ENV['AWS_REGION'] || 'us-east-1'` and change to `ENV['AWS_REGION'] || 'sa-east-1'`
  - [ ] Verify queue-depth polling logic (`METRICS_ENDPOINT` + `PROCESS_NAME`) is unchanged
  - [ ] Verify Redis lock key check (`ecs_scaling:lock:*`) is unchanged
  - [ ] Verify hysteresis counter logic (`ecs_scaling:empty_checks:*`) is unchanged
  - [ ] Verify error handling and logging logic is preserved
- **Affected files/areas:** `lambda/worker-payroll-autoscaling/lambda_function.rb` (new file)
- **Completion criteria:** Fargate-variant Lambda code created with all ASG calls removed, ECS calls in place, environment variable defaults updated, queue and lock logic intact
- **Observations:** The core business logic (queue polling, hysteresis, scaling thresholds) does not change — only the infrastructure calls do.

### Task 4 — Phase 4: Update Gemfile and dependencies
- **Objective:** Ensure the new Lambda has the correct dependencies without ASG-related gems.
- **Actions (checklist):**
  - [ ] Copy `lambda/worker-autoscaling/Gemfile` to `lambda/worker-payroll-autoscaling/Gemfile`
  - [ ] Copy `lambda/worker-autoscaling/Gemfile.lock` to `lambda/worker-payroll-autoscaling/Gemfile.lock`
  - [ ] Remove `aws-sdk-autoscaling` gem from the Gemfile (if present)
  - [ ] Keep `aws-sdk-ecs` gem (needed for ECS calls)
  - [ ] Keep `redis` gem (needed for queue polling)
  - [ ] Run `bundle install` in the new directory to verify no dependency issues
- **Affected files/areas:** `lambda/worker-payroll-autoscaling/Gemfile`, `lambda/worker-payroll-autoscaling/Gemfile.lock` (new files)
- **Completion criteria:** Gemfile updated, no ASG gem present, `bundle install` succeeds

### Task 5 — Phase 4: Create README.md for the new Lambda
- **Objective:** Document the Fargate-native Lambda for future operators and engineers.
- **Actions (checklist):**
  - [ ] Copy `lambda/worker-autoscaling/README.md` to `lambda/worker-payroll-autoscaling/README.md`
  - [ ] Update the README to document:
    - [ ] This is a Fargate-native variant of `worker-autoscaling` (not ASG-based)
    - [ ] Removed env vars: `AUTO_SCALING_GROUP_NAME`
    - [ ] Required env vars: `ECS_CLUSTER_NAME`, `ECS_SERVICE_NAME`, `METRICS_ENDPOINT`, `PROCESS_NAME`, `MINIMUM_CAPACITY`, `MAXIMUM_CAPACITY`, `AWS_REGION`, `REDIS_URL`, `EMPTY_QUEUE_CHECK_THRESHOLD`
    - [ ] Default `AWS_REGION` is `sa-east-1` (not `us-east-1`)
    - [ ] Behavior: polls queue depth and busy workers, scales ECS service up/down via `update_service`
    - [ ] Lock and hysteresis logic unchanged from the original
    - [ ] Links to the ECS service and Lambda Terraform configuration
- **Affected files/areas:** `lambda/worker-payroll-autoscaling/README.md` (new file)
- **Completion criteria:** README clearly explains the Lambda's purpose, env vars, and differences from the ASG variant

### Task 6 — Phase 4: Manual smoke test (local Redis + simulated metrics)
- **Objective:** Verify the Lambda logic works end-to-end with a local Redis and mocked ECS calls.
- **Actions (checklist):**
  - [ ] Set up a local Redis instance (or use an existing one if accessible)
  - [ ] Set up environment variables for local testing:
    - [ ] `ECS_CLUSTER_NAME = test-cluster`
    - [ ] `ECS_SERVICE_NAME = test-service`
    - [ ] `METRICS_ENDPOINT = http://localhost:9292` (or mock server URL)
    - [ ] `PROCESS_NAME = test-process`
    - [ ] `MINIMUM_CAPACITY = 0`
    - [ ] `MAXIMUM_CAPACITY = 5`
    - [ ] `AWS_REGION = sa-east-1`
    - [ ] `REDIS_URL = redis://localhost:6379/0` (or your local Redis)
    - [ ] `EMPTY_QUEUE_CHECK_THRESHOLD = 3`
  - [ ] Create a simple test script (e.g., `test_lambda.rb`) that:
    - [ ] Loads the Lambda function
    - [ ] Calls the Lambda handler with a mock event (or simulates its polling cycle)
    - [ ] Verifies queue-depth reading works with a test Redis key
    - [ ] Verifies scaling thresholds are read from `MINIMUM_CAPACITY` and `MAXIMUM_CAPACITY` env vars (not from ASG)
    - [ ] Mocks the ECS client to verify `update_service` is called (not ASG methods)
    - [ ] Tests the scale-to-zero logic: `MINIMUM_CAPACITY = 0` should allow scaling to 0 tasks
  - [ ] Run the test and verify:
    - [ ] No ASG-related errors
    - [ ] `update_service` is called with correct parameters
    - [ ] Scale-to-zero behavior works (desired_count = 0 is allowed)
    - [ ] Queue depth polling works
  - [ ] Document the test results and any issues found
- **Affected files/areas:** `lambda/worker-payroll-autoscaling/test_lambda.rb` (temporary test file, not committed; can be deleted after passing)
- **Completion criteria:** Manual smoke test passes; Lambda correctly reads env vars, calls ECS, and scales to zero
- **Observations:** This test does not need to integrate with real AWS ECS; mocking the ECS client is sufficient. The goal is to verify the logic changes (ASG removal, ECS integration, env var reads) are correct.

### Task 7 — Phase 4: Package Lambda code and upload to S3
- **Objective:** Create a deployment package (zip file) and upload to S3 for use by Terraform.
- **Actions (checklist):**
  - [ ] Navigate to `lambda/worker-payroll-autoscaling/`
  - [ ] Confirm the `Gemfile.lock` is present (for reproducible builds)
  - [ ] Create a packaging script (or follow the existing pattern from `worker-autoscaling` if one exists):
    - [ ] Install dependencies: `bundle install --deployment` (creates a `vendor/` directory)
    - [ ] Create a zip file: `zip -r worker-payroll-autoscaling.zip lambda_function.rb Gemfile Gemfile.lock vendor/`
    - [ ] Verify the zip includes: `lambda_function.rb`, dependencies in `vendor/`, Gemfiles
  - [ ] Upload to S3 at a consistent key (e.g., `s3://4shark-lambda-deployments/worker-payroll-autoscaling/worker-payroll-autoscaling.zip` or similar per your project convention):
    - [ ] `aws s3 cp worker-payroll-autoscaling.zip s3://4shark-lambda-deployments/worker-payroll-autoscaling/worker-payroll-autoscaling.zip --region us-east-1`
    - [ ] (Adjust bucket and region as needed; verify with existing Lambda deployment pattern)
  - [ ] Document the S3 key for use in Terraform Phase 7
  - [ ] Optionally, store the S3 key in a local variable or environment file for reference
- **Affected files/areas:** `lambda/worker-payroll-autoscaling/` (code ready for deployment); S3 bucket (zip uploaded)
- **Completion criteria:** Lambda zip successfully uploaded to S3; S3 key documented for Phase 7 Terraform invocation
- **Observations:** Follow the existing Lambda deployment pattern in your project (e.g., if there's a CI/CD pipeline for Lambda packaging, use that; if manual, follow the exact structure of the existing `worker-autoscaling` deployment).

### Task 8 — Commit Lambda changes
- **Objective:** Commit all new Lambda files to the feature branch.
- **Actions (checklist):**
  - [ ] Stage all new files in `lambda/worker-payroll-autoscaling/`:
    - [ ] `git add lambda/worker-payroll-autoscaling/lambda_function.rb`
    - [ ] `git add lambda/worker-payroll-autoscaling/Gemfile`
    - [ ] `git add lambda/worker-payroll-autoscaling/Gemfile.lock`
    - [ ] `git add lambda/worker-payroll-autoscaling/README.md`
  - [ ] Commit with a message following Angular guidelines:
    - [ ] `git commit -m "feat(lambda): add worker-payroll-autoscaling Lambda (Fargate-native variant)"`
    - [ ] Include a brief description of the Fargate adaptation (removed ASG calls, ECS calls, env var reads) if needed
  - [ ] Verify the commit appears in `git log`
- **Affected files/areas:** `lambda/worker-payroll-autoscaling/` (committed to feature branch)
- **Completion criteria:** All Lambda files committed; commit message is clear and follows project conventions

---

## 2) Items Requiring User Confirmation

- [ ] **Lambda S3 bucket:** confirm the exact S3 bucket and key path where Lambda zips are stored (e.g., `4shark-lambda-deployments`, key pattern, region). This is needed for Task 7 upload and Phase 7 Terraform.
- [ ] **Metrics endpoint for local testing:** confirm the URL and authentication method for the `METRICS_ENDPOINT` used in smoke testing. If the endpoint is internal/restricted, provide a mock URL or instructions.
- [ ] **Redis access for testing:** confirm whether a local Redis or shared Redis (reachable from your environment) is available for the smoke test in Task 6.
- [ ] **Phase 0 output (required for Task 1 reference):** confirm the PROCESS_NAME value from the EC2 inventory (e.g., `atento-br-outbound`, `app-outbound-atento-br`, etc.). This is used in Lambda testing and Terraform wiring.

---

## 3) Pending Items After This Iteration (if any arise)

- [ ] **Cross-region Lambda testing:** after Phase 7 Terraform (sa-east-1 Lambda created), verify the Lambda can reach the METRICS_ENDPOINT and Redis from sa-east-1 (may require network/VPN verification).
- [ ] **Lambda version pinning:** if your Lambda deployment uses version aliases or explicit versions, document how `modules/lambda-ecs-autoscaling` specifies the Lambda version in Terraform (ARN with version or alias).
- [ ] **Phase 4 completion gates Phase 7:** confirm Phase 4 is fully complete (Lambda uploaded to S3) before Phase 7 Terraform begins; if Phase 4 slips, it blocks Phase 7.
