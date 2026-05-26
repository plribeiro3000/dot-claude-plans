# TASKS — app-outbound-atento-br Migration (app/) ✅ ALL DONE

> **Reference:** `~/.claude/plans/active/app-outbound-atento-br/PLAN.md`
> **Status:** every app-side task in Phases 5b, 6, and 8 is delivered. No pending work in this repo. Migration now waits on Phase 2.5 (Terraform SSM cleanup) and Phase 9 (operational cutover).

## Status Summary (Updated 2026-05-05 — post-Phase 8)

| Task | Phase | Status | Notes |
|---|---|---|---|
| Task 1 — `build-image.yaml` dual-push | 5b | ✅ Completed | app#4953 — atento-001 image to us-east-1 + sa-east-1 ECR |
| Task 2 — HireFire dyno `worker_payroll_tiger_shark` | 6 | ✅ Completed | app#4952 |
| Task 3 — Reusable `deploy-payroll-worker.yaml` | 8a | ✅ Completed | 356 lines. Lock/quiet/deploy/release/cleanup-recovery |
| Task 4 — Sibling job `deploy-payroll` in `deploy-atento-001.yaml` | 8b | ✅ Completed | app#3618a4cbf. Calls reusable workflow with `environment_name: atento-001` |
| Task 5 — Sibling job `deploy-runner-payroll` | 8b extension | ✅ Completed | app#1283f01b8. Refreshes runner task def each deploy so `bin/ecs run app-outbound-atento-br` picks up current code |
| Task 6 — Cross-track rollback | 8b extension | ✅ Completed | app#47eb1ffd9. `rollback-main-on-payroll-failure` + `rollback-payroll-on-main-failure` |
| Task 7 — Cleanup-on-failure recovery hardening | 8a hardening | ✅ Completed | app#4988. Recovers quieted Sidekiq workers via task def rollback or task force-stop |
| Task 8 — E2E validation | 8e | ✅ Completed | 5 consecutive successful production deploys through 2026-04-30 |

---

## Key decisions made during execution

1. **Single GitHub Actions environment for all tracks.** All sibling jobs (main-app, payroll worker, payroll runner) use `environment: atento-001`. The original spec proposed `atento-001-payroll`; rejected because credentials and Redis URLs are shared across the whole atento-001 fleet, and the same IAM user already has sa-east-1 ECR + ECS access via terraform#352. **Rationale:** with N future payroll services for atento-001, all N must deploy under the same invocation — no per-track environment scales cleanly.

2. **Auto-trigger post-build is not implemented and not planned.** Deploys remain manual `workflow_dispatch` per policy. Merging to master fires `build-image.yaml` (which dual-pushes the image), but the deploy is engineer-triggered.

3. **Sibling jobs over matrix.** Original spec called for a top-level `matrix.target` in `deploy-atento-001.yaml`. Rejected because main-app is 13 interdependent jobs (CodeDeploy blue/green, async hook mechanism, per-worker Sidekiq deploy) — gating each with `matrix.target == 'main-app'` would lose per-job UI visibility and retry semantics. Sibling jobs deliver the same parallelism with cleaner observability.

4. **Cross-track rollback added during stabilisation.** Without it, a payroll failure after main-app success (or vice versa) would leave the two tracks on different code revisions. Implemented in app#47eb1ffd9 to keep the whole atento-001 fleet on one version.

5. **Runner service in the outbound cluster.** Added beyond the original plan because `bin/ecs run app-outbound-atento-br` needs a long-lived runner task def to attach to — same pattern as the main-app runner in us-east-1. Task family `app-outbound-atento-br-runner`, `desired_count=0` permanent, refreshed every deploy.

---

## Followups (out of scope for this migration)

- When `deploy-shared-001.yaml` (or any other env) gets its first payroll client, reuse `deploy-payroll-worker.yaml` by adding a sibling job calling it with the new client's infra identifiers. No changes to the reusable workflow itself.
