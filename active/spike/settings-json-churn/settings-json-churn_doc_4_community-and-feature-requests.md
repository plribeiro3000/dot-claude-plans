# Auxiliary — community proposals and open feature requests (fetched)

## anthropics/claude-code#4800 — "extends" field feature request

Source: https://github.com/anthropics/claude-code/issues/4800
Status: **Open** (not shipped)
Labels: `area:core`, `enhancement`
Opened: 2026-07-30 (per fetch)
Assignees/milestone/projects: none. "Development section shows: No branches or pull requests" — i.e. no implementation in progress.

Proposal (extraction):

```json
{ "extends": "@ourteam/claude-config" }
```

Supported sources proposed: NPM packages, local paths, git URLs. Multiple inheritance supported (array form), "later sources overriding earlier ones and local config overriding all", modeled explicitly on ESLint/TSConfig `extends`.

**Conclusion: as of this research, `extends`/import of shared config from an arbitrary file Claude Code loads on its own is NOT a shipped capability — it is an unimplemented, unassigned feature request.**

## hardwood-hq/hardwood#590 — split tracked/untracked settings (community project, not Claude Code itself)

Source: https://github.com/hardwood-hq/hardwood/issues/590

This is an issue in a THIRD-PARTY project's own repo (not anthropics/claude-code) describing the same class of problem in reverse: `.claude/settings.local.json` had been accidentally committed, imposing "one developer's personal and exploratory permission grants... on everyone."

Proposed fix (extraction):
1. Untrack `.claude/settings.local.json` from version control, gitignore it, so each developer's settings stay personal.
2. Add a committed `.claude/settings.json` with "a curated, project-wide permission allow-list" (conservative defaults — build tools, GitHub CLI operations, read-only git inspection, documentation fetching).

No discussion of the desktop app overwriting/rewriting the committed file was found in this issue — it addresses the opposite direction (personal settings leaking INTO the tracked file via accidental commit), not the app REWRITING the tracked file post-commit. Relevant as confirmation that the intended shape (tracked file = team-shared, untracked local file = personal) matches 4Shark's own model — the difference is 4Shark's tracked file lives at the USER scope (`~/.claude/settings.json`) rather than PROJECT scope (`.claude/settings.json` in a repo working tree), because `~/.claude/` itself IS the git repo.

## gitattributes / custom JSON merge drivers (general git tooling, not Claude-Code-specific)

Sources: https://git-scm.com/docs/gitattributes, https://github.com/jonatanpedersen/git-json-merge, https://nesbitt.io/2026/03/30/git-diff-drivers.html

Extraction: `.gitattributes` can bind a custom merge driver to `*.json` paths; tools like `git-json-merge` use xdiff to auto-resolve JSON structural differences and can normalize formatting so structurally-equal JSON diffs cleanly. This mechanism operates on `git merge`'s three-way merge of **committed** revisions (ancestor/ours/theirs).

Important mechanical limit (general git behavior, not a quoted claim from a single source — corroborated across multiple git-error-explainer pages such as git-tower.com/learn/git/faq/git-force-pull and labex.io/tutorials/git-how-to-address-error-your-local-changes-would-be-overwritten-by-merge-in-git-417548): the observed failure mode in this spike's ground truth (`git pull` aborting with "Your local changes to the following files would be overwritten by merge") is Git refusing to even START a merge because the **working tree has uncommitted modifications** to a path the incoming merge also touches. This check happens BEFORE any merge/diff driver runs — a merge driver only engages once Git is actually merging two commits, not when there are dirty, uncommitted local edits. A `.gitattributes` merge driver therefore would not, by itself, prevent this specific pull-abort unless the app's rewrite were first committed (turning the dirty-tree case into an actual merge case).
