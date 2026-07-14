# TASKS — Split deploy credentials (runtime + deploy IAM users), Terraform-managed

Derived from `PLAN.md` (same directory). Three PRs, one per group, each on its own day. One commit per PR. Every `apply` is apply-before-merge with `/elevate-aws-access` + `--profile 4shark-mfa`; nothing auto-merges. Reads stay on the default profile.

**Cutover procedure is identical for every stack** — the per-group sections below list only the stacks and their specifics; the procedure is defined once here.

## The per-stack procedure (applies to every stack in every group)

**Task 0 — Confirm topology** (read-only): deploy key pattern (A imported / B native), runtime consumer present?, runtime module present? Note deviations before writing code.

**Phase A — Split (zero runtime impact):**
- [ ] A1. Add new deploy user `<stack>-deploy` + `module "iam_deploy"` + new Terraform-native `aws_iam_access_key`; repoint the GitHub secret (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) to it.
- [ ] A2. `apply`, then **verify a real GitHub Actions deploy** succeeds on the new deploy-only key.
- [ ] A3. Remove `module "iam_deploy"` from the old user; rename `aws_iam_user.deploy` → `aws_iam_user.runtime` via a **`moved {}` block** (state move, never destroy+create).
- [ ] A4. `apply`, then **verify runtime S3** still works (document upload / CarrierWave).

**Phase B — Runtime key under Terraform (Option C):**
- [ ] B1. Replace the runtime user's key with a Terraform-native `aws_iam_access_key` (mint new — 2 keys briefly); wire the runtime SSM `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` from it, dropping `ignore_changes` for **only** those two parameter names.
- [ ] B2. `apply` (old key stays active — no gap).
- [ ] B3. Roll tasks onto the new key — non-prod: redeploy / let cycle; **prod: coordinated redeploy in the blue/green window** (old key active until new tasks healthy).
- [ ] B4. Verify runtime S3 on the new key, then **remove the old key**.

**Definition of done (per stack):** deploy user has no `s3` grant; runtime user has no `iam_deploy`; GitHub deploy is green on the deploy-only key; app S3 works on the runtime key; no manual `aws ssm put-parameter` remains for the two AWS_* names.

---

## PR 1 — Integrator (first — lowest risk, runtime module already exists)

Branch: `feature/split-deploy-credentials-integrator`. Runtime user = the `integrator_iam` module user (`module.iam`); apply the `moved{}` rename against that module's user resource. All internal-only → Phase B has no window concern.

Run the per-stack procedure for each:

| Stack | Deploy key pattern today | Notes |
|---|---|---|
| `integrator-almaviva` | Pattern A (imported) | — |
| `integrator-atento` | Pattern A (imported) | GitHub secret is country-level (`the same key backs every atento country service`) — confirm the deploy user split covers all atento country services |
| `integrator-commcenter` | Pattern A (imported) | — |
| `integrator-maqnelson` | Pattern A (imported) | — |
| `integrator-redebrasil` | Pattern A (imported) | — |

- [ ] Task 0 across all 5 (confirm the `integrator_iam` + `iam_deploy` pairing is on one user, as SPIKE Finding 1 states).
- [ ] Phase A + Phase B per stack (procedure above).
- [ ] Optional: update `ADR-010` naming row for the runtime/deploy split (or defer to a doc follow-up).
- [ ] One commit, PR, apply+verify all 5 before merge, merge on day 1.

## PR 2 — App (second — contains the two productive stacks)

Branch: `feature/split-deploy-credentials-app`. Runtime policy is **inline** today. **Apply order within the PR: `beta-001` → `demo-001` → `shared-001` → `atento-001`** — pilot both phases on the non-prod pair before the productive pair.

| Stack | Productive | Phase B rollout |
|---|---|---|
| `app-beta-001` | No | redeploy / let cycle |
| `app-demo-001` | No | redeploy / let cycle |
| `app-shared-001` | **Yes** | coordinated redeploy in blue/green window; check Sidekiq queue depth first |
| `app-atento-001` | **Yes** | coordinated redeploy in blue/green window; check Sidekiq queue depth first |

- [ ] Task 0 across all 4.
- [ ] **Decide (open item 1):** extract a shared `app_runtime_iam` module (mirroring `integrator_iam`) vs keep runtime policy inline. If extracting, do it first in this PR and use it for all 4.
- [ ] Phase A + Phase B per stack, in the apply order above.
- [ ] For `shared-001`/`atento-001` Phase B: confirm the productive-deploy queue check before the windowed redeploy.
- [ ] One commit, PR, apply+verify all 4 before merge, merge on day 2.

## PR 3 — Setup / Onboarding (last)

Branch: `feature/split-deploy-credentials-setup-onboarding`. Both inline runtime today; `onboarding` deploy key is **already Pattern B**.

| Stack | Specifics |
|---|---|
| `onboarding` | Deploy key already Terraform-native (`aws_iam_access_key.deploy`) — Phase A skips the import repoint; still split the runtime policy onto a new/renamed runtime user. Confirm productive flag → Phase B rollout accordingly |
| `setup` | Runtime `AWS_*` SSM params have **no code consumer** (SPIKE Finding 3). **Task 0 must confirm** — if genuinely unused, collapse `setup` to **deploy-only** (drop the dead runtime cred + SSM injection — Kaizen) instead of building a runtime user. Otherwise run the full procedure |

- [ ] Task 0 across both — especially the `setup` runtime-consumer check (decides full-split vs deploy-only).
- [ ] Phase A (+ Phase B where a runtime user exists) per stack.
- [ ] One commit, PR, apply+verify before merge, merge on day 3.

---

## Execution notes for the implementing session

- Follow `~/.claude/docs/TERRAFORM-CONVENTIONS.md` and `TERRAFORM-POLICY.md`; run reads via `scripts/terraform.sh`, writes on the gated MFA path.
- Pattern Priming before writing any HCL: read the sibling stack that already does it right (`auth-001` for the separated shape; `onboarding`/`mongodb` for the Terraform-native key + `github_actions_environment_secret` publish) and confirm the pattern before generating code.
- Never print a key value/ID into chat, a commit, or these docs — reference by category.
- Zero-downtime is the invariant on every step: if any Phase B rollout can't be done without risking a gap, stop and re-sequence rather than proceed.
