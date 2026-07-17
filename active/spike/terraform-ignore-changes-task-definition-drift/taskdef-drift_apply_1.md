# Auxiliary — raw evidence from the `track_latest` apply-and-revert (2026-07-16)

Preserves the primary evidence for **F23, F24, F25** in `SPIKE.md`. Two provenance classes, kept explicitly separate:

- **[MAIN-TRACE]** — the coordinator's own tool results from the apply/revert session (terraform plan/apply output, state inspection, S3 object versions). These are primary evidence for this spike; they are NOT re-derivable now because the change has been reverted.
- **[VERIFIED-HERE]** — re-read directly by `@agent-spike` during this pass, against the live repo. Every `file:line` in `SPIKE.md` traces to this class.

> **Verification note.** The briefing that commissioned this pass carried three citation errors, each caught by re-reading the source: `deploy-shared-001.yaml:828` is actually **:842**; the uncertainty resolved is **#5**, not #8 (#8 is the unrelated CodeDeploy-rewrites-`taskDefinition` question, still open); and the config/GHA `command` divergence is **not scoped to the runner** — it holds for **every service in every app stack** (E7). Per the citation discipline, the verified values are what `SPIKE.md` states.

---

## E1 [VERIFIED-HERE] — `track_latest` is fully reverted from the repository

```
$ grep -rn "track_latest" ~/Projects/4Shark/terraform --include='*.tf'
(no matches)

$ git -C ~/Projects/4Shark/terraform branch --show-current
develop

$ git -C ~/Projects/4Shark/terraform status --short
(clean)
```

The module's task definition resource carries no `track_latest` argument today. The apply described in E2–E5 happened on a feature branch and was reverted at the state layer (E6); the code side is clean on `develop`.

---

## E2 [MAIN-TRACE] — The enabling apply IS a silent no-op

Plan, on each of `beta-001` / `demo-001` / `atento-001`, with `track_latest = true` added to `aws_ecs_task_definition.this` only (the service's `ignore_changes` untouched):

```
Plan: 0 to add, 9 to change, 0 to destroy.
```

Every one of the 9 changes was of the shape:

```
  ~ track_latest = false -> true
    # (17 unchanged attributes hidden)
```

No `aws_ecs_service` resource appeared in any change set.

Apply result, all three stacks:

```
Apply complete! Resources: 0 added, 9 changed, 0 destroyed.
```

Post-apply verification: **no new task definition revision was registered by the apply.** The only new revision on the account at the time, `atento-001-worker-user:33`, was registered at 12:44 (hours before the apply) by:

```
registeredBy: arn:aws:iam::405749097490:user/app-atento-001
```

— the GitHub Actions deploy user, not Terraform. Every service remained `desired == running` on its pre-existing task definition pointer.

**What this sustains:** the *enabling* apply is inert, exactly as the two-step plan's premise assumed. That half of the premise is confirmed.

---

## E3 [MAIN-TRACE] — The NEXT plan is permanently dirty (the premise's other half fails)

With `track_latest = true` now in **both** config and state, the next plan on `beta-001`:

```
Plan: 7 to add, 0 to change, 7 to destroy.
```

Every task definition reports `must be replaced`. Representative diff:

```
# module.ecs_services["beta-001-runner-service"].aws_ecs_task_definition.this must be replaced
  ~ container_definitions = jsonencode(
      ~ [
          ~ {
              - command          = [
                  - "sleep",
                  - "infinity",
                ]
              - mountPoints      = []
                name             = "beta-001-runner"
              - systemControls   = []
              - volumesFrom      = []
            }
        ] # forces replacement
    )
  ~ revision = 82 -> (known after apply)
```

**Reading the diff direction.** The `-` lines are fields present in the **AWS-registered revision** that Terraform's rendered config does **not** contain. Terraform is no longer comparing its config against its own stale state entry — it is comparing against what AWS actually has. Four fields differ; `command` is the load-bearing one (E7 explains why it is absent from config). `mountPoints`/`systemControls`/`volumesFrom` are empty-array fields present on the registered revision and absent from the module's `jsonencode` block — recorded as observed, with no claim here about which side originates them.

**What this sustains:** the *steady state* is NOT inert. This falsifies the second half of the two-step premise — that a later un-ignore of `task_definition` would be a no-op.

---

## E4 [MAIN-TRACE] — State inspection: what the apply actually rewrote

Before the apply, state held Terraform's **own** revision with Terraform's **own** content. After, state holds **GHA's** revision with **GHA's** content.

Byte-level diff of the two S3 state object versions:

| Property | Before | After |
|---|---|---|
| `serial` | 128 | 129 |
| `lineage` | *(identical)* | *(identical)* |
| resource count | 14 | 14 |
| changed fields | — | `track_latest`, `arn`, `revision`, `container_definitions` |

Nothing was created or lost. Example, `beta-001-runner`:

```
arn: .../beta-001-runner:80  ->  .../beta-001-runner:82
```

**What this sustains:** the mechanism behind E3. `track_latest = true` re-pointed Terraform's state at the latest ACTIVE revision (GHA's), which is exactly what the argument is documented to do (F17). The permanent diff is the consequence, not a bug in the argument.

---

## E5 [MAIN-TRACE] — Why the revert was NOT done via `terraform apply`

The revert plan (removing `track_latest` from config, state still holding GHA's revision) would have produced an `N to add / N to destroy` on the task definitions. In AWS API terms:

- the `N to destroy` is a **`DeregisterTaskDefinition`** against GHA's live revisions;
- the `N to add` is a **`RegisterTaskDefinition`** from Terraform's config — the config that, per E7, has no `command`.

That is the #711 shape, deliberately armed: Terraform registers a revision the services do not run, while the services stay pinned to a pointer Terraform ignores (F1/F3). Reverting via plan would have created the exact bomb the spike exists to document.

---

## E6 [MAIN-TRACE] — The revert path actually used: S3 object-version restore

Per stack, the pre-apply state object version was restored:

```
aws s3api copy-object --copy-source '<bucket>/<key>?versionId=<pre-apply-version-id>' ...
```

Pre-flight performed before any write:

1. download both object versions (pre-apply and post-apply);
2. diff them and confirm `serial`, `lineage`, resource count, and the changed-field set match the expectations in E4;
3. only then copy the old version forward.

Post-restore verification, all three stacks:

```
No changes. Your infrastructure matches the configuration.
```

All services `desired == running`. **Zero ECS mutation API calls were made** across the entire revert — no `RegisterTaskDefinition`, no `DeregisterTaskDefinition`, no `UpdateService`.

### E6a [VERIFIED-HERE] — Why no lock had to be invalidated

`app-beta-001/providers.tf:46-51`:

```hcl
  backend "s3" {
    bucket       = "4shark-terraform-state"
    key          = "app-beta-001/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
```

`use_lockfile = true` and no `dynamodb_table` argument — locking is S3-native (a lock object beside the state), so there is no DynamoDB digest entry that a hand-restored state object would leave stale. This is what makes the object-version restore clean rather than a state-surgery hazard.

---

## E7 [VERIFIED-HERE] — The root cause: Terraform's config has NEVER declared `command` for ANY app service

**This is broader than the briefing stated** (which scoped it to the runner). Every service in every app stack lacks a `command` key.

Module default — `modules/ecs_service/variables.tf:132-136`:

```hcl
variable "command" {
  description = "Container command"
  type        = list(string)
  default     = []
}
```

Module render — `modules/ecs_service/main.tf:30`:

```hcl
      command     = length(var.command) > 0 ? var.command : null
```

So an undeclared `command` renders as **`null`** in `container_definitions`.

Scan across all four app stacks, service blocks only (everything before the `scheduled_tasks` map):

```
$ for d in app-beta-001 app-demo-001 app-atento-001 app-shared-001; do
    awk '/^scheduled_tasks/{exit} /^[[:space:]]*command[[:space:]]*=/{print FILENAME":"NR}' \
      ~/Projects/4Shark/terraform/$d/terraform.tfvars
  done
--- app-beta-001 ---     (no matches)
--- app-demo-001 ---     (no matches)
--- app-atento-001 ---   (no matches)
--- app-shared-001 ---   (no matches)
```

The only `command =` keys in those files are under `scheduled_tasks` (which use `modules/ecs_scheduled_task`, the module with no trap — F12). Note `enable_execute_command` is a *different* key and is not a match.

Representative service block, `app-atento-001/terraform.tfvars:217-239` — the runner, verbatim, with its own comment:

```hcl
  # desired_count = 0 permanently — task def exists only to provide image, network
  # config, env vars and secrets for ephemeral debug tasks started via bin/ecs run.
  "atento-001-runner-service" = {
    task_family                  = "atento-001-runner"
    container_name               = "atento-001-runner"
    image                        = "405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-app:latest"
    task_cpu                     = 2048
    task_memory                  = 2048
    container_cpu                = 0
    container_memory             = null
    container_memory_reservation = null
    container_port               = null
    desired_count                = 0

    execution_role_arn     = "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
    task_role_arn          = "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
    enable_execute_command = true

    cloudwatch_log_group_name              = "/ecs/atento-001-runner"
    create_cloudwatch_log_group            = true
    cloudwatch_log_group_retention_in_days = 180
    enable_cloudwatch_logging              = true
  }
```

No `command` key. Same shape for all 9 services in the file.

---

## E8 [VERIFIED-HERE] — The other side: GHA injects `command` at deploy time

`app/.github/actions/deploy-ecs/action.yaml:5-6` — the action's declared input:

```yaml
  command:
    description: 'Container command as JSON array (e.g., ["bundle", "exec", "puma", "-C", "config/puma.rb"])'
```

`action.yaml:87-97` — it reads the current task def, patches `command` into it, and registers a new revision:

```yaml
        # Set container command from input
        jq --arg NAME "$CONTAINER_NAME" \
           --argjson CMD '${{ inputs.command }}' \
          '(.containerDefinitions[] | select(.name == $NAME)).command = $CMD' \
          final-task.json > final-task-cmd.json
        mv final-task-cmd.json final-task.json

        TASK_DEF_ARN=$(aws ecs register-task-definition \
          --cli-input-json file://final-task.json \
          --query 'taskDefinition.taskDefinitionArn' \
          --output text)
```

Every caller passes a concrete command. `app/.github/workflows/deploy-shared-001.yaml` (line numbers verified — the briefing's `:828` is actually `:842`):

```
:388   command: '["bundle", "exec", "puma", "-C", "config/puma.rb"]'
:552   command: '["sleep", "infinity"]'
:579   command: '["bundle", "exec", "sidekiq", "-C", "config/sidekiq_migration.yml"]'
:606   command: '["bundle", "exec", "sidekiq", "-C", "config/sidekiq_cleansing.yml"]'
:842   command: '["bundle", "exec", "sidekiq", "-C", "config/${{ matrix.worker.configuration_file }}"]'
:1039  command: '["sleep", "infinity"]'
```

`deploy-shared-001.yaml:550-556` confirms `:552`'s target is the runner service:

```yaml
      - uses: ./.github/actions/deploy-ecs
        with:
          command: '["sleep", "infinity"]'
          ecr-repo: ${{ env.WEB_ECR_REPO }}
          ecs-cluster: ${{ env.CLUSTER_NAME }}
          ecs-service: ${{ env.RUNNER_SERVICE_NAME }}-service
          service-name: ${{ env.RUNNER_SERVICE_NAME }}
```

Same pattern on `app/.github/workflows/deploy-beta-001.yaml` — the stack whose plan is quoted in E3:

```
:363   command: '["bundle", "exec", "puma", "-C", "config/puma.rb"]'
:527   command: '["sleep", "infinity"]'          # runner
:554   command: '["bundle", "exec", "sidekiq", "-C", "config/sidekiq_migration.yml"]'
:581   command: '["bundle", "exec", "sidekiq", "-C", "config/sidekiq_cleansing.yml"]'
:817   command: '["bundle", "exec", "sidekiq", "-C", "config/${{ matrix.worker.configuration_file }}"]'
```

`:527`'s `["sleep", "infinity"]` is the literal value the E3 plan proposes to remove from `beta-001-runner`.

---

## E9 [VERIFIED-HERE] — Commit `13d32a0`: what it actually claimed, and its scope

Fetched with `git -C ~/Projects/4Shark/terraform log -1 --format=%B 13d32a0`, verbatim:

```
feat(integrator-almaviva): bring environment variables under Terraform management

All ECS services (web, worker, runner) and the scheduled task now declare
their environment variables and SSM secrets via Terraform. Removed
ignore_changes on container_definitions so Terraform has full ownership
of task definition content. Startup commands for web (puma) and worker
(sidekiq) are also declared to match the running task definitions.
```

Two details the SPIKE's F2 did not carry, both load-bearing:

1. **The scope is `integrator-almaviva`** — the commit's own type/scope prefix. It removed `ignore_changes` from the **shared** `modules/ecs_service`, but only declared commands in the stack it was about.
2. **"Startup commands for web (puma) and worker (sidekiq) are also declared"** — declared *there*. Confirmed present, `integrator-almaviva/compute.tf`:

```
:130   command        = ["bundle", "exec", "puma", "-C", "config/puma.rb"]
:171   command        = ["bundle", "exec", "sidekiq"]
:375   command     = ["bin/rails", "integration:cron"]
```

So the "full ownership" claim was **locally true for `integrator-almaviva`** and silently false for the four app stacks, which inherited the module change without ever declaring a command (E7). The commit did not overreach in its own stack; the shared module carried its premise to stacks it did not audit.

**Note the runner asymmetry even in almaviva:** the body says commands were declared for "web (puma) and worker (sidekiq)" — the runner is named in sentence 1 (env vars) but not in sentence 3 (commands). `compute.tf:375` is the scheduled task (`integration:cron`), not a runner service.

---

## E10 — Not researched / deliberately not claimed

- **Why the app stacks never declared `command`** — no source found stating intent. This is recorded as an open uncertainty in `SPIKE.md`, not answered. Neither `git log` on the app stacks' tfvars nor the module README was searched exhaustively for a rationale; a targeted archaeology pass (`git log -S 'command' -- app-*/terraform.tfvars`) was not run and could plausibly settle it.
- **The origin of `mountPoints`/`systemControls`/`volumesFrom`** in the E3 diff — observed as present-on-AWS/absent-from-config. Whether they are `RegisterTaskDefinition` API defaults, carried forward by the GHA action's `describe-task-definition` base, or both, was not traced. Not load-bearing for F23/F24 (`command` alone sustains both), so it is left as an observation.
- **Whether `beta-001`'s 7 task definitions vs the apply's 9 changed resources** reflects a per-stack service-count difference or a plan-scope difference — the numbers come from two different commands in the [MAIN-TRACE] and were not reconciled. Recorded to avoid implying a discrepancy was investigated.
