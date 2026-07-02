# SPIKE — Managing deploy AWS credentials in Terraform

**Question**: The AWS access keys we put in GitHub (per environment, for deploy) and reuse in local tools are created **manually** today, outside Terraform. Every time we need a value we have to hunt for it or regenerate it, losing control. How does the community recommend managing these credentials, and how do we bring them under Terraform with a single retrievable source of truth?

**Date**: 2026-07-01
**Repo**: `~/Projects/4Shark/terraform`
**Status**: Research complete — awaiting engineer's direction on which approach to adopt.

---

## 1. Current state (repo analysis)

### 1.1 Deploy identity per stack

Every deployable stack creates an IAM **user** named after the environment and attaches the shared `modules/iam_deploy` policy (ECR push, ECS update-service, PassRole, CodeDeploy, etc.).

| Stack | IAM user (TF) | Access key | Where the key value lives |
|---|---|---|---|
| `auth-001` | ✅ `auth-001/iam.tf` | ✅ TF (`aws_iam_access_key.deploy`) | Sensitive TF **output** → state only |
| `onboarding` | ✅ `onboarding/main.tf` | ✅ TF (`aws_iam_access_key.deploy`) | Sensitive TF **output** → state only |
| `app-shared-001` | ✅ `main.tf:541` | ❌ **manual** | Nowhere in TF |
| `app-beta-001` | ✅ | ❌ **manual** | Nowhere in TF |
| `app-demo-001` | ✅ | ❌ **manual** | Nowhere in TF |
| `app-atento-001` | ✅ | ❌ **manual** | Nowhere in TF |
| `setup` | ✅ `setup/main.tf:347` | ❌ **manual** | Nowhere in TF |
| integrators (`modules/integrator_iam`) | ✅ `main.tf:5` | ❌ **manual** | Nowhere in TF |

### 1.2 Three gaps confirmed

1. **The access key itself is manual for most stacks.** Only `auth-001` and `onboarding` (the two most recent) create `aws_iam_access_key` in Terraform. Every app stack, `setup`, and every integrator has the IAM user in code but the key was minted by hand in the console. This is the reported loss of control.
2. **No single retrievable store for the value.** For `auth-001`/`onboarding` the secret is only a `sensitive` TF output → it lives in state, never in SSM or Secrets Manager. `grep` for `aws_ssm_parameter` shows SSM is used only for **app runtime config/secrets**, never for the deploy keys. So even the two "managed" stacks don't satisfy "pick it up from a known place".
3. **GitHub Actions secrets are not managed in Terraform at all.** No `github_actions_secret` / `github_actions_environment_secret` anywhere, even though the `github` provider is used heavily in `identity/` (repos, branch protection). The key still reaches GitHub by a **manual paste**.

### 1.3 The decisive finding — the deploy key is triple-use

The same `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` has **three consumers**, not one:

1. **CI** — pasted into GitHub Actions secrets for deploy.
2. **App runtime** — the *same* key is injected into the ECS task as env vars from SSM (`app-shared-001/compute.tf:64`); the app uses it for **S3** (hence `aws_iam_policy.deploy_s3_access` attached to the deploy *user*, `main.tf:578`). The ECS `task_role_arn` exists (`main.tf:461`) but is `null` — so the app relies on a static user key, not a task role.
3. **Local tools** — the same key, outside CI and the app.

And the SSM slot already exists but **TF deliberately does not own the value**: every app secret is created as `value = "PLACEHOLDER"` with `lifecycle { ignore_changes = [value] }` (`app-shared-001/ssm.tf:31`) — the repo-wide convention is "TF creates the slot, a human fills the secret". If TF starts minting the key *and* writing it to SSM, it becomes the value owner for those two params, breaking that uniform convention. **This is the real fork in the plan.**

**Engineer's answers (2026-07-01)**: local tools *need* static keys; the app *keeps* the static key for now. → OIDC cannot be a complete solution (two of three consumers require a static key); the realistic target is **Option B**.

### 1.4 What already exists to build on

- `modules/iam_deploy` — reusable **policy** module (does not create the user or the key; each stack does).
- The `auth-001`/`onboarding` `aws_iam_access_key.deploy` + output shape — the seed of a standard pattern.
- The `github` provider is already wired in `identity/` — pushing secrets to GitHub from TF is a small addition, not a new provider.

---

## 2. What the community recommends (grounded)

### 2.1 For the GitHub Actions deploy half → OIDC, not static keys

This is the strongest and most consistent finding. AWS and GitHub both recommend **replacing long-lived IAM user access keys with GitHub OIDC → an IAM role** (`AssumeRoleWithWebIdentity`, short-lived STS tokens):

- AWS Security Blog: *"begin to delete AWS access keys from your IAM users and use short-term credentials"*; the OIDC role approach *"removes the need for IAM user access keys."* ([AWS](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/))
- `aws-actions/configure-aws-credentials` supports `role-to-assume` with OIDC as the documented default. ([GitHub](https://github.com/aws-actions/configure-aws-credentials))
- Community consensus: *"OIDC eliminates stored credentials entirely and is the gold standard for security... that should be your default choice for new workflows."* ([oneuptime](https://oneuptime.com/blog/post/2026-02-23-how-to-store-terraform-secrets-in-github-actions/view))

Benefit: **zero keys, zero rotation, nothing to store or paste.** The workflow gets `permissions: id-token: write` and assumes a role scoped to the repo/branch. Cost: touches each service's GitHub Actions workflow, and the `iam_deploy` identity becomes a **role with a trust policy** instead of a user.

### 2.2 For genuine long-lived-key use cases → manage in TF, value in SSM/Secrets Manager

OIDC only covers CI/CD. Our keys are **also used in local tools** ("em outras ferramentas, para acessar as coisas") — those can't assume an OIDC role. For that case the community recommendation matches your hypothesis exactly:

- Create `aws_iam_access_key` in Terraform, then **write the value into SSM Parameter Store (`SecureString`) or Secrets Manager**, and reference it from code. ([oneuptime](https://oneuptime.com/blog/post/2026-02-23-how-to-create-iam-access-keys-in-terraform/view))
- **SSM SecureString** — simpler, standard tier is free, fine for "store and retrieve". **Secrets Manager** — costs per secret but adds **native automatic rotation** and cross-account sharing. *"Use Secrets Manager when you need automatic secret rotation... or you are storing credentials."* ([oneuptime](https://oneuptime.com/blog/post/2026-02-12-manage-secrets-manager-secrets-terraform/view))
- AWS Prescriptive Guidance has a canonical pattern for **automatic IAM access-key rotation via Secrets Manager + a Lambda**, at org scale. ([AWS PG](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/automatically-rotate-iam-user-access-keys-at-scale-with-aws-organizations-and-aws-secrets-manager.html))

### 2.3 Close the GitHub loop from Terraform

Whether or not we keep static keys, the `github` provider can push the value straight to GitHub, ending the manual paste:

- `github_actions_secret` (repo) / `github_actions_environment_secret` (per environment) sourced from the `aws_iam_access_key` / SSM value. ([oneuptime](https://oneuptime.com/blog/post/2026-02-23-how-to-create-github-actions-secrets-with-terraform/view))

### 2.4 Universal caveat — Terraform state

Any static key (created by `aws_iam_access_key`, or written to SSM/Secrets Manager from TF) **lands in Terraform state in plaintext**. State must stay encrypted and access-restricted. This is already true for the `auth-001`/`onboarding` outputs today; it is not a new risk, just a constraint that carries to every option that keeps a static key. OIDC is the only option with **no** secret in state.

---

## 3. Options (decision needed)

| | A — OIDC for GitHub Actions | B — Static keys, fully in TF + SSM/Secrets Manager | C — Hybrid |
|---|---|---|---|
| GitHub deploy auth | OIDC role, short-lived STS | Managed `aws_iam_access_key`, pushed via `github_actions_secret` | OIDC role (no keys in CI) |
| Local tools auth | ❌ not solved (tools can't do OIDC) | ✅ same key, retrievable from SSM/Secrets Manager | ✅ separate managed static key in SSM/Secrets Manager |
| Secret in TF state | **None** | Yes (state must stay encrypted) | Only the tools key |
| Rotation burden | Zero (auto) | Manual, or Secrets Manager auto-rotation | Only the tools key |
| Change surface | Each repo's workflow + `iam_deploy` → role | `iam_deploy` standardized to also mint key + SSM + GitHub secret | Both of the above |
| Matches "used in other tools" reality | ✗ partially | ✓ fully | ✓ fully |

- **A** is the security gold standard but leaves the "tools" use case unsolved — so it's incomplete for what you described.
- **B** is your stated hypothesis and solves both halves with one source of truth; it keeps long-lived keys (weaker posture, state caveat).
- **C** is the best posture (no keys in CI, one managed key only where a tool truly needs it) at the cost of two mechanisms.

**Decision axis**: *do the GitHub Actions deploys and the local tools need to share the same credential, or can CI move to keyless (OIDC) while only the tools keep a managed static key?*

---

## 4. Recommendation

**Option C (hybrid)** is the community-aligned target: OIDC removes the largest attack surface (long-lived keys sitting in every repo's secrets) at zero rotation cost, and the remaining tools use a single Terraform-managed key stored in Secrets Manager (or SSM SecureString) — retrievable, versioned, no more hunt-or-regenerate.

If the appetite for touching every repo's workflow is low right now, **Option B** is the pragmatic first step: it immediately ends the manual-key problem and the manual GitHub paste, standardizing on the `auth-001`/`onboarding` seed pattern extended with an SSM/Secrets Manager write. OIDC can layer on later.

Either way the concrete building block is a small extension to `modules/iam_deploy` (or a sibling module) that, given a deploy user: mints the key, writes it to SSM SecureString / Secrets Manager, and — optionally — pushes it to GitHub via `github_actions_secret`.

---

## Sources

- [AWS Security Blog — Use IAM roles to connect GitHub Actions to AWS](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)
- [aws-actions/configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
- [Configuring OpenID Connect in AWS — GitHub Docs](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [AWS Prescriptive Guidance — Automatically rotate IAM user access keys with Secrets Manager](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/automatically-rotate-iam-user-access-keys-at-scale-with-aws-organizations-and-aws-secrets-manager.html)
- [AWS Prescriptive Guidance — Centralize IAM access key management with Terraform](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/centralize-iam-access-key-management-in-aws-organizations-by-using-terraform.html)
- [oneuptime — How to Create IAM Access Keys in Terraform](https://oneuptime.com/blog/post/2026-02-23-how-to-create-iam-access-keys-in-terraform/view)
- [oneuptime — How to Create GitHub Actions Secrets with Terraform](https://oneuptime.com/blog/post/2026-02-23-how-to-create-github-actions-secrets-with-terraform/view)
- [oneuptime — Manage Secrets Manager Secrets with Terraform](https://oneuptime.com/blog/post/2026-02-12-manage-secrets-manager-secrets-terraform/view)
- [oneuptime — How to Store Terraform Secrets in GitHub Actions](https://oneuptime.com/blog/post/2026-02-23-how-to-store-terraform-secrets-in-github-actions/view)
