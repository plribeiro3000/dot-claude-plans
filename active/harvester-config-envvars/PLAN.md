# PLAN — Harvester Config Env-Vars Refactor

> Reference: derived from PLAN-SPIKE.md (harvester-config-envvars); auxiliary seeding_procedure_1.md

## Objective

Move the 9 root-level scalar keys of the harvester's `appsettings.json` out to environment variables. The 2 connection strings (`ConnectionString_Simplex`, `ConnectionString_4Shark`) become ECS task-definition **secrets** backed by new per-env SSM `SecureString` parameters. The 7 non-secret scalars become plain `environment` entries in the task-def. `COMPANIES` stays in `appsettings.json`, written by the entrypoint from a renamed SSM parameter (`appsettings` → `companies`). The entrypoint env var is renamed from `APPSETTINGS_SSM_PARAMETER` to `COMPANIES_SSM_PARAMETER`. `Program.cs` and `_4SharkService.cs` are not changed — `AddEnvironmentVariables()` is already last in the config builder chain (`Program.cs:27-31`), so it wins over the JSON file without any code change.

## DESIGN UPDATE (2026-06-28) — Option B: COMPANIES injected directly (SUPERSEDES the param-name parts below)

Following the 4Shark env-var convention (verified in `integrator/lib/application_configuration.rb`: domain-named env vars, storage mechanism never in the name, secret VALUES injected directly via task-def `secrets` — e.g. `CLIENT_PASSWORD`), the COMPANIES delivery changed from "entrypoint fetches an SSM param by name" to **direct injection**:

- **No `APPSETTINGS_SSM_PARAMETER` / `COMPANIES_SSM_PARAMETER` env var at all.** COMPANIES is a task-def **secret** named **`COMPANIES`**, `valueFrom` an SSM `SecureString` `/integrator-atento-harvester-<env>/companies` that holds the **inner** companies map (`{"<code>":{"RootAdmin":…,"Admins":[…]}}`, NOT the full appsettings doc).
- **Entrypoint** (`.github/docker/entrypoint.sh`) no longer calls `aws ssm get-parameter`. It requires `COMPANIES` and writes `printf '{"COMPANIES":%s}' "$COMPANIES" > /app/appsettings.json`, then execs. Delivered in PR #32.
- **`awscli` removed** from the runtime image (`.github/docker/Dockerfile`) — the entrypoint was its only user; the .NET app uses no AWS SDK. Delivered in PR #32.
- **Harvester TASK role no longer needs `ssm:GetParameter`** — the in-container fetch is gone. The `ssm-read-appsettings` inline policy on each task role is **REMOVED** (not renamed to `ssm-read-companies`). COMPANIES + the 2 connection-string secrets are resolved by the **execution role** (`ecsTaskExecutionRole`, inline `integrator-atento-ssm-read`, already covers `parameter/integrator-atento-*` + default SSM KMS key) at container start, same as the Rollbar token.
- **`AWS_REGION`** env var in the task-def was only used by the entrypoint's `aws` call — review whether to drop it (the .NET app does not use AWS).
- Code side (PR #32, done): committed `appsettings.json` + examples trimmed to `{ "COMPANIES": {} }` placeholder.

Wherever the Scope/sections below say "rename `APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`" or "rename IAM policy `ssm-read-appsettings` → `ssm-read-companies`", read instead: **drop the param-name env var entirely; add the `COMPANIES` secret; remove the task-role SSM policy.** The connection-string secrets + 7 plain env vars are unchanged from the plan below.

## Scope

### In scope

- `simplex-harvester/.github/docker/entrypoint.sh`: rename required-check at line 9 from `APPSETTINGS_SSM_PARAMETER` to `COMPANIES_SSM_PARAMETER`
- `simplex-harvester/appsettings.exampleDevOps.json` + `simplex-harvester/appsettings.example.json`: trim the 9 root scalars
- `simplex-harvester/appsettings.json` (committed, baked into Docker image via `SimplexPE.Global4Shark.csproj:27-29` `PreserveNewest`): replace the current wrong structure (`COUNTRIES`/`ConnectionStrings.MEX`) with `{ "COMPANIES": {} }` — a valid placeholder that holds the section present and fails fast in `_4SharkService.cs:356-358` if the SSM fetch fails
- `terraform/integrator-atento/ssm_harvester_staging.tf`: add `companies` + 2 connection-string `SecureString` params for mx-staging and co-staging; remove old `appsettings` staging param resources
- `terraform/integrator-atento/compute_harvester_staging.tf`: add 7 plain env vars + 2 `secrets` items per staging task-def; rename `APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`; remove old `appsettings` SSM param references; rename IAM inline policies from `ssm-read-appsettings` to `ssm-read-companies` (`compute_harvester_staging.tf:65-68`, `compute_harvester_staging.tf:151-154`)
- `terraform/integrator-atento/ssm_harvester.tf`: add `companies` + 2 connection-string `SecureString` params for mx and co prod; remove old `appsettings` prod param resources
- `terraform/integrator-atento/compute_harvester.tf`: add 7 plain env vars + 2 `secrets` items per prod task-def; rename `APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`; remove old `appsettings` SSM param references; rename IAM inline policies from `ssm-read-appsettings` to `ssm-read-companies` (`compute_harvester.tf:70`, `compute_harvester.tf:167`)
- Out-of-band SSM seeding (ops, not in a PR): seed `companies` + 2 connection-string params per env before each Terraform apply
- CHANGELOG entry in `simplex-harvester`

### Out of scope

- `Program.cs` and `_4SharkService.cs` — zero code changes (locked decision from brief)
- Chile / future countries
- Phase 23 scope (project rename, per-country build isolation, deploy-only-from-master) — Phase 23 owns the master push that reaches prod ECRs; this plan couples to that window but does not change Phase 23's scope

---

## Chosen approach

**Direction:** Option A — Two-phase (staging now, prod with Phase 23)

**Rationale (from engineer):** Merge the code PR to `develop` immediately so staging ECRs are updated (CI `build.yaml:57-60` gates prod ECR pushes to `master` only). Apply staging Terraform and validate with a manual `aws ecs run-task`. Prod Terraform is applied only after the Phase 23 HubFlow release pushes the new image to the prod ECRs — the same release that ships the already-merged Rollbar retry (simplex-harvester PR #30) to prod. This keeps prod untouched and fully functional on the old config until the Phase 23 release window, when everything is ready.

**Phase 23 coupling:** This plan's Phase 3 and Phase 4 depend on the Phase 23 release in `~/.claude/plans/active/simplex-harvester/PLAN.md:2333-2355`. Specifically: the Phase 23 `git hf release finish` triggers `build.yaml:57-60`, which pushes to the prod ECRs. Only after those ECRs carry the new image (with the renamed `COMPANIES_SSM_PARAMETER` entrypoint) is it safe to apply the prod Terraform PR (Phase 4 below). The two plans must be coordinated at the release window.

**Prod cron safety:** Engineer chose sub-option i — rely on the ~23h safe window. After CO fires at 08:30 UTC and MX fires at 09:30 UTC, there is a ~22h 45m window before the next CO fire (`compute_harvester.tf:200` for CO, `compute_harvester.tf:113` for MX). The prod Terraform apply must be scheduled inside this window (after 09:30 UTC). Schedules are NOT disabled before applying. For the staging phase this is N/A — staging tasks are `state = "DISABLED"` + `create_schedule = false` (`compute_harvester_staging.tf:107-108`), so there is no cron fire risk at any time.

**Source patterns referenced:**
- `terraform/integrator-atento/compute_harvester.tf:129` — `ROLLBAR_ACCESS_TOKEN` as `secrets` item (exact shape for connection-string secrets)
- `terraform/integrator-atento/ssm_harvester.tf:10-42` — existing appsettings param resources (template for new `companies` + connection-string params)
- `terraform/integrator-atento/ssm.tf:39-58` — execution role wildcard `arn:aws:ssm:sa-east-1:405749097490:parameter/integrator-atento-*` (confirms new params covered without IAM changes)

---

## IAM findings — no changes to execution role or task-role resource scopes

Two facts confirmed in the draft remove IAM work:

**Execution role** (`ecsTaskExecutionRole`) — `ssm.tf:47-50`:
```hcl
Action   = ["ssm:GetParameters"]
Resource = ["arn:aws:ssm:sa-east-1:405749097490:parameter/integrator-atento-*"]
```
The new connection-string params (`/integrator-atento-harvester-{env}/ConnectionString_Simplex`, `/integrator-atento-harvester-{env}/ConnectionString_4Shark`) match this wildcard. Default SSM KMS key decrypt already granted (`ssm.tf:53-55`). No change to the execution role.

**Task roles** (one per env) — `compute_harvester.tf:78-81`:
```hcl
Resource = "arn:aws:ssm:sa-east-1:405749097490:parameter/integrator-atento-harvester-mx/*"
```
The renamed `companies` param at `/integrator-atento-harvester-mx/companies` is under the `mx/*` wildcard. Same for CO and staging (`compute_harvester.tf:175-178`, `compute_harvester_staging.tf:65-68`, `compute_harvester_staging.tf:151-154`). No change to the task-role resource scopes.

The **inline policy names** (`ssm-read-appsettings` → `ssm-read-companies`) are renamed in both staging and prod TF files for consistency with the param rename. This is a metadata change only; it does not affect the policy's resource scope or any AWS permission evaluation.

---

## How the .NET config provider resolves values after the refactor

`Program.cs:27-31`:
```csharp
IConfiguration configuration = new ConfigurationBuilder()
    .SetBasePath(Directory.GetParent(AppContext.BaseDirectory)!.FullName)
    .AddJsonFile("appsettings.json", optional: false)
    .AddEnvironmentVariables()
    .Build();
```

Providers are merged in registration order; later providers win on conflict. `AddEnvironmentVariables()` is last, so any key present in both `appsettings.json` and the process environment resolves to the env-var value. After the refactor, `appsettings.json` contains only `COMPANIES`; the 7 plain scalars and 2 connection strings arrive as ECS-injected env vars (plain `environment` array + `secrets` array resolved by the execution role before the container starts). `_4SharkService.cs:341` reads them via `GetSection(key).Value` — the config provider is transparent to the caller.

ECS secrets are injected as env vars before the entrypoint runs (`exec dotnet` at `entrypoint.sh:32` inherits the full environment).

---

## Layer-0: connection-string handling

`ConnectionString_Simplex` and `ConnectionString_4Shark` hold passwords. They are **never printed to the terminal or chat** at any point. All seeding goes through local temp files and `--value file://` so the value never appears in shell history or session output. See seeding procedure below.

---

## `.csproj` `PreserveNewest` finding

`SimplexPE.Global4Shark.csproj:27-29`:
```xml
<None Update="appsettings.json">
  <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
</None>
```
`CopyToOutputDirectory: PreserveNewest` applies to both `dotnet build` and `dotnet publish`. `Dockerfile:25` copies the publish output, so the committed `appsettings.json` is baked into the runtime image at `/app/appsettings.json`. The entrypoint overwrites it at container start. After the refactor, the committed file contains only `{ "COMPANIES": {} }` so that if the SSM fetch fails and the baked fallback is used, the app fails fast rather than running with stale scalars. No change to the `.csproj` entry is required.

---

## Execution phases

### Phase 1: Code PR (simplex-harvester)

**Objective:** Update the harvester code (entrypoint + example files + committed appsettings.json) and merge to `develop`, which triggers CI to push to the staging ECRs.

**Files:**
- `simplex-harvester/.github/docker/entrypoint.sh` — replace `APPSETTINGS_SSM_PARAMETER` required check at line 9 with `COMPANIES_SSM_PARAMETER`
- `simplex-harvester/appsettings.exampleDevOps.json` — trim the 9 root scalars
- `simplex-harvester/appsettings.example.json` — trim the 9 root scalars
- `simplex-harvester/appsettings.json` — replace current wrong structure (`COUNTRIES`/`ConnectionStrings.MEX`) with `{ "COMPANIES": {} }`
- `simplex-harvester/CHANGELOG.md` — add entry under `### Changed`: `Harvester appsettings — moved scalar config to environment variables`

**PR commit type:** `feat(harvester): move scalar config to environment variables`

**When merged to develop:** CI `build.yaml:57-60` pushes to staging ECRs (`integrator-atento-harvester-mx-staging`, `integrator-atento-harvester-co-staging`). Prod ECRs are **not** updated until a `master` push.

**Dependencies:** None. This is the first step.

**Success criteria:**
- [ ] `entrypoint.sh:9` checks `COMPANIES_SSM_PARAMETER`
- [ ] `appsettings.example.json` and `appsettings.exampleDevOps.json` contain no root scalars other than `COMPANIES`
- [ ] `appsettings.json` is `{ "COMPANIES": {} }` (replacing the old `COUNTRIES`/`ConnectionStrings.MEX` structure)
- [ ] CI build passes; staging ECRs updated

---

### Phase 2: Staging Terraform PR + seeding ops

**Objective:** Add SSM params and update staging task-defs; validate with a manual run on each staging env.

**Files (Terraform repo):**
- `terraform/integrator-atento/ssm_harvester_staging.tf` — add 3 new SSM params per staging env (6 total): `companies`, `ConnectionString_Simplex`, `ConnectionString_4Shark`; remove old `appsettings` staging param resources
- `terraform/integrator-atento/compute_harvester_staging.tf` — add 7 plain env vars to `local.harvester_mx_staging_env_vars` and `local.harvester_co_staging_env_vars` (`compute_harvester_staging.tf` locals, pattern: `compute_harvester.tf:19-30`); add 2 `secrets` items per task-def (pattern: `compute_harvester.tf:129`); rename `APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`; rename IAM inline policy name `ssm-read-appsettings` → `ssm-read-companies` at `compute_harvester_staging.tf:65-68` and `compute_harvester_staging.tf:151-154`

**Apply order (mandatory):**

1. **Seed mx-staging** (seeding procedure, Steps 1–5 for env=`mx-staging`) — before apply; new SSM resources are created as PLACEHOLDER by the first apply but the companies and connection-string params must be seeded before the task-def secrets reference is live
2. **Seed co-staging** (same, env=`co-staging`)
3. `terraform apply` (staging TF PR)
4. Verify staging params are populated (length check per seeding procedure Step 2 and Step 3)
5. `aws ecs run-task` on mx-staging — sign-off run
6. `aws ecs run-task` on co-staging — sign-off run
7. Confirm task exit code 0 for both

**Terraform apply note:** Apply creates the new SSM param resources (initially with PLACEHOLDER value), new task-def revision, and removes the old `appsettings` staging param resources. The old params must still exist in AWS when the apply runs (they will, since they are destroyed as part of the same apply after the new task-def is in place). Seeding must happen before the apply so the execution role can resolve the `secrets` items on the first task launch.

**Dependencies:** Phase 1 merged; staging ECRs carry the new entrypoint (`COMPANIES_SSM_PARAMETER`).

**Success criteria:**
- [ ] `terraform plan` shows no unexpected diffs
- [ ] Seeding: `companies` param length > 2 for both staging envs
- [ ] Seeding: both connection-string params length > 0 for both staging envs
- [ ] `terraform apply` exits 0
- [ ] `aws ecs run-task` on mx-staging exits 0 with no config errors in CloudWatch logs
- [ ] `aws ecs run-task` on co-staging exits 0 with no config errors in CloudWatch logs

---

### Phase 3: Phase 23 HubFlow release (out-of-band)

**Objective:** Push the new simplex-harvester image (including the `COMPANIES_SSM_PARAMETER` entrypoint change from Phase 1) to the prod ECRs via a `master` push.

**Owner:** Phase 23 plan (`~/.claude/plans/active/simplex-harvester/PLAN.md:2333-2355`). This phase is not driven by the current plan — it is a dependency gate.

**What happens in CI:** `build.yaml:57-60` detects `github.ref_name == master` and sets `suffix=""`, pushing to `integrator-atento-harvester-mx` and `integrator-atento-harvester-co` (prod ECRs).

**Coupling note:** The Phase 23 release also ships simplex-harvester PR #30 (Rollbar retry) to prod. The two changes travel together in the same release. The prod Terraform PR (Phase 4) must not be applied before this release completes and the new images are confirmed in the prod ECRs.

**Dependencies:** Staging sign-off (Phase 2) must be completed; Phase 23 release must be ready to go.

**Success criteria:**
- [ ] `git hf release finish` for Phase 23 has run; `master` has the Phase 1 commit
- [ ] CI confirms push to `integrator-atento-harvester-mx` (prod ECR)
- [ ] CI confirms push to `integrator-atento-harvester-co` (prod ECR)

---

### Phase 4: Prod Terraform PR + seeding ops

**Objective:** Add SSM params and update prod task-defs; remove old `appsettings` prod params. Apply within the safe ~23h cutover window after the daily cron fires.

**Files (Terraform repo):**
- `terraform/integrator-atento/ssm_harvester.tf` — add 3 new SSM params per prod env (6 total): `companies`, `ConnectionString_Simplex`, `ConnectionString_4Shark`; remove `aws_ssm_parameter.harvester_mx_appsettings` and `aws_ssm_parameter.harvester_co_appsettings`
- `terraform/integrator-atento/compute_harvester.tf` — add 7 plain env vars to prod task-def locals (pattern: `compute_harvester.tf:19-30`); add 2 `secrets` items per task-def (pattern: `compute_harvester.tf:129`); rename `APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`; remove old `appsettings` SSM param references; rename IAM inline policy name `ssm-read-appsettings` → `ssm-read-companies` at `compute_harvester.tf:70` and `compute_harvester.tf:167`

**Safe apply window:** Apply after 09:30 UTC on any day (both daily fires complete by ~09:45 UTC; next CO fire is 08:30 UTC the following day). The `ecs_scheduled_task` module uses LATEST task-def revision (`modules/ecs_scheduled_task/main.tf:90`), so the new revision is picked up on the next automatic cron fire without any service restart. Prod schedules are **not** disabled before applying (engineer chose sub-option i).

**Apply order (mandatory):**

1. **Seed mx prod** (seeding procedure, Steps 1–5 for env=`mx`) — before apply
2. **Seed co prod** (same, env=`co`)
3. `terraform apply` (prod TF PR) — after 09:30 UTC
4. Verify prod params populated (length checks)
5. Next automatic cron fires (CO at 08:30 UTC, MX at 09:30 UTC the following morning) validate the end-to-end flow

**Dependencies:** Phase 3 (Phase 23 release confirmed; prod ECRs carry new image).

**Success criteria:**
- [ ] `terraform plan` shows no unexpected diffs
- [ ] Seeding: `companies` param length > 2 for both prod envs
- [ ] Seeding: both connection-string params length > 0 for both prod envs
- [ ] `terraform apply` exits 0 after 09:30 UTC
- [ ] `aws_ssm_parameter.harvester_mx_appsettings` and `harvester_co_appsettings` no longer exist in SSM
- [ ] Next CO cron fire (08:30 UTC next day) exits successfully; next MX cron fire (09:30 UTC next day) exits successfully

---

## Execution order summary

```
Phase 1: Code PR (simplex-harvester)
  → merge to develop → staging ECRs updated (CI)
Phase 2: Staging TF PR
  → seed mx-staging + co-staging params
  → terraform apply (staging)
  → aws ecs run-task mx-staging (validate)
  → aws ecs run-task co-staging (validate)
  → staging fully migrated and signed off
Phase 3: Phase 23 HubFlow release (out-of-band gate)
  → git hf release finish → master → prod ECRs updated
Phase 4: Prod TF PR
  → seed mx-prod + co-prod params
  → terraform apply (prod) — after 09:30 UTC
  → next automatic cron fires validate (CO 08:30, MX 09:30 next morning)
```

---

## Seeding procedure

> Layer-0: connection-string values contain passwords. They are NEVER printed to the terminal or chat. All seeding goes through local temp files and `--value file://` so the value never appears in shell history or session output.

**Pre-conditions for each env:**
- `4shark-mfa` profile is active (`/elevate-aws-access`)
- Existing SSM `appsettings` param for the env is still live (not yet destroyed by Terraform)
- New Terraform resources exist in SSM with PLACEHOLDER value (first TF apply already done OR seeding happens before apply — see apply order notes above)

**Note on timing:** For staging (Phase 2), seed before `terraform apply` so the execution role can resolve the `secrets` items on the first task launch. For prod (Phase 4), same.

### Step 1 — Download existing appsettings value

```bash
aws ssm get-parameter --name "/integrator-atento-harvester-<env>/appsettings" --with-decryption --query "Parameter.Value" --output text --profile 4shark-mfa > /tmp/appsettings_<env>.json
```

Verify: `wc -c /tmp/appsettings_<env>.json` should be non-trivial (not just "PLACEHOLDER").

### Step 2 — Extract and seed the `companies` value

Extract only the COMPANIES subtree:

```bash
jq '{COMPANIES: .COMPANIES}' /tmp/appsettings_<env>.json > /tmp/companies_<env>.json
```

Seed into the new `/companies` param:

```bash
aws ssm put-parameter --name "/integrator-atento-harvester-<env>/companies" --value "$(cat /tmp/companies_<env>.json)" --type SecureString --overwrite --profile 4shark-mfa
```

Verify the param is populated (value length only, no echo):

```bash
aws ssm get-parameter --name "/integrator-atento-harvester-<env>/companies" --with-decryption --query "length(Parameter.Value)" --profile 4shark-mfa
```

### Step 3 — Extract and seed connection-string secrets

Extract to temp files (never echoed to terminal):

```bash
jq -r '.ConnectionString_Simplex' /tmp/appsettings_<env>.json > /tmp/cs_simplex_<env>.txt
jq -r '.ConnectionString_4Shark' /tmp/appsettings_<env>.json > /tmp/cs_4shark_<env>.txt
```

Seed via `file://` path to avoid terminal exposure:

```bash
aws ssm put-parameter --name "/integrator-atento-harvester-<env>/ConnectionString_Simplex" --value "file:///tmp/cs_simplex_<env>.txt" --type SecureString --overwrite --profile 4shark-mfa
aws ssm put-parameter --name "/integrator-atento-harvester-<env>/ConnectionString_4Shark" --value "file:///tmp/cs_4shark_<env>.txt" --type SecureString --overwrite --profile 4shark-mfa
```

Verify (length only):

```bash
aws ssm get-parameter --name "/integrator-atento-harvester-<env>/ConnectionString_Simplex" --with-decryption --query "length(Parameter.Value)" --profile 4shark-mfa
aws ssm get-parameter --name "/integrator-atento-harvester-<env>/ConnectionString_4Shark" --with-decryption --query "length(Parameter.Value)" --profile 4shark-mfa
```

### Step 4 — Extract 7 plain scalar values

These go into Terraform `environment_variables` locals — not into SSM. Extract for reference when writing the Terraform locals:

```bash
jq '{UserRegisterType,SubsidiaryRegisterType,State,DefaultCity,ExternalIdSource,EmailDomain,EmailSource}' /tmp/appsettings_<env>.json
```

`EmailDomain` and `EmailSource` are optional in the code (`string.IsNullOrWhiteSpace` check in `_4SharkService.cs:324` and `_4SharkService.cs:330`). If either is absent or empty, the code uses its default (`"atento.com"` for `EmailDomain`, `null` for `EmailSource`).

### Step 5 — Clean up local temp files

```bash
rm /tmp/appsettings_<env>.json /tmp/companies_<env>.json /tmp/cs_simplex_<env>.txt /tmp/cs_4shark_<env>.txt
```

### Environments to seed (in order)

1. `mx-staging` (Phase 2)
2. `co-staging` (Phase 2)
3. `mx` prod (Phase 4)
4. `co` prod (Phase 4)

Seed staging first so Step 4 scalar values can be validated with the Phase 2 test run before they are hardcoded in the Terraform locals for prod.

---

## Technical decisions

| Decision | Choice | Rationale (from engineer) |
|----------|--------|---------------------------|
| Prod-coupling strategy | Option A — two-phase (staging now, prod with Phase 23) | Prod is untouched until Phase 23's release window; staging run validates all resource shapes and the entrypoint rename before prod is touched; aligns with existing release discipline |
| Prod cron safety during apply | Sub-option i — rely on the ~23h safe window (no schedule disable) | The prod apply + SSM seed is a few minutes, far inside the ~23h gap between cron fires (CO 08:30 UTC, MX 09:30 UTC); three-apply cycle adds unnecessary complexity |
| Terraform PR count | 2 PRs (staging PR and prod PR) | Follows from Option A; staging PR can be reviewed and applied independently; prod PR waits for Phase 23 release gate |
| Committed `appsettings.json` placeholder | `{ "COMPANIES": {} }` | Keeps the section present and self-documenting; also fixes the current wrong structure (`COUNTRIES`/`ConnectionStrings.MEX` — per engineer brief) |
| Old `appsettings` param removal | Removed in the same PR that adds new params (staging params in PR 2, prod params in PR 4) | Old params are still live when the task-def switch occurs (they are destroyed after the new task-def is in place within the same apply); avoids a separate cleanup PR |
| IAM inline policy name | Rename `ssm-read-appsettings` → `ssm-read-companies` | Consistency with the param rename; metadata change only, no effect on resource scope or permission evaluation |
| Staging sign-off depth | Manual `aws ecs run-task` (not a full cron cycle) | Sufficient to validate the entrypoint change and config resolution; staging is `create_schedule=false` so a cron cycle would require re-enabling and re-disabling |

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| New task-def applied before new image reaches prod ECR | Entrypoint looks for `COMPANIES_SSM_PARAMETER`, finds it unset → task fails | Option A: prod TF PR (Phase 4) is applied only after Phase 23 confirms prod ECRs carry the new image |
| New `companies` SSM param not seeded before task-def apply | Entrypoint fetches PLACEHOLDER → dotnet crashes immediately at startup | Seed BEFORE each Terraform apply (mandatory apply order in Phase 2 and Phase 4); verify with length check (seeding procedure Step 2) |
| Connection-string params not seeded before task-def secrets injection | ECS task launch fails at execution role secret resolution → task never starts | Seed params BEFORE applying task-def changes (seeding procedure Step 3); ECS refuses to start a task if a secrets ARN returns PLACEHOLDER |
| Plain env var values transposed between MX and CO | Wrong country's normalized base or Simplex source written to | Extract values per-env from each env's existing SSM `appsettings` param (seeding procedure Step 4); validate with staging manual run before hardcoding prod TF locals |
| Old `appsettings` param destroyed before new image reaches prod ECR | Old image entrypoint tries `APPSETTINGS_SSM_PARAMETER` pointing to a destroyed param → prod task fails | Staging TF PR only removes staging old params; prod old params are removed in Phase 4 after Phase 23 confirms the new image is live in prod ECRs |
| Phase 23 delayed indefinitely | Staging and prod diverge; prod carries the monolithic appsettings SSM param with credentials for an extended period | Option A mitigates: staging is fully migrated; prod continues to work on old config. The divergence is visible and bounded by Phase 23 scheduling |
| Apply inside cron fire window | New task-def revision registered mid-fire could be picked up by a concurrent scheduled run | Apply after 09:30 UTC (both fires complete by ~09:45 UTC); ~22h 45m window is available (`compute_harvester.tf:113`, `compute_harvester.tf:200`) |

---

## Assumptions

- CI `build.yaml:57-60` continues to gate ECR pushes by branch: `master` → prod ECRs, all else → staging ECRs (established fact from draft)
- The `ecs_scheduled_task` module continues to use LATEST task-def revision (`modules/ecs_scheduled_task/main.tf:90`), so a new revision registered by Terraform apply takes effect on the next scheduled fire without a service restart
- The existing `integrator-atento-*` wildcard on the execution role (`ssm.tf:47-50`) covers all new SSM param paths without any IAM change
- The existing `integrator-atento-harvester-mx/*` and equivalent CO/staging wildcards on the task roles cover the renamed `companies` param without any IAM change
- Phase 23 will produce a `git hf release finish` that pushes to `master` — this is the mechanism Phase 4 depends on
- The existing prod `appsettings` SSM params remain live and accessible throughout Phases 1–3; they are not modified or deleted before Phase 4
