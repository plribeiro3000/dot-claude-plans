# PLAN — Bring deploy AWS credentials under Terraform

> ✅ **DONE (2026-07-03).** Delivered across all 12 stacks via **PR #589 (merged)**, all applied with 0 change/destroy. See `terraform/credential-hygiene/PLAN.md` (Workstream 1) for the closed summary.

**Project**: `terraform` (`~/Projects/4Shark/terraform`)
**Origin**: `~/.claude/plans/active/spike/terraform-deploy-credentials/SPIKE.md`
**Decision (locked with engineer, 2026-07-01)**: Option B — static keys, fully in Terraform. Import existing keys (no rotation), read current values from live infra (SSM), and push to GitHub automatically.

---

## 1. Goal

Every deploy IAM user's access key becomes a Terraform-managed resource, and its value reaches GitHub Actions from Terraform — ending the two manual steps (mint the key in the console, paste it into GitHub). The credential stays retrievable from a single known place (the existing SSM SecureString parameter), which Terraform references.

**Non-goals** (explicitly out of scope, confirmed with engineer):
- No key rotation — existing keys are imported and kept.
- No OIDC migration — the app runtime and local tools need static keys.
- No change to how the app consumes the key — it keeps reading `AWS_*` from SSM.
- No `ignore_changes` removal — SSM stays the human-filled source of truth; Terraform only references it.

## 2. Key technical decisions

### 2.1 Import, don't recreate — and the secret is not recoverable

`terraform import aws_iam_access_key` populates `id` but **not** `secret`: AWS never returns the secret after creation ([provider #17790](https://github.com/hashicorp/terraform-provider-aws/issues/17790)). So the imported resource's `.secret` is `null` in state — which is fine and desirable (zero secret in state for these). Import is done via an `import {}` block (TF `>= 1.11`, supported since 1.5) so it is reviewable in the PR.

Consequence: the GitHub push cannot source the value from `aws_iam_access_key.secret` for imported keys. It sources from the **live SSM value** instead.

### 2.2 Value flows from SSM, not from the key resource

- Current secret value already lives in `/{env}/AWS_ACCESS_KEY_ID` and `/{env}/AWS_SECRET_ACCESS_KEY` (verified: `app-shared-001` key `***REMOVED***` matches the SSM value).
- `data "aws_ssm_parameter"` (with `with_decryption`) reads both → feeds the GitHub secret. SSM parameter resources stay untouched (`ignore_changes = [value]` preserved).

Two sub-cases the module must handle:
- **Key already TF-created** (`auth-001`, `onboarding`): `.secret` is known in state → push can come from the resource directly.
- **Key manual → imported** (`app-shared-001`, `app-beta-001`, `app-demo-001`, `app-atento-001`, `setup`, integrators): `.secret` is null → push comes from the SSM data source.

The generic interface: the GitHub-push building block takes the **secret value as an input string** (either `aws_iam_access_key.deploy.secret` or `data.aws_ssm_parameter...value`), so it does not care which sub-case produced it.

### 2.3 DECIDED — GitHub push lives per-stack (Option B, engineer 2026-07-01)

The `github` provider + `GITHUB_TOKEN` are added to each app/service stack, and the `github_actions_environment_secret` lives in the same stack as the deploy user that produced the key. Each stack reads its own SSM value locally; each secret stays in its own stack's state. Rationale below (table kept for the record).

---

_Original open-decision record:_

`github_actions_secret` / `github_actions_environment_secret` need the `github` provider, which today is configured **only in `identity/`** (with `GITHUB_TOKEN` in `identity/.envrc`). App/service stacks have only the `aws` provider. Two placements:

| | A — Centralize in `identity/` (recommended) | B — Per-stack |
|---|---|---|
| Provider spread | github provider stays in one stack | github provider + `GITHUB_TOKEN` added to ~7 stacks' `.envrc` |
| Conceptual fit | GitHub-as-code (repos, branch protection) already lives here | Secret colocated with the key that produced it |
| Cross-stack read | identity reads other stacks' SSM values via `data "aws_ssm_parameter"` (by name/ARN) | each stack reads its own SSM locally |
| Secret-in-state spread | app secrets also land in identity's state | each secret stays in its own stack's state |

**Recommendation: A.** GitHub configuration is already identity's domain; centralizing keeps the `github` provider and token in one place. identity reads each stack's SSM value by parameter name (cross-account/region via provider alias if needed). **This is the one decision to confirm before implementation of Phase 3.**

## 3. Building block — new module `modules/iam_deploy_key` (engineer 2026-07-01)

Pattern Priming finding: `modules/iam_deploy` is a **policy module** — it does not create the user or the key; each stack hand-rolls `aws_iam_user.deploy` + `aws_iam_access_key.deploy` in its own `iam.tf`/`main.tf` (auth-001, onboarding). Extending it to own the key would be Convention Drift. Engineer chose a **new sibling module** `modules/iam_deploy_key` (DRY across ~5 stacks) over repeating the block per stack.

The module encapsulates, given a deploy user + repo/environment + SSM value inputs:
1. `aws_iam_access_key` — the key resource (imported for existing users via an `import {}` block placed in the **stack** targeting `module.<x>.aws_iam_access_key.this`; created for new ones).
2. `github_actions_environment_secret` ×2 — `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for the repo+environment, sourced from the value input (the SSM data source in the caller, or `.secret` for TF-created keys).

The module needs the `github` provider passed by the caller. Each caller stack adds `provider "github"` (mirroring `identity/providers.tf`: `owner = var.github_org`, `integrations/github ~> 6.0`) and `GITHUB_TOKEN` to its `.envrc`. Module conventions mirror `modules/iam_deploy` (snake_case vars, `count`-toggles, named attributes, `description`+`value` outputs).

## 4. Inventory (stacks × current key)

| Stack | Repo / GitHub environment | Deploy user | Current key | Action |
|---|---|---|---|---|
| `app-shared-001` | `app` / `shared-001` | `app-shared-001` | `***REMOVED***` (active) | import + SSM data + push |
| `app-beta-001` | `app` / `beta-001` | `app-beta-001` | (to enumerate) | import + SSM data + push |
| `app-demo-001` | `app` / `demo-001` | `app-demo-001` | (to enumerate) | import + SSM data + push |
| `app-atento-001` | `app` / `atento-001` | `app-atento-001` | (to enumerate) | import + SSM data + push |
| `setup` | `setup` | `setup` | (to enumerate) | import + SSM data + push |
| `onboarding` | `onboarding` | `onboarding` | already TF-created | push from `.secret` |
| `auth-001` | `keycloak` | `auth-001` | already TF-created | push from `.secret` |
| integrators (`integrator_iam`) | `integrator` | per client | (to enumerate) | import + push (no SSM AWS key today — confirm value source) |

Key IDs for the remaining users are enumerated read-only (`aws iam list-access-keys --user-name <user>`) at execution start. **Integrators need a check**: they may not have `AWS_*` SSM params (they were only S3/EC2 users) — confirm whether they even feed a GitHub deploy secret before including them.

## 5. Execution phases

1. **Pattern Priming** on `modules/iam_deploy` + 2–3 caller stacks → confirm module shape, naming, extend-vs-sibling. (Gate: engineer confirms pattern.)
2. **Enumerate** every deploy user's current active key id (read-only AWS) and confirm each stack's SSM param names.
3. **Confirm §2.3** (centralize vs per-stack) with the engineer.
4. **Module change** — add key management + import support + value output.
5. **Per-stack wiring** — `import {}` block per existing key; `data "aws_ssm_parameter"` for the value; GitHub secret push (per §2.3 location). Start with **one pilot stack** (`app-shared-001`), `terraform plan`, verify the import shows no destroy/recreate and the GitHub secret is an add.
6. **Roll out** to the remaining stacks once the pilot plan is clean.
7. **Validate** — after apply, the GitHub environment secret matches the live key; a deploy still works; the app still boots (key value unchanged).

## 6. Risks

- **Import that recreates instead of adopting** — a wrong `import {}` target/ID makes the plan show destroy+create, which would rotate the key and break the running app. Mitigation: pilot on one stack, read the plan carefully, never apply an import that shows a replace.
- **Secret spread to more state** — centralizing in identity puts app secrets in identity's state (already the case per-stack for `auth-001`/`onboarding`). State is already encrypted/restricted; accept, do not expand access.
- **Integrators may not fit** — if they have no `AWS_*` GitHub deploy secret, they are out of scope for the push half; still importable for lifecycle. Confirm before touching.
- **`terraform apply` is apply-before-merge** — every stack change follows the 4Shark flow: plan captured, PR open, engineer approves each apply.

## Sources

- [Terraform provider — aws_iam_access_key import limitation (#17790)](https://github.com/hashicorp/terraform-provider-aws/issues/17790)
- [aws_iam_access_key resource docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_access_key)
- [AWS Security Blog — IAM roles for GitHub Actions (OIDC, the deferred alternative)](https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/)
- Spike: `~/.claude/plans/active/spike/terraform-deploy-credentials/SPIKE.md`
