<!-- Auxiliary file for SPIKE.md — credential-risk-classification -->
<!-- Raw evidence: the "Terraform ENV" 1Password bootstrap item and what it authorizes -->

# Excerpt 2 — The `Terraform ENV` bootstrap item and its blast radius

## `identity/.envrc` (full file)

```bash
# identity — break-glass stack. Runs as the ivo profile (guard.tf enforces it) and needs the
# Cloudflare, MongoDB Atlas, Rollbar and GitHub credentials for its providers. No source_up:
# the secrets are listed explicitly so this stack loads only what it uses.
export AWS_PROFILE=ivo

terraform_environment="$(op item get 'Terraform ENV' --vault 'Employee' --account=4shark.1password.com --format json)"

export CLOUDFLARE_API_TOKEN="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "CLOUDFLARE_API_TOKEN").value')"
export GITHUB_TOKEN="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "GITHUB_TOKEN").value')"
export MONGODB_ATLAS_PRIVATE_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "MONGODB_ATLAS_PRIVATE_KEY").value')"
export MONGODB_ATLAS_PUBLIC_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "MONGODB_ATLAS_PUBLIC_KEY").value')"
export ROLLBAR_API_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "ROLLBAR_API_KEY").value')"
```

## `app-shared-001/.envrc` (full file) — same bootstrap item, different subset of fields exported

```bash
# app-shared-001 — MongoDB Atlas + Redis Cloud + GitHub credentials for this stack's providers.
# Pulled from the shared "Terraform ENV" 1Password item (Employee vault). No source_up:
# this stack needs only these secrets, none of the others.
terraform_environment="$(op item get 'Terraform ENV' --vault 'Employee' --account=4shark.1password.com --format json)"

export MONGODB_ATLAS_PRIVATE_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "MONGODB_ATLAS_PRIVATE_KEY").value')"
export MONGODB_ATLAS_PUBLIC_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "MONGODB_ATLAS_PUBLIC_KEY").value')"
export REDISCLOUD_ACCESS_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "REDISCLOUD_ACCESS_KEY").value')"
export REDISCLOUD_SECRET_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "REDISCLOUD_SECRET_KEY").value')"
export GITHUB_TOKEN="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "GITHUB_TOKEN").value')"
```

Every stack directory under `~/Projects/4Shark/terraform/` that has an `.envrc` follows this same
`op item get 'Terraform ENV' ...` pattern (confirmed present in 16 stack directories via
`find ... -iname ".envrc"`); the two shown above are representative of the two shapes (the
break-glass `identity` stack pulling every field, an ordinary app stack pulling only what its
providers need).

## `TERRAFORM-POLICY.md` (Tier 2 doc) — confirms the wrapper loads `.envrc` for BOTH plan and apply

> **READ commands run through the wrapper — `bash ~/.claude/scripts/terraform.sh <stack-dir> <read-subcommand> [args]`.** ... it runs `init` only when needed, applies direnv try-first, rejects `-target`, and loads the stack env internally

**Source:** `~/.claude/docs/TERRAFORM-POLICY.md:3`

This confirms the `Terraform ENV` item's fields are fetched (via direnv → `.envrc` → `op item get`)
regardless of whether the terraform subcommand is a read (`plan`) or a write (`apply`) — the
wrapper's whole job is to load the same stack `.envrc` for reads that the raw `direnv exec` path
loads for writes.

## `identity/providers.tf` (github provider block)

```hcl
provider "github" {
  owner = var.github_org
}
```

The `integrations/github` Terraform provider reads its token from the `GITHUB_TOKEN` environment
variable by default when no `token` attribute is set on the provider block — none is set here, so
the token exported by `.envrc` (from the `Terraform ENV` item) is what authenticates every
`github_*` resource in this stack, at the configured `owner` (the 4Shark GitHub org).

## `identity/github_repositories.tf` — what that token can rewrite (lines 112–169, excerpted)

```hcl
resource "github_repository" "this" {
  for_each = local.repositories
  name        = each.key
  description = each.value.description
  visibility  = each.value.visibility
  ...
}

resource "github_branch_protection" "master" {
  for_each = local.hubflow_repositories

  repository_id = github_repository.this[each.value].node_id
  pattern       = "master"

  enforce_admins      = false
  allows_force_pushes = false
  allows_deletions    = false

  required_pull_request_reviews {
    required_approving_review_count = 0
  }
  ...
}

resource "github_branch_protection" "develop" {
  for_each = local.hubflow_repositories
  repository_id = github_repository.this[each.value].node_id
  pattern       = "develop"
  enforce_admins      = false
  allows_force_pushes = false
  allows_deletions    = false
  ...
}
```

Also in the same file (`identity/github_repositories.tf:74-106`, confirmed via direct read):
`github_membership` (org membership), `github_team` / `github_team_membership` (team roles),
`github_team_repository` with `permission = "admin"` grants on essentially every 4Shark repo
(`app`, `onboarding`, `setup`, `terraform`, `integrator`, `dot-claude`, etc.).

**Significance for blast radius:** the same `GITHUB_TOKEN` sourced from the `Terraform ENV` item
is the one Terraform uses to define `allows_force_pushes = false` / `allows_deletions = false` on
`master`/`develop` for every HubFlow repository. A token with sufficient scope, if exfiltrated,
could be used directly against the GitHub API (bypassing Terraform entirely) to alter or remove
those same branch-protection settings — i.e., a compromise of this credential is not bounded by
the very protections the org relies on elsewhere as a compensating control for a compromised
git-push SSH key.

## `dns/*.tf` — what `CLOUDFLARE_API_TOKEN` (same bootstrap item) manages

Files present: `public_dns_4shark_com_br.tf`, `public_dns_4sharkpay_com.tf`,
`public_dns_app4shark_com.tf`, `public_dns_app4shark_com_br.tf`, `public_dns_4shark_com.tf`,
`redirect_app4shark_com.tf`, `redirect_app4shark_com_br.tf` — public DNS zones for every
4Shark-owned domain, managed by the `cloudflare` Terraform provider authenticated with
`CLOUDFLARE_API_TOKEN` from the same `Terraform ENV` item.
