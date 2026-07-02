# PLAN — Keycloak image CI/CD (apply the Docker-image tool-repo standard)

## Goal

Bring the `keycloak` repo up to the **Docker-image tool-repo standard** (`~/.claude/docs/DOCKER-IMAGE-TOOL-REPOS.md`) so a new upstream Keycloak version flows to the `auth-NNN` production instances automatically, with the 4Shark supply-chain guarantees (Renovate + 7-day min-age). Today `keycloak` has a `Dockerfile` and nothing else — no CI, no build, no deploy, no Renovate.

Reference implementation: `pgbouncer` (already at standard). This plan is the second application of the standard; the first for a repo with **zero** CI/CD infra and a **multi-region, per-client** topology.

## Decisions already made (engineer)

1. **Deploy model** = `:latest` + `force-new-deployment` (the pgbouncer model). Requires the Terraform task definition to track `:latest` instead of the current immutable `:1`.
2. **Base image pin** = exact upstream version + digest (same format as pgbouncer/the doc): `quay.io/keycloak/keycloak:26.1.5@sha256:be6a86215213145bfb4fb3e2b3ab982a806d00262655abdcf3ffa6a38d241c7c` (26.1.5 is what `:26.1` resolves to today; a fresh build already produces it — this only makes it explicit, immutable, and Renovate-trackable).

## Current state — validation against the standard

| Item | Keycloak today |
|---|---|
| 1. Single `main` | ✅ (already in `identity` `main_branch_repositories`) |
| 2. Base pin tag+digest | ❌ `quay.io/keycloak/keycloak:26.1` — tag-only, moving minor, no digest |
| 3. Renovate | ❌ no `renovate.json` |
| 4. hadolint CI | ❌ no workflows |
| 5. Min-age gate | ❌ no workflows; not in `main_branch_repositories_with_min_age_check` |
| 6. Build-on-merge | ❌ image built manually, pushed as `auth-001-app:1` |
| 7. Deploy dispatch | ❌ task def references immutable `auth-001-app:1` |
| 8. STOPSIGNAL | ⚠️ Keycloak (JVM) handles SIGTERM itself — likely no custom signal; confirm |
| 9. Governance (Terraform) | 🟡 branch protection exists; min-age check not required |
| 10. CHANGELOG/release | ❌ no `CHANGELOG.md` |

## Topology — why this is NOT a pgbouncer copy-paste

- **`auth-NNN` instances, multi-region, per client base / IdP** — not `<env>` in a single region. Today only `auth-001` exists, in **sa-east-1** (the poolers are 4 envs in us-east-1).
- Cluster `auth-{NNN}-cluster`, service `auth-{NNN}`, task family `auth-{NNN}-web`, ECR `auth-{NNN}-app`. The ECR already exists (`auth-001-app`).
- **Single web service per instance, stateful role** (SSO), state in the external database — the container is rollable like pgbouncer.
- **No non-production instance** — `auth-001` is productive SSO. There is no beta to validate a new image on before it reaches users.

## Execution phases (ordered by dependency)

### Phase 0 — Grounding to confirm before touching anything

Read-only, resolves the last unknowns so the later phases are exact:

1. `terraform/auth-001/ecs.tf` — where the task-definition image `auth-001-app:1` is declared, and the service's `desired_count` + deployment configuration (min/max healthy percent) — needed to judge zero-downtime on a single service.
2. How the `app-*` stacks push AWS creds into the GitHub Environment (Terraform `github_actions_environment_secret`, or manual) — to mirror the exact mechanism for `auth-001`.
3. Keycloak 26 graceful-shutdown behaviour on SIGTERM under ECS — decide whether a `STOPSIGNAL` / `stopTimeout` tuning is needed (item 8).

### Phase 1 — Terraform `auth-001` stack (the prerequisite)

The repo automation cannot deploy until the deploy identity + target exist:

1. **IAM deploy user + `iam_deploy` policy** scoped to cluster `auth-001-cluster`, ECR `auth-001-app`, the task-execution role — mirroring the `app-*` `module "iam_deploy"` usage.
2. **GitHub Environment `auth-001`** with the AWS credential secrets (same mechanism Phase 0.2 finds).
3. **Task definition image → `:latest`** (from `auth-001-app:1`) so `force-new-deployment` picks up new builds.
4. ECR `auth-001-app` already exists — no creation.
5. Apply-before-merge; one PR to `terraform`.

### Phase 2 — `keycloak` repo automation

After the GitHub Environment + secrets exist (Phase 1):

1. `Dockerfile` — pin to `quay.io/keycloak/keycloak:26.1.5@sha256:be6a86…`, with the comment about keeping the tag for Renovate.
2. `renovate.json` — copied verbatim from `pgbouncer`/`terraform`.
3. `.github/workflows/ci.yaml` — hadolint (`Continuous Integration` / `Hadolint (Linter)`).
4. `.github/workflows/verify-minimum-age.yaml` + `reverify-minimum-age.yaml` + `.github/scripts/verify-minimum-age.sh` — copied.
5. `.github/workflows/build.yaml` — one job `auth-001`, **region sa-east-1**, GitHub Environment `auth-001`, push `:latest` + `:<short-sha>` to `auth-001-app`. Structured so adding a future `auth-NNN` (possibly another region) is one more job.
6. `.github/workflows/deploy.yaml` — `workflow_dispatch` `environment` choice `auth-001`, region sa-east-1, `aws ecs update-service --cluster auth-001-cluster --service auth-001 --task-definition auth-001-web --force-new-deployment` + wait stable.
7. `CHANGELOG.md` — created (Keep a Changelog + SemVer + yearly-archival note).
8. `.dockerignore` — if warranted.

One PR (or split hygiene vs pin like pgbouncer, engineer's call at execution).

### Phase 3 — identity governance

Add `keycloak` to `local.main_branch_repositories_with_min_age_check` once the repo produces the `Verify Minimum Age` check. One PR to `terraform` `identity/` (apply-before-merge). (Mirror of pgbouncer PR #585.)

### Phase 4 — First release + first deploy

1. First release: date `## [Unreleased]` → `## [X.Y.Z] - YYYY-MM-DD`, merge, then manual `vX.Y.Z` tag (explicit engineer confirmation — no HubFlow).
2. **First deploy to `auth-001`** — engineer-controlled, productive SSO (see Risks). Build-on-merge already staged the image in ECR; deploy is the dispatch.

## Risks

1. **Productive SSO, no validation env (highest).** Unlike pgbouncer (validated on `beta-001`), the first new image goes straight to the only instance, `auth-001`, which is live SSO. Mitigations to decide in Phase 4: check `desired_count` / deployment min-healthy so the rolling deploy keeps a healthy task; deploy during low-traffic; have a rollback (previous task-def revision / previous image tag) ready. A new image is Keycloak 26.1.5 vs whatever older 26.1.x `auth-001-app:1` was built from — a patch move within 26.1, low but non-zero.
2. **Task-def `:1` → `:latest` is itself a change** — the first apply re-points the running service's task def to `:latest`; confirm the current `:latest` in ECR is a sane image (or push a known-good `:latest` before the task-def flip).
3. **Multi-region future** — the workflows must not hard-assume sa-east-1 globally; region is per-instance. Keep it a per-job value so `auth-002` in another region is additive.
4. **GitHub Environment secrets provisioning** — if the app-stack mechanism is manual (not Terraform), Phase 1.2 needs the engineer to place the secrets; flag at execution.

## Phase 0 — Resolutions (done)

- **Task-def image**: `auth-001/ecs.tf:58` `image = "${aws_ecr_repository.app.repository_url}:1"` — a one-line `:1` → `:latest` change.
- **Zero-downtime**: `desired_count = 2` + `deployment_circuit_breaker { rollback = true }` + ECS rolling controller + `lifecycle { ignore_changes = [task_definition] }` — a rolling deploy keeps a healthy task and auto-rolls-back on failure. This is the pgbouncer `:latest` model already wired. **Risk 1 downgraded**: not a single task, and self-healing.
- **Graceful shutdown (item 8)**: NO custom `STOPSIGNAL` needed. ECS sends SIGTERM; Keycloak 26 on `start` (the task-def does NOT use `--optimized`, so the known `--optimized` no-shutdown bug does not apply) gracefully drains the HTTP stack by default. Different from pgbouncer (SIGINT).
- **GitHub Environment secrets**: NOT Terraform-managed anywhere in the repo (only IAM users/keys are). The `auth-001` GitHub Environment + its AWS secrets are a **manual engineer step**.
- **Deploy-creds decision (engineer)**: Terraform (auth-001 stack) creates `aws_iam_user.deploy` + `aws_iam_access_key.deploy` + `iam_deploy` policy + a **sensitive output** of the key id/secret (the `onboarding` pattern); the engineer reads the output and pastes it into the GitHub Environment `auth-001`.

## Still open (decide at execution)

- Whether to split the keycloak repo work into hygiene vs pin PRs (as pgbouncer did) or one PR.
- Optional Keycloak shutdown-delay/timeout tuning (defaults 1s each) for better connection draining — optimization, not required.
