# SPIKE — GitHub Squash Merge Perpetual Drift

## Investigation question

Why does `github_repository.this["app"]` in the `identity/` Terraform stack show perpetual in-place drift on `squash_merge_commit_message` (`BLANK` -> `COMMIT_MESSAGES`) and `squash_merge_commit_title` (`PR_TITLE` -> `COMMIT_OR_PR_TITLE`) on every plan, even after 4+ successful applies? What is the permanent fix?

## Sources consulted

- `identity/github_repositories.tf` — resource definition, all repo declarations, attribute set on `github_repository.this`
- `identity/providers.tf` — provider version constraint (`~> 6.0`) and lock file entry
- `identity/.terraform.lock.hcl` — confirms pinned provider version: `integrations/github v6.12.1`
- `https://github.com/integrations/terraform-provider-github/blob/main/github/resource_github_repository.go` — provider source code: schema defaults, read path, write path
- `gh api repos/4shark/<repo>` — live GitHub API for all 18 repos in `local.repositories` (see auxiliary: `github-squash-drift_data_1.txt`)
- `https://github.com/integrations/terraform-provider-github/issues/2147` — bug report: provider sets squash defaults even when squash disabled, GitHub rejects with 422
- `https://github.com/integrations/terraform-provider-github/issues/1295` — bug report: upgrading to v4.31.0 introduces plan drift on merge commit message/title fields
- `https://github.com/integrations/terraform-provider-github/issues/2246` — bug report: drift detected on squash + merge settings despite no config change
- `https://github.com/integrations/terraform-provider-github/releases` — v6.12.1 (current) is the latest; no squash-drift fix in any v6.x release
- See auxiliary: `github-squash-drift_data_1.txt` — live GitHub API dump for all 18 repos
- See auxiliary: `github-squash-drift_excerpt_1.go` — provider source code read/write path excerpts with drift cycle annotation

## Findings

### Finding 1: Root cause — provider schema defaults + conditional write path + unconditional read path

**Evidence:**
```go
// Schema defaults (from resource_github_repository.go)
"squash_merge_commit_title": {
    Optional: true,
    Default:  "COMMIT_OR_PR_TITLE",
},
"squash_merge_commit_message": {
    Optional: true,
    Default:  "COMMIT_MESSAGES",
},

// Read path — UNCONDITIONAL
_ = d.Set("squash_merge_commit_message", repo.GetSquashMergeCommitMessage())
_ = d.Set("squash_merge_commit_title",   repo.GetSquashMergeCommitTitle())

// Write path — CONDITIONAL on allow_squash_merge
if allowSquashMerge {
    repository.SquashMergeCommitTitle   = new(d.Get("squash_merge_commit_title").(string))
    repository.SquashMergeCommitMessage = new(d.Get("squash_merge_commit_message").(string))
}
```
**Source:** `https://github.com/integrations/terraform-provider-github/blob/main/github/resource_github_repository.go` (confirmed via WebFetch, see `github-squash-drift_excerpt_1.go`)

**Significance:** Three facts combine to create the perpetual loop:
1. The schema declares `Default: "COMMIT_MESSAGES"` and `Default: "COMMIT_OR_PR_TITLE"` — Terraform uses these as the desired state when the attributes are absent from the HCL resource block (which they are in `github_repositories.tf`).
2. The read path runs on every plan and unconditionally reads whatever GitHub has stored, placing it into Terraform state.
3. The write path is gated on `allow_squash_merge = true`. Since `github_repository.this` sets `allow_squash_merge = false`, the write is permanently skipped. GitHub's stored values are never updated.

The cycle: plan reads `BLANK`/`PR_TITLE` from GitHub → compares with defaults `COMMIT_MESSAGES`/`COMMIT_OR_PR_TITLE` → diff detected → apply skips write (squash disabled) → GitHub unchanged → next plan: same diff. Applying never breaks the cycle.

### Finding 2: Why only `app` — confirmed by live GitHub API

**Evidence (from `github-squash-drift_data_1.txt`):**
```
repo                     squash_msg          squash_title         allow_squash
ansible                  COMMIT_MESSAGES     COMMIT_OR_PR_TITLE   false
app                      BLANK               PR_TITLE             false   ← ONLY DRIFTER
app-mobileclient         COMMIT_MESSAGES     COMMIT_OR_PR_TITLE   false
[...all other 16 repos]  COMMIT_MESSAGES     COMMIT_OR_PR_TITLE   false
```
**Source:** `gh api repos/4shark/<repo>` for all 18 repos, 2026-06-27

**Significance:** The `app` repo is the only one where GitHub's stored values (`BLANK`, `PR_TITLE`) differ from the provider's schema defaults (`COMMIT_MESSAGES`, `COMMIT_OR_PR_TITLE`). For all other 17 repos, stored values match defaults exactly — no diff is generated, so no drift is visible. The provider skips the write for all repos (squash disabled everywhere), but only `app` has a mismatch between GitHub-state and desired-state.

The historical cause cannot be recovered without a full audit trail, but the most likely origin is: at some point, the `app` repo had squash merge enabled with explicit non-default settings (`BLANK` message, `PR_TITLE` title). When squash was later disabled, GitHub preserved those configured values. All other repos either had squash configured to GitHub's defaults or were created after those defaults matched what the provider expects.

### Finding 3: Known provider behavior — issues closed as "not planned", no fix in v6.x

**Evidence:**

Issue #2147 (closed as not planned): *"The provider code sets a default for `squash_merge_commit_message` and `squash_merge_commit_title`, even when `allow_squash_merge` is set to `false`."* The GitHub API returns a 422 validation error when these are sent while squash is disabled: *"Sorry, you need to allow the squash merge strategy in order to set the default squash commit message title or message."*

Issue #1295 (closed as not planned): *"Presumably this plan may confuse users since it says something is going to happen, however the changes are simply setting new defaults and they are safe to apply."* The drift was introduced in v4.31.0 when the new commit-message fields were added to the schema with defaults.

Issue #2246 (closed as not planned): Similar drift pattern on merge commit settings after no user changes, no resolution provided.

**Source:** `https://github.com/integrations/terraform-provider-github/issues/2147`, `https://github.com/integrations/terraform-provider-github/issues/1295`, `https://github.com/integrations/terraform-provider-github/issues/2246`

**Significance:** The provider maintainers closed all three related issues without a fix and without an indication that one is planned. The v6.12.1 release notes (latest, confirmed via `gh api repos/integrations/terraform-provider-github/releases`) contain no entry addressing squash commit drift. A provider upgrade does not resolve this.

### Finding 4: Provider version — v6.12.1 is current latest, no newer fix version exists

**Evidence:**
```
# identity/.terraform.lock.hcl line 67-68
provider "registry.terraform.io/integrations/github" {
  version     = "6.12.1"
  constraints = "~> 6.0"
```
Release list from GitHub API (latest 4 tags): `v6.12.1`, `v6.12.0`, `v6.11.1`, `v6.11.0`. None contain a squash-drift fix.

**Source:** `identity/.terraform.lock.hcl:67-68`, `gh api repos/integrations/terraform-provider-github/releases`

**Significance:** The stack is already pinned to the latest available version. A provider upgrade cannot resolve the drift.

### Finding 5: The `lifecycle { ignore_changes }` trade-off — `for_each` applies it to all repos

**Evidence:** From `identity/github_repositories.tf:80-104`:
```hcl
resource "github_repository" "this" {
  for_each = local.repositories
  ...
  allow_squash_merge = false
  ...
  # squash_merge_commit_message and squash_merge_commit_title NOT declared
}
```
**Source:** `identity/github_repositories.tf:80-104`

**Significance:** The `github_repository.this` resource manages all 18 repos via a single `for_each` block. A `lifecycle { ignore_changes }` added to this resource applies uniformly to every instance in the for_each. Since the 4Shark merge policy enforces `allow_squash_merge = false` for all repos (stated in the file comment at lines 8-9: "merge commit only (squash and rebase disabled)"), the ignored attributes are functionally inert for every repo in the set. If squash merge is ever re-enabled on any repo in a future change, the engineer would need to remove `squash_merge_commit_message` and `squash_merge_commit_title` from `ignore_changes` (or remove the `ignore_changes` block entirely) at the same time.

### Finding 6: Explicit per-repo squash config as an alternative — requires locals map restructuring

**Evidence:** From `identity/github_repositories.tf:32-51`:
```hcl
repositories = {
  "app" = { visibility = "private", has_wiki = false, has_projects = false, description = null }
  ...
}
```
The `app` entry contains only `visibility`, `has_wiki`, `has_projects`, `description`. Adding `squash_message` and `squash_title` override fields only for `app` (using `try(each.value.squash_message, "COMMIT_MESSAGES")` in the resource block) would make the desired state match GitHub's actual state for `app` without touching any other repo.

**Source:** `identity/github_repositories.tf:32-51`

**Significance:** This approach does not use `ignore_changes` — Terraform continues to track the attributes. The drift stops because desired state is aligned to GitHub's actual state per-repo. The downside: the write path still skips writing these values when squash is disabled, so the fix relies on the desired config exactly matching what GitHub has stored. If any repo's GitHub-side values change out-of-band (GitHub UI), drift reappears for that repo. Also requires restructuring the locals map type to include optional squash fields.

## Trade-offs surfaced

| Approach | Pros | Cons | Apply-stickiness | Source |
|---|---|---|---|---|
| **A. `lifecycle { ignore_changes = [squash_merge_commit_message, squash_merge_commit_title] }`** | Single addition to resource block; permanently breaks drift cycle for all repos; semantically correct (attributes are inert while squash disabled); no API calls; no plan noise | Applies to ALL repos in for_each; if squash is re-enabled on any repo, these fields won't be managed until `ignore_changes` is removed; drift cause (GitHub state != defaults) stays, just hidden | Permanent — Terraform ignores these fields in every subsequent plan regardless of GitHub state | `github_repositories.tf:80`, provider source |
| **B. Per-repo squash config via `try()` in locals + resource block** | Attributes remain tracked by Terraform; explicit about values; engineer can see what GitHub actually stores per repo; does not hide attributes | Requires locals map restructuring to support optional per-repo fields; relies on desired state = GitHub state (fragile if GitHub UI used); if another repo gets non-default values later, drift reappears for that repo and requires another locals entry | Permanent as long as GitHub state doesn't change; write path still skips writes when squash off | `github_repositories.tf:32-51`, live API data |
| **C. Provider upgrade** | Would be a proper upstream fix if one existed | No fix exists in any v6.x release; v6.12.1 is the latest | N/A — no fix version | issue #2147, #1295; release notes |
| **D. Two-step apply (enable squash → apply → disable → apply)** | Permanently syncs GitHub state to provider defaults for `app`; no code change needed afterward | Temporarily enables squash merge on `app` (visible to team); requires two separate applies; operational complexity; relies on provider applying squash defaults when squash is enabled | Permanent if both steps succeed and GitHub retains the written values | GitHub API behavior, provider write path logic |

## What remains uncertain

- The exact historical event that put `app`'s GitHub-side squash values at `BLANK`/`PR_TITLE` is not recoverable without a full audit trail. This is informational only and does not affect the fix.
- Whether the provider maintainers plan to fix the read-without-write cycle in a future release. Issues #2147 and #2246 are both closed as "not planned" — no upstream fix on the horizon.
- If Option D (two-step apply) is chosen, it is not confirmed whether GitHub persists the written squash values after squash merge is subsequently disabled. The API behavior when re-disabling squash is not documented in the provider issues. Option A avoids this uncertainty entirely.

## Suggested options for main and the engineer

**Option A (recommended by evidence, simplest permanent code change):**

Add `lifecycle { ignore_changes = [squash_merge_commit_message, squash_merge_commit_title] }` to `github_repository.this` in `identity/github_repositories.tf`. Add a comment documenting the reason. File and line: `identity/github_repositories.tf`, inside the `github_repository "this"` block after line 103 (current last line before closing `}`).

```hcl
resource "github_repository" "this" {
  for_each = local.repositories
  # ... existing attributes ...

  lifecycle {
    # squash_merge_commit_message and squash_merge_commit_title drift perpetually on the
    # `app` repo because the provider reads these values unconditionally from GitHub but
    # only writes them when allow_squash_merge = true. Since 4Shark policy sets
    # allow_squash_merge = false for all repos, the write is always skipped and GitHub's
    # stored values (BLANK / PR_TITLE for `app`) can never be reconciled to the provider's
    # schema defaults (COMMIT_MESSAGES / COMMIT_OR_PR_TITLE). The attributes are
    # functionally inert while squash merge is disabled. Remove this ignore_changes if
    # squash merge is intentionally re-enabled on any repo managed by this resource.
    ignore_changes = [squash_merge_commit_message, squash_merge_commit_title]
  }
}
```

After this change, `terraform plan` produces zero changes for these attributes on every subsequent run. No API calls needed. The fix is a single commit.

**Option B (explicit, no hidden ignore — more config churn):**

Add optional `squash_message`/`squash_title` fields to the `local.repositories` map type, provide them only for `app` (`"BLANK"` and `"PR_TITLE"`), use `try(each.value.squash_message, "COMMIT_MESSAGES")` in the resource block. This aligns desired state to GitHub's actual state per-repo. More verbose change, fragile if GitHub UI is used to change squash settings on any repo.

**Option D (operational fix, no code change):**

Temporarily change `allow_squash_merge = false` to `true` for `app` only (by adding a per-repo flag in the locals map), apply once (the write path then sends `COMMIT_MESSAGES`/`COMMIT_OR_PR_TITLE` to GitHub for `app`), then revert and apply again. After both applies, GitHub's stored values for `app` would match the provider defaults and no drift would appear. Requires two PRs and two applies; introduces temporary squash availability on `app`.
