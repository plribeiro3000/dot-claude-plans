# PLAN — PR/commit sensitive-data policy + reinjection hook

## Context

Agent-authored PR descriptions (and commit messages) organically narrate customer/infra detail into permanent GitHub records. Concrete incident: a Terraform PR body spelled out the customer (Atento CO), QA/prod hostnames, DB name, DB username, and user count. None are credentials, so no existing tool catches them.

Research (full evidence in `~/.claude/plans/active/spike/ai-pr-description-data-leakage/SPIKE.md`, 12 sources) concluded: the community does not name or tool for this case; GitHub Secret Scanning / gitleaks / trufflehog / Nightfall all target credentials in diffs; there is nothing to converge with. This is a 4Shark-side build.

## Decisions locked (engineer)

1. **Approach**: interpretable textual rule (the brain) + reinjection hook (keeps the rule fresh in context at the moment of `gh pr create` / `git commit`). **No value list, no value matching, no blocking.**
2. **Scope**: both PR descriptions **and** commit messages.
3. **Where to document a value that genuinely must be recorded**: left open — decided at the time per the data; the rule forbids it in PR/commit and points to "an appropriate internal location", without pinning one.
4. **Detection**: rejected a value list (would be huge, high-maintenance, and would itself version customer names/hostnames into the repo — the disease it cures). The rule is semantic and interpreted by the model; the hook does not interpret or match values.

## The central artifact — proposed rule text (REVIEW THIS)

This is the wording to land in `CLAUDE.md` § Pull Request Policy (and cross-referenced from § Git Commit Policy). English (internal engineering doc). Refine freely — this is the piece to get right before it spreads across files.

> ### No Client/Infra Data in PR Descriptions and Commit Messages
>
> - **A PR description and a commit message explain the change and its need in generic technical/product terms — WHAT changed and WHY — never WHOSE it is or the VALUES of an environment.** Both are permanent, often-public records on GitHub; once pushed, the data is in the record even if later edited out.
> - **Allowed (the legitimate "why")**: the technical/product motivation — "we need this functionality", "in this scenario X must happen", the behavior the change enables. This is what a reviewer needs to judge the change.
> - **Forbidden (client/environment data)**: client/customer names; infrastructure hostnames, connection strings, database names, database usernames; business volume figures (user counts, record counts); any concrete value drawn from a client's environment. Never justify a change with "because client X needs it" or "client X's environment has Y" — state the need generically instead.
> - **If a specific value genuinely needs to be recorded**, put it in an appropriate internal location decided at the time (a non-public, non-permanent place) — never in the PR description or the commit message.
> - **The test**: would a reader learn *which client* this is, or a concrete value from their environment, from the prose? If yes, rewrite it generically.

## Files to change

| File | Change |
|---|---|
| `CLAUDE.md` | New subsection (rule text above) under § Pull Request Policy; one cross-reference line in § Git Commit Policy pointing to it. Single source of truth, always in context (Tier 1). |
| `docs/PULL-REQUEST-CONVENTIONS.md` | Add a "Forbidden content" section mirroring the rule (Tier 2 detail). Extend Key Rules. |
| `scripts/inject-pr-commit-data-policy.sh` | New reinjection hook (name TBD — see open question). Emits the rule as `additionalContext`; never blocks. |
| `settings.json` | Register the hook under `PreToolUse` with `if` matchers for `gh pr create` and `git commit`. |
| `CHANGELOG.md` | One `### Added` entry under `## [Unreleased]`. |

Note: the repo's `CLAUDE.md` is the source that becomes `~/.claude/CLAUDE.md` on `git pull` after merge — editing the repo copy is the correct path; no direct `~/.claude/` edit.

## Hook design (Pattern Priming — sibling findings)

Read `inject-terraform-context.sh` and `inject-output-preservation-reminder.sh`. Pattern across dimensions:

- **Structural**: standalone `scripts/*.sh`; shebang + header comment block (purpose / wiring / why / always-exit-0); `set -u`; read or drain stdin; emit `hookSpecificOutput` JSON via `jq` (manual-escape fallback); always `exit 0` (a reminder hook must never block).
- **Two registration styles**: (a) terraform — `if: "Bash(<cmd> *)"` matcher in settings.json, no self-filtering, fires every time; (b) output-preservation — broad `"Bash"` matcher + self-filter on command text + once-per-session marker.
- **Output shape for a non-blocking reminder**: `additionalContext` only, **no** `permissionDecision` (output-preservation style). Correct for ours — pure reminder.
- **Anti-patterns checked**: none triggered — single-purpose script, no iceberg/pipeline/phase-extraction. It mirrors an established sibling exactly.

Chosen shape: terraform-style `if` matchers (clean, no command self-parsing) + output-preservation-style `additionalContext`-only emission.

## Open design question (decide before coding the hook)

**Cadence**: fire **every time** (terraform style) or **once per session** (output-preservation style)?
- `gh pr create` is rare → every-time is cheap and lands at the exact moment.
- `git commit` is frequent → every-time could be context noise; once-per-session is quieter but the reminder might be stale by the time a commit actually happens.
- Candidate: every-time on `gh pr create`, once-per-session on `git commit`. To confirm at the Pattern-Priming gate.

## Execution order

1. Land the rule text in `CLAUDE.md` + `docs/PULL-REQUEST-CONVENTIONS.md`.
2. Write `inject-pr-commit-data-policy.sh` (after the Pattern-Priming AskUserQuestion confirms name + cadence).
3. Register in `settings.json`.
4. `CHANGELOG.md` entry.
5. `/test` (shell hook sanity: feed a sample `gh pr create` JSON on stdin, assert valid JSON out + exit 0).
6. Commit (one commit), push with explicit refspec, open PR — and the PR description for *this* feature is the first test of the new rule.

## Risks / caveats

- **Shell-variable body hole**: if a PR body is passed as `--body "$BODY"` / `--body-file`, a *blocking* hook couldn't read it — but ours doesn't read the body at all (it only reinjects the rule), so this hole does not apply. The rule + reinjection act before the body is composed.
- **Probabilistic**: reinjection raises adherence; it does not guarantee. Accepted by the engineer (blocking-by-value-match was rejected as infeasible).
- **Noise**: mitigated by the cadence decision above.

## Out of scope (follow-ups, not this PR)

- Server-side GitHub Actions gate (defense-in-depth) — deferred.
- TruffleHog `--pr-comments` post-creation CI — deferred.
- Structural-shape backstop (regex for connection-string/credential formats) — deferred; can be added to the same hook later without rework.
