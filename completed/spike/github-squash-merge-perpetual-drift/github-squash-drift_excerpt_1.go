// Source: https://github.com/integrations/terraform-provider-github/blob/main/github/resource_github_repository.go
// Provider version: integrations/github v6.12.1 (current pinned version in identity/.terraform.lock.hcl)
// Fetched: 2026-06-27 via WebFetch

// ─── 1. SCHEMA DEFINITIONS ───────────────────────────────────────────────────
// These are the Terraform-visible schema defaults for the two drifting attributes.
// When the engineer does NOT set these in the resource block, Terraform uses these
// defaults as the "desired state" for plan comparison.

"squash_merge_commit_title": {
    Type:        schema.TypeString,
    Optional:    true,
    Default:     "COMMIT_OR_PR_TITLE",
    Description: "Can be 'PR_TITLE' or 'COMMIT_OR_PR_TITLE' for a default squash merge commit title.",
},
"squash_merge_commit_message": {
    Type:        schema.TypeString,
    Optional:    true,
    Default:     "COMMIT_MESSAGES",
    Description: "Can be 'PR_BODY', 'COMMIT_MESSAGES', or 'BLANK' for a default squash merge commit message.",
},

// ─── 2. READ PATH (resourceGithubRepositoryRead) ─────────────────────────────
// Called on every plan/refresh. Runs UNCONDITIONALLY regardless of allow_squash_merge.
// This means GitHub's stored values are always read back into state.

_ = d.Set("squash_merge_commit_message", repo.GetSquashMergeCommitMessage())
_ = d.Set("squash_merge_commit_title", repo.GetSquashMergeCommitTitle())

// ─── 3. WRITE PATH (resourceGithubRepositoryCreate / resourceGithubRepositoryUpdate) ──
// CONDITIONAL on allow_squash_merge. When allow_squash_merge = false (4Shark's config),
// these attributes are NEVER sent to the GitHub API, regardless of what is in the
// resource block or the schema defaults.

// only configure squash commit if we are in squash merge strategy
allowSquashMerge, ok := d.Get("allow_squash_merge").(bool)
if ok {
    if allowSquashMerge {
        repository.SquashMergeCommitTitle =
            new(d.Get("squash_merge_commit_title").(string))
        repository.SquashMergeCommitMessage =
            new(d.Get("squash_merge_commit_message").(string))
    }
}

// ─── DRIFT CYCLE EXPLAINED ───────────────────────────────────────────────────
// For the `app` repo, GitHub stores: squash_msg="BLANK", squash_title="PR_TITLE"
//
// 1. terraform plan:
//    - read path runs: state gets BLANK / PR_TITLE from GitHub API
//    - desired state: COMMIT_MESSAGES / COMMIT_OR_PR_TITLE (schema defaults)
//    - diff: BLANK → COMMIT_MESSAGES, PR_TITLE → COMMIT_OR_PR_TITLE
//
// 2. terraform apply:
//    - write path checks: allow_squash_merge = false → SKIPS writing squash attrs
//    - GitHub state unchanged: still BLANK / PR_TITLE
//
// 3. next terraform plan:
//    - read path runs again: still gets BLANK / PR_TITLE
//    - drift identical to step 1 → PERPETUAL LOOP
