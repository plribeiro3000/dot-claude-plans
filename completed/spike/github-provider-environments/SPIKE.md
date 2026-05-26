# SPIKE — GitHub Provider for Terraform: Managing GitHub Environment Secrets

**Conducted by:** Engineering
**Date:** 2026-03-21
**Status:** Closed — Option A selected (monitor issue #3202)

---

## Goal

Determine whether the Terraform GitHub provider (`integrations/github`) can be used to manage GitHub Environment secrets for the `4shark/app` repository — specifically to keep `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in sync with the values already stored in AWS SSM Parameter Store.

Questions to answer:

1. Does the provider support GitHub Environment secrets and variables? What resources exist?
2. How does secret encryption work (GitHub uses libsodium/NaCl)?
3. Can SSM Parameter Store values be referenced automatically to populate GitHub Environment secrets?
4. What are the risks — specifically, do secret values appear in Terraform state?
5. Is there a viable alternative pattern (e.g., a GHA workflow that syncs SSM → GitHub Environments)?

---

## Method

- Fetched official provider documentation from the GitHub source of `integrations/terraform-provider-github`
- Fetched HashiCorp documentation on `aws_ssm_parameter` data source and Terraform 1.11 write-only attributes
- Reviewed existing SSM configuration in the project (`app-beta-001`, `app-demo-001`, `app-atento-001`, `app-shared-001`)
- Searched for community patterns combining `aws_ssm_parameter` + `github_actions_environment_secret`
- Reviewed open GitHub issues on the provider repository (issue #3202)
- Searched for alternative GHA-based sync workflows

---

## Evidence

### 1. Available Resources in the GitHub Provider

The `integrations/github` provider (v4.12.0+) includes three resources directly relevant to this task:

| Resource | Purpose | Introduced |
|---|---|---|
| `github_repository_environment` | Creates/manages the environment itself | v4.12.0 (Jun 2021) |
| `github_actions_environment_secret` | Manages secrets within an environment | v4.12.0 (Jun 2021) |
| `github_actions_environment_variable` | Manages non-secret variables within an environment | After v4.24.0 |

There is also a data source `github_actions_environment_public_key` that retrieves the public key for a given environment, needed for pre-encrypting secrets.

**Source:** `integrations/terraform-provider-github` website/docs (markdown source on GitHub)

---

### 2. How `github_actions_environment_secret` Works

**Required arguments:**
- `repository` — repository name
- `environment` — environment name
- `secret_name` — name of the secret

**Value input — two mutually exclusive options:**
- `value` — plaintext; the provider encrypts it automatically using Go's `crypto/box` module (compatible with GitHub's libsodium decoder)
- `value_encrypted` + `key_id` — pre-encrypted base64 value; the caller is responsible for encryption using the environment's public key (from `github_actions_environment_public_key` data source)

**Encryption mechanism:**
The provider uses Go's `crypto/box` (NaCl sealed box), which is interoperable with the libsodium library that GitHub uses server-side to decrypt. The encryption is performed transparently by the provider when `value` is used. The GitHub API never receives a plaintext value over the wire.

**Import format:** `repository:environment:secret_name`

**Import limitation:** When importing existing secrets, `value` / `value_encrypted` fields are NOT populated in state (GitHub's API does not return secret values). This means Terraform cannot detect drift in the value of an existing secret.

**Source:** `integrations/terraform-provider-github` — `website/docs/r/actions_environment_secret.html.markdown`

---

### 3. The Critical State Problem

**The `value` field is marked `sensitive` in Terraform, but this does NOT hide it from state files.**

Quote from the official documentation:
> "The contents of the `value` field have been marked as sensitive to Terraform, but this does not hide it from state files. You should treat state as sensitive always."

This means: if you pass a plaintext secret via `value`, it will be stored in plaintext inside `terraform.tfstate`. The project already stores state in S3 (`4shark-terraform-state`), which mitigates risk at rest — but the value is still visible to anyone with S3 read access or who runs `terraform show`.

**Source:** Official documentation + search results confirming this behavior

---

### 4. The SSM Integration Problem

**The current project pattern deliberately avoids reading SSM values in Terraform.**

All four environment stacks (`app-beta-001`, `app-demo-001`, `app-atento-001`, `app-shared-001`) have this in their `ssm.tf`:

```hcl
resource "aws_ssm_parameter" "secrets" {
  for_each = local.ssm_secret_names
  name     = "/<env>/${each.key}"
  type     = "SecureString"
  value    = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [value]
  }
}
```

The `ignore_changes = [value]` was a deliberate decision: Terraform creates the parameter structure but does NOT own the value. Values are rotated manually via `aws ssm put-parameter --overwrite`.

**Consequence for this spike:** To pass SSM values into `github_actions_environment_secret`, Terraform would need to READ the current SSM value via `data "aws_ssm_parameter"`. This requires removing (or working around) `ignore_changes` and accepting that:

1. The decrypted SecureString value will land in Terraform state
2. The AWS SSM `data` source documentation explicitly warns: "The unencrypted value of a SecureString will be stored in the raw state as plain-text"

This creates a state that contains the exact secrets the team is trying to protect.

**Source:** Local codebase analysis + HashiCorp AWS provider documentation

---

### 5. Write-Only Attributes (Terraform 1.11) — Not Yet Available for GitHub Provider

Terraform 1.11 introduced write-only arguments: resource attributes that are never persisted in state or plan files. This would be the ideal solution — read an ephemeral SSM value and pass it directly to a write-only field on `github_actions_environment_secret`.

**However:** The GitHub provider does NOT yet support write-only arguments for secrets.

- Issue [#3202](https://github.com/integrations/terraform-provider-github/issues/3202) — "Support write-only (ephemeral) values for GitHub environment secrets" — is **open and blocked as of March 18, 2026**
- The issue is labeled "Status: Blocked" and "Status: Triage"
- A contributor noted the feature depends on a broader refactor (PR #3225) before write-only fields can be enabled
- No timeline has been committed

AWS and Azure providers already implement write-only (`password_wo`, `value_wo`), but GitHub's provider has not followed yet.

**Source:** GitHub issue #3202 on `integrations/terraform-provider-github`

---

### 6. Alternative: GHA Workflow to Sync SSM → GitHub Environments

A pattern exists where a GitHub Actions workflow (not Terraform) reads from SSM and updates GitHub Environment secrets using the `gh` CLI or the GitHub REST API.

**General pattern:**
```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::ACCOUNT:role/github-sync-role
    aws-region: us-east-1

- name: Read from SSM and update GitHub secret
  env:
    GH_TOKEN: ${{ secrets.GH_ADMIN_TOKEN }}
  run: |
    VALUE=$(aws ssm get-parameter \
      --name "/beta-001/AWS_ACCESS_KEY_ID" \
      --with-decryption \
      --query Parameter.Value \
      --output text)
    gh secret set AWS_ACCESS_KEY_ID \
      --env beta-001 \
      --repo 4shark/app \
      --body "$VALUE"
```

**Characteristics of this approach:**
- The secret value exists only in memory during the workflow run; it is never written to any file
- `gh secret set` encrypts the value client-side before sending to the GitHub API (same libsodium mechanism)
- Workflow can be triggered manually or on a schedule after credential rotation
- Requires a PAT (`GH_ADMIN_TOKEN`) with `repo` scope stored as a repository-level secret
- Requires an IAM role with `ssm:GetParameter` + `kms:Decrypt` permissions on the relevant paths

**Limitation:** The secret value transits through the GHA runner's memory. It never appears in logs (GitHub masks secrets), but the runner itself is ephemeral managed infrastructure (GitHub-hosted), which is considered an acceptable trust boundary for most teams.

**Source:** GitHub Actions `gh` CLI documentation + community patterns found via web search

---

### 7. Provider Authentication Requirements

To use `github_actions_environment_secret`, the GitHub provider requires:
- A token (PAT or GitHub App) with **`repo` scope** (grants full repository access)
- The token owner must have **collaborator (write) access** to the repository

For GitHub App authentication: the app needs the "Secrets" repository permission set to "Read and write".

**Source:** GitHub REST API documentation for environment secrets

---

### 8. Current Project Terraform Version Constraint

The project stacks use `required_version = ">= 1.0"`. Write-only attributes require Terraform 1.11. This is compatible with a future version bump, but would need to be verified across all stacks before adopting write-only patterns.

---

## Conclusions

### What is technically possible today

The GitHub provider **does** support creating and updating GitHub Environment secrets via Terraform. The resources are mature (introduced in 2021) and actively maintained. A basic implementation would work.

### Why the SSM → Terraform → GitHub path is problematic right now

The combination of two facts creates an unacceptable security profile:

1. **SSM values land in state.** Reading `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` via `data "aws_ssm_parameter"` decrypts them into Terraform state in plaintext. State is stored in S3, but any engineer with S3 read access can extract production credentials.

2. **Write-only attributes are not yet available for the GitHub provider.** The only mechanism that would prevent this — ephemeral write-only fields — is blocked (issue #3202, open as of March 2026). There is no workaround within Terraform itself.

Adopting this pattern today means accepting that Terraform state becomes a credential store, which contradicts the existing project decision to use `ignore_changes` precisely to keep credentials out of state.

### What the viable path looks like

The GHA workflow pattern (SSM → runner memory → `gh secret set`) achieves the stated goal — automatic sync of credentials to GitHub Environments after rotation — without any state exposure. It is:

- Already possible with existing infrastructure (IAM roles, OIDC)
- Narrowly scoped (reads only the 4-5 specific secrets per environment, not all SSM params)
- Auditable via GHA workflow run logs
- Triggered manually or by a scheduled event after rotation

The Terraform approach becomes viable once the GitHub provider implements write-only support (issue #3202). At that point, the pattern would be:

```hcl
# Ephemeral: never written to state
ephemeral "aws_ssm_parameter" "access_key" {
  name            = "/beta-001/AWS_ACCESS_KEY_ID"
  with_decryption = true
}

resource "github_actions_environment_secret" "aws_access_key" {
  repository  = "app"
  environment = "beta-001"
  secret_name = "AWS_ACCESS_KEY_ID"
  value_wo    = ephemeral.aws_ssm_parameter.access_key.value  # hypothetical, pending issue #3202
}
```

---

## Next Steps

Three options for the engineer to decide:

**Option A — Do nothing for now, monitor issue #3202** ✅ SELECTED (2026-03-21)
The current state (manual rotation + manual GitHub Environment updates) remains unchanged. Subscribe to issue #3202 and revisit when write-only support is released. Low effort, leaves the manual sync gap open.

**Option B — Implement a GHA sync workflow**
Create a workflow in `4shark/app` that reads the 4-5 relevant secrets per environment from SSM and pushes them to GitHub Environments using `gh secret set`. Triggered manually after credential rotation. This closes the sync gap without Terraform state exposure. Requires: IAM role with SSM read access, a PAT with `repo` scope stored as a GitHub secret.

**Option C — Adopt Terraform GitHub provider with accepted state risk**
Add the GitHub provider to the app environment stacks and use `data "aws_ssm_parameter"` + `github_actions_environment_secret` today, accepting that credentials flow through Terraform state. Justification would require: encrypted S3 backend with strict IAM access controls, confirmed `ignore_changes` removal for only the specific SSM params used, and a team agreement on the security trade-off.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
