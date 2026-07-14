# PLAN — Split deploy credentials into runtime + deploy IAM users (per app × environment), Terraform-managed

## Context and decision

Today each app × environment stack provisions **one IAM user** whose single access key is used both by GitHub Actions to deploy (ECR push, ECS register/update, CodeDeploy) and, at runtime, by the running application (S3 via CarrierWave/Fog). A leak of the GitHub-stored key therefore exposes the application's runtime permissions too. This plan splits that single identity into **two IAM users per stack** — a **runtime user** (the application's own permissions) and a **deploy user** (only the minimal GitHub Actions deploy permissions) — so the credential stored in GitHub carries deploy-only access.

Source investigation: `../../spike/deploy-credentials-split/SPIKE.md` (verified — citations resolve into the live `terraform/` and `app/` repos).

**Engineer decisions (locked 2026-07-13):**

- **Option C** — both keys (deploy AND runtime) are 100% Terraform-managed, closing the rotation loop. Rotating either key becomes a `terraform apply`. This is the truest fit to the stated goal ("todas as chaves via Terraform para facilitar rotação").
- **Access keys, not OIDC** — long-lived `aws_iam_access_key`, managed by Terraform. OIDC is explicitly out of scope.
- **Zero-downtime is a hard constraint; there is no deadline.** This is a security hardening, not on any critical path. It may span weeks or months — the only invariant is that nothing goes offline.
- **Grouping: 3 PRs, one per group, executed on separate days.** Order: **Integrator → App → Setup/Onboarding**.

## Scope

**In scope — 11 stacks carrying the runtime+deploy mix** (each currently one user with both permission sets):

| Group (PR) | Stacks | Productive? | Runtime module today |
|---|---|---|---|
| **1 — Integrator** | `integrator-almaviva`, `integrator-atento`, `integrator-commcenter`, `integrator-maqnelson`, `integrator-redebrasil` | No — internal-only, rolling deploy when idle | `modules/integrator_iam` (already extracted) |
| **2 — App** | `app-beta-001`, `app-demo-001`, `app-shared-001`, `app-atento-001` | `shared-001` + `atento-001` = **productive**; `beta`/`demo` non-prod | Inline per stack (no module) |
| **3 — Setup/Onboarding** | `setup`, `onboarding` | To confirm per stack | Inline per stack |

**Out of scope (verified — no runtime+deploy mix to split):**

- `auth-001` — **already separated**; reference implementation (deploy user carries only `iam_deploy`; runtime via ECS task role + Secrets Manager).
- `vpn` — **no deploy credential at all** (no `aws_iam_user` / `aws_iam_access_key` / GitHub secret). Nothing to split. (The engineer initially grouped VPN into PR 3; removed after verification.)
- `app-outbound-atento-br` — no deploy credential of this shape.
- `mongodb` — has a Packer/AMI **`build`** user (already Terraform-native key); a build credential, not an app runtime+deploy mix. Optional hygiene follow-up, not part of this work.

## Target design (Option C)

Per stack, the end state is two users:

- **Runtime user** = the **existing** user, renamed for clarity but **not recreated** (keeps its identity, its runtime policy, and — until Phase B — its current key). The `iam_deploy` policy attachment is **removed** from it. Its access key becomes a Terraform-native `aws_iam_access_key` whose `.secret` feeds the runtime SSM parameters directly (closing the runtime side of the loop).
- **Deploy user** = a **new** user (`<stack>-deploy`), carrying **only** `modules/iam_deploy`, with a **new Terraform-native** `aws_iam_access_key` whose `.id`/`.secret` publish straight to the GitHub Actions secret via `github_actions_environment_secret` (Pattern B — the shape `onboarding`/`auth-001`/`mongodb` already use).

`modules/iam_deploy` itself needs **no change** — it already contains zero `s3:*` and no workflow calls `aws s3` (SPIKE Finding 4). The split is purely at the stack level: detach the runtime policy onto a second identity.

## Zero-downtime cutover mechanics

The split is decomposed into two phases. **Phase A alone already delivers the security goal** (the GitHub-stored key becomes deploy-only) with **zero runtime impact**. Phase B closes the Option-C rotation loop and is the only part that touches the live runtime credential.

### Phase A — Split (zero runtime impact, every stack)

1. Add the **new deploy user** + `iam_deploy` + a new Terraform-native deploy key; **repoint the GitHub secret** (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) to the new deploy key. The old key still exists on the old user and still feeds runtime SSM — the running app is untouched. `apply`.
2. **Verify**: trigger a deploy via GitHub Actions and confirm it succeeds using the new deploy-only key.
3. **Remove** `module "iam_deploy"` from the old (runtime) user — it is now runtime-only. Rename the resource `aws_iam_user.deploy` → `aws_iam_user.runtime` via a **`moved {}` block** (state rename, **not** recreation — preserves the key and the identity). `apply`.
4. **Verify**: the runtime app still reaches S3 (upload a document / exercise CarrierWave).

At the end of Phase A the leak surface is already fixed: GitHub holds a deploy-only key.

### Phase B — Runtime key under Terraform (Option C, per stack)

5. Replace the runtime user's current key with a **Terraform-native** `aws_iam_access_key` (mint new — the user briefly holds 2 keys, AWS max). Wire the runtime SSM `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` parameters from the new key's attributes, **dropping `ignore_changes` for those two parameter names only** (every other secret in the same set stays on the manual-SSM pattern).
6. `apply` → SSM now holds the new runtime key; the **old key stays active**, so running tasks (still holding the old key in their injected env) keep working. No gap.
7. Roll the running tasks onto the new key:
   - **Non-productive** (`beta`, `demo`, all integrators, likely `setup`): trigger a redeploy or let tasks cycle; the new task reads the new key from SSM.
   - **Productive** (`shared-001`, `atento-001`, `onboarding` if confirmed): coordinated redeploy in the normal ~5-min blue/green window — the old key remains active until the new tasks are healthy, so it is zero-downtime, not an outage.
8. **Verify** runtime S3 works on the new key, then **remove the old key** (back to 1 key). Rotation loop is now closed: future rotation = bump the key resource + `apply` + (for productive) a windowed redeploy.

## Naming and the `moved {}` gotcha

- The existing resource is literally `aws_iam_user.deploy` (app stacks) / `module.iam` user (integrator). Keeping it as the **runtime** user makes the address `…deploy` misleading, so rename to `aws_iam_user.runtime` (or the integrator module's equivalent). Use a **`moved {}` block** so Terraform performs a state move rather than destroy+create — recreation would drop the key and break runtime.
- The **new** deploy user takes the `<stack>-deploy` name. The runtime user keeps the current stack-named identity, because live infrastructure (ECS task, SSM) already references it — minimizing churn.
- ADR-010 currently labels the single mixed user "IAM deploy user"; this split makes the runtime user the primary stack identity. Update ADR-010's row as part of PR 1 (or note it as a doc follow-up).

## Grouping, order, and rationale

**PR 1 — Integrator (first).** Lowest risk: internal-only (no productive downtime concern even in Phase B) and the runtime module (`integrator_iam`) already exists, so the split is the cleanest. This is where the pattern is proven before touching anything productive. 5 stacks, one procedure, a per-stack table.

**PR 2 — App (second).** Contains the two productive stacks. Within the PR, apply order is **`beta-001` → `demo-001` → `shared-001` → `atento-001`** — the two non-productive stacks pilot Phase A **and** Phase B before the productive pair, and the productive pair does Phase B in a deploy window. App runtime policy is inline (no module today) — decide during PR 2 whether to extract an `app_runtime_iam` module mirroring `integrator_iam`, or keep it inline (see Open items).

**PR 3 — Setup/Onboarding (last).** 2 stacks. `onboarding` already uses a Terraform-native deploy key (Pattern B) — partial work already done. `setup` has runtime `AWS_*` SSM params with **no code consumer** (SPIKE Finding 3) — confirm, and if genuinely unused, `setup` collapses to a **deploy-user-only** stack (drop the dead runtime cred entirely — Kaizen), which is less work than a full split.

Each PR is one commit (4Shark: one commit per PR), applied and verified stack-by-stack **before merge** (apply-before-merge), then merged on its own day. Nothing is auto-merged.

## Per-stack heterogeneity — confirm before acting

The stacks are not uniform; each group's Task 0 is a **topology confirmation** (distrust-the-premise):

- **Deploy key pattern**: Pattern A "imported key" (`app-*`, `setup`, `integrator-*` via `modules/iam_deploy_key` + `import{}`) vs Pattern B Terraform-native (`onboarding`). Pattern B stacks skip the import dance.
- **Runtime consumer present?** `setup` appears to have none — verify before building it a runtime user.
- **Runtime module present?** integrator yes (`integrator_iam`); app/onboarding/setup inline.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Recreating the existing user drops the live key → runtime outage | `moved {}` block (state rename, never destroy+create); Phase A keeps the original key until Phase B |
| Productive Phase B rotation causes a gap | Two-active-keys rotation: new key active alongside old; old removed only after new tasks are healthy in the blue/green window |
| Deploy breaks after detaching `iam_deploy` from the old user | Phase A step 2 verifies a real GHA deploy on the new deploy key **before** step 3 removes the old deploy policy |
| `AKIA…` key IDs / secrets leaking into the plans repo (auto-committed daily) | Never write a key value/ID into any doc or commit; reference by category (already applied to the SPIKE) |
| Terraform writes require MFA on productive stacks | Every `apply` uses `/elevate-aws-access` + `--profile 4shark-mfa`; reads stay on the default profile |
| Dropping `ignore_changes` on the wrong SSM params | Scope the change to exactly `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`; leave every other secret untouched |

## Verification (per stack, both phases)

- **Deploy path**: a GitHub Actions deploy completes green using the deploy-only key; the deploy user has **no** `s3` grant.
- **Runtime path**: the app still performs its S3 operation (document upload via CarrierWave) on the runtime key.
- **Separation**: the runtime user has **no** `iam_deploy` policy; the deploy user has **no** runtime policy.
- **Rotation loop (Option C)**: the runtime SSM value and the GitHub secret both derive from Terraform-managed key resources; no manual `aws ssm put-parameter` remains for the two AWS_* names.

## Open items to decide during execution (not blocking the plan)

1. **App runtime module** — extract a shared `app_runtime_iam` module (mirroring `integrator_iam`) during PR 2, or keep the runtime policy inline per app stack. Recommendation: extract, for parity — but decide when PR 2 starts.
2. **`setup` runtime user** — confirm the runtime `AWS_*` SSM params have no consumer; if so, collapse `setup` to deploy-only instead of building a runtime user.
3. **ADR-010 update** — reflect the runtime/deploy user split in the naming ADR (doc-only; fold into PR 1 or a follow-up).

## Out of scope / follow-ups

- `mongodb` Packer `build` user hygiene (separate concern).
- Moving deploy secrets from GitHub **Environment** secrets to repo/org level (raised by a prior spike; not revisited here).
- OIDC migration (explicitly declined for this work).
