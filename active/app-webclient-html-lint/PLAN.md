# PLAN — Activate HTML linting in app-webclient

> Source: `memory-20260522-pr-6273-html-lint-followup.md` (migrated from `~/.claude/memory/`)
> Repository: `~/Projects/4Shark/app-webclient/`
> Depends on: PR #6273 (`chore(deps): migrate ESLint to v9 + flat config`) — **MERGED 2026-05-22**, dependency satisfied.

## Objective

Enable HTML linting via `@angular-eslint/template` on `app-webclient`. The block is already declared at `eslint.config.mjs:65-73`, but the `lint` script in `package.json:12` still restricts the glob to `ts,js,json`. This plan covers flipping the switch, deciding what to do with the existing `htmlhint`, running `yarn lint --fix`, and fixing whatever remains until the build passes clean.

## Scope

### In scope
- Enable `@angular-eslint/template` in the `lint` script of `package.json`
- Decide what to do with `htmlhint` (keep in parallel, remove, or replace)
- Run `yarn lint --fix` and manually fix whatever is left reported
- Ensure the build passes clean

### Out of scope
- Changes to other rules in `eslint.config.mjs` (TS/JS/JSON) — out of scope for this follow-up
- Refactoring templates beyond the minimum needed for lint to pass
- Touching `stylelint` or SCSS rules

## Current state (verified 2026-05-26)

- `eslint.config.mjs:65-73` — HTML block declared:
  ```js
  {
    files: ['**/*.html'],
    languageOptions: { parser: angular.templateParser },
    plugins: { '@angular-eslint/template': angular.templatePlugin },
    rules: { ...angular.configs.templateRecommended.at(-1).rules }
  }
  ```
- `package.json:12` — `lint` script:
  ```
  "lint": "eslint \"src/**/*.{ts,js,json}\" --quiet && stylelint \"src/**/*.scss\" && htmlhint \"src\" --config .htmlhintrc"
  ```
- `package.json:122` — `htmlhint` still as devDependency (`^1.9.2`)
- `.htmlhintrc` active with 17 rules (tag-pair, attr-value-double-quotes, no inline-style/script, doctype-html5, etc.)

## Pending decision — what to do with htmlhint

`@angular-eslint/template` focuses on Angular template syntax + accessibility. `htmlhint` focuses on generic HTML validity. There is partial overlap but they do not substitute 1:1.

| Option | Trade-off |
|---|---|
| **A. Keep htmlhint in parallel** | Maximum coverage (valid HTML + Angular rules). Cost: two tools in the pipeline, possible duplicate findings. |
| **B. Remove htmlhint** | Simpler pipeline (one tool). Cost: loses generic HTML rules like `tag-pair`, `attr-value-double-quotes`, `inline-style-disabled` — `@angular-eslint/template` does not cover all of them. |
| **C. Replace htmlhint with equivalent rules in `@angular-eslint/template`** | Unified pipeline keeping the coverage. Cost: investigate which `.htmlhintrc` rules have an equivalent and which do not — may surface a gap. |

**The decision is the engineer's** — it is not made in this plan.

## Execution phases

### Phase 1: Decide what to do with htmlhint
- Engineer picks between A, B, or C above
- If C: investigate the rule-by-rule mapping before continuing

### Phase 2: Enable HTML lint
- Update the `lint` script glob in `package.json:12` to include `html`: `"src/**/*.{ts,js,json,html}"`
- If option B: remove `htmlhint` from the `lint` script, from `lint:htmlhint`, and from `devDependencies` (`yarn remove htmlhint`); delete `.htmlhintrc`
- If option C: apply the mapping decided in Phase 1; remove `htmlhint` afterwards

### Phase 3: Run lint and fix
- `yarn lint --fix` — auto-fixable issues are applied
- Inspect the output — fix manually whatever remains until `yarn lint` exits 0
- Validate with `yarn build` (or local CI pipeline) that nothing broke in production

### Phase 4: Changelog + PR
- Update the `app-webclient` `CHANGELOG.md` under `### Added` (HTML linting) or `### Changed` depending on the htmlhint outcome
- Branch: `feature/activate-html-lint` (or similar)
- Commit: `feat(lint): activate @angular-eslint/template HTML linting`
- PR against `develop`

## Success criteria

- [ ] Decision recorded about the htmlhint outcome
- [ ] `lint` script includes `html` in the glob
- [ ] `yarn lint` passes with exit code 0
- [ ] `yarn build` passes
- [ ] CHANGELOG updated
- [ ] PR opened in `4shark/app-webclient` against `develop`

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| `templateRecommended` reports many errors (accessibility, Angular syntax) that are not auto-fixable | Med | Phase 3 reserved for manual fixes. If the volume is infeasible, propose a smaller PR (critical rules only) and follow with batched fixes |
| Removing `htmlhint` (option B/C) silently drops coverage | Med | Explicit decision in Phase 1. Option C forces a rule-by-rule mapping |
| CI build uses a path different from the local `lint` script | Low | Validate `yarn build` in Phase 3 before the PR |

## Assumptions

- Engineer will work in an `app-webclient` worktree (consistent with the pattern of other parallel Claude sessions)
- No urgency — can proceed at a comfortable pace
- PR is independent; does not block other changes in `app-webclient`
