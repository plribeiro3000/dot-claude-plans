# ANALYSIS — shared-001 connection-pooler outage (secret `app-` prefix)

**Date:** 2026-07-23
**Stack:** `app-shared-001` (productive)
**Trigger question:** when/where/why did the pooler secret naming flip from `shared-001-…` to `app-shared-001-…`, and where is the process gap.

## Summary

The `app-` prefix on the shared-001 connection-pooler secrets was **not** an unplanned or silent change. It was a deliberate, temporary disambiguation used only on shared-001 during a zero-downtime rename (expand/contract) of the legacy `pgbouncer` pooler into the new `connection-pooler`. It was introduced in one commit and removed in the next.

The outage was not caused by the naming choice. It was caused by a **state-vs-reality drift** the standard Terraform workflow cannot see: Terraform state believes the pooler service runs task definition **revision 3** with the standard `shared-001-…` secrets, while the ECS service is actually running **revision 1** with the old `app-…` secrets. The commit that dropped the `app-` prefix renamed the secrets, and because a Secrets Manager secret `name` is ForceNew, that rename **scheduled the old `app-…` secrets for deletion** (2026-07-05). The live service never moved off revision 1, so it kept depending on secrets that were being deleted. The running tasks survived on their already-injected values until they recycled today; on restart they could not fetch the deleted secrets and the pooler went to 0/2.

## Timeline (git evidence)

| Date | Commit | What it did |
|---|---|---|
| Jul 3 18:26 | `77df606` `feat(pooler): stand up connection-pooler alongside pgbouncer (rename expand)` | Created `app-shared-001/connection_pooler.tf` with secrets named `app-shared-001-connection-pooler-*`, `desired_count = 0`. Code comment states the reason verbatim: standing up **ALONGSIDE the legacy pgbouncer.tf pooler during the zero-downtime rename (expand/contract)**. The `app-` prefix avoided a name collision with the legacy pooler that only shared-001 had. |
| Jul 5 09:30 | `c8c89cd` `chore(pooler): standardize connection_pooler.tf across stacks and drop shared secret app- prefix` | Renamed the three secrets back to the standard `shared-001-connection-pooler-*`, set `desired_count = 2`. Secret `name` is ForceNew → this rename destroys the `app-` secrets and creates the `shared-` ones. |
| Jul 5 13:42 | — (apply) | The `app-shared-001-connection-pooler-*` secrets were **scheduled for deletion** — date and time match the `c8c89cd` rename. The `shared-001-…` secrets were created (empty, populated out of band). |
| Jul 6 10:38 | `c7e5641` `refactor(app-shared-001): adopt modules/app…` | Moved the pooler under `module.app`. State reflects this (`module.app.module.connection_pooler.*` present). |
| Jul 15 16:14 / 17:49 | `009a74a` + PR #713 `migrate-pooler-datadog-keys` | Fed the pooler Datadog secret from the per-stack key. |
| Jul 23 (morning) | — | Running pooler tasks recycled; on restart they could not fetch the deleted `app-` secrets → `ResourceInitializationError`, service at 0/2. |

## Root cause

Two facts, established from state and AWS:

- **Terraform state** — `module.app.module.connection_pooler.aws_ecs_task_definition.this` is **revision 3**, `valueFrom` = `shared-001-connection-pooler-{userlist,datadog-api-key,stats-password}` (suffixes `GI2S8o` / `ASlQ3u` / `fGQzLn`).
- **AWS reality** — the ECS service `shared-001-connection-pooler` runs task definition **revision 1**, `valueFrom` = `app-shared-001-connection-pooler-*` (suffixes `lEGExx` / `IBhVpu` / `Qb4aLP`).

State converged to the desired `shared-` generation; the live service never left the `app-` generation. Because `terraform plan` compares **code ↔ state** (both already `shared-`), the plan shows clean and the drift is invisible. When `c8c89cd`'s rename deleted the `app-` secrets, the still-running revision-1 service lost the secrets it depended on — latent, because ECS injects secret values at task start, so the failure only surfaced when the tasks recycled 18 days later.

## Blast radius

**shared-001 only.** The `app-` prefix existed nowhere else. `beta-001`, `demo-001`, and `atento-001` have a single, clean `-connection-pooler-*` secret generation and no `app-` secrets — they were greenfield connection-poolers with no legacy pgbouncer to migrate from, so they never needed the disambiguation. They are not latent time bombs of this kind.

## What was done to restore service (stopgap, 2026-07-23)

1. Rewrote the pooler exec role inline policy to grant `GetSecretValue` on the current (`app-`) ARNs — the policy had been left pointing at an even older ARN set.
2. Restored the three `app-shared-001-connection-pooler-*` secrets from scheduled deletion (values preserved from before Jul 5).
3. Forced a new deployment; the service returned to 2/2 on revision 1 / `app-` secrets.

This is a stopgap. It keeps the service on the non-standard `app-` generation, opposite to the code and state, and the IAM policy edit will be reverted by the next apply.

## Process-improvement opportunities

1. **A ForceNew rename of a secret consumed by a live service is a destroy-and-replace of that dependency.** The contract step (rename/delete the old name) must be gated on the consumer being redeployed onto the new name **and verified running**, never bundled with the rename while a live service still references the old name. The expand/contract discipline was applied to the pooler itself but not to its secrets.

2. **State-vs-reality drift is invisible to `terraform plan`.** Plan compares code ↔ state; it cannot see that AWS runs a different task-def revision than state records. This is the reason the problem went undetected for 18 days with a clean plan. Mitigation: a drift-detection pass (periodic `terraform plan -refresh-only`, or a tool such as driftctl), and/or a post-apply check that the **actual** running task-def revision equals the one in state whenever an apply touched a service.

3. **Secret deletion has a delayed blast radius.** A secret scheduled for deletion keeps running tasks alive but kills the next task start, so the failure detaches from the change that caused it by days or weeks. Mitigation: alert when a secret referenced by a live task definition is scheduled for deletion; and/or force a service redeploy as part of any rename apply, so a broken secret reference fails at apply time — while the engineer is watching — instead of silently later.

4. **Out-of-band-populated secrets return empty on recreation.** The `shared-001-…` secrets created by `c8c89cd` are declared `populated out of band` with `ignore_changes = [secret_string]`, so they were created **empty** and may still be. Any migration onto them must repopulate them first.

## Plan result (2026-07-23) — a plain apply is now a landmine

`terraform plan` on `app-shared-001` returns **1 change**: revert `module.app.module.connection_pooler.aws_iam_role_policy.read_userlist_secret` from the `app-` ARNs (the CLI stopgap) back to the `shared-` ARNs. It sees **no** change for the ECS service or task definition — the refresh did not correct the service's task-def in state, so the rev-1/`app-` reality stays invisible.

Consequence: **a plain `terraform apply` on shared-001 right now would re-break the pooler.** It reverts the exec-role policy to the `shared-` ARNs while the running service is still on revision 1 / `app-` secrets, so the tasks lose permission to the secrets they actually use, and Terraform will not move the service to `shared-` because it believes it is already there. Do not apply shared-001 until the service is reconciled onto the `shared-` generation.

## Reconciliation executed (2026-07-23)

The `shared-` secrets turned out to be already populated — `describe-secret` on `shared-001-connection-pooler-userlist` and `-stats-password` shows a non-Terraform version (plain-UUID version stage) written ~74s after creation on Jul 5, i.e. the out-of-band population was done at rename time. Step 1 was therefore already satisfied. The cutover ran:

1. Widened the exec-role inline policy to allow **both** secret generations (`app-` + `shared-`) — removes the ordering trap so the running rev-1 tasks keep access while rev-3 can pull.
2. Confirmed task-def revision 3 exists in AWS, references the `shared-` secrets, and uses the same exec role.
3. `update-service --task-definition shared-001-connection-pooler:3 --force-new-deployment` — rolling cutover.
4. Verified functionally from the pooler logs: real app clients (users `ezmrcJDJeJaPtVuP` / `DiYtoADDmejVyXhg`, from the app subnets `10.100.x.x`) authenticate and query through the rev-3 tasks. The `shared-` userlist is valid. Reached 2/2 on rev 3, 0 failed tasks. The only warnings were the Datadog sidecar's internal auth-token retry (benign) and the localhost `postgres` stats probe (expected).

State and reality now agree: the service runs rev 3 with the `shared-` secrets.

## Terraform reconciliation — DONE (2026-07-23)

`terraform apply` on `app-shared-001` ran with a saved plan: **0 added, 1 changed, 0 destroyed** — the single change reverted the exec-role policy from the widened (both-generation) CLI stopgap back to the `shared-` ARNs the code declares. A confirming `terraform plan` afterwards returns **"No changes. Your infrastructure matches the configuration."** — state, code, and live AWS fully agree. There was no `.tf` code change and therefore no diff/PR: the code was already correct; the apply only realigned the live IAM policy that the CLI stopgap had drifted.

## Cleanup — DONE (2026-07-23)

The three orphan `app-shared-001-connection-pooler-*` secrets were scheduled for deletion via `delete-secret --recovery-window-in-days 30` (deletion date 2026-08-22, restorable until then). Nothing referenced them after the cutover — the service runs rev 3 / `shared-` secrets and the exec-role policy grants only `shared-`. Post-drop the pooler stayed 2/2 on rev 3.

Blast-radius audit across the account: the `app-` prefix existed only on shared-001, and no pooler secret in any environment is scheduled for deletion — so no other pooler can be in this failure mode.

Final state: pooler reconciled to the canonical `shared-` generation, Terraform state/code/AWS in agreement, orphans scheduled for removal with a 30-day recovery net.

## Original recommended sequence (superseded by the executed reconciliation above)

End state: the service runs the task-def revision that references the `shared-` secrets, the policy grants `shared-`, the `app-` secrets are gone. Because state already believes the service is on revision 3 / `shared-`, this must be driven by a deliberate forced redeploy, not a normal apply. Sequence, in order, on a productive stack:

1. **Populate the `shared-` secrets first.** `shared-001-connection-pooler-datadog-api-key` is fed by Terraform from the per-stack key, but `-userlist` and `-stats-password` are `ignore_changes` / out-of-band and were created empty — set them to the same values the running `app-` secrets hold. Nothing else in this list is safe until this is done.
2. **Move the service to the `shared-` revision** — `aws ecs update-service --task-definition shared-001-connection-pooler:3 --force-new-deployment` (or `-replace` the service in Terraform). This is what actually reconciles the rev-1/`app-` reality with state.
3. **Verify** the running task def is the `shared-` one and tasks are healthy at 2/2 before continuing.
4. **Apply Terraform** — now the pending IAM-policy revert to the `shared-` ARNs is correct, because the service uses `shared-`. The CLI stopgap stops being drift.
5. **Re-schedule the `app-` secrets for deletion** (the contract), properly this time — after the consumer is confirmed off them.
