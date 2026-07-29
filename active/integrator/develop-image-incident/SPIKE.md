# SPIKE — Binding integrator image builds to the correct branch per environment class

Follow-up to `ANALYSIS.md` in this directory, open item 3: *"`build.yaml` has no guard and no develop trigger. The intended rule — staging builds on merge to develop, productive builds only from master — is not implemented on either branch."*

## Investigation question

How do we guarantee that a **productive** integrator environment can only ever receive an image built from `master`, and a **staging** integrator environment can only ever receive an image built from `develop` — such that the guarantee does not depend on the person who dispatches the build?

## Environment classification

`vars.INTEGRATORS` (repository variable, updated 2026-05-06) maps each integrator slug to the GitHub Environment that carries its AWS credentials:

```json
{"almaviva":"almaviva","atento-br":"atento","atento-cl":"atento","atento-cl-staging":"atento","atento-co":"atento","atento-co-staging":"atento","atento-mx":"atento","atento-mx-staging":"atento","commcenter":"commcenter","commcenter-staging":"commcenter","maqnelson":"maqnelson","redebrasil":"redebrasil"}
```

Twelve slugs. The class is carried entirely by the `-staging` suffix in the slug — there is no separate field:

| Class | Slugs | Count |
|---|---|---|
| Staging | `atento-cl-staging`, `atento-co-staging`, `atento-mx-staging`, `commcenter-staging` | 4 |
| Productive | `almaviva`, `atento-br`, `atento-cl`, `atento-co`, `atento-mx`, `commcenter`, `maqnelson`, `redebrasil` | 8 |

Each slug has its own ECR repository (`integrator-<slug>`, region `sa-east-1`), all with `imageTagMutability: MUTABLE`. The four `integrator-atento-harvester-*` repositories in the same registry are **not** in this map and are never touched by `build.yaml` — out of scope.

## Sources consulted

- `~/Projects/4Shark/integrator/.github/workflows/build.yaml` — the trigger, the matrix, and the absence of any branch guard
- `~/Projects/4Shark/integrator/.github/workflows/deploy.yaml` — confirms the deploy consumes `:latest` only
- `~/Projects/4Shark/app/.github/workflows/build-image.yaml` — 4Shark's own precedent for per-environment branch gating
- GitHub Actions run history for `build.yaml` (`gh run list`) and two full run logs — empirical proof of which workflow file executes per ref
- ECR (`aws ecr describe-repositories`, `describe-images`) — current image state per repository
- GitHub Changelog, *"GitHub Actions: Limit which branches can deploy to an environment"* — the server-side mechanism
- `ANALYSIS.md` (this directory) — the 2026-07-28 incident record

## Findings

### Finding 1: `build.yaml` builds every integrator from `master`, including the staging ones, and has no `develop` trigger at all

**Evidence:**

```yaml
on:
  push:
    branches: [master]
  workflow_dispatch:
    inputs:
      integrator:
        description: 'Integrator to build (leave empty to build all)'
        required: false
        type: string
```

and the matrix, when no integrator is named:

```bash
echo "matrix=$(echo '${{ vars.INTEGRATORS }}' | jq -c 'keys')" >> $GITHUB_OUTPUT
```

`jq -c 'keys'` returns all twelve slugs — staging included. There is no branch condition anywhere in the file.

**Source:** `~/Projects/4Shark/integrator/.github/workflows/build.yaml:7-15` and `:37`

**Significance:** The intended rule is not merely unenforced — the current behavior is the *inverse* of it for staging. Every merge to `master` overwrites `:latest` in the four staging repositories with production code, and no automatic path exists for develop code to reach staging at all.

### Finding 2: The staging repositories are, right now, carrying `master` code

**Evidence:** `integrator-atento-cl-staging` most recent images:

```json
[{"tags": null, "pushed": "2026-07-28T13:23:23-03:00"},
 {"tags": ["8.4.23-5efc1f5", "latest"], "pushed": "2026-07-28T13:23:24-03:00"},
 {"tags": ["buildcache"], "pushed": "2026-07-28T13:23:25-03:00"}]
```

`5efc1f5` is the `origin/master` HEAD SHA recorded in `ANALYSIS.md:17` (*"Only `integrator-redebrasil` was untouched and stayed on `8.4.23-5efc1f5` (SHA = `origin/master` HEAD)"*).

**Source:** `aws ecr describe-images --region sa-east-1 --repository-name integrator-atento-cl-staging`

**Significance:** Finding 1 is not theoretical. A staging environment intended to exercise develop code is running the same image as production. Whatever guard is chosen must also *start* feeding staging from develop, not only stop feeding productive from develop.

### Finding 3: `workflow_dispatch` accepts any ref combined with any integrator — this is the door the incident walked through

**Evidence:** The dispatch input is a free-text `type: string` with no relation to `github.ref`, and no job-level `if:` exists. Run history for 2026-07-28:

```
2026-07-28T13:11:52Z  develop  workflow_dispatch  success  Build   (×11 runs through 13:28)
2026-07-28T16:19:28Z  master   workflow_dispatch  success  Build   (×11 runs, the remediation)
```

**Source:** `gh run list --workflow=build.yaml`; corroborated by `ANALYSIS.md:17`

**Significance:** Nothing in the system distinguishes a legitimate dispatch from the one that caused the incident. The same command, with a different `--ref`, is either the fix or the outage.

### Finding 4: The workflow file that *executes* comes from the dispatched ref — a guard written on one branch does not protect the other

**Evidence:** `build.yaml` differs between the two branches only in pinned action SHAs. `origin/master` pins `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd` (v6); `origin/develop` pins `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1` (v7). The logs of the two runs:

```
run 30362362244 (ref develop): Run actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1
run 30377692288 (ref master):  Run actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
```

**Source:** `git diff origin/master origin/develop -- .github/workflows/build.yaml`; `gh run view <id> --log`

**Significance:** This is the decisive constraint on any in-file guard. A `if: github.ref == 'refs/heads/master'` added to `master`'s `build.yaml` is simply absent from the file that runs when someone dispatches from `develop`. An in-file guard must land on **both** branches to hold, and it remains bypassable by any branch whose copy of the file omits it.

### Finding 5: GitHub Environments enforce a branch policy server-side, independently of the workflow file

**Evidence:** *"When a job tries to deploy to an environment with Deployment branches configured Actions will check the value of `github.ref` against the configuration and if it does not match the job will fail and the run will stop."*

**Source:** https://github.blog/changelog/2021-02-17-github-actions-limit-which-branches-can-deploy-to-an-environment/

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed in the changelog body.

**Significance:** This is the only mechanism found that is immune to Finding 4 — the policy lives in repository settings, not in a file that travels with the branch. It is the difference between a convention and a guarantee.

### Finding 6: The current environments are grouped by client, not by class — so a branch policy cannot be applied to them as they stand

**Evidence:** The repository has exactly five deployment environments plus a test one, none with protection rules:

```json
{"name":"almaviva","protection":[]}
{"name":"atento","protection":[]}
{"name":"commcenter","protection":[]}
{"name":"maqnelson","protection":[]}
{"name":"redebrasil","protection":[]}
{"name":"Test","protection":[]}
```

Each holds only `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`; the repository has no repo-level secrets.

**Source:** `gh api repos/4shark/integrator/environments`; `gh api repos/4shark/integrator/environments/atento/secrets`

**Significance:** Environment `atento` is referenced by `atento-br`, `atento-cl`, `atento-co`, `atento-mx` (productive) **and** `atento-cl-staging`, `atento-co-staging`, `atento-mx-staging` (staging). One branch policy on `atento` cannot say "master for these four, develop for those three". Finding 5's mechanism therefore cannot be applied without changing which environment a job references.

### Finding 7: The same environments are referenced by `deploy`, `startup`, and `shutdown` — a branch policy on them would break day-to-day operations

**Evidence:**

```
deploy.yaml:32,104,155,225,248,272:   environment: ${{ fromJSON(vars.INTEGRATORS)[inputs.integrator] }}
startup.yaml:28:                      environment: ${{ fromJSON(vars.INTEGRATORS)[inputs.integrator] }}
shutdown.yaml:26:                     environment: ${{ fromJSON(vars.INTEGRATORS)[inputs.integrator] }}
build.yaml:47:                        environment: ${{ fromJSON(vars.INTEGRATORS)[matrix.integrator] }}
```

The repository's default branch is `develop`, so a `workflow_dispatch` with no explicit `--ref` runs against `develop`.

**Source:** `grep -rn INTEGRATORS .github/workflows/`; `gh repo view --json defaultBranchRef`

**Significance:** Restricting the client environments to `master` would make every routine `deploy` / `startup` / `shutdown` dispatch fail, because those are normally fired from the default branch. Any use of Finding 5's mechanism must therefore introduce a **new** environment referenced only by the build, not repurpose the existing ones.

### Finding 8: 4Shark's own precedent in `app` uses a job-level `if:` — and its `||` makes the dispatch input bypass the branch check

**Evidence:**

```yaml
build-beta-001:
  if: github.ref == 'refs/heads/develop' || inputs.environment == 'beta-001' || inputs.environment == 'all'
...
build-atento-001:
  if: github.ref == 'refs/heads/master' || inputs.environment == 'atento-001' || inputs.environment == 'all'
```

**Source:** `~/Projects/4Shark/app/.github/workflows/build-image.yaml:34` and `:267`

**Significance:** The `app` repo already models "beta builds on develop, productive builds on master" — the pattern to follow structurally. But the condition is a disjunction: dispatching from `develop` with `environment: atento-001` satisfies the second clause and builds a productive image from develop code. The same class of hole exists there; whatever shape is adopted for the integrator must use a conjunction (ref **and** target), not a disjunction.

### Finding 9: Release and hotfix branches have historically been used to build

**Evidence:**

```
2026-07-03T17:55:20Z  hotfix/8.4.20  workflow_dispatch  success  Build
2026-07-03T16:32:30Z  hotfix/8.4.20  workflow_dispatch  success  Build
2026-06-01T21:34:53Z  fix/request-job-optional-belongs-to  workflow_dispatch  success  Build
```

**Source:** `gh run list --workflow=build.yaml --limit 40`

**Significance:** A literal "productive builds only from `master`" rule would reject a build from `hotfix/8.4.20`. Whether that is desired or whether `release/*` and `hotfix/*` must stay eligible is a policy question the mechanism has to encode — it changes the allowed-ref list from one branch to a pattern set.

### Finding 10: The build is the single control point — the deploy adds no independent exposure

**Evidence:** Every deploy job pins the mutable tag:

```yaml
- uses: ./.github/actions/deploy
  with:
    ecr-repo: ${{ env.ECR_REGISTRY }}/integrator-${{ inputs.integrator }}
    image-tag: latest
```

and the cron registration step does the same: `IMAGE_URI="${{ env.ECR_REGISTRY }}/integrator-${{ inputs.integrator }}:latest"`.

**Source:** `~/Projects/4Shark/integrator/.github/workflows/deploy.yaml:238`, `:261`, `:284`, `:317`; corroborated by `ANALYSIS.md:19` (*"No deploy ran that day. The task definitions pin `:latest`, so the ECS scale-up schedule alone was enough to launch tasks on the new image."*)

**Significance:** Guarding the build is sufficient and necessary. Guarding the deploy would add nothing, because the deploy never chooses code — and because the ECS scale-up schedule can launch a wrong `:latest` with no deploy at all, guarding *only* the deploy would be useless.

## Trade-offs surfaced

| Approach | Pros | Cons |
|---|---|---|
| **A — Branch-derived matrix + conjunctive guard in `build.yaml`** | Pure YAML, no infra change, fully visible in a PR diff, reversible; fixes both halves (productive from master, staging from develop) in one file | In-file guard: must land on `develop` **and** `master` to hold (Finding 4), and any branch whose copy omits it bypasses it. Convention, not guarantee |
| **B — Restructure client environments into `<client>-productive` / `<client>-staging` with branch policies** | Server-side, branch-independent guarantee (Finding 5) | Breaks `deploy` / `startup` / `shutdown`, which reference the same environments from the default branch (Finding 7); duplicates AWS credentials across more environments; changes the `INTEGRATORS` map shape consumed by four workflows |
| **C — Hybrid: branch-derived matrix + a policy-only gate environment the build `needs:`** | Server-side guarantee without touching the client environments or the operational workflows; the credentials stay where they are; the gate job is tiny | Two new environments to create by hand in repository settings (an action outside version control); adds one job to the graph; the gate must exist on both branches for the *ergonomic* half, though the server-side half holds regardless |
| **D — AWS IAM separation (staging credentials cannot push to productive ECR repos)** | Defense in depth at a layer GitHub cannot reach | Terraform work; does not address the staging-from-develop half; credentials are per client today, so it would require splitting IAM users per class |

## What was decided and shipped

Implemented in [integrator#2286](https://github.com/4shark/integrator/pull/2286), against `develop`.

The branch decides the class on every path — push trigger and manual dispatch alike. `master` builds the productive slugs, `develop` builds the staging ones, any other ref builds nothing, and a dispatch naming a slug of the other class fails in `setup` before an image exists. The class is derived from the `-staging` suffix already present in each slug, so `INTEGRATORS` keeps its shape and `deploy` / `startup` / `shutdown` are untouched (Finding 7's constraint, satisfied by not needing environments at all).

Two of the three open questions below were resolved rather than asked. **`release/*` and `hotfix/*` do not build productive images** — `HUBFLOW.md:72-75` builds from the push to `master` after the release PR merges, and `DEPLOY-REFERENCE.md:110` records the integrator build as *"auto on push to master"*; the `hotfix/8.4.20` dispatches in Finding 9 were ad hoc, not the documented flow. **Staging builds automatically on every push to `develop`**, symmetric with the existing `master` behavior.

**What this does not yet cover.** The change lands on `develop`, which closes the direction that caused the incident: Finding 4 proves a dispatch from `develop` executes `develop`'s copy of the file, so the guard is present exactly where the incident's dispatch would hit it. The reverse direction — a push to `master` still building the staging slugs from master code — only stops when this reaches `master` through the next release.

**Hardening still available, not taken.** The server-side gate of Finding 5 (a policy-only environment restricted per branch, referenced by a no-op job the build `needs:`) remains the only mechanism immune to a branch carrying a modified workflow file. It was not included because it requires creating environments in repository settings — an action outside version control — and the in-file guard closes the observed failure. Worth revisiting if a second incident arrives through a branch other than `develop`.

## What remains uncertain

- **Does anything today depend on staging carrying master code?** Finding 2 shows it currently does. Flipping staging to develop is the intended behavior, but it is a behavior change for whoever uses those environments, and nobody was consulted about it.
- **Staging still builds with `RAILS_ENV=production`.** The `app` repo builds its develop-fed environment as `RAILS_ENV=development` with `BUNDLE_WITHOUT=test` (`app/.github/workflows/build-image.yaml:97-98`). Whether the integrator's staging images should follow that was out of scope for the change and was deliberately left alone.
- **Not investigated:** whether `startup.yaml` / `shutdown.yaml` have an analogous class-confusion exposure. They scale services and do not choose images, so they are almost certainly out of scope — but this was not read line by line.

---

> **Authoring:** written in the main session as time-boxed research. Every claim cites its source (`file:line`, command, or URL + verbatim quote). Continues `ANALYSIS.md` open item 3 in this directory.
