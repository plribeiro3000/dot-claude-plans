---
source: ~/.claude/memory/20260522-100010-pr-6273-html-lint-followup.md
migrated: 2026-05-26
---
<!-- saved: 2026-05-22 10:00 | source: /Users/plribeiro3000/Projects/4Shark/app-webclient (PR #6273) -->

After PR #6273 (`chore(deps): migrate ESLint to v9 + flat config` on app-webclient) is merged into `develop`, open a separate PR to:

1. Enable HTML linting via `@angular-eslint/template` in `eslint.config.mjs` (the block is already declared; only the `lint` script needs to include `html` in the glob).
2. Run `yarn lint --fix` and fix manually whatever remains until the build passes clean.

Context: in PR #6273 the legacy behavior was preserved (the `lint` script runs only on `ts,js,json`) even with the HTML block declared in the flat config, to avoid introducing new failures in that PR. The follow-up is to flip the switch and apply the fixes.
