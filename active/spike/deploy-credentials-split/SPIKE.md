# SPIKE — Splitting Deploy Credentials into Two IAM Users (Runtime + Deploy) per Application × Environment

## Investigation question

Today, 4Shark provisions ONE IAM user per application × environment, and its access key is used both by GitHub Actions to deploy (ECR push, ECS register/update, CodeDeploy) and, in several stacks, by the running application itself (S3 access via CarrierWave/Fog). The question: how should this be restructured into a two-IAM-user pattern — one **runtime** user (application's own operational permissions) and one **deploy** user (minimal GitHub Actions deploy permissions) — so that the credential stored in GitHub carries only deploy-shaped access, and a leak of it does not expose the application's runtime permissions?

**Scope refinement from the engineer (received mid-investigation):** access keys (IAM user + long-lived `aws_iam_access_key`) are the given, decided mechanism — GitHub OIDC role-assumption is explicitly out of scope as a recommended path (mentioned only once, briefly, below, for technical honesty). The central additional requirement is that **the two users, their policies, and their access keys must be 100% Terraform-managed, structured to make future rotation easy** — including how the secret value reaches GitHub Actions secrets and how it reaches the running application, both via Terraform, without ever printing a credential value in this document.

## Sources consulted

- `terraform/modules/iam_deploy/main.tf` — the existing deploy-permission policy module (ECR/ECS/CodeDeploy/AutoScaling/EC2 start-stop)
- `terraform/modules/iam_deploy/README.md` — documents the module's known limitation on access-key creation
- `terraform/modules/iam_deploy_key/main.tf` — the existing "imported key" pattern for publishing the deploy key to GitHub secrets
- `terraform/modules/integrator_iam/*.tf` — existing per-client runtime IAM module for the integrator (S3 + EC2 describe), the closest existing precedent for a dedicated "runtime module"
- `terraform/app-atento-001/iam_deploy_user.tf`, `github_deploy.tf`, `ssm.tf` — the current single-user, dual-purpose wiring for `app`
- `terraform/app-beta-001/compute.tf` — where the same access key is injected into the running ECS task as `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
- `terraform/integrator-atento/github_deploy.tf`, `alb.tf` — confirms the same single-user pattern for `integrator`
- `terraform/onboarding/main.tf`, `ssm.tf`, `github_deploy.tf` — confirms the pattern and shows an alternative, cleaner Terraform-native key-management style
- `terraform/setup/main.tf`, `ssm.tf`, `github_deploy.tf` — confirms the pattern, and shows the runtime secret with no code consumer
- `terraform/auth-001/iam.tf`, `github_deploy.tf` — the one stack where deploy and runtime are ALREADY separate (deploy = static IAM user; runtime = ECS task role + Secrets Manager)
- `terraform/mongodb/iam.tf` — a third example of a Terraform-native (non-imported) access key
- `terraform/docs/adr/ADR-010-resource-naming-convention.md` — naming convention that currently labels the single mixed-purpose user as "IAM deploy user"
- `app/lib/application_configuration.rb`, `app/config/initializers/carrierwave.rb` — the Rails-level runtime consumer of the static credential
- `app/.github/workflows/deploy-atento-001.yaml`, `build-image.yaml`; `setup/.github/workflows/deploy.yaml` — the exact AWS actions the deploy/build pipelines invoke
- `app/.github/actions/deploy-ecs/action.yaml` — the composite action used by every deploy job
- Prior spike `~/Projects/4Shark/dot-claude-plans/active/spike/integrator-iam-terraform/SPIKE.md` (2026-03-03) — already researched IAM user vs IAM role for the integrator and documented the access-key state-file trade-offs
- Prior spike `~/Projects/4Shark/dot-claude-plans/active/spike/github-envs-to-terraform-ssm/SPIKE.md` (2026-03-21) — already flagged that `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` serve "different use cases" (deploy vs runtime) without going the extra step of splitting identities
- [HashiCorp Support: How to Automate AWS IAM Access Key Rotation](https://support.hashicorp.com/hc/en-us/articles/28354367124627-How-to-Automate-AWS-IAM-Access-Key-Rotation) — `replace_triggered_by` rotation pattern for `aws_iam_access_key`, quote verified by re-fetch
- [AWS Security Blog: How to Rotate Access Keys for IAM Users](https://aws.amazon.com/blogs/security/how-to-rotate-access-keys-for-iam-users/) — confirms the two-active-keys-per-user rotation mechanic, quote verified by fetch

No auxiliary files were needed — every citation below resolves to a file already in the engineer's own repositories, or to a URL quoted inline.

## Findings

### Finding 1: The current single IAM user genuinely carries both runtime and deploy permissions — not just in theory

**Evidence:**

```hcl
# terraform/app-atento-001/iam_deploy_user.tf:8-40
resource "aws_iam_user" "deploy" {
  name = "app-atento-001"
  tags = local.tags
}

resource "aws_iam_policy" "deploy_s3_access" {
  name        = "S3-bucket-4shark-atento-001"
  description = "S3 access for atento-001 environment"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListAllMyBuckets"], Resource = "arn:aws:s3:::*" },
      { Effect = "Allow", Action = "s3:*", Resource = [module.s3_bucket.bucket_arn, "${module.s3_bucket.bucket_arn}/*"] }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "deploy_s3_access" {
  user       = aws_iam_user.deploy.name
  policy_arn = aws_iam_policy.deploy_s3_access.arn
}

module "iam_deploy" {
  source        = "../modules/iam_deploy"
  # ... ECS/ECR/CodeDeploy permissions ...
  iam_user_name = aws_iam_user.deploy.name
}
```

**Source:** `terraform/app-atento-001/iam_deploy_user.tf:8-82`

**Significance:** the single user named `app-atento-001` gets a full-object S3 policy (`s3:*` on the environment's bucket) attached directly, in addition to the ECS/ECR/CodeDeploy policy from `modules/iam_deploy`. The S3 grant is a runtime permission (see Finding 3); the ECS/ECR/CodeDeploy grant is a deploy permission. Both live on one identity today. The same shape repeats verbatim in `app-beta-001`, `app-demo-001`, `app-shared-001` (`iam_deploy_user.tf` in each), and the equivalent `integrator_iam` + `iam_deploy` pairing in every `integrator-*` stack.

### Finding 2: The exact same physical access key is injected into the running container AND into GitHub Actions secrets

**Evidence:**

```hcl
# terraform/app-beta-001/compute.tf:55-57
secrets = [
  { name = "AWS_ACCESS_KEY_ID", valueFrom = aws_ssm_parameter.secrets["AWS_ACCESS_KEY_ID"].arn },
  { name = "AWS_SECRET_ACCESS_KEY", valueFrom = aws_ssm_parameter.secrets["AWS_SECRET_ACCESS_KEY"].arn },
  ...
```

```hcl
# terraform/app-beta-001/github_deploy.tf:8-15
module "deploy_key" {
  source                     = "../modules/iam_deploy_key"
  iam_user_name              = aws_iam_user.deploy.name
  github_repository          = "app"
  github_environment         = var.environment
  ssm_secret_access_key_name = aws_ssm_parameter.secrets["AWS_SECRET_ACCESS_KEY"].name
}
```

**Source:** `terraform/app-beta-001/compute.tf:55-57` and `terraform/app-beta-001/github_deploy.tf:8-15` (identical wiring confirmed in `app-atento-001`, `app-demo-001`, `app-shared-001`, `onboarding`, `setup`; the integrator equivalent uses a country-level SSM parameter — `terraform/integrator-atento/github_deploy.tf:6-8`: *"the same key backs every atento country service"*)

**Significance:** the ECS task's runtime container reads `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` from the SAME SSM parameter (`aws_ssm_parameter.secrets["AWS_SECRET_ACCESS_KEY"]`) that `iam_deploy_key` reads from to publish the GitHub Actions secret. One value, two consumers — exactly the problem the engineer described.

### Finding 3: The runtime consumer is real application code, not a dead configuration value

**Evidence:**

```ruby
# app/lib/application_configuration.rb:5-15
def aws_access_key
  ENV.fetch('AWS_ACCESS_KEY_ID', nil)
end

def aws_secret_access_key
  ENV.fetch('AWS_SECRET_ACCESS_KEY', nil)
end
```

```ruby
# app/config/initializers/carrierwave.rb:3-12
CarrierWave.configure do |config|
  config.fog_credentials = {
    provider: 'AWS',
    aws_access_key_id: ApplicationConfiguration.aws_access_key,
    aws_secret_access_key: ApplicationConfiguration.aws_secret_access_key
  }
  config.fog_directory = ApplicationConfiguration.aws_bucket
  config.fog_public = false
end
```

**Source:** `app/lib/application_configuration.rb:5-15`, `app/config/initializers/carrierwave.rb:3-12`; the same `carrierwave.rb` shape exists in `onboarding/config/initializers/carrierwave.rb` and `integrator/config/initializers/carrierwave.rb` (confirmed present via directory listing, not fully re-read here)

**Significance:** CarrierWave/Fog uses the static access key to talk to S3 at runtime — this is the "runtime bucket" of permissions. Notably, `setup` defines the same `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` SSM parameters and injects them into its ECS task (`setup/compute.tf:23-24`, `setup/ssm.tf:17-18`), but no `carrierwave.rb`, `Aws::S3`, or `fog_credentials` reference was found anywhere under `setup/config`, `setup/app`, or `setup/lib` — the runtime credential in `setup` currently appears to have no code consumer. This is worth confirming with the team before assuming `setup` needs a runtime user/key at all.

### Finding 4: The deploy-only permission set is already well-scoped in `modules/iam_deploy` — no `s3` action anywhere in it

**Evidence:**

```hcl
# terraform/modules/iam_deploy/main.tf — statement Sids present:
# ECRAuth, ECRPushPull, ECSTaskDef, ECSClusterAll, ALB, Logs, PassRole,
# CodeDeploy, SSMCodeDeployHooks, AutoScaling, EC2Describe, EC2StartStop
```

**Source:** `terraform/modules/iam_deploy/main.tf:13-196` (full statement list read in this investigation)

Cross-referenced against the exact AWS CLI calls the deploy/build pipelines issue:

```yaml
# app/.github/workflows/deploy-atento-001.yaml (representative calls found)
aws ecs describe-services / describe-task-definition / register-task-definition
aws ecs update-service / list-tasks / execute-command / wait tasks-stopped / run-task
aws deploy create-deployment / get-deployment / put-lifecycle-event-hook-execution-status / stop-deployment
aws autoscaling describe-auto-scaling-groups / update-auto-scaling-group
aws ssm get-parameter                      # CodeDeploy hook signal
```

```yaml
# app/.github/workflows/build-image.yaml — aws-actions/amazon-ecr-login (ECR push)
```

**Source:** `app/.github/workflows/deploy-atento-001.yaml` (lines 277-478, 693-923 read in this investigation), `app/.github/actions/deploy-ecs/action.yaml:51-125`, `setup/.github/workflows/deploy.yaml` (full file read)

A repo-wide search for `aws s3` inside every `.github/workflows/*` and `.github/actions/*/*.yaml` in `app`, `integrator`, `onboarding`, `setup` returned **no matches**.

**Significance:** the deploy/build pipelines never call S3 directly. The `modules/iam_deploy` policy already matches this — it has no `s3:*` statement. The S3 grant found in Finding 1 is attached *alongside* it on the same user, not *by* the same module — confirming the mixing is additive at the stack level, not baked into the deploy module itself. Splitting into two users does not require touching `modules/iam_deploy`'s own policy content.

### Finding 5: One stack already achieves the target separation, via a different runtime mechanism

**Evidence:**

```hcl
# terraform/auth-001/iam.tf:78-106
resource "aws_iam_user" "deploy" {
  name = "auth-001"
}

module "iam_deploy" {
  source = "../modules/iam_deploy"
  # ECS/ECR/CodeDeploy only
  iam_user_name = aws_iam_user.deploy.name
}

resource "aws_iam_access_key" "deploy" {
  user = aws_iam_user.deploy.name
}
```

Runtime secrets for Keycloak come from a **task IAM role**, not this user:

```hcl
# terraform/auth-001/iam.tf:22-63 (ecs_task IAM policy, attached to aws_iam_role.ecs_task_execution)
Action = ["secretsmanager:GetSecretValue"]
Resource = ["arn:aws:secretsmanager:sa-east-1:405749097490:secret:keycloak-WSaBCz", aws_secretsmanager_secret.auth_001.arn]
```

**Source:** `terraform/auth-001/iam.tf:1-106`

**Significance:** in `auth-001`, the `aws_iam_user.deploy` carries ONLY the `iam_deploy` policy — no runtime grant is ever attached to it. Keycloak's own runtime access to its secrets goes through the ECS task's IAM **role** (`aws_iam_role.ecs_task_execution`) reading AWS Secrets Manager, with no static access key involved at all. This is not the two-IAM-user-with-access-keys pattern the engineer asked to investigate (it uses a role, not a second user), but it is direct proof that 4Shark already treats "deploy identity" and "runtime identity" as separable concerns in at least one stack, and that the existing `iam_deploy` module is designed to be attached to a deploy-only user without modification.

### Finding 6: Two different Terraform patterns for the deploy key already coexist — one is rotation-friendly, one is not

**Pattern A — "imported key" (used by `app-*`, `integrator-*`, `setup`):**

```hcl
# terraform/app-atento-001/github_deploy.tf:8-20
module "deploy_key" {
  source                     = "../modules/iam_deploy_key"
  iam_user_name              = aws_iam_user.deploy.name
  github_repository          = "app"
  github_environment         = var.environment
  ssm_secret_access_key_name = aws_ssm_parameter.secrets["AWS_SECRET_ACCESS_KEY"].name
}

import {
  to = module.deploy_key.aws_iam_access_key.this
  id = "<current imported access key ID for app-atento-001 — redacted>"
}
```

```hcl
# terraform/modules/iam_deploy_key/main.tf:1-11 (module header comment)
# Manages the deploy IAM user's access key under Terraform and publishes its
# credentials as GitHub Actions environment secrets, ending the manual mint +
# manual paste. Existing keys are adopted via an `import {}` block in the caller
# stack (targeting `module.<name>.aws_iam_access_key.this`); the secret cannot
# be read back from an imported key, so AWS_SECRET_ACCESS_KEY is sourced from
# the SSM parameter that already holds it, while AWS_ACCESS_KEY_ID comes from
# the managed key's own id (available on import).
```

**Source:** `terraform/app-atento-001/github_deploy.tf:1-20`, `terraform/modules/iam_deploy_key/main.tf:1-11`. The header comment on the resource itself states plainly: *"No rotation — the current key is imported."* (`terraform/app-atento-001/github_deploy.tf:6`, and identically in `beta-001`, `demo-001`, `setup`, `integrator-atento`).

**Pattern B — Terraform-native key, no import (used by `onboarding`, `auth-001`, `mongodb`):**

```hcl
# terraform/onboarding/main.tf:311-316
resource "aws_iam_access_key" "deploy" {
  user = aws_iam_user.deploy.name
}
```

```hcl
# terraform/onboarding/github_deploy.tf:1-27 (header comment + resources)
# The deploy access key is already managed by Terraform (aws_iam_access_key.deploy),
# so its value is known in state — no import or SSM lookup is needed.
resource "github_actions_environment_secret" "deploy_access_key_id" {
  repository  = "onboarding"
  environment = "Production"
  secret_name = "AWS_ACCESS_KEY_ID"
  value       = aws_iam_access_key.deploy.id
}
resource "github_actions_environment_secret" "deploy_secret_access_key" {
  repository  = "onboarding"
  environment = "Production"
  secret_name = "AWS_SECRET_ACCESS_KEY"
  value       = aws_iam_access_key.deploy.secret
}
```

**Source:** `terraform/onboarding/main.tf:311-316`, `terraform/onboarding/github_deploy.tf:1-27`. The identical shape exists in `terraform/auth-001/github_deploy.tf:1-27` and `terraform/mongodb/iam.tf:10` + `terraform/mongodb/github.tf:24,31`.

**Significance:** Pattern B is the one that lines up with the engineer's stated goal ("facilitate future rotation"). Because the key is created directly by Terraform (never imported), its `.secret` attribute is known in state at all times, so a `github_actions_environment_secret` resource can read it directly — no manual SSM population step, no chicken-and-egg. Per the HashiCorp rotation guide: *"Configure the `aws_iam_access_key` resource to use the `replace_triggered_by` meta-argument. This tells Terraform to destroy and recreate the access key whenever the body of the `access_key_ttl.json` file changes."* ([HashiCorp Support](https://support.hashicorp.com/hc/en-us/articles/28354367124627-How-to-Automate-AWS-IAM-Access-Key-Rotation) — quote reconfirmed by direct re-fetch). Pattern A cannot use this technique cleanly: replacing an imported key still creates a new key whose secret Terraform *does* now know (post-replacement it behaves like Pattern B), but the existing SSM-sourced `data.aws_ssm_parameter` lookup in `iam_deploy_key` would go stale and would need to be manually re-populated first — the module was designed around "adopt an existing key," not "rotate a managed one."

### Finding 7: Even Pattern B does not close the loop on the runtime side today

**Evidence:**

```hcl
# terraform/onboarding/ssm.tf:1-13, 31-40
# Sensitive environment variables are stored as SecureString parameters.
# Values are NOT managed by Terraform after initial creation (ignore_changes).
# To set or rotate a value:
#   aws ssm put-parameter --name "/onboarding/<NAME>" --value "<VALUE>" --type SecureString --overwrite --region us-east-1
...
resource "aws_ssm_parameter" "secrets" {
  for_each = local.ssm_secret_names
  name     = "/onboarding/${each.key}"
  type     = "SecureString"
  value    = "PLACEHOLDER"
  lifecycle {
    ignore_changes = [value]
  }
}
```

**Source:** `terraform/onboarding/ssm.tf:1-41` (full file read)

**Significance:** even in `onboarding`, where the deploy key IS fully Terraform-native (Finding 6, Pattern B), the RUNTIME copy of `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` that the ECS task reads (`onboarding/compute.tf:21-22`) is a `PLACEHOLDER` value frozen by `ignore_changes`, populated once by hand and never touched by Terraform again. Rotating the Terraform-managed deploy key would update the GitHub secret automatically on the next apply, but would **not** update this runtime SSM value — that still needs a manual `aws ssm put-parameter --overwrite` today, for every stack, regardless of whether the two identities are split. This is a pre-existing gap independent of the split, but directly relevant to "facilitate rotation": splitting into two users does not by itself remove this gap unless the runtime SSM value is also wired to read directly from a Terraform-managed access key resource's `.secret` attribute (see Options below).

### Finding 8: Prior spikes already researched adjacent ground and reached compatible, not contradictory, conclusions

**Evidence:**

> "If IAM users are used: Do NOT create `aws_iam_access_key` via Terraform (secrets appear in state file) ... store in SSM Parameter Store as SecureString"

**Source:** `~/Projects/4Shark/dot-claude-plans/active/spike/integrator-iam-terraform/SPIKE.md:316-318` (section `### 5. Secret Management` → "If IAM users are used")

> "Deploy credentials must stay in GH Secrets — `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for the IAM deploy user must remain in GH secrets to authenticate the deployment. They can optionally also be in SSM for the application runtime (they serve different purposes)."

**Source:** `~/Projects/4Shark/dot-claude-plans/active/spike/github-envs-to-terraform-ssm/SPIKE.md` (Conclusions, item 9)

**Significance:** the `integrator-iam-terraform` spike (2026-03-03) already weighed Terraform-managed access keys (state-file exposure) against IAM roles, and recommended IAM roles as the long-term path for the integrator's EC2 workloads — a recommendation the current engineer instruction supersedes for the purposes of this spike (access keys are the given). Within the access-key branch it evaluated, "Terraform creates keys, outputs as sensitive, stored in state" (its Option A) is the same shape as Pattern B above, and it already flagged: *"Rotation requires `terraform taint aws_iam_access_key.this` + apply + update application env vars."* The `github-envs-to-terraform-ssm` spike (2026-03-21) already named runtime and deploy as "different use cases" for the same credential without concluding they should be different IAM identities — this spike's Finding 1 through 4 supplies the missing evidence (the actual permission sets differ, not just the "use case" label) that would justify the split these two prior spikes stopped short of.

## Trade-offs surfaced

All options below assume **two IAM users per app × environment** (runtime + deploy), **both with long-lived access keys**, **both 100% Terraform-managed**. They differ only in how the key lifecycle and rotation plumbing are structured.

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **A — Two users, both keys kept on the "imported key" pattern** (`modules/iam_deploy_key` + `import {}`, as done today for `app-*`/`integrator-*`/`setup`) | Smallest Terraform diff; reuses the exact module already in use; no behavior change to the GitHub secret publishing mechanism | Does not improve rotation — the module's own design assumes "adopt an existing key," and the header comment on every current instance says "No rotation — the current key is imported"; doubles this friction (now 2 imported keys instead of 1) | `terraform/modules/iam_deploy_key/main.tf:1-11`, `terraform/app-atento-001/github_deploy.tf:6` |
| **B — Two users, both keys created directly by Terraform** (`aws_iam_access_key` with no `import {}`, mirroring `onboarding`/`auth-001`/`mongodb`) | Matches the engineer's rotation goal for the *deploy* side out of the box — `.secret` is known in state, `github_actions_environment_secret` reads it directly, no manual SSM step; can adopt `replace_triggered_by` (HashiCorp-documented) for a clean future rotation trigger | Requires a migration step: existing imported keys must either be replaced (an actual key rotation event, need to sequence GitHub secret + running app cutover) or the two new users get freshly minted keys from day one, retiring the old single key from both roles at once | `terraform/onboarding/github_deploy.tf:1-27`, [HashiCorp rotation guide](https://support.hashicorp.com/hc/en-us/articles/28354367124627-How-to-Automate-AWS-IAM-Access-Key-Rotation) |
| **C — Two users, Pattern B for the deploy key, runtime SSM value ALSO wired directly from the runtime user's managed key** (removing `ignore_changes` on `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` specifically, keeping it for every other secret) | Closes the loop end-to-end: one `terraform apply` after a rotation trigger updates both the GitHub secret (deploy) and the ECS-injected SSM value (runtime) — no manual `aws ssm put-parameter` step for these two names ever again | The access-key secret value now flows through Terraform state into the `aws_ssm_parameter` resource too (already true for the GitHub secret in Pattern B); every other secret in the same `ssm_secret_names` list stays untouched/manual, so this is a narrow, deliberate exception, not a blanket policy change | `terraform/onboarding/ssm.tf:1-41`, `terraform/app-beta-001/compute.tf:55-57` |
| **D — Phased: adopt B for the deploy user now, leave the runtime user on the current manual-SSM pattern, revisit C later** | Lowest-risk first step; deploy-side rotation friction is solved immediately; runtime-side stays exactly as reliable/unreliable as it is today | The stated goal ("facilitate rotation") is only half-delivered until a follow-up closes the runtime gap; two credentials with two different rotation stories to track in the interim | Derived from Findings 6 and 7 |

**Module-structure sub-question (orthogonal to the above):** `modules/iam_deploy` is already deploy-only and needs no change. The runtime side, however, is hand-rolled per stack today for `app`/`onboarding`/`setup` (inline `aws_iam_policy` block, e.g. `terraform/app-atento-001/iam_deploy_user.tf:14-40`), while the `integrator` project already extracted this into a reusable `modules/integrator_iam` module (`terraform/modules/integrator_iam/{main,s3,ec2}.tf`). Splitting into two users is a natural point to also extract an equivalent runtime module for `app`/`onboarding`/`setup`, following the `integrator_iam` precedent — or to keep the policy inline per stack, since the four app-family stacks are more heterogeneous than the integrator's per-client repetition. This is a naming/module-boundary decision, not resolved by this investigation (see Ask, Don't Decide below).

**On OIDC (one line, per the engineer's scope instruction):** GitHub Actions OIDC (federated short-lived STS credentials via `aws-actions/configure-aws-credentials`'s `role-to-assume`, no stored access key) is a documented alternative CI-auth pattern and was surfaced only to flag that it exists — it is out of scope here because the engineer has already decided to keep IAM-user access keys for this design.

## What remains uncertain

- **Naming for the two new users.** Today the single user is named after the stack (`app-atento-001`, `onboarding`, `setup`, `auth-001` for keycloak) per `ADR-010-resource-naming-convention.md`'s "IAM deploy user | app- (native) | app-<env>-001" row — but that row describes what is actually a mixed-purpose user. Whether the runtime user keeps the existing name (for continuity, since it is the one already referenced by running infrastructure) and the new user gets a `-deploy` suffix, or vice versa, is a naming decision for the engineer, not resolved here.
- **Cutover sequencing.** Because today's single key already serves both roles, splitting means the currently-active key must be retired from one of the two new roles at cutover — this needs a decided order (e.g., stand up the new deploy user and repoint GitHub secrets first, while the running application keeps its current key unchanged; or the reverse). Not investigated in this spike.
- **Whether Option C's `ignore_changes` removal should be scoped to just `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, or should prompt a broader look at every other secret still on the manual-SSM pattern.** This spike only evaluated the two AWS-credential parameters; widening the change touches unrelated secrets (`DATABASE_URL`, `SECRET_KEY_BASE`, etc.) in the same `ssm_secret_names` set and was not investigated.
- **Whether `setup` needs a runtime IAM user/key at all.** Finding 3 found no code path in `setup` that reads `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` — if confirmed genuinely unused, `setup` might only need a deploy user, simplifying its case relative to `app`/`onboarding`/`integrator`. This should be confirmed with the team (a broader repo search than this spike performed, or direct confirmation from whoever owns `setup`) before deciding to drop it.
- **Where the deploy secret should live (GitHub Environment vs repository/org secret).** The `github-envs-to-terraform-ssm` spike's Next Steps already raised moving deploy credentials to repository- or org-level secrets instead of per-environment ones; this spike did not revisit that question and assumes the current per-environment placement is unchanged.
- **Module boundary for the runtime side** (extract a shared module akin to `integrator_iam`, vs. keep it inline per stack) — flagged above, genuinely open.

## Suggested options for main and the engineer

- **Option A** — Two users per app × environment, both keys managed via the existing "imported key" pattern (`modules/iam_deploy_key`). Minimal change, but does not deliver the rotation-facilitation goal.
- **Option B** — Two users, both keys created directly by Terraform (no import), GitHub secrets populated straight from each key's own `.secret` attribute — mirrors the `onboarding`/`auth-001`/`mongodb` precedent already in the repo.
- **Option C** — Same as B, plus the runtime user's `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` SSM parameter values are also wired directly from that user's managed key (dropping `ignore_changes` for just these two names), closing the loop for both consumers in one `terraform apply`.
- **Option D** — Phased adoption of B now (deploy side), C later (runtime side), as two separate pieces of work.
- Separately: whether to extract a shared "runtime IAM module" for `app`/`onboarding`/`setup` (following the `integrator_iam` precedent) or keep the policy inline per stack, as part of whichever option above is chosen.

(No recommendation — the evidence above surfaces the trade-offs; the engineer and main choose the path.)
