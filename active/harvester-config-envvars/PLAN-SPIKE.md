# PLAN-SPIKE — Harvester Config Env-Vars Refactor

> Reference: ESTABLISHED FACTS section in engineer's brief + codebase reads (cited below)

## Objective

Move the 9 root-level scalar keys of the harvester's `appsettings.json` out to environment variables. The 2 connection strings (`ConnectionString_Simplex`, `ConnectionString_4Shark`) become ECS task-definition **secrets** backed by new per-env SSM `SecureString` params. The 7 non-secret scalars become plain `environment_variables` in the task-def. `COMPANIES` stays in `appsettings.json` written by the entrypoint from a renamed SSM param (`appsettings` → `companies`). The entrypoint env var is renamed from `APPSETTINGS_SSM_PARAMETER` to `COMPANIES_SSM_PARAMETER`. No changes to `Program.cs` or `_4SharkService.cs`.

## Scope

### In scope

- `entrypoint.sh`: rename `APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`
- `appsettings.exampleDevOps.json` + `appsettings.example.json`: trim the 9 root scalars
- Committed `appsettings.json`: trim to COMPANIES placeholder only (it is baked into the Docker image via `.csproj` `CopyToOutputDirectory`; overwritten at runtime by the entrypoint)
- Terraform `ssm_harvester.tf` / `ssm_harvester_staging.tf`: add `companies` + 2 connection-string SSM params per env; remove old `appsettings` params
- Terraform `compute_harvester.tf` / `compute_harvester_staging.tf`: add 7 plain env vars + 2 connection-string secrets per env; rename `APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`; remove the old `appsettings` SSM param references
- Ops seeding: extract values from existing SSM `appsettings` params; seed new params out-of-band before apply

### Out of scope (open question)

- `Program.cs` and `_4SharkService.cs` — zero code changes (locked decision)
- Phase 23 scope (project rename, per-country build isolation, deploy-only-from-master) — the config refactor MAY couple to Phase 23's release window for prod ECRs (see Candidate Approaches)
- Chile / future countries

---

## Critical constraint: prod ECR image update requires a master push

`build.yaml:57-60` gates ECR pushes by branch:

```yaml
if [ "${{ github.ref_name }}" = "master" ]; then
  suffix=""        # → prod ECRs (integrator-atento-harvester-{mx,co})
else
  suffix="-staging" # → staging ECRs only
fi
```

Merging the code PR to `develop` updates **staging ECRs only**. Prod ECRs (`integrator-atento-harvester-mx`, `integrator-atento-harvester-co`) are only updated by a push to `master`, which requires a HubFlow release (`git hf release finish`). This constraint is the dominant sequencing fork: the three candidate approaches differ mainly in how they handle it.

---

## IAM coverage (no changes required)

Two confirmed facts remove an entire category of work:

**Execution role** (`ecsTaskExecutionRole`) — `ssm.tf:47-50`:
```hcl
Action   = ["ssm:GetParameters"]
Resource = ["arn:aws:ssm:sa-east-1:405749097490:parameter/integrator-atento-*"]
```
The new connection-string params (`/integrator-atento-harvester-{env}/ConnectionString_Simplex` etc.) match this wildcard. The default SSM KMS key decrypt is already granted (`ssm.tf:53-55`). No IAM change for the execution role.

**Task roles** (one per env) — `compute_harvester.tf:78-81`:
```hcl
Resource = "arn:aws:ssm:sa-east-1:405749097490:parameter/integrator-atento-harvester-mx/*"
```
The renamed `companies` param (at `/integrator-atento-harvester-mx/companies`) is under the `mx/*` wildcard. Same wildcard in the CO and staging task roles (`compute_harvester.tf:175-178`, `compute_harvester_staging.tf:65-68`, `compute_harvester_staging.tf:151-154`). No IAM change for task roles.

---

## How the .NET config provider resolves these after the refactor

`Program.cs:27-31`:
```csharp
IConfiguration configuration = new ConfigurationBuilder()
    .SetBasePath(Directory.GetParent(AppContext.BaseDirectory)!.FullName)
    .AddJsonFile("appsettings.json", optional: false)
    .AddEnvironmentVariables()
    .Build();
```

Providers are merged in registration order; later providers win on conflict. `AddEnvironmentVariables()` is last, so any key present in both `appsettings.json` and the process environment resolves to the env-var value. After the refactor, `appsettings.json` contains only `COMPANIES`; the 7 plain scalars and 2 connection strings arrive as env vars injected by ECS (plain `environment` array + `secrets` array resolved by the execution role before the container starts). `_4SharkService.cs:341` reads them via `GetSection(key).Value` — the provider is transparent to the caller.

ECS secrets are injected as env vars before the entrypoint runs (`exec dotnet` at entrypoint.sh:32 inherits the full environment). Both the bash entrypoint and the dotnet process see them.

---

## The `.csproj` `appsettings.json` copy-to-output

`SimplexPE.Global4Shark.csproj:27-29`:
```xml
<None Update="appsettings.json">
  <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
</None>
```
`CopyToOutputDirectory: PreserveNewest` applies to both `dotnet build` and `dotnet publish`. `Dockerfile:25` copies the publish output:
```dockerfile
COPY --from=build /app ./
```
So the committed `appsettings.json` is baked into the runtime image at `/app/appsettings.json`. The entrypoint overwrites it at container start. After the refactor, the committed file must contain only a COMPANIES placeholder (not the old 9 scalars) so that if the SSM fetch fails and the image fallback is hit, the app fails fast in `_4SharkService.cs:356-358` rather than silently running with stale scalars.

---

## Timing window for prod cutover

`compute_harvester.tf:113` — MX fires at `cron(30 3 * * ? *)` `America/Mexico_City` = **09:30 UTC**.
`compute_harvester.tf:200` — CO fires at `cron(30 3 * * ? *)` `America/Bogota` = **08:30 UTC**.

After both fires complete (empirically ~15 min from start to exit), there is a ~22h 45m safe window before the next CO fire. The Terraform `ecs_scheduled_task` module uses LATEST task-def revision (`modules/ecs_scheduled_task/main.tf:90`):
```hcl
task_definition_arn = replace(aws_ecs_task_definition.this.arn, "/:\\d+$/", "")
```
A new task-def revision registered by Terraform apply takes effect on the immediately subsequent scheduled fire — no service restart.

Staging tasks are `state = "DISABLED"` + `create_schedule = false` (`compute_harvester_staging.tf:107-108`) — no automatic fire risk there at any time.

---

## Candidate Approaches

### Option A: Two-phase — staging now, prod with Phase 23

**Approach summary:** The code PR is merged to `develop` immediately (updates staging ECRs). A staging-only Terraform PR is applied and validated with a manual `aws ecs run-task`. Prod changes wait for the Phase 23 HubFlow release, which pushes to prod ECRs. After the release, a prod Terraform PR is applied within the safe cutover window.

**Sequencing:**

1. Code PR (`simplex-harvester`): trim `appsettings.example*.json` + update `entrypoint.sh` (`APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`) + trim committed `appsettings.json` to COMPANIES placeholder. Merge to `develop` → staging ECRs updated.
2. Terraform PR (staging only — `ssm_harvester_staging.tf` + `compute_harvester_staging.tf`): add `companies` + 2 connection-string params for mx-staging and co-staging; update staging task-def locals. Apply → seed params (see auxiliary `seeding_procedure_1.md`) → manual `aws ecs run-task` for mx-staging and co-staging to validate.
3. Phase 23: `git hf release start/finish` → master push → prod ECRs updated with the entrypoint change.
4. Terraform PR (prod — `ssm_harvester.tf` + `compute_harvester.tf`): add prod SSM params; update prod task-def locals; remove old `appsettings` params + `APPSETTINGS_SSM_PARAMETER` env var. Apply after seeding, within safe window (after 09:30 UTC).

**Pros:**
- No prod cron risk at any point — prod is untouched until Phase 23's release window when everything is ready.
- Staging run validates all 10 Terraform resource shapes and the entrypoint change before prod is touched.
- Aligns cleanly with the existing release discipline (Phase 23 owns the master push).
- The ROLLBAR_ACCESS_TOKEN precedent (`secrets` item in task-def) is already proven in staging — no unknowns for the connection-string secrets shape.

**Cons:**
- Prod carries the old monolithic appsettings SSM param until Phase 23 (could be days/weeks depending on Phase 23 schedule).
- Two Terraform PRs; the prod PR has to be coordinated with Phase 23 timeline.
- If Phase 23 is delayed indefinitely, staging and prod diverge for an extended period.

**Cost / effort:** ~2 code files + 2 Terraform files changed in the code PR; ~2 Terraform files in the staging TF PR; ~2 Terraform files in the prod TF PR. Seeding: 4 envs × (download + 3 puts) = ~12 SSM operations.

**Risk:** Low. The entrypoint change only affects containers using the new image. The old prod image reads `APPSETTINGS_SSM_PARAMETER` from the still-present env var + old param. No prod run is affected until the Phase 23 image update.

**Source patterns referenced:**
- `terraform/integrator-atento/compute_harvester.tf:129` — ROLLBAR_ACCESS_TOKEN as `secrets` item (exact shape for connection-string secrets)
- `terraform/integrator-atento/ssm_harvester.tf:10-25` — existing appsettings param resource (template for new companies + connection-string params)
- `terraform/integrator-atento/ssm.tf:39-58` — execution role policy scope (confirms new params are covered without IAM changes)
- See auxiliary: `seeding_procedure_1.md` — out-of-band seeding procedure for all 4 envs

---

### Option B: Backward-compatible entrypoint (dual env-var fallback)

**Approach summary:** The entrypoint is updated to accept EITHER `COMPANIES_SSM_PARAMETER` (new name, checked first) OR `APPSETTINGS_SSM_PARAMETER` (old name, fallback). This makes the new image backward-compatible with the old task-def. A single Terraform PR covers all 4 environments. Terraform is applied to staging immediately, to prod immediately after Phase 23's image reaches the prod ECRs. The old `appsettings` params and `APPSETTINGS_SSM_PARAMETER` env vars remain until a cleanup Terraform PR after Phase 23.

**Entrypoint change shape:**
```bash
# Accept either name; COMPANIES_SSM_PARAMETER wins when both are set.
param_name="${COMPANIES_SSM_PARAMETER:-${APPSETTINGS_SSM_PARAMETER:-}}"
: "${param_name:?One of COMPANIES_SSM_PARAMETER or APPSETTINGS_SSM_PARAMETER must be set}"
```

**Sequencing:**

1. Code PR: backward-compatible entrypoint + trimmed appsettings files. Merge to `develop`.
2. Single Terraform PR (all 4 envs): add `companies` params + 2 connection-string params per env; add 7 plain env vars; add 2 connection-string secrets; keep `APPSETTINGS_SSM_PARAMETER` pointing to old param (old param not deleted yet). Apply staging after seeding mx-staging/co-staging. Apply prod after Phase 23 image update + seeding mx/co prod.
3. Phase 23: release → master push → prod ECRs updated.
4. Cleanup Terraform PR: remove old `appsettings` SSM params and `APPSETTINGS_SSM_PARAMETER` env var from task-defs.

**Pros:**
- Single Terraform PR covers all envs (easier to review, one apply for staging, one for prod).
- Backward compatibility means the old image continues to work even if Terraform is applied before the new image reaches prod — no race condition.
- The entrypoint gracefully handles both transition states (new task-def + old image; new task-def + new image).

**Cons:**
- The entrypoint's fallback logic adds transient complexity that must be cleaned up in Phase 23 (or a follow-on PR).
- The old `appsettings` SSM params persist until the cleanup PR — two Terraform apply cycles even in this option.
- The transitional dual-param state is invisible in the code once Phase 23 is done but leaves a gap in intermediate history.

**Cost / effort:** ~3 code files changed (entrypoint is slightly more complex); ~4 Terraform files in the single TF PR; cleanup PR touches 4 Terraform files again.

**Risk:** Medium. The fallback logic in bash is simple but adds a new code path that must be explicitly removed later. If the cleanup is forgotten, both env vars exist indefinitely.

**Source patterns referenced:**
- `simplex-harvester/.github/docker/entrypoint.sh:9` — current required-env-var check (pattern for the dual fallback)
- `terraform/integrator-atento/compute_harvester.tf:19-30` — current env-vars locals shape
- `terraform/integrator-atento/compute_harvester.tf:129` — existing `secrets` shape for ROLLBAR_ACCESS_TOKEN

---

### Option C: Phase 23 first, then config refactor entirely in one release window

**Approach summary:** Do not touch the harvester config until Phase 23 is ready. Run `git hf release start/finish` first (promoting develop → master, updating prod ECRs with the current code). Then apply the config refactor code PR + Terraform PR in a single cycle, targeting all 4 envs with no backward-compat complexity, since both staging and prod ECRs carry the new image from the outset.

**Sequencing:**

1. Phase 23: `git hf release start X.Y.Z` + release PR + `git hf release finish`. Prod ECRs updated (with current code that still uses `APPSETTINGS_SSM_PARAMETER`).
2. Code PR: entrypoint rename + appsettings trims (no backward-compat needed — the release already gated the old image into prod). Merge to `develop`.
3. Terraform PR (all 4 envs): add all new params; update all task-defs. Apply staging → seed → validate → apply prod (within safe window).
4. Old `appsettings` params and `APPSETTINGS_SSM_PARAMETER` removed in the same Terraform PR.

**Pros:**
- Cleanest code path — no transitional fallback logic ever committed.
- Single Terraform PR + single ops window covers all 4 envs.
- Staging and prod carry the same entrypoint logic from the start.

**Cons:**
- Phase 23 must happen BEFORE this refactor can go to prod. If Phase 23 is complex (branch cleanup, rename, build parameterization), it serializes this otherwise-independent work.
- Phase 23's scope is already large; adding the config refactor as a prerequisite adds scheduling pressure.
- A delay in Phase 23 means the monolithic appsettings SSM param continues to hold credentials alongside the plaintext scalars in a single param — the security improvement is deferred.

**Cost / effort:** ~2 code files + 4 Terraform files in one cycle. Lowest total file count.

**Risk:** Low (clean single cycle) but dependent on Phase 23 scheduling. If Phase 23 is delayed beyond a few days, the refactor is blocked.

**Source patterns referenced:**
- `simplex-harvester/.github/workflows/build.yaml:57-60` — branch-to-ECR mapping (this option removes the sequencing constraint by doing Phase 23 first)
- `~/.claude/plans/active/simplex-harvester/PLAN.md:2333-2355` — Phase 23 scope and deferred conditions

---

## Sub-options for prod cron safety (apply to whichever Option A/B/C reaches prod)

### Sub-option i: Rely on the 23h safe window

After CO fires at 08:30 UTC and MX fires at 09:30 UTC each day, no automatic run occurs until the next day's CO fire at 08:30 UTC. A Terraform apply that completes within this ~22h 45m window has no overlap with a live cron fire. The `ecs_scheduled_task` module points at LATEST task-def; an in-progress apply registers a new revision only after the current fire has already started or not yet started. The fire takes ~5-10 min; the apply takes ~1-2 min for a task-def-only change. Overlap is possible only if the apply starts exactly as a fire is firing, which is not a realistic risk in a 22h window.

**Pros:** No extra Terraform ops; applies are clean and minimal.
**Cons:** Requires timing awareness — the engineer must apply after 09:30 UTC. Weekend or holiday applies are fine as long as they're within the window.

### Sub-option ii: Temporarily disable prod schedules before applying

Add a preparatory Terraform change that sets `state = "DISABLED"` for the MX and CO prod schedules, apply it, then apply the full config changes, then re-enable. Three Terraform applies for prod instead of one.

**Pros:** Belt-and-suspenders — no overlap risk even if the apply is scheduled at the wrong time.
**Cons:** Three applies = three plan + apply cycles; re-enabling the schedule is an easy step to forget; EventBridge schedule disable/enable is an ephemeral ops detail that adds noise to the Terraform history.

---

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|---|---|---|---|
| Prod image cutover coupling | A: two-phase (staging now, prod with Phase 23) / B: backward-compat entrypoint / C: Phase 23 first | A is simplest but serializes on Phase 23; B adds transient complexity; C is cleanest but fully blocks on Phase 23 | □ |
| Prod cron safety during apply | i: rely on 23h window / ii: disable schedules first | i is simpler; ii is belt-and-suspenders | □ |
| Terraform PR count | 2 PRs (staging, prod) / 1 PR (all envs, apply sequentially) | 2 PRs mean a separate review for prod; 1 PR means one apply per env environment from the same plan | □ |
| Committed `appsettings.json` content | `{ "COMPANIES": { "0": { "RootAdmin": 0, "Admins": [] } } }` (valid placeholder) / `{}` (empty, fail-fast) | Valid placeholder matches the code's COMPANIES validation expectation; empty causes ReifySubsidiaries to fail-fast with a clear error | □ |
| Old `appsettings` param retention | Remove in same PR as new params / keep until cleanup PR | Removing in the same PR keeps prod at zero old params; keeping until cleanup avoids a two-step cutover at the cost of lingering credentials | □ |

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| New task-def applied before new image reaches prod ECR (Options A/B) | Container starts, entrypoint looks for `COMPANIES_SSM_PARAMETER`, finds it unset → task fails | Option B's backward-compat fallback; or only apply prod TF after Phase 23 image push is confirmed |
| New `companies` SSM param not seeded before task-def apply | Entrypoint fetches PLACEHOLDER → `dotnet` crashes immediately at startup (appsettings.json has string "PLACEHOLDER" not JSON) | Always seed BEFORE or right after `terraform apply` creates the PLACEHOLDER resource; verify with length check (seeding_procedure_1.md step 2) |
| Connection-string params not seeded before task-def secrets injection | ECS task launch fails at execution role secret resolution → task never starts | Seed params BEFORE applying task-def changes; ECS will refuse to start the task if a secrets ARN returns PLACEHOLDER |
| Plain env var values wrong (transposed between MX and CO) | Wrong country's normalized base or Simplex source written to | Extract values per-env from each env's existing SSM appsettings (seeding_procedure_1.md step 4); validate with staging run first |
| `appsettings` param deleted before new image deployed to prod | Old image entrypoint tries to fetch `APPSETTINGS_SSM_PARAMETER` pointing to a deleted param → task fails | Keep old `appsettings` param alive until prod image is confirmed; remove only in cleanup PR |
| Phase 23 delayed indefinitely | Config refactor blocked in prod (Options A and B) or entirely (Option C) | Option A mitigates: staging is fully refactored now, prod still works on old config |

---

## PR decomposition (for whichever option is chosen)

### PR 1 — Code (simplex-harvester)

**Files:** `.github/docker/entrypoint.sh`, `appsettings.exampleDevOps.json`, `appsettings.example.json`, `appsettings.json`

Entrypoint change is in `entrypoint.sh:9` — replace `APPSETTINGS_SSM_PARAMETER` required check with `COMPANIES_SSM_PARAMETER`. Remove 9 root scalars from the two example files. Update committed `appsettings.json` to COMPANIES-only placeholder.

CHANGELOG entry under `### Changed`: `Harvester appsettings — moved scalar config to environment variables`

**When merged to develop:** staging ECRs updated automatically. **No prod ECR update until master.**

### PR 2 — Terraform (staging envs)

**Files:** `terraform/integrator-atento/ssm_harvester_staging.tf`, `terraform/integrator-atento/compute_harvester_staging.tf`

Add `harvester_mx_staging_companies`, `harvester_mx_staging_connection_string_simplex`, `harvester_mx_staging_connection_string_4shark`, and CO-staging equivalents (6 new SSM params). Update `local.harvester_mx_staging_env_vars` and `local.harvester_co_staging_env_vars` to include 7 plain scalars. Add 2 `secrets` items per task. Rename `APPSETTINGS_SSM_PARAMETER` → `COMPANIES_SSM_PARAMETER`. Remove old `appsettings` SSM param references.

**Apply order:** seed staging params (seeding_procedure_1.md) → `terraform apply` → validate with `aws ecs run-task` on each staging task.

### PR 3 — Terraform (prod envs, post-Phase-23)

**Files:** `terraform/integrator-atento/ssm_harvester.tf`, `terraform/integrator-atento/compute_harvester.tf`

Same shape as PR 2 for MX prod and CO prod. Remove `aws_ssm_parameter.harvester_mx_appsettings` and `harvester_co_appsettings`. Apply within safe cutover window (after 09:30 UTC).

---

## Execution order (Option A, the baseline)

```
PR 1 (code)  →  merge to develop
                   │
                   ↓ staging ECRs updated (CI)
PR 2 (TF-staging) → seed mx-staging + co-staging params
                   → terraform apply (staging)
                   → aws ecs run-task mx-staging (validate)
                   → aws ecs run-task co-staging (validate)
                   │
                   ↓ staging fully migrated
Phase 23      →  git hf release finish  →  master  →  prod ECRs updated
                   │
PR 3 (TF-prod) → seed mx-prod + co-prod params
              → terraform apply (prod)   ← after 09:30 UTC
              → next automatic cron run validates (03:30 MX + CO the next morning)
```

---

## Open questions for the engineer

1. **Phase 23 timing:** Is Phase 23 imminent (days) or open-ended (weeks)? If imminent, Option C (Phase 23 first) avoids all staging/prod divergence. If open-ended, Option A (staging now, prod with Phase 23) is better.
2. **Committed `appsettings.json` placeholder format:** The current committed `appsettings.json` has a `COUNTRIES` structure (unrelated to the current code). Should it be replaced with a clean COMPANIES-only placeholder (`{ "COMPANIES": {} }`) or an empty object (`{}`)? The empty object causes `ReifySubsidiaries` to throw `"appsettings.COMPANIES is empty"` — clear error; the COMPANIES placeholder is slightly more self-documenting.
3. **Old `appsettings` param retention:** Removing the old `appsettings` params in the same Terraform PR that adds `companies` is the cleanest approach but requires the old param to still be live when the task-def is switched (it is, since it's removed only after the new task-def is in place). Is a two-Terraform-PR approach wanted instead (add new first, remove old separately)?
4. **IAM policy name collision:** Both `compute_harvester.tf:70` (MX task role) and `compute_harvester.tf:167` (CO task role) have `name = "ssm-read-appsettings"`. That name stays accurate even after the rename (the task role still reads SSM). Should this policy name be updated to `ssm-read-companies` for clarity, or left as-is?
5. **Staging validation depth:** Is a `aws ecs run-task` invocation against each staging env sufficient for sign-off before prod, or is a full one-day staging cron run (re-enabling the schedule for one cycle) needed?

---

## Sources

- `simplex-harvester/Program.cs:27-31` — ConfigurationBuilder with AddJsonFile + AddEnvironmentVariables (env vars win)
- `simplex-harvester/Services/_4SharkService.cs:307-348` — ResolveConfig reading all 7 plain scalars via RequireConfig
- `simplex-harvester/Services/_4SharkService.cs:373-374` — ConnectionString_Simplex read
- `simplex-harvester/Services/_4SharkService.cs:1499` — ConnectionString_4Shark read
- `simplex-harvester/SimplexPE.Global4Shark.csproj:27-29` — appsettings.json CopyToOutputDirectory (file is in the Docker image)
- `simplex-harvester/.github/docker/entrypoint.sh:9` — APPSETTINGS_SSM_PARAMETER required check
- `simplex-harvester/.github/docker/entrypoint.sh:12-25` — SSM fetch with 5-attempt retry
- `simplex-harvester/.github/docker/entrypoint.sh:32` — exec dotnet (inherits full env including ECS-injected secrets)
- `simplex-harvester/.github/docker/Dockerfile:25-28` — runtime image COPY from build output
- `simplex-harvester/.github/workflows/build.yaml:57-60` — branch-gated ECR push (master → prod, all else → staging)
- `terraform/integrator-atento/ssm.tf:39-58` — execution role SSM GetParameters wildcard + KMS key (no IAM change needed)
- `terraform/integrator-atento/ssm_harvester.tf:10-42` — existing appsettings param resources (template for new params)
- `terraform/integrator-atento/compute_harvester.tf:19-30` — current env-vars locals (add 7 plain scalars here)
- `terraform/integrator-atento/compute_harvester.tf:69-91` — task role with ssm:GetParameter on harvester-mx/* wildcard (covers renamed companies param)
- `terraform/integrator-atento/compute_harvester.tf:113` — MX cron fires at 03:30 Mexico_City = 09:30 UTC
- `terraform/integrator-atento/compute_harvester.tf:129` — ROLLBAR_ACCESS_TOKEN secrets shape (precedent for connection-string secrets)
- `terraform/integrator-atento/compute_harvester.tf:200` — CO cron fires at 03:30 Bogota = 08:30 UTC
- `terraform/integrator-atento/compute_harvester_staging.tf:107-108` — state=DISABLED, create_schedule=false (no cron fire risk)
- `terraform/modules/ecs_scheduled_task/main.tf:90` — `replace(..., "/:\\d+$/", "")` → LATEST task-def revision picked up at next fire
- `~/.claude/plans/active/simplex-harvester/PLAN.md:2333-2355` — Phase 23 scope and coupling
- See auxiliary: `seeding_procedure_1.md` — out-of-band SSM seeding procedure for all 4 environments
