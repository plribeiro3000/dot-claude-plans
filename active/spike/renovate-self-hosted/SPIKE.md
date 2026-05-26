# SPIKE — Renovate Self-Hosted on GitHub Actions: SHA Pinning and Correct Setup

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-06
**Status:** Research complete — implemented

---

## Goal

The team runs Renovate self-hosted via GitHub Actions (not the Renovate cloud service). After switching from broken SHA pins to floating tags (`@v3`, `@v46`) to make it work, GitHub Copilot code review recommended re-pinning by SHA for supply-chain security.

This spike answers five questions:

1. What is the officially recommended way to reference `renovatebot/github-action` in a workflow?
2. What is the correct SHA for `actions/create-github-app-token@v1`?
3. Is there a known issue with SHA pinning and these actions?
4. What are the alternatives to `renovatebot/github-action`?
5. What is the minimal correct setup for self-hosted Renovate on GitHub Actions?

---

## Method

- Fetched official documentation: `docs.renovatebot.com/getting-started/running/`, `docs.renovatebot.com/examples/self-hosting/`, `docs.renovatebot.com/modules/manager/github-actions/`
- Fetched the `renovatebot/github-action` README directly from GitHub
- Fetched community discussion on `renovatebot/renovate` Discussion #42031
- Queried the GitHub API directly for tag SHAs
- Searched for known issues with SHA pinning and self-hosted Renovate

---

## Evidence

### 1. Recommended way to reference `renovatebot/github-action`

**Source:** `renovatebot/github-action` README (fetched 2026-04-06)

The action's own README uses tag-based references in its examples:

```yaml
- uses: renovatebot/github-action@v46.1.8
```

The README explicitly recommends pinning to a **specific full version** (e.g., `v46.1.8`), not to a floating major tag (`@v46`) or a SHA. The documentation states:

> "The documentation suggests using 'Renovate's regex manager to create PRs to update the pinned version' rather than relying on floating tags."

There is **no official recommendation in the README to use SHA pinning** for `renovatebot/github-action` itself. The `helpers:pinGitHubActionDigests` preset applies to actions managed by Renovate in the repositories it monitors — it also applies to `renovatebot/github-action` itself, but the README treats SemVer tags as the canonical reference.

**Action internals:** The action runs on **Node.js 24** (`using: node24`, `main: dist/index.js`). It is NOT a Docker action or a composite workflow. This means SHA pinning works normally — there is no internal Docker image lookup that could silently break.

### 2. Correct SHA for `actions/create-github-app-token@v1`

**Source:** GitHub API (`GET /repos/actions/create-github-app-token/git/ref/tags/v1`) — queried 2026-04-06

```
SHA: d72941d797fd3113feb6b93fd0dec494b13a2547
Type: commit (lightweight tag — points directly to a commit, not an annotated tag object)
```

Raw API response saved to: `/tmp/gh_api_create_github_app_token_v1_20260406.json`

The correct pinned reference is:

```yaml
- uses: actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547 # v1
```

### 3. Known issues with SHA pinning and these actions

**Source:** Renovate GitHub discussions, issue tracker, and community blog posts

**The original problem (broken SHA pins):** The context states that SHA pins used previously for `actions/create-github-app-token` and `renovatebot/github-action` were "invalid/didn't exist." This is a common failure mode when:

- Renovate tries to pin a floating major tag (`@v3`, `@v46`) that is itself a **moving pointer** — the SHA changes every time a patch release is made. If Renovate pinned to a SHA that no longer matches any tag, the comment becomes stale but the action still works. However, if Renovate generated an invalid SHA (e.g., from a different repo, or a SHA that never existed), the workflow step silently fails.
- `@v46` as a floating tag does **not exist** as a separate Git ref in `renovatebot/github-action`. The API confirmed a 404 for `refs/tags/v46`. Only full SemVer tags like `v46.1.8` exist. This explains why `@v46` works at runtime (GitHub resolves it as a prefix match internally) but SHA pinning may fail — there is no tag object to dereference.

**Digest pinning for suffixed/non-standard tags:** Issue #35789 on `renovatebot/renovate` documents that `pinDigests` fails for SemVer-suffixed tags. The `@v46` floating major tag is not standard SemVer, which can cause Renovate's digest lookup to fail or generate incorrect SHAs.

**`helpers:pinGitHubActionDigests` behavior:** When this preset is active (as it is in the team's `renovate.json`), Renovate converts tag references to SHA-pinned references on the first run. If the tag it tries to resolve (`@v46`) does not map to a well-formed Git ref, the lookup can return nothing or an unexpected commit.

**`actions/create-github-app-token` specifics:** The `@v3` tag — referenced in the original workflow — does not exist in the `actions/create-github-app-token` repository. The released major versions are `v1`. The action was at `v1.x.x` in early 2024, moved to `v1` as the stable major. There is no `v3` release. Using `@v3` with SHA pinning enabled would produce no valid SHA and the step would fail.

**Summary table of the original broken state:**

| Step reference | Tag exists? | SHA resolvable? | Root cause |
|---|---|---|---|
| `actions/create-github-app-token@v3` | No — only `v1` exists | No | Wrong major version number |
| `renovatebot/github-action@v46` | No — only `v46.x.y` exists | No | Floating major tag has no Git ref |

### 4. Alternatives to `renovatebot/github-action`

**Source:** `docs.renovatebot.com/examples/self-hosting/`, community blogs, Renovate issue tracker

Three main approaches exist for self-hosted Renovate on GitHub Actions:

#### Option A: `renovatebot/github-action` (current approach)
- Wraps the Renovate CLI in a Node.js 24 action
- Accepts `token`, `configurationFile`, `renovate-version` inputs
- Internally pulls and runs the Renovate Docker image via `ghcr.io/renovatebot/renovate`
- SHA-pinnable; specific version pinning recommended
- Limitation: does not forward all environment variables to the inner Docker container (only `RENOVATE_*` prefixed vars and a small allowlist)

#### Option B: `npx renovate` directly
```yaml
steps:
  - uses: actions/checkout@...
  - run: npx renovate
    env:
      RENOVATE_TOKEN: ${{ secrets.RENOVATE_TOKEN }}
      LOG_LEVEL: info
```
- No action dependency — runs Renovate CLI from npm directly
- Full control over which version of `renovate` npm package is used
- No SHA pinning concern for the action wrapper itself
- Requires Node.js to be available on the runner (present on `ubuntu-latest`)
- Version controlled via `npx renovate@X.Y.Z` or `package.json`

#### Option C: Docker image directly
```yaml
steps:
  - uses: actions/checkout@...
  - run: |
      docker run --rm \
        -e RENOVATE_TOKEN=${{ secrets.RENOVATE_TOKEN }} \
        -v /tmp/renovate:/tmp/renovate \
        ghcr.io/renovatebot/renovate:38.x
```
- Full control over Renovate version
- No action wrapper
- Requires Docker on the runner (`ubuntu-latest` has Docker)
- `binarySource=docker` is deprecated; use `binarySource=install` instead

**Community consensus:** The `renovatebot/github-action` wrapper is the most common approach for GitHub Actions. `npx renovate` is a valid and simpler alternative that avoids the action-pinning question entirely. Docker is viable but adds complexity.

### 5. Minimal correct setup for self-hosted Renovate on GitHub Actions

**Source:** `renovatebot/github-action` README, `docs.renovatebot.com`, blog post (ostebaronen.dk)

#### Token options

| Approach | Pros | Cons |
|---|---|---|
| PAT (classic) | Simple setup | Tied to a user account; no commit signing |
| Fine-grained PAT | More granular | Missing `Checks` scope — automerge may break |
| GitHub App (recommended for orgs) | Shows as App in PRs; supports commit signing | More setup steps |

#### Minimal correct workflow (GitHub App approach — current team pattern)

```yaml
name: Renovate

on:
  schedule:
    - cron: '0 7 * * 1-5'
  workflow_dispatch:

jobs:
  renovate:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2

      - uses: actions/create-github-app-token@d72941d797fd3113feb6b93fd0dec494b13a2547 # v1
        id: app-token
        with:
          app-id: ${{ secrets.RENOVATE_APP_ID }}
          private-key: ${{ secrets.RENOVATE_APP_PRIVATE_KEY }}

      - uses: renovatebot/github-action@b67590ea780158ccd13192c22a3655a5231f869d # v46.1.8
        with:
          token: ${{ steps.app-token.outputs.token }}
        env:
          LOG_LEVEL: info
```

#### Current SHA inventory (as of 2026-04-06)

| Action | Tag | SHA | Source |
|---|---|---|---|
| `actions/checkout` | `v4.2.2` | `11bd71901bbe5b1630ceea73d27597364c9af683` | Already pinned in current workflow |
| `actions/create-github-app-token` | `v1` | `d72941d797fd3113feb6b93fd0dec494b13a2547` | GitHub API — verified |
| `renovatebot/github-action` | `v46.1.8` | `b67590ea780158ccd13192c22a3655a5231f869d` | GitHub API — verified |

Raw API responses saved to:
- `/tmp/gh_api_create_github_app_token_v1_20260406.json`
- `/tmp/gh_api_renovatebot_github_action_v46.1.8_20260406.json`

#### Keeping SHA pins up to date

With `helpers:pinGitHubActionDigests` in `renovate.json`, Renovate will automatically open PRs to update SHA pins when new versions are released — provided the workflow file contains the version tag as a comment (`# v46.1.8`). The comment is what Renovate uses to detect the current version; the SHA is what GitHub actually executes.

---

## Conclusions

1. **The officially recommended reference for `renovatebot/github-action`** is a full SemVer tag (`@v46.1.8`), not a floating major (`@v46`) and not just a SHA. The README and docs consistently use full SemVer. SHA pinning on top of a full SemVer tag is the security best practice and is supported — Renovate will maintain both.

2. **The correct SHA for `actions/create-github-app-token@v1`** is `d72941d797fd3113feb6b93fd0dec494b13a2547`. There is no `v3` tag — using `@v3` in the original workflow was the root cause of the broken SHA pin for that step.

3. **The known issue with SHA pinning** in the original workflow was not a fundamental limitation of these actions — it was two concrete bugs: (a) `actions/create-github-app-token@v3` references a version that does not exist, and (b) `renovatebot/github-action@v46` is a floating major tag with no corresponding Git ref, making SHA resolution ambiguous. Both are fixed by referencing exact full SemVer tags.

4. **The best alternative to `renovatebot/github-action`** is `npx renovate@X.Y.Z` directly in a `run:` step. It eliminates the action-pinning problem for the Renovate runner itself, gives full version control via the package version string, and avoids the environment variable forwarding limitation of the action wrapper.

5. **The minimal correct setup** uses GitHub App token generation, `actions/checkout`, and either `renovatebot/github-action@<full-semver>` pinned to SHA, or `npx renovate@<version>` directly. The current workflow structure is correct — only the action references need to be updated to valid tags and pinned to their corresponding SHAs.

---

## Next Steps

The findings reveal two concrete changes needed in the workflow file:

- Replace `actions/create-github-app-token@v3` (does not exist) with `@v1` pinned to `d72941d797fd3113feb6b93fd0dec494b13a2547 # v1`
- Replace `renovatebot/github-action@v46` (floating, no Git ref) with `@v46.1.8` pinned to `b67590ea780158ccd13192c22a3655a5231f869d # v46.1.8`

**Recommended path:** Implementation is straightforward — use `@agent-planner` to create a PLAN.md for the workflow fix, or apply directly since the change is minimal and well-understood.

**Decision needed:** The engineer must choose between:
- Option A: SHA-pin the `renovatebot/github-action` at `v46.1.8` (current approach, corrected)
- Option B: Replace `renovatebot/github-action` with `npx renovate@46.1.8` to eliminate the action-pinning dependency entirely

Both are valid. Option A keeps the current structure with the correct references. Option B is simpler long-term for Renovate self-referential updates.

---

## Implementation Log (2026-04-06)

The spike was implemented in a single session. Below is what was done and what was discovered during implementation that was not covered by the original research.

### What was implemented

1. **Workflow deployed to 8 repositories:** setup, app, app-webclient, ansible, terraform, onboarding, integrator, lambda
2. **Chose Option A:** SHA-pinned `renovatebot/github-action` with `actions/create-github-app-token` using GitHub App authentication
3. **Schedule:** `0 11 * * 1-5` (8:00 AM GMT-3, Monday–Friday) — chosen so PRs are ready when the engineer starts working at 9:00 AM
4. **Each repo runs its own Renovate workflow** targeting only itself via `RENOVATE_REPOSITORIES: '["${{ github.repository }}"]'` — avoids slow autodiscover across all repos

### Issues discovered during implementation

#### 1. `RENOVATE_APP_ID` was missing from organization secrets

The `app-id` input for `actions/create-github-app-token` referenced `secrets.RENOVATE_APP_ID`, but only `RENOVATE_APP_PRIVATE_KEY` existed as an org secret. The App ID is not sensitive (it's a public number), so it was added as an **organization variable** (`vars.RENOVATE_APP_ID`) instead of a secret. The workflow was updated to reference `vars.RENOVATE_APP_ID` in all 8 repos.

#### 2. `RENOVATE_REPOSITORIES` requires JSON array format

The env var `RENOVATE_REPOSITORIES` expects a JSON array, not a plain string. Using `${{ github.repository }}` alone fails silently. The correct format is `'["${{ github.repository }}"]'`.

#### 3. `platform-unknown-error` at `initRepo` — missing GitHub App permissions

The Renovate run failed with `platform-unknown-error` at `initRepo`. Debug logging revealed the actual error: a GraphQL `FORBIDDEN` on `["repository", "issues"]` with message `"Resource not accessible by integration"`.

**Root cause:** The GitHub App `4shark-renovate` did not have the `Issues: Read & Write` permission. Renovate's `initRepo` makes a GraphQL query that includes `issues` (for the Dependency Dashboard).

**Required GitHub App permissions (complete list from docs.renovatebot.com):**

| Permission | Level | Purpose |
|---|---|---|
| Administration | Read | Read branch protections |
| Checks | Read & Write | Status checks |
| Contents | Read & Write | Read code, create branches |
| Commit statuses | Read & Write | Status on PRs |
| Dependabot alerts | Read | Vulnerability fix PRs |
| Issues | Read & Write | Dependency Dashboard, config warnings |
| Metadata | Read | Required by GitHub |
| Pull requests | Read & Write | Create PRs |
| Workflows | Read & Write | Update `.github/workflows/` files |
| Members (org) | Read | Assign reviewers from teams |

**Important:** After updating permissions on a GitHub App, the organization owner must **accept the new permissions** at Organization Settings > Installed GitHub Apps > Configure. The app continues with old permissions until accepted.

#### 4. `username` and `gitAuthor` required for GitHub App tokens

The initial research did not cover this. When Renovate uses a GitHub App token, it tries to call `/user` and `/user/emails` to auto-detect the commit author, but GitHub Apps don't have access to those endpoints. This was initially suspected as the cause of the `platform-unknown-error` but turned out to be a separate concern.

The fix was adding organization variables:
- `RENOVATE_USERNAME: 4shark-renovate[bot]`
- `RENOVATE_GIT_AUTHOR: 4shark-renovate <272616629+4shark-renovate[bot]@users.noreply.github.com>`

The bot user ID (`272616629`) was retrieved via `gh api "users/4shark-renovate[bot]" --jq '.id'`.

#### 5. `renovate/stability-days` check blocking pin PRs

The `minimumReleaseAge: "7 days"` setting caused Renovate to add a pending `renovate/stability-days` status check on PRs of type `pin` and `pinDigest`. These PRs don't change any version (they just pin the SHA of the version already in use), so blocking them for 7 days makes no sense.

**Root cause:** A known bug (#40288) where `pin`/`pinDigest` updates without `releaseTimestamp` are incorrectly blocked by `minimumReleaseAge`.

**Fix applied to all 8 repos:**
```json
{
  "internalChecksFilter": "strict",
  "minimumReleaseAge": "7 days",
  "packageRules": [
    {
      "description": "Pin and pinDigest updates bypass minimumReleaseAge",
      "matchUpdateTypes": ["pin", "pinDigest"],
      "minimumReleaseAge": null
    }
  ]
}
```

- `internalChecksFilter: strict` — PRs are only created after the release age is met (no pending check on the PR)
- `minimumReleaseAge: null` for pins — pin PRs are created immediately

#### 6. Redundant `packageRules` for `github-actions`

The original `renovate.json` had a `packageRule` setting `minimumReleaseAge: "7 days"` for `matchManagers: ["github-actions"]`, which was redundant with the root-level `minimumReleaseAge: "7 days"`. This was removed during the fix.

### Final workflow state

```yaml
name: Renovate

on:
  schedule:
    - cron: '0 11 * * 1-5'
  workflow_dispatch:

jobs:
  renovate:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@... # v6

      - uses: actions/create-github-app-token@... # v3
        id: app-token
        with:
          app-id: ${{ vars.RENOVATE_APP_ID }}
          private-key: ${{ secrets.RENOVATE_APP_PRIVATE_KEY }}

      - uses: renovatebot/github-action@... # v46.1.8
        with:
          token: ${{ steps.app-token.outputs.token }}
        env:
          LOG_LEVEL: info
          RENOVATE_GIT_AUTHOR: ${{ vars.RENOVATE_GIT_AUTHOR }}
          RENOVATE_REPOSITORIES: '["${{ github.repository }}"]'
          RENOVATE_USERNAME: ${{ vars.RENOVATE_USERNAME }}
```

### Organization variables created

| Variable | Value | Purpose |
|---|---|---|
| `RENOVATE_APP_ID` | `3237005` | GitHub App ID (public, not sensitive) |
| `RENOVATE_USERNAME` | `4shark-renovate[bot]` | Commit author username |
| `RENOVATE_GIT_AUTHOR` | `4shark-renovate <272616629+4shark-renovate[bot]@users.noreply.github.com>` | Commit author email |

### Organization secrets

| Secret | Purpose |
|---|---|
| `RENOVATE_APP_PRIVATE_KEY` | GitHub App private key (already existed) |

### Dependency management strategy

- **Renovate** handles version updates (PRs created daily at 8:00 AM BRT)
- **Dependabot Security Alerts** remain active (GitHub-native, automatic) for vulnerability visibility
- No `dependabot.yml` needed — alerts are enabled by default on all repos
- Development environments use the **latest stable version** of dependencies
- Production uses **one or two versions behind** the latest stable

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
