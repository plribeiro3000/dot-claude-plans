# PLAN — Cron Durability & Observability (app envs)

## Context

On **2026-05-31 ~11:54 UTC**, `paulo@4shark.com.br` deleted the SSM parameter
`/shared-001/MIGRATION_DATABASE_URL` (and the same key in `atento-001`, `demo-001`,
`beta-001`) — correct, because it is a **GitHub Actions deploy-time secret**, not an
SSM-backed task secret. It is injected only by the migration runner during deploy
(`app/.github/workflows/deploy-shared-001.yaml:443-446`) as an override of
`DATABASE_URL`; the migration task even strips the `DATABASE_URL` secret first
(`:423`). No long-lived/cron task should ever reference it.

But every **`shared-001-cron-*`** task definition still referenced
`/shared-001/MIGRATION_DATABASE_URL` as a secret. From the **12:01 UTC** run onward,
each hourly invocation failed at `ResourceInitializationError` /
`TaskFailedToStart` — the container never started, so no app logs, no partials.
**All 7 shared-001 crons were silently dead for ~10 days.**

### Root cause (two layers)

1. **Deploy carry-forward.** `register-cron-tasks`
   (`deploy-shared-001.yaml:573-598`) rebuilds each cron task def by
   `describe-task-definition` of the **live** revision, `jq del(...)` of metadata
   only (never touches `.secrets`), updates the image, re-registers. The stale
   `MIGRATION_DATABASE_URL` secret was copied forward on every deploy — including
   rev 47 (2026-06-09). The deploy **perpetuated** the break, never re-reading
   source of truth.
2. **Terraform drift.** `app-shared-001/scheduled-tasks.tf:55-77` calls
   `../modules/ecs_scheduled_task` **without passing `secrets`** → module default
   `[]` (`modules/ecs_scheduled_task/variables.tf:109`). The module's task def has
   **no `lifecycle { ignore_changes }`** (`modules/ecs_scheduled_task/main.tf:44`).
   So the live secrets list (22 entries) exists only because of the deploy
   carry-forward; a `terraform apply` today would register the crons with
   `secrets=[]` and break them a **different** way (no `DATABASE_URL`).

### Detection gap (why 10 days passed silently)

- **No cron/scheduler alarm exists for `shared-001` or `atento-001`** (alarm
  inventory: only `ecs-service-down` / `unable-to-place` for the always-on
  *services*, plus rds/opensearch/lambda alarms — nothing for scheduled tasks).
- `demo-001` and `beta-001` *do* have `scheduler-invocations-dropped` +
  `scheduler-target-errors`, **but those would not have caught this**: the
  EventBridge Scheduler invoked `RunTask` **successfully** (the task was created,
  then died at startup). `TargetErrorCount` counts invocation failures, not
  downstream ECS task-start failures → reads 0. Nobody watches
  *"did the cron task start and finish successfully?"*.

## Status — what is already done

- **Point 1 (stop the bleeding): DONE & verified.** Registered clean revision **48**
  for all 7 `shared-001-cron-*` families (live task def minus the
  `MIGRATION_DATABASE_URL` secret; nothing else changed). Schedule targets the
  family-latest (`modules/ecs_scheduled_task/main.tf:81`), so the next tick picks it
  up. Verified: the **14:01 UTC** partial-commissions run succeeded
  (`Enqueued successfully (JID: 49128fb01d9e7d1dbd0c5b38)`). The other 6 self-heal
  on their own schedules. **Infra-only, no code.**

## Blast radius / scope confirmed

- **MIGRATION bug**: `shared-001` only. `atento-001` / `demo-001` / `beta-001` cron
  task defs do **not** reference `MIGRATION_DATABASE_URL` (the param deletion there
  is harmless).
- **Separate anomaly (to audit, not the same bug)**: `atento-001-cron-partial-commissions-generator`
  has `secrets=null` and **no log group** — looks like it has never run. Needs its
  own investigation (Phase 2).
- Envs & crons: `shared-001` (7), `atento-001` (7), `demo-001` (4), `beta-001` (4).

## Decisions (locked with engineer)

- **Alerting mechanism: BOTH layers** (log-based + EventBridge task-state-change).
- **Sequencing: durability first**, then audit, then alerting.
- **Delivery: Terraform** (`monitoring.tf` / `scheduled-tasks.tf` per stack) → PR per
  repo → apply-before-merge. No alarms created ad-hoc via CLI.

## Technical decision (LOCKED with engineer)

**Terraform owns the FULL cron task-def config (env vars + secrets)** — it controls
added **and** removed variables. No deploy path may resurrect a removed one.

Key facts that corrected the earlier (too-narrow) framing:

- The live cron task def carries **57 env vars + 21 secrets**, but the
  `ecs_scheduled_task` module call passes **neither** `environment_variables` nor
  `secrets` (both default empty) — so today the ENTIRE payload lives only in the
  deploy carry-forward, not in Terraform. A clean `terraform apply` would wipe it.
- The `deploy-ecs` composite action (web/services) uses the **same** carry-forward
  shape (`action.yaml:65-94`), so carry-forward is the de-facto provisioning model
  system-wide; Terraform defines the canonical env/secrets for *services*
  (`locals.tf` `local.services`) but **not** for crons.
- `register-cron-tasks` injects **nothing** — it only copies the live task def
  forward and sets `:latest`. So it is NOT the path new variables take; new
  variables come from Terraform + `apply`. But because Terraform passes empty to
  crons today, there is currently **no clean path** to add a cron variable at all.

Consequences (the corrected approach):

- Pass **both** `environment_variables` and `secrets` to the cron module.
  **Option B (engineer's choice): replicate the cron's current full env** — give the
  cron the same env Terraform computes for the web service (inherits the web set,
  "cruft" included) so **nothing the cron has today is dropped**, plus
  `secrets = local.secrets`. Reconciliation step: verify the live 57 env vars are a
  subset of what Terraform provides; add any gap explicitly.
- Image is `:latest` (`terraform.tfvars:42`+; pulled at every scheduled `RunTask`) —
  new code flows without re-registering.
- **Only after** Terraform fully owns env+secrets and is applied, **remove the
  `register-cron-tasks` job** (+ its paired "deregister … registered by this run"
  rollback step + `needs:`/status-aggregation references) in all 4 deploy workflows.
  Removing it before Terraform owns the config would leave new cron variables with
  no path — hence the strict ordering below.

## Phase 1 — Durability (root-cause prevention) — `app` + `terraform`

> Implementation will follow Pattern Priming on the actual workflow/Terraform files
> before editing (read siblings, confirm shape). Validate on **`beta-001` first**,
> then `demo-001`, `atento-001`, `shared-001`. **Strict ordering per env: Terraform
> (step 1) applied BEFORE the workflow change (step 2).**

1. **Terraform — make the cron module own env + secrets** (`scheduled-tasks.tf`
   module call currently passes neither). Pass `secrets = local.secrets` and
   `environment_variables = <web env>` (Option B — the cron inherits the web
   service's full env so nothing it has today is dropped). **Reconciliation:**
   diff the live 57 cron env vars against what Terraform would render; add any var
   present live but absent from the Terraform source. Confirm `terraform plan`
   shows the cron task def converging to the **full** current env+secrets (not `[]`,
   no unexpected drops). One PR per stack; apply-before-merge.
2. **Deploy workflows** (`deploy-<env>.yaml`, all 4): **remove the
   `register-cron-tasks` job** + its paired "deregister cron task definitions
   registered by this run" rollback step + every `needs:` / status-aggregation
   reference. With Terraform owning the task def and image at `:latest`, the job has
   no remaining function and its carry-forward is what resurrects removed vars.
3. Re-verify per env: a `terraform apply` and a full deploy both leave the crons
   healthy (task starts, success marker logged). `beta-001` is the canary.

## Phase 2 — Audit all 4 envs

- For every cron family in all 4 envs: confirm the live task def has the correct
  secret list and that the cron has a recent successful run.
- Resolve the `atento-001` partial-commissions anomaly (`secrets=null`, no log
  group — never ran).
- Output: a per-env/per-cron health table; remediate any other silent failures.

## Phase 3 — Observability (BOTH layers, all 4 envs) — `terraform`

> Tune `treatMissingData` + period to each cron's cadence (hourly / daily / monthly).

1. **Layer A — log-based (catches "didn't run" AND "ran but failed before
   success"):** per-cron CloudWatch **metric filter** on the success marker in
   `/ecs/<env>-cron-<name>` + alarm with `treatMissingData = breaching`, evaluation
   window = cadence + buffer.
2. **Layer B — EventBridge ECS Task State Change (catches failed-to-start /
   non-zero exit):** rule matching `stoppedReason ~ TaskFailedToStart` OR
   `containers[].exitCode != 0` for the cron families → metric → alarm.
3. Wire both to the existing SNS notification target used by the other
   `*-ecs-service-down` alarms.
4. Backfill the `scheduler-invocations-dropped` / `scheduler-target-errors` alarms
   to `shared-001` + `atento-001` for parity (necessary but **not sufficient** —
   Layers A/B are the ones that would have caught this incident).

## Risks

- Editing 4 deploy workflows can break deploys — validate on `beta-001` first.
- `secrets = local.secrets` on crons must include everything the runner needs to
  boot Rails (DATABASE_URL, REDIS_*, MONGO_URL, RAILS_MASTER_KEY, …) — confirm the
  web list is the right superset.
- Alarm tuning: monthly/daily crons need long evaluation windows or they false-alarm.
- `git tag` / version bumps / releases: none implied here; deploy-workflow and
  Terraform changes go through normal PRs.

## Out of scope (this plan)

- The deploy-time GHA secret `MIGRATION_DATABASE_URL` itself is correct as-is — no
  change.
