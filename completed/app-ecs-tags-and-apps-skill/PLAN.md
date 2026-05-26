# PLAN - App ECS Tags and /apps Skill

> Standard workflow — no DDD documents.

## Objective

Add discovery tags (`Project`, `Environment`, `ManagedBy`) to all four `app-*` stacks by replacing their `local.tags` block, then build the `/apps` skill in Claude Config so engineers can manage app ECS clusters by name using the same interface as `/integrators`.

Because `local.tags` propagates to every resource that receives it — cluster, IAM role, instance profile, SG, key pair, ALB, and more — the change achieves full traceability: any orphaned resource can be identified by tag. This mirrors the integrator pattern exactly (e.g., `integrator-almaviva/mongodb.tf` tags the MongoDB instance with `Client`, `Role`, etc.).

The two deliverables are causally ordered: the skill depends on the tags being live in AWS. Without the tags applied, `aws resourcegroupstaggingapi get-resources --tag-filters Project=app` returns nothing.

## Scope

### In Scope

- Replace `local.tags` block in all four app stacks: `app-shared-001`, `app-atento-001`, `app-beta-001`, `app-demo-001`
- Run `terraform plan` per stack, present structured summary, wait for approval, apply
- Create `apps-services.sh` script in `~/Projects/4Shark/.claude/scripts/`
- Create `apps.md` slash command in `~/Projects/4Shark/.claude/commands/`
- Update `CLAUDE.md` (Available Commands section) and `CHANGELOG.md` in the `.claude` working copy
- Update `CHANGELOG.md` in the Terraform repository
- Two separate PRs in two separate repositories

### Out of Scope

- Modifying `modules/ecs_cluster` or any other Terraform module
- Renaming the `app-atento-001-cluster` cluster, the stack directory, or the stack itself
- Aligning `app-atento-001` naming to the non-prefixed convention (deferred to future migration)
- Unifying `/apps` and `/integrators` into a single command
- Adding a `Client` tag to app clusters

## Execution Phases

### Phase 1: Terraform — Replace `local.tags` in the Four App Stacks

**Objective**: Replace the `local.tags` block in each stack with the canonical three-tag schema. Tags propagate automatically to all resources that already receive `local.tags` — no per-resource changes required.

**`local.tags` — state current → state target for each stack:**

| Stack | File | Current | Target |
|-------|------|---------|--------|
| `app-shared-001` | `main.tf:18-22` | `Environment = "shared-001"`, `Automation = "terraform"`, `Cluster = "shared-001-cluster"` | `Project = "app"`, `Environment = "shared-001"`, `ManagedBy = "terraform"` |
| `app-beta-001` | `main.tf:18-22` | `Environment = "beta-001"`, `Automation = "terraform"`, `Cluster = "beta-001-cluster"` | `Project = "app"`, `Environment = "beta-001"`, `ManagedBy = "terraform"` |
| `app-demo-001` | `main.tf:18-22` | `Environment = "demo-001"`, `Automation = "terraform"`, `Cluster = "demo-001-cluster"` | `Project = "app"`, `Environment = "demo-001"`, `ManagedBy = "terraform"` |
| `app-atento-001` | `main.tf:11-15` | `Environment = "app-atento-001"`, `Automation = "terraform"`, `Cluster = "app-atento-001-cluster"` | `Project = "app"`, `Environment = "atento-001"`, `ManagedBy = "terraform"` |

**Tag changes per stack (key-by-key):**

- `Project = "app"` — **added** (new across all stacks)
- `Environment` — **kept**, but on atento changes from `"app-atento-001"` to `"atento-001"` (drops the `app-` prefix)
- `Automation = "terraform"` → `ManagedBy = "terraform"` — **renamed** (aligns with integrator)
- `Cluster = "..."` — **removed** (redundant; cluster name is already on the AWS resource)

**Note on atento:** the actual cluster keeps the name `app-atento-001-cluster` — it will not be renamed. The `Environment="atento-001"` tag stays mismatched against the cluster name until the future migration. This is intentional.

**Expected `terraform plan` impact per stack:**

Since `local.tags` is referenced across multiple modules and direct resources, the plan will show many resources with `~ tags`. All are in-place updates — no resource is created or destroyed.

| Stack | Files referencing `local.tags` | Estimated resources with `~ tags` |
|-------|--------------------------------|------------------------------------|
| `app-shared-001` | `main.tf`, `scheduled-tasks.tf`, `s3.tf`, `opensearch.tf`, `rds.tf` | ~26 refs |
| `app-atento-001` | `main.tf`, `compute.tf`, `s3.tf`, `opensearch.tf`, `rds.tf` | ~25 refs |
| `app-beta-001` | `main.tf`, `scheduled-tasks.tf`, `s3.tf`, `rds.tf` | ~22 refs |
| `app-demo-001` | `main.tf`, `scheduled-tasks.tf`, `s3.tf`, `rds.tf` | ~23 refs |

**What is expected in each plan:**
- `~ tags` across multiple resources (cluster, IAM role, instance profile, SG, ALB, RDS, OpenSearch, S3, scheduled tasks, etc.)
- **No** `+` (created) or `-` (destroyed) resources
- If any `+` or `-` appears: stop and investigate before applying

**Apply order**: shared-001 first (production, validate the pattern), then beta-001, demo-001, atento-001 last. Atento is last because it has the largest resource graph and a dedicated VPC — requires more careful plan review.

**Per-stack plan + apply sequence** (runs with the PR already open — see full flow below):
1. `terraform plan -out=/tmp/terraform_plan_<stack>_<timestamp>.tfplan`
2. Present structured summary (N resources with `~ tags`, zero `+`/`-`, flag any sensitive resource)
3. Wait for explicit engineer approval
4. `terraform apply /tmp/terraform_plan_<stack>_<timestamp>.tfplan`

**Full Phase 1 flow** (follows the apply-before-merge workflow — see `~/.claude/docs/TERRAFORM-PR-WORKFLOW.md`):
1. Edit `local.tags` in the four stacks
2. Update `CHANGELOG.md`
3. Commit (single atomic commit)
4. Push to remote
5. **Open PR** (target `develop`) — the PR is the mandatory audit trail before any apply
6. Plan the four stacks (one by one, individual review)
7. Apply the four stacks (after per-stack approval — order: shared-001, beta-001, demo-001, atento-001)
8. If an apply fails: fix on the same PR (commit + push), re-plan, re-apply
9. Merge the PR only after **all four applies have succeeded**
10. `/merge-cleanup`

> Apply without an open PR is a policy violation — the PR is the formal audit trail of the work.

**Apply order table** (the entire plan + apply cycle runs with **a single PR open** from step 5 onward):

| Order | Stack | Reason |
|-------|-------|--------|
| 1 | `app-shared-001` | Production, validates the pattern early |
| 2 | `app-beta-001` | Non-prod, low risk |
| 3 | `app-demo-001` | Non-prod, low risk |
| 4 | `app-atento-001` | Largest resource graph and dedicated VPC — extra review |

**Dependencies**: None. The four stacks are independent.

**Success Criteria**:
- [ ] `local.tags` replaced in the four stacks with the correct three-tag block
- [ ] PR opened before the first plan (policy compliance)
- [ ] `terraform plan` for each stack shows only `~ tags` — zero `+` and zero `-`
- [ ] After applying all four stacks, `aws resourcegroupstaggingapi get-resources --tag-filters '[{"Key":"Project","Values":["app"]}]' --resource-type-filters ecs:cluster` returns the four clusters
- [ ] Changelog entry added in `terraform/CHANGELOG.md` under `[Unreleased] > ### Changed`
- [ ] PR merged only after all four applies have succeeded

### Phase 2: Claude Config — /apps Skill

**Objective**: Create the `apps-services.sh` script and `apps.md` command, mirroring the `/integrators` pattern. All changes go through the working copy at `~/Projects/4Shark/.claude/` — never edited directly in `~/.claude/`.

**Two projects, two regions:**

| Project | Region | Clusters (post-Phase 1 tags) |
|---------|--------|------------------------------|
| `app` | `us-east-1` | `shared-001-cluster`, `beta-001-cluster`, `demo-001-cluster`, `app-atento-001-cluster` |
| `app-outbound` | `sa-east-1` | `app-outbound-atento-br-cluster` |

The script queries `us-east-1` for `Project=app` and `sa-east-1` for `Project=app-outbound`, then unions the results. When `--project app` is passed, only `us-east-1` is queried. When `--project app-outbound` is passed, only `sa-east-1` is queried.

**All tag values live in AWS after Phase 1:**

| Project | Environment | Region | Cluster |
|---------|-------------|--------|---------|
| `app` | `shared-001` | `us-east-1` | `shared-001-cluster` |
| `app` | `beta-001` | `us-east-1` | `beta-001-cluster` |
| `app` | `demo-001` | `us-east-1` | `demo-001-cluster` |
| `app` | `atento-001` | `us-east-1` | `app-atento-001-cluster` |
| `app-outbound` | `outbound-atento-br` | `sa-east-1` | `app-outbound-atento-br-cluster` |

**Components**:

**`scripts/apps-services.sh`** — mirrors `integrator-services.sh`:
- Region-per-project mapping encoded in the script: `app` → `us-east-1`, `app-outbound` → `sa-east-1`
- When `--project` is omitted: queries both regions and unions results
- Cache file: `/tmp/apps_ecs_services.json`
- Tag filter per region: `Project=app` (us-east-1) and `Project=app-outbound` (sa-east-1)
- CLI flags:
  - `--project <name>` — optional; values: `app`, `app-outbound`; default: query both
  - `--environment <env>` — optional; filter by `Environment` tag value (e.g., `shared-001`, `outbound-atento-br`)
  - `--no-cache` — bypass cache, force fresh AWS query
- No `--client` flag (app and app-outbound have no Client tag)
- Output JSON fields: `Project`, `Cluster`, `Environment`, `Name`, `Status`, `Running`, `Desired`
  - `Project` field is added to distinguish `app` vs `app-outbound` results when both regions are queried
- Same AWS API sequence as integrator script: `get-resources` → `list-tags-for-resource` → `list-services` → `describe-services`

**`commands/apps.md`** — mirrors `integrators.md`:
- Documents available tag values (`Project` values, `Environment` values per project, `ManagedBy`)
- Documents naming conventions per project (e.g., `shared-001-cluster`, `app-outbound-atento-br-cluster`)
- Documents the two-project, two-region layout explicitly
- Cache behavior: check `/tmp/apps_ecs_services.json` before querying AWS
- CLI interface exposed to engineer:
  ```bash
  bash ~/.claude/scripts/apps-services.sh                                   # all clusters (both projects)
  bash ~/.claude/scripts/apps-services.sh --project app                    # only app (us-east-1)
  bash ~/.claude/scripts/apps-services.sh --project app-outbound           # only app-outbound (sa-east-1)
  bash ~/.claude/scripts/apps-services.sh --environment shared-001         # filter by Environment tag
  bash ~/.claude/scripts/apps-services.sh --no-cache                       # bypass cache
  ```
- Scale up / scale down flow with MFA fallback (must use correct region per project)
- Logs flow with CloudWatch log group pattern `/ecs/<service-name>` (correct region per project)

**`CLAUDE.md`** — add `/apps` entry in the Available Commands section, immediately after `/integrators`:
```
### /apps
- **Purpose**: Manage app ECS clusters and services (list, scale up/down, check status, logs)
- **Behavior**: Discovers clusters by `Project=app` and `Project=app-outbound` tags across `us-east-1` and `sa-east-1`, filters by `Project` and `Environment` tags, acts on services, reports the result — caches results in session
- **Important**: Only ask when information is genuinely missing — if the engineer already specified environment and action, execute immediately
```

**`CHANGELOG.md`** — add entry under `[Unreleased] > ### Added`:
```
- `/apps` skill for managing app ECS clusters and services
```

**Dependencies**: Phase 1 complete and applied. The script must find clusters in AWS to be validated end-to-end. The PR can be opened before apply, but functional testing requires the tags to be live.

**Success Criteria**:
- [ ] `bash ~/.claude/scripts/apps-services.sh` returns all five clusters (four app + one app-outbound)
- [ ] `bash ~/.claude/scripts/apps-services.sh --project app` returns the four app clusters from `us-east-1` only
- [ ] `bash ~/.claude/scripts/apps-services.sh --project app-outbound` returns the one app-outbound cluster from `sa-east-1` only
- [ ] `bash ~/.claude/scripts/apps-services.sh --environment shared-001` returns only shared-001 cluster
- [ ] `bash ~/.claude/scripts/apps-services.sh --no-cache` forces fresh AWS query against both regions
- [ ] Output JSON contains a `Project` field on every record
- [ ] `apps.md` command file created with two-project, two-region documentation
- [ ] `CLAUDE.md` and `CHANGELOG.md` updated in working copy
- [ ] PR opened against `develop` in the `.claude` repository

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Where to add tags | Replace `local.tags` in each stack (not via module variable) | `local.tags` already propagates to every resource that needs traceability — cluster, IAM role, instance profile, SG, ALB, etc. This mirrors the integrator pattern where each stack tags resources across multiple files (compute, mongodb, etc.). A `cluster_tags` variable on the module would tag only the cluster, breaking full traceability. |
| `Environment` tag value for atento | `"atento-001"` (without `app-` prefix) | Matches the stack-id convention used by the other three stacks. The `app-` prefix on the cluster name is a naming artifact from before the convention was established. Full alignment is deferred to the future atento migration. |
| `Automation` → `ManagedBy` rename | Renamed | Aligns with the integrator pattern. All integrator stacks use `ManagedBy = "terraform"`. |
| Remove `Cluster` tag | Removed | Redundant — the cluster name is already set on the AWS resource itself. The integrator pattern does not use a `Cluster` tag. |
| No `Client` tag on app clusters | Omitted | App stacks are not per-client in the integrator sense. The environment already encodes the deployment target. |
| Separate script and command from `/integrators` | `apps-services.sh` + `apps.md` (new files) | Different tag schema (no Client), different cluster naming, different log group patterns. Merging the two commands would add complexity to both with no benefit. |
| Apply order | shared-001, beta-001, demo-001, atento-001 | Production-first on the lowest-risk stacks. Atento last because it has the largest resource graph and dedicated VPC — requires more careful plan review. |
| Two PRs, two repos | Terraform PR + Claude Config PR | Required by Configuration Changes Policy (no direct edits to `~/.claude/`) and by the fact that these are independent repositories with separate review cycles. |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Terraform plan shows unexpected `+`/`-` changes | High | Each stack plan is reviewed individually before apply. If any resource creation or destruction appears — even unrelated — stop and investigate. Only `~ tags` are expected. |
| `app-atento-001` plan blast radius | Medium | Atento has the most resources (compute.tf + main.tf + s3.tf + opensearch.tf + rds.tf). Plan is run last and reviewed with extra care. Expect only `~ tags` across all files; any `+`/`-` is a stop signal. |
| Tag change alters resource behavior | Low | Tags are metadata in AWS — they do not affect resource behavior, routing, or IAM. Updates are always in-place. |
| `Environment` tag value change in atento breaks existing automation | Low | The old value `"app-atento-001"` was inconsistent with the other stacks and likely not used as a selector anywhere. Confirm with engineer before applying if any automation depends on this tag value. |
| `.claude` PR merged before Terraform apply | Low | The script will return empty results until tags are live. This is not a correctness issue — it's a known temporary state. Document in PR description. |

## Assumptions

- All four `app-*` stacks are initialized and the Terraform state is current (no pending drift unrelated to this change).
- App ECS clusters (`Project=app`) run in `us-east-1`. App-outbound clusters (`Project=app-outbound`) run in `sa-east-1`.
- `aws resourcegroupstaggingapi get-resources` is available with the default read-only AWS profile.
- The `.claude` working copy at `~/Projects/4Shark/.claude/` is on a clean branch or can have a feature branch created from it.
- The engineer will validate script output after Phase 1 apply before merging the Phase 2 PR.
- No existing automation or monitoring depends on the old `Automation = "terraform"` or `Cluster = "..."` tag keys in any of the four stacks.

---

**Status:** READY FOR TASK CREATION
