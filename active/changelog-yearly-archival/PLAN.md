# PLAN — CHANGELOG Yearly Archival Convention

## Goal

Standardize, across every 4Shark repository, the convention `app` already uses: the
`CHANGELOG.md` keeps only the **current year's** entries; previous years are archived
under a `changelogs/` folder (one `YYYY.md` per year), with a header in `CHANGELOG.md`
pointing to it. The convention itself is documented once in the dot-claude policy doc so
all repos follow the same rule.

## Current state (verified 2026-06-18)

- `app` is the reference implementation: `changelogs/` folder with `2016.md … 2025.md`,
  main file keeps 2026 + `[Unreleased]`, and a header text already exists
  (`app/CHANGELOG.md:10-11`). Only the header wording needs canonicalization.
- `dot-claude/docs/CHANGELOG.md` (the canonical team policy) does **not** mention the
  yearly-archival convention — this is the documentation gap.
- `app-webclient/CHANGELOG.md` is 72KB with entries from `2019-11-08` to today and no
  archival header — the repo that triggered this work.

## Canonical convention

- **Folder name**: `changelogs/` (lowercase, plural) — matches `app`. Decided.
- **Rule**: `CHANGELOG.md` holds only the current year + `[Unreleased]`. All entries from
  prior years move to `changelogs/<YYYY>.md`, one file per year. At each new year's first
  release, the closed year is moved into its own file.
- **Header text (candidate — to be validated in PR 1)**, placed right after the
  Keep-a-Changelog / SemVer preamble and before `## [Unreleased]`:

  > To keep this file readable, only the current year's releases and hotfixes are kept here.
  > Entries from previous years are archived in the [changelogs](changelogs) folder.

  Each `changelogs/<YYYY>.md` mirrors the format of `app/changelogs/2025.md` (a `# <YYY/>`
  title followed by the year's sections).

## Phases

### Phase 1 — PR in `app` (validation gate)
Refine `app/CHANGELOG.md` header to the canonical wording. This is the wording the engineer
validates. Nothing else changes in `app` (folder + archives already exist).
→ Engineer reviews wording → merge.

### Phase 2 — PR in `dot-claude` (policy)
Add the yearly-archival convention to `docs/CHANGELOG.md` (folder name, the current-year
rule, the header template, the per-year-rollover step). Also add the header pointer to
dot-claude's own `CHANGELOG.md`. Uses the wording validated in Phase 1.

### Phase 3 — Replication, one PR per repo
Apply the convention to every remaining repo with a `CHANGELOG.md`, grouped by treatment:

| Treatment | Repos | Action |
|---|---|---|
| Full split (multi-year) | app-webclient, integrator, ansible | Create `changelogs/<YYYY>.md` for every prior year present; keep only current year + `[Unreleased]` in main; add header |
| Light split (one prior year) | terraform, setup, lambda, app-sdk-advpl, app-sdk-dotnet | Move 2025 entries to `changelogs/2025.md`; keep 2026 + `[Unreleased]`; add header |
| Header only | onboarding, data-privacy | Add header pointer; no archive file yet (nothing prior to current year) |

`app-mobileclient` has no `CHANGELOG.md` (out of scope). `keycloak` is not cloned locally
(out of scope here).

Each replication PR is a pure content reorganization of markdown — no code, no behavior
change. Each repo's `CHANGELOG.md` itself gets a `### Changed` entry under `[Unreleased]`
naming the archival reorganization (per the Changelog Policy).

## Open points to confirm before Phase 3
1. PR cadence for Phase 3 — all repos at once, or batch by treatment tier and review tier
   by tier?
2. Whether `data-privacy` (no dated entries) should get the header now or be skipped until
   it has real entries.
3. Confirm the per-year split is data-driven (every year actually present in the file),
   not the hand-listed years from the request (which skipped 2021).
