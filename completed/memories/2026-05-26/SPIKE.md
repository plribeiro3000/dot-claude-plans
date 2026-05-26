# SPIKE — Memory Cleanup 2026-05-26

**Status:** Open — proposing destinations; engineer decisions pending.
**Run folder:** `~/.claude/plans/active/memories/2026-05-26/`
**Round:** 1

## Proposed destinations

| # | Source | Summary | Destination | Why | Origin |
|---|---|---|---|---|---|
| 1 | `~/.claude/memory/20260522-100010-pr-6273-html-lint-followup.md` | Follow-up to enable HTML linting via `@angular-eslint/template` in `app-webclient` after PR #6273 (ESLint v9 + flat config) is merged. | active plan (`app-webclient-html-lint`) | In-flight work, depends on another PR being merged first; not a rule, just a contextual TODO. | NEW |
| 2 | `~/.claude/projects/-Users-plribeiro3000-Projects-4Shark-app/memory/feedback_api_exposure_verification.md` | When classifying API surface in Rails, always start from `config/routes.rb` + strong_params; never infer from model names. | Tier 2 doc: `~/.claude/docs/RAILS-CONVENTIONS-CONTEXT.md` | Convention applicable to any Rails project (app, integrator, setup) — does not fit in a single `<repo>/CLAUDE.md`. Content is not covered in the current doc. | NEW |
| 3 | `~/.claude/projects/-Users-plribeiro3000-Projects-4Shark-terraform/memory/feedback_temporary_resources_no_changelog.md` | Temporary resources (exploratory VMs, ad-hoc tooling) do not go into the terraform `CHANGELOG.md`, despite the global rule requiring a changelog entry on every feature branch. | `~/Projects/4Shark/terraform/CLAUDE.md` (CREATE — file does not exist yet) | Exception specific to the terraform repo; not a cross-cutting rule. The terraform CLAUDE.md does not yet exist — this memory creates it. | NEW |
| 4 | `~/.claude/projects/-Users-plribeiro3000-Projects-4Shark-terraform/memory/feedback_terraform_use_worktree.md` | Changes in the terraform repo must run in a worktree, never switch branches on the main checkout (other sessions may be working in parallel). | `~/Projects/4Shark/terraform/CLAUDE.md` (APPEND) | Same justification as #3 — terraform-repo-specific rule. After PR #3 is merged, this PR will append into the same file. | NEW |

## Manual handling

None. All decoded paths exist on disk.

## Summary

Total: 4 entries — 0 drops · 0 global CLAUDE.md · 1 Tier 2 edit · 2 per-repo edits · 1 plan migration · 0 manual · 0 carry-overs.

PRs that will be opened: 3 (rows 2, 3, 4).
Plan migrations (local, no PR): 1 (row 1).

**Note on rows 3 and 4:** both memories target the same file (`~/Projects/4Shark/terraform/CLAUDE.md`). Each becomes a separate PR by skill design. PR for row 4 branches from `develop` before PR 3 is merged — after PR 3 is merged, PR 4 needs a rebase to resolve the create/append conflict on the same file. Alternative: accept only one at a time (e.g., approve 3, leave 4 as carry-over for the next run).
